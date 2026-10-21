import Foundation
import SoundAnalysis
import AVFoundation
import CoreMedia

/// Výsledek klasifikace jednoho klipu.
struct ClassificationOutcome {
    let category: SoundCategory
    let confidence: Double
}

/// Service kolem Applem vestavěného on-device klasifikátoru zvuku
/// (`SNClassifySoundRequest`, `.version1`, ~303 kategorií zvuků ze
/// `SoundAnalysis` frameworku). Appka si nepíše vlastní Core ML model – jen
/// bere hotový systémový klasifikátor a mapuje jeho výstupní labely na naše
/// tři sledované kategorie (chrápání, mluvení, prdění); cokoliv jiného (nebo
/// cokoliv s nízkou jistotou) spadne do "Jiný zvuk".
///
/// Apple veřejně negarantuje přesný seznam labelů ani jejich stabilitu mezi
/// verzemi systému – konkrétně není jisté, že je "prdění" mezi těmi ~303
/// kategoriemi zastoupené jako samostatný, dost granulární label. Mapování
/// se proto nestaví na natvrdo napsaném seznamu, ale ověřuje se za běhu
/// proti `SNClassifySoundRequest.knownClassifications`: pokud žádný z
/// kandidátních labelů pro danou kategorii v aktuálním běhu neexistuje, ta
/// kategorie se prostě nikdy nepřiřadí – appka na to nijak nespadne, klipy
/// pro ni jen vždy skončí jako "Jiný zvuk".
final class SoundClassifierService {

    enum Threshold {
        /// Pod touto jistotou (0...1) označíme klip jako "Jiný zvuk", i kdyby
        /// nejlepší identifikovaný label náhodou patřil do jedné z našich
        /// kategorií – nejistou klasifikaci radši neukazujeme jako jistou.
        static let minimumClassificationConfidence: Double = 0.4
        /// Krátké analytické okno, ať i jednovteřinové klipy (minimální délka
        /// klipu dle `AudioMonitorService`) dostanou aspoň jeden výsledek.
        /// Vestavěný klasifikátor (`.version1`) podporuje okna 0.5–15 s
        /// (ověřeno nezávisle mimo kompilátor, viz komentář u `request`
        /// níže), takže 1.5 s je bezpečně uprostřed tohoto rozsahu. Při
        /// změně téhle konstanty zůstaň v rozsahu 0.5–15 s.
        static let analysisWindowDurationSeconds: Double = 1.5
        static let analysisOverlapFactor: Double = 0.5
    }

    /// Kandidátní labely, které by Apple pro danou kategorii mohl používat.
    /// Skutečná dostupnost se ověřuje přes `knownClassifications` – viz výše.
    private enum CandidateLabels {
        static let snoring = ["snoring", "snore"]
        static let speech = ["speech", "mumble", "whispering", "shout", "yell", "babble"]
        static let flatulence = ["flatulence", "fart", "burping_eructation"]
    }

    /// Všechna práce (sestavení requestu, analýza souboru) běží sekvenčně na
    /// téhle frontě – mimo jiné i proto, aby lazy inicializace `request`
    /// (první, poměrně drahé vytvoření `SNClassifySoundRequest`) nikdy
    /// neblokovala hlavní vlákno a zároveň nebyla přistupována souběžně z
    /// více vláken najednou.
    private let analysisQueue = DispatchQueue(label: "com.sleeptracker.sound-classification")

    /// Sdílený, jednou vytvořený klasifikační request. `nil`, pokud se ho
    /// vůbec nepodařilo sestavit (appka pak klipy jen nechá jako "Jiný zvuk",
    /// nic nespadne).
    ///
    /// `windowDuration` se nastavuje napřímo na `Threshold.analysisWindowDurationSeconds`
    /// bez dodatečného ověřování proti `SNClassifySoundRequest.windowDurationConstraint`.
    /// Zvažovali jsme to i opačně (přečíst constraint za běhu a hodnotu si
    /// podle něj ořezat/vybrat), ale přesný Swift tvar té API (přesná jména
    /// case u typu, který Swift reprezentuje jako refinovaný enum nad ObjC
    /// třídou) jsme si nedokázali ověřit bez přístupu ke kompilátoru – špatně
    /// odhadnutá jména case by appku vůbec nepustila ke kompilaci, což je
    /// horší výsledek než riziko, které se tím snažíme pokrýt. Vestavěný
    /// klasifikátor `.version1` prokazatelně podporuje okna 0.5–15 s (ověřeno
    /// nezávisle dvakrát), takže zvolených 1.5 s je bezpečně uprostřed tohoto
    /// rozsahu. Pokud by se `analysisWindowDurationSeconds` výše v budoucnu
    /// měnilo, je potřeba zůstat v tomhle 0.5–15s rozsahu.
    private lazy var request: SNClassifySoundRequest? = {
        guard let request = try? SNClassifySoundRequest(classifierIdentifier: .version1) else {
            return nil
        }
        request.windowDuration = CMTimeMakeWithSeconds(
            Threshold.analysisWindowDurationSeconds,
            preferredTimescale: 600
        )
        request.overlapFactor = Threshold.analysisOverlapFactor
        return request
    }()

