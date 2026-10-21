import Foundation
import AVFoundation
import Observation

/// Výsledek jednoho dokončeného klipu, připravený k uložení do SwiftData.
/// `AudioMonitorService` tyto hodnoty jen publikuje – zápis do modelu
/// (vytvoření `SoundClip` a jeho navázání na `Night`) dělá view vrstva,
/// protože service nemá (a nemá mít) přístup k `ModelContext`.
struct CapturedClip: Identifiable, Equatable {
    let id = UUID()
    let relativePath: String
    let timestamp: Date
    let duration: TimeInterval
    let peakPower: Float
}

enum AudioMonitorError: LocalizedError {
    case microphonePermissionDenied
    case documentsDirectoryUnavailable
    case audioSessionConfigurationFailed(Error)
    case recorderCreationFailed(Error)
    case nightAlreadyInProgress
    case noActiveNight

    var errorDescription: String? {
        switch self {
        case .microphonePermissionDenied:
            return "Přístup k mikrofonu byl zamítnut. Povol ho v Nastavení > SleepTracker > Mikrofon."
        case .documentsDirectoryUnavailable:
            return "Nepodařilo se najít úložiště aplikace na zařízení."
        case .audioSessionConfigurationFailed(let error):
            return "Nepodařilo se připravit zvukový systém: \(error.localizedDescription)"
        case .recorderCreationFailed(let error):
            return "Nepodařilo se spustit nahrávání: \(error.localizedDescription)"
        case .nightAlreadyInProgress:
            return "Noc už probíhá."
        case .noActiveNight:
            return "Žádná noc právě neprobíhá."
        }
    }
}

/// Pomocné cesty k souborům na disku. Noci a jejich klipy se ukládají do
/// Documents/Nights/<night-id>/clip-<timestamp>.m4a, aby šly snadno dohledat
/// i mimo appku (např. přes Files appku se zapnutým "Supports Document Browser"),
/// a aby smazání noci v UI stačilo provést smazáním celé její složky.
enum AudioFileLayout {
    static let nightsDirectoryName = "Nights"
    static let clipFilePrefix = "clip-"
    static let clipFileExtension = "m4a"
    static let monitorScratchFileName = "monitor-scratch.m4a"

    static func documentsDirectory() throws -> URL {
        guard let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            throw AudioMonitorError.documentsDirectoryUnavailable
        }
        return url
    }

    static func nightFolderURL(nightID: UUID) throws -> URL {
        try documentsDirectory()
            .appendingPathComponent(nightsDirectoryName, isDirectory: true)
            .appendingPathComponent(nightID.uuidString, isDirectory: true)
    }

    /// Jméno souboru odvozené z timestampu, aby klipy ve složce byly přirozeně
    /// seřazené podle názvu a zároveň měly unikátní, čitelný název.
    static func newClipURL(inNightFolder nightFolder: URL, timestamp: Date) -> URL {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let safeName = formatter.string(from: timestamp)
            .replacingOccurrences(of: ":", with: "-")
        return nightFolder.appendingPathComponent("\(clipFilePrefix)\(safeName).\(clipFileExtension)")
    }

    /// Dočasný soubor, do kterého se nahrává, dokud appka jen "naslouchá" a žádný
    /// klip zrovna nevzniká. Jeho obsah se nikam neukládá, appka ho periodicky
    /// (viz `Threshold.maxMonitorSegmentDuration`) i při ukončení noci přepisuje
    /// nebo maže, aby neúměrně nerostl na disku.
    static func monitorScratchURL() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(monitorScratchFileName)
    }

    static func relativePath(for fileURL: URL, relativeTo documentsDirectory: URL) -> String {
        let docsPath = documentsDirectory.standardizedFileURL.path
        let filePath = fileURL.standardizedFileURL.path
        guard filePath.hasPrefix(docsPath) else {
            return fileURL.lastPathComponent
        }
        var relative = String(filePath.dropFirst(docsPath.count))
        if relative.hasPrefix("/") {
            relative.removeFirst()
        }
        return relative
    }
}

/// Jádro appky: hlídá hlasitost mikrofonu přes noc a kdykoliv hlasitost
/// přesáhne práh, začne nahrávat samostatný klip. Klip se ukončí až po
/// určité době ticha (hystereze + "padding"), aby se neuřízl konec
/// chrápání nebo věty.
///
/// Implementační poznámka: v jednu chvíli běží vždy přesně jeden
/// `AVAudioRecorder` – buď "monitorovací" (nahrává do zahazovaného
/// scratch souboru a slouží jen ke čtení `averagePower`), nebo "klipový"
/// (nahrává přímo do výsledného .m4a souboru klipu). Přepínáním mezi
/// nimi se appka vyhne běhu dvou nahrávačů najednou nad stejným vstupem,
/// což by na iOS bylo nespolehlivé.
///
/// Appka navíc hlídá dva druhy "mimořádných událostí", ke kterým při
/// celonočním běhu na pozadí reálně může dojít, a snaží se z nich sama
/// zotavit: (1) výpadek monitorovacího nahrávače (viz `tick()` a
/// `restartMonitorRecorderIfPossible()`), (2) přerušení zvukové session
/// systémem – telefonát, budík, Siri (viz `handleInterruption(_:)`) a
/// vzácný reset celé zvukové soustavy (`handleMediaServicesReset(_:)`).
@Observable
final class AudioMonitorService: NSObject {

    // MARK: - Laditelné konstanty

    private enum Threshold {
        /// Hlasitost nad tímto prahem (dBFS) zahájí nový klip.
        static let startDB: Float = -30.0
        /// Dokud je hlasitost nad tímto (nižším) prahem, klip pokračuje.
        /// Mezera mezi startDB a endDB je hystereze, aby mírné kolísání
        /// kolem jedné hranice nerozsekávalo jeden zvuk na desítky klipů.
        static let endDB: Float = -40.0
        /// Jak dlouho musí hlasitost nepřetržitě zůstat pod endDB, než se
        /// klip skutečně ukončí. Tím vzniká "padding" ticha na konci klipu.
        static let silenceHoldToEndClip: TimeInterval = 2.5
        /// Klipy kratší než toto se zahodí (typicky náhodný šum/šramot).
        static let minimumClipDuration: TimeInterval = 1.0
        /// Jak často se čte hlasitost z mikrofonu.
        static let meteringInterval: TimeInterval = 0.3
        /// Prakticky "ticho" – používá se jako výchozí/klidová hodnota metru.
        static let silenceFloorDB: Float = -80.0
        /// Maximální délka jednoho "běhu" monitorovacího nahrávače, než se
        /// appka sama přepne na čerstvý scratch soubor. Bez tohoto limitu by
        /// při tiché noci jeden soubor v tmp rostl klidně 8 hodin v kuse.
        static let maxMonitorSegmentDuration: TimeInterval = 300.0
        /// Kolikrát po sobě musí selhat pokus o obnovení monitorovacího
        /// nahrávače, než appka uživateli ukáže chybovou hlášku. Appka se
        /// i poté dál pokouší zotavit na každém ticku.
        static let maxMonitorRestartAttemptsBeforeWarning = 5
    }

    private static let recorderSettings: [String: Any] = [
        AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
        AVSampleRateKey: 44_100,
        AVNumberOfChannelsKey: 1,
        AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue
    ]

    // MARK: - Publikovaný stav (čte ho UI)