    /// Mapování "label -> kategorie" sestavené jen z labelů, které tahle
    /// verze systémového klasifikátoru opravdu zná (viz vysvětlení u typu).
    private lazy var labelToCategory: [String: SoundCategory] = {
        guard let knownClassifications = request?.knownClassifications else {
            return [:]
        }
        let known = Set(knownClassifications)
        var mapping: [String: SoundCategory] = [:]
        for label in CandidateLabels.snoring where known.contains(label) {
            mapping[label] = .snoring
        }
        for label in CandidateLabels.speech where known.contains(label) {
            mapping[label] = .speech
        }
        for label in CandidateLabels.flatulence where known.contains(label) {
            mapping[label] = .flatulence
        }
        return mapping
    }()

    /// Spustí klasifikaci nad hotovým souborem klipu a zavolá `completion` s
    /// výsledkem. Analýza běží asynchronně na vlastní background frontě –
    /// `completion` se proto volá na téže frontě (ne na hlavním vlákně).
    /// Volající je zodpovědný za přeskok zpět na hlavní vlákno, pokud s
    /// výsledkem dál pracuje s SwiftData `ModelContext` nebo `@Model`
    /// instancí (obojí není thread-safe).
    func classify(fileURL: URL, completion: @escaping (ClassificationOutcome) -> Void) {
        analysisQueue.async { [self] in
            guard let request else {
                completion(ClassificationOutcome(category: .other, confidence: 0))
                return
            }

            do {
                let analyzer = try SNAudioFileAnalyzer(url: fileURL)
                let observer = ClassificationResultCollector(
                    labelToCategory: labelToCategory,
                    completion: completion
                )
                try analyzer.add(request, withObserver: observer)
                // `SNAudioFileAnalyzer` drží observer jen slabě (stejně jako
                // v Applově vlastním sample kódu "SystemAudioClassifier", kde
                // si ho proto schovávají do vlastní property) – lokální
                // `observer` proměnná by tak teoreticky mohla být uvolněná
                // ARC-em hned po posledním použití (po `add(_:withObserver:)`),
                // ještě PŘED tím, než `analyze()` doběhne a zavolá jeho
                // delegátní metody (hlavně v optimalizovaném Release buildu).
                // `analyze()` je sice synchronní, ale výslovné držení
                // `observer` až za ní (přes `finishIfNeeded()`) zaručuje, že
                // instance žije po celou dobu analýzy, a zároveň garantuje
                // přesně jedno zavolání `completion` i kdyby `analyze()`
                // skončila bez volání `requestDidComplete` (poškozený/prázdný
                // soubor apod.) – `finishIfNeeded()` je idempotentní.
                analyzer.analyze()
                observer.finishIfNeeded()
            } catch {
                completion(ClassificationOutcome(category: .other, confidence: 0))
            }
        }
    }
}

/// Sbírá klasifikační výsledky ze všech (překrývajících se) oken klipu a na
/// konci vybere nejvyšší jistotu, se kterou se napříč klipem objevil label
/// patřící do některé z našich sledovaných kategorií.
private final class ClassificationResultCollector: NSObject, SNResultsObserving {
    private let labelToCategory: [String: SoundCategory]
    private let completion: (ClassificationOutcome) -> Void

    private var bestLabel: String?
    private var bestConfidence: Double = 0
    private var didComplete = false

    init(labelToCategory: [String: SoundCategory], completion: @escaping (ClassificationOutcome) -> Void) {
        self.labelToCategory = labelToCategory
        self.completion = completion
    }

    func request(_ request: SNRequest, didProduce result: SNResult) {
        guard let classificationResult = result as? SNClassificationResult else { return }

        // `classifications` jsou v rámci jednoho okna seřazené sestupně podle
        // jistoty. Hledáme první, jejíž label vůbec patří do některé z našich
        // kategorií – ne prostě nejjistější label v okně jako takovém. Každý
        // klip appka ukončuje až po pár vteřinách ticha
        // (`AudioMonitorService.Threshold.silenceHoldToEndClip`), takže
        // poslední okna klipu bývají čisté ticho/ambient, na které bývá
        // klasifikátor mimořádně jistý (klidně jistější, než na skutečném
        // chrápání/mluvení na začátku klipu) – kdybychom brali nejjistější
        // okno jako celek bez ohledu na to, čeho se týká, "vyhrálo" by skoro
        // vždy ticho a appka by fakticky nikdy nic nerozpoznala.
        guard let mappedClassification = classificationResult.classifications.first(where: { labelToCategory[$0.identifier] != nil }) else {
            return
        }

        if mappedClassification.confidence > bestConfidence {
            bestConfidence = mappedClassification.confidence
            bestLabel = mappedClassification.identifier
        }
    }

    func request(_ request: SNRequest, didFailWithError error: Error) {
        finishIfNeeded()
    }

    func requestDidComplete(_ request: SNRequest) {
        finishIfNeeded()
    }

    /// Idempotentní – bezpečné zavolat víckrát (z `requestDidComplete`/
    /// `didFailWithError` i explicitně po `analyze()`, viz `classify(fileURL:completion:)`).
    fileprivate func finishIfNeeded() {
        guard !didComplete else { return }
        didComplete = true

        guard let bestLabel,
              bestConfidence >= SoundClassifierService.Threshold.minimumClassificationConfidence,
              let category = labelToCategory[bestLabel] else {
            completion(ClassificationOutcome(category: .other, confidence: bestConfidence))
            return
        }
        completion(ClassificationOutcome(category: category, confidence: bestConfidence))
    }
}