    private(set) var isRecordingNight = false
    /// `true`, když appka zrovna nahrává konkrétní klip (ne jen naslouchá).
    private(set) var isCapturingClip = false
    /// Aktuální hlasitost v dBFS (typicky -80 až 0), pro live ukazatel v UI.
    private(set) var currentPowerLevel: Float = Threshold.silenceFloorDB
    /// Klipy dokončené od posledního zavolání `drainFinishedClips()`.
    private(set) var newlyFinishedClips: [CapturedClip] = []
    /// Poslední chyba k zobrazení uživateli (např. alertem). UI si ji po
    /// zobrazení nastaví zpět na `nil`.
    var lastErrorMessage: String?

    // MARK: - Interní stav

    private var activeRecorder: AVAudioRecorder?
    private var meteringTimer: Timer?

    private var currentNightFolderURL: URL?

    private var currentClipURL: URL?
    private var currentClipStartedAt: Date?
    private var currentClipPeakPower: Float = Threshold.silenceFloorDB
    private var silenceStreakStartedAt: Date?

    /// Počítadlo neúspěšných pokusů o restart monitorovacího nahrávače v řadě.
    /// Resetuje se na 0 při prvním dalším úspěchu.
    private var monitorRestartFailureCount = 0

    /// `true` mezi `.began` a `.ended` přerušením audio session (telefonát,
    /// budík, Siri...). Po dobu přerušení je session neaktivní, takže `record()`
    /// na novém nahrávači spolehlivě selže – `tick()` proto automatické
    /// obnovování monitorovacího nahrávače po tuto dobu vůbec nezkouší, ať
    /// appka zbytečně nebije do audio systému a hlavně ať z toho nevznikne
    /// falešná chybová hláška, která by po `.ended` zůstala viset, i když se
    /// nahrávání mezitím v pořádku obnovilo.
    private var isInterrupted = false

    // MARK: - Veřejné API

    /// Zahájí novou noc: nastaví zvukovou session, vytvoří složku pro noc
    /// a spustí monitorování hlasitosti. Vrací ID nově vytvořené noci.
    @discardableResult
    func startNight() throws -> UUID {
        guard !isRecordingNight else {
            throw AudioMonitorError.nightAlreadyInProgress
        }

        try configureAudioSession()

        let nightID = UUID()
        let folder = try AudioFileLayout.nightFolderURL(nightID: nightID)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        } catch {
            throw AudioMonitorError.recorderCreationFailed(error)
        }

        currentNightFolderURL = folder
        newlyFinishedClips.removeAll()
        lastErrorMessage = nil
        monitorRestartFailureCount = 0

        try startMonitorRecorder()
        registerForAudioSessionNotifications()
        startMeteringTimer()
        isRecordingNight = true
        return nightID
    }

    /// Ukončí aktuální noc. Pokud zrovna probíhá nahrávání klipu, klip se
    /// korektně dokončí a uloží (nebude přerušený uprostřed).
    func stopNight() {
        guard isRecordingNight else { return }

        meteringTimer?.invalidate()
        meteringTimer = nil
        unregisterForAudioSessionNotifications()

        if isCapturingClip {
            finishCurrentClip(at: Date(), restartMonitoring: false)
        }

        activeRecorder?.stop()
        activeRecorder = nil

        do {
            try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        } catch {
            // Appka noc i tak korektně uzavře – deaktivace sdílené session
            // při úklidu po sobě není kritická (appka ji stejně příští noc
            // znovu aktivuje v `configureAudioSession()`), proto zde chybu
            // jen tiše ignorujeme a nepřepisujeme jí případnou předchozí
            // (relevantnější) hlášku v `lastErrorMessage`.
        }

        // Scratch soubor monitorovacího nahrávače dál nemá smysl držet na disku.
        try? FileManager.default.removeItem(at: AudioFileLayout.monitorScratchURL())

        currentNightFolderURL = nil
        isRecordingNight = false
        isCapturingClip = false
        currentPowerLevel = Threshold.silenceFloorDB
        silenceStreakStartedAt = nil
        currentClipURL = nil
        currentClipStartedAt = nil
        monitorRestartFailureCount = 0
        isInterrupted = false
    }

    /// Vrátí a vyprázdní frontu nově dokončených klipů. Volá se z UI vrstvy,
    /// která je zapíše do SwiftData a napojí na aktuální `Night`.
    @discardableResult
    func drainFinishedClips() -> [CapturedClip] {
        let clips = newlyFinishedClips
        newlyFinishedClips.removeAll()
        return clips
    }

    // MARK: - Audio session

    private func configureAudioSession() throws {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.record, mode: .default, options: [.allowBluetooth])
            try session.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            throw AudioMonitorError.audioSessionConfigurationFailed(error)
        }
    }

    // MARK: - Přerušení zvukové session (telefonát, budík, Siri, reset systému)

    private func registerForAudioSessionNotifications() {
        let center = NotificationCenter.default
        center.addObserver(
            self,
            selector: #selector(handleInterruption(_:)),
            name: AVAudioSession.interruptionNotification,
            object: nil
        )
        center.addObserver(
            self,
            selector: #selector(handleMediaServicesReset(_:)),
            name: AVAudioSession.mediaServicesWereResetNotification,
            object: nil
        )
    }

    private func unregisterForAudioSessionNotifications() {
        let center = NotificationCenter.default
        center.removeObserver(self, name: AVAudioSession.interruptionNotification, object: nil)
        center.removeObserver(self, name: AVAudioSession.mediaServicesWereResetNotification, object: nil)
    }

    @objc private func handleInterruption(_ notification: Notification) {
        // Apple negarantuje, na kterém vlákně notifikace dorazí, zatímco
        // zbytek třídy (Timer na RunLoop.main, @Observable stav čtený SwiftUI)
        // je psaný jako main-thread-only – proto si tělo přehodíme na hlavní
        // vlákno, než sáhneme na `activeRecorder`/publikovaný stav.
        DispatchQueue.main.async { [weak self] in
            self?.processInterruption(notification)
        }
    }

    private func processInterruption(_ notification: Notification) {
        guard isRecordingNight,
              let userInfo = notification.userInfo,
              let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else { return }

        switch type {
        case .began:
            // Systém nám právě odebral mikrofon (telefonát, budík, Siri...).
            // Rozdělaný klip korektně dokončíme (nenahrává se dál do session,
            // která teď stejně není aktivní). `isInterrupted` zablokuje
            // automatické pokusy o restart monitorovacího nahrávače v `tick()`
            // po dobu přerušení – jinak by `record()` spolehlivě selhávalo
            // 3× za sekundu a po pár vteřinách by se zbytečně objevila
            // chybová hláška, i když se vše po `.ended` v pořádku obnoví.
            isInterrupted = true
            if isCapturingClip {
                finishCurrentClip(at: Date(), restartMonitoring: false)
            }
            stopActiveRecorderOnly()

        case .ended:
            isInterrupted = false
            monitorRestartFailureCount = 0
            do {
                try configureAudioSession()
                restartMonitorRecorderIfPossible()
            } catch {
                lastErrorMessage = "Nahrávání se po přerušení (hovor, budík…) nepodařilo obnovit: \(error.localizedDescription)"
            }

        @unknown default:
            break
        }
    }

    @objc private func handleMediaServicesReset(_ notification: Notification) {
        DispatchQueue.main.async { [weak self] in
            self?.processMediaServicesReset()
        }
    }

    private func processMediaServicesReset() {
        guard isRecordingNight else { return }

        // Vzácný, ale fatální stav – celá zvuková soustava systému se
        // restartovala a staré AVAudioSession/AVAudioRecorder instance jsou
        // neplatné. Rozdělaný klip nejde zachránit (podkladová session
        // zmizela) – smažeme i jeho rozepsaný soubor, ať po appce nezůstane
        // navždy ležet osiřelý .m4a bez odpovídajícího SwiftData záznamu.
        activeRecorder = nil
        isCapturingClip = false
        if let clipURL = currentClipURL {
            try? FileManager.default.removeItem(at: clipURL)
        }
        currentClipURL = nil
        currentClipStartedAt = nil
        silenceStreakStartedAt = nil
        isInterrupted = false
        monitorRestartFailureCount = 0

        do {
            try configureAudioSession()
            restartMonitorRecorderIfPossible()
        } catch {
            lastErrorMessage = "Po resetu zvukového systému se nepodařilo obnovit nahrávání: \(error.localizedDescription)"
        }
    }

    // MARK: - Metering timer / state machine

    private func startMeteringTimer() {
        meteringTimer?.invalidate()
        let timer = Timer(timeInterval: Threshold.meteringInterval, repeats: true) { [weak self] _ in
            self?.tick()
        }
        RunLoop.main.add(timer, forMode: .common)
        meteringTimer = timer
    }

    private func tick() {
        guard let recorder = activeRecorder else {
            // Monitorovací nahrávač z nějakého důvodu neběží (selhal restart,
            // nestihl se ještě nahodit po přerušení...). Zkusíme ho obnovit na
            // každém ticku, ať appka co nejdřív zase sleduje hlasitost místo
            // toho, aby tiše "spala" se zapnutým UI "Naslouchám…".
            if isRecordingNight, !isCapturingClip, !isInterrupted {
                restartMonitorRecorderIfPossible()
            }
            return
        }

        recorder.updateMeters()
        let power = recorder.averagePower(forChannel: 0)
        currentPowerLevel = power

        let now = Date()

        if isCapturingClip {
            currentClipPeakPower = max(currentClipPeakPower, power)

            if power < Threshold.endDB {
                if let silenceStart = silenceStreakStartedAt {
                    if now.timeIntervalSince(silenceStart) >= Threshold.silenceHoldToEndClip {
                        finishCurrentClip(at: now, restartMonitoring: true)
                    }
                } else {
                    silenceStreakStartedAt = now
                }
            } else {
                silenceStreakStartedAt = nil
            }
        } else {
            if power > Threshold.startDB {
                beginClip(at: now)
            } else if recorder.currentTime >= Threshold.maxMonitorSegmentDuration {
                // Dlouhodobě tichá noc – monitorovací soubor by jinak rostl
                // bez omezení. Pravidelně ho "zahodíme" za čerstvý.
                restartMonitorRecorderIfPossible()
            }
        }
    }

    // MARK: - Klip start/konec

    private func beginClip(at date: Date) {
        guard let nightFolder = currentNightFolderURL else { return }

        let clipURL = AudioFileLayout.newClipURL(inNightFolder: nightFolder, timestamp: date)
        stopActiveRecorderOnly()

        do {
            let recorder = try AVAudioRecorder(url: clipURL, settings: Self.recorderSettings)
            recorder.delegate = self
            recorder.isMeteringEnabled = true
            guard recorder.record() else {
                throw AudioMonitorError.recorderCreationFailed(
                    NSError(domain: "AudioMonitorService", code: -1, userInfo: [NSLocalizedDescriptionKey: "AVAudioRecorder.record() selhal."])
                )
            }
            activeRecorder = recorder
            currentClipURL = clipURL
            currentClipStartedAt = date
            currentClipPeakPower = Threshold.silenceFloorDB
            silenceStreakStartedAt = nil
            isCapturingClip = true
        } catch {
            lastErrorMessage = error.localizedDescription
            // Pokud se klip nepodaří založit, zkusíme alespoň obnovit
            // monitorování, aby appka dál sledovala hlasitost.
            restartMonitorRecorderIfPossible()
        }
    }

    private func finishCurrentClip(at date: Date, restartMonitoring: Bool) {
        guard let recorder = activeRecorder,
              let startedAt = currentClipStartedAt,
              let clipURL = currentClipURL else {
            // Nekonzistentní stav (neměl by při normálním běhu nastat) – i tak
            // appku vrátíme do "nenahrávám klip", ať neuvízne natrvalo
            // s `isCapturingClip == true` bez skutečně běžícího nahrávače.
            activeRecorder = nil
            isCapturingClip = false
            silenceStreakStartedAt = nil
            currentClipURL = nil
            currentClipStartedAt = nil
            currentClipPeakPower = Threshold.silenceFloorDB
            if restartMonitoring {
                restartMonitorRecorderIfPossible()
            }
            return
        }

        recorder.stop()
        activeRecorder = nil
        isCapturingClip = false
        silenceStreakStartedAt = nil

        let duration = date.timeIntervalSince(startedAt)

        if duration >= Threshold.minimumClipDuration {
            if let documents = try? AudioFileLayout.documentsDirectory() {
                let relativePath = AudioFileLayout.relativePath(for: clipURL, relativeTo: documents)
                let captured = CapturedClip(
                    relativePath: relativePath,
                    timestamp: startedAt,
                    duration: duration,
                    peakPower: currentClipPeakPower
                )
                newlyFinishedClips.append(captured)
            }
        } else {
            // Příliš krátký zvuk (náhodný šum) – klip zahodíme i se souborem.
            try? FileManager.default.removeItem(at: clipURL)
        }

        currentClipURL = nil
        currentClipStartedAt = nil
        currentClipPeakPower = Threshold.silenceFloorDB

        guard restartMonitoring else { return }
        restartMonitorRecorderIfPossible()
    }

    // MARK: - Monitorovací nahrávač

    private func startMonitorRecorder() throws {
        let url = AudioFileLayout.monitorScratchURL()
        do {
            let recorder = try AVAudioRecorder(url: url, settings: Self.recorderSettings)
            recorder.delegate = self
            recorder.isMeteringEnabled = true
            guard recorder.record() else {
                throw AudioMonitorError.recorderCreationFailed(
                    NSError(domain: "AudioMonitorService", code: -2, userInfo: [NSLocalizedDescriptionKey: "Monitorovací nahrávač se nespustil."])
                )
            }
            activeRecorder = recorder
        } catch {
            throw AudioMonitorError.recorderCreationFailed(error)
        }
    }

    /// Nekonfliktní varianta `startMonitorRecorder()` pro automatické
    /// zotavení (z `tick()`, po přerušení session nebo při periodické
    /// recyklaci scratch souboru) – chybu nenechá appku spadnout, jen si ji
    /// započítá a až po `maxMonitorRestartAttemptsBeforeWarning` neúspěších
    /// za sebou o tom (jednou) uvědomí uživatele přes `lastErrorMessage`.
    /// Appka se i po zobrazení hlášky dál pokouší zotavit na dalších ticích.
    private func restartMonitorRecorderIfPossible() {
        stopActiveRecorderOnly()
        do {
            try startMonitorRecorder()
            monitorRestartFailureCount = 0
        } catch {
            activeRecorder = nil
            monitorRestartFailureCount += 1
            if monitorRestartFailureCount == Threshold.maxMonitorRestartAttemptsBeforeWarning {
                lastErrorMessage = "Nahrávání na pozadí přestalo fungovat a appka se ho opakovaně nedaří obnovit (\(error.localizedDescription)). Zkontroluj appku, případně noc ukonči a začni novou."
            }
        }
    }

    private func stopActiveRecorderOnly() {
        activeRecorder?.stop()
        activeRecorder = nil
    }
}

// MARK: - AVAudioRecorderDelegate

extension AudioMonitorService: AVAudioRecorderDelegate {
    func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        if !flag {
            lastErrorMessage = "Nahrávání se nedokončilo úspěšně."
        }
    }

    func audioRecorderEncodeErrorDidOccur(_ recorder: AVAudioRecorder, error: Error?) {
        lastErrorMessage = error?.localizedDescription ?? "Při nahrávání zvuku došlo k neznámé chybě."
    }
}
