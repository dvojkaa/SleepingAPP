import SwiftUI

extension Color {
    /// Tyrkysová zvýrazňující barva appky, stejná jako ve zvukových vlnách
    /// na ikoně appky (`#4FD1C5`). Appka si ji drží jako barvu v kódu (ne
    /// jako "AccentColor" v Assets.xcassets), takže se dá přes
    /// `Color.sleepTrackerAccent` použít konzistentně napříč pozadím,
    /// grafem i ovládacími prvky bez závislosti na Asset katalogu.
    static let sleepTrackerAccent = Color(red: 0x4F / 255.0, green: 0xD1 / 255.0, blue: 0xC5 / 255.0)

    /// Nejtmavší odstín "nočního nebe" pozadí appky – používá se i jinde
    /// (např. jako podklad pod kartami), aby barevné schéma zůstalo jednotné.
    static let sleepTrackerNavy = Color(red: 0.07, green: 0.08, blue: 0.20)
}

/// Tmavé "noční nebe" pozadí appky – gradient v barvách appkové ikony
/// (tmavě modrá/fialová obloha), jemně blikající hvězdy a pomalu pulzující
/// srpek měsíce. Sdílené pozadí pro `NightsListView`, `RecordingView` i
/// `NightDetailView`, ať appka působí jako jeden vizuální celek místo
/// výchozího systémového vzhledu.
struct NightSkyBackgroundView: View {
    /// Hvězdné pole se generuje jen jednou, při první inicializaci stavu pro
    /// danou identitu view (`@State` inicializátor), ne při každém
    /// vyhodnocení `body`. Kdyby se `stars` počítalo jako obyčejná `let`
    /// vlastnost nastavená v `init()`, přegenerovalo by se (s novými
    /// náhodnými pozicemi i novými `id`) při KAŽDÉM překreslení rodiče –
    /// a rodiči jako `RecordingView` se `body` přepočítává ~3× za sekundu
    /// kvůli živému ukazateli hlasitosti. To by každou chvíli zahodilo a
    /// znovu vytvořilo celou `ForEach(stars)` hierarchii i s jejími
    /// animacemi, místo jemného blikání by vznikal neklidný "šum" a appka
    /// by zbytečně pálila výkon na obrazovce, která má svítit celou noc.
    @State private var stars: [Star]

    init(starCount: Int = 44) {
        _stars = State(initialValue: Star.randomField(count: starCount))
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.05, green: 0.06, blue: 0.16),
                    Color(red: 0.12, green: 0.10, blue: 0.29),
                    Color.sleepTrackerNavy
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            GeometryReader { proxy in
                ZStack {
                    MoonView()
                        .frame(width: proxy.size.width * 0.34, height: proxy.size.width * 0.34)
                        .position(x: proxy.size.width * 0.78, y: proxy.size.height * 0.15)

                    ForEach(stars) { star in
                        StarView(star: star)
                            .position(
                                x: star.relativeX * proxy.size.width,
                                y: star.relativeY * proxy.size.height
                            )
                    }
                }
            }
        }
        .ignoresSafeArea()
    }
}

/// Popis jedné hvězdy na obloze – pozice je relativní (0...1), ať se
/// pozadí dá bez přepočtů použít na obrazovkách libovolné velikosti.
private struct Star: Identifiable {
    let id = UUID()
    let relativeX: Double
    let relativeY: Double
    let size: CGFloat
    let minOpacity: Double
    let maxOpacity: Double
    let twinkleDuration: Double
    let twinkleDelay: Double

    /// Vygeneruje náhodné, ale rozumně rozprostřené pole hvězd. Každá hvězda
    /// má jinou délku i zpoždění "blikání", aby obloha nepůsobila synchronně
    /// (coby by blikaly všechny najednou).
    static func randomField(count: Int) -> [Star] {
        (0..<count).map { _ in
            Star(
                relativeX: .random(in: 0...1),
                relativeY: .random(in: 0...0.9),
                size: .random(in: 1.5...3.0),
                minOpacity: .random(in: 0.1...0.25),
                maxOpacity: .random(in: 0.6...1.0),
                twinkleDuration: .random(in: 1.5...4.0),
                twinkleDelay: .random(in: 0...3.0)
            )
        }
    }
}

private struct StarView: View {
    let star: Star
    @State private var isBright = false

    var body: some View {
        Circle()
            .fill(Color.white)
            .frame(width: star.size, height: star.size)
            .opacity(isBright ? star.maxOpacity : star.minOpacity)
            .onAppear {
                withAnimation(
                    Animation.easeInOut(duration: star.twinkleDuration)
                        .repeatForever(autoreverses: true)
                        .delay(star.twinkleDelay)
                ) {
                    isBright = true
                }
            }
    }
}

/// Jemně pulzující srpek měsíce v pozadí – čistě dekorativní, neinteraktivní
/// prvek. Srpek se "vykrojí" pomocí `.blendMode(.destinationOut)` uvnitř
/// `compositingGroup()` – jde o skutečnou průhlednou díru (ne jen kruh v
/// přibližné barvě pozadí), takže vypadá správně nad jakýmkoliv podkladem.
private struct MoonView: View {
    @State private var isPulsing = false

    var body: some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.95, green: 0.93, blue: 0.80),
                            Color(red: 0.85, green: 0.82, blue: 0.65)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            Circle()
                .fill(Color.black)
                .blendMode(.destinationOut)
                .offset(x: 10, y: -6)
        }
        .compositingGroup()
        .opacity(0.35)
        .scaleEffect(isPulsing ? 1.05 : 0.95)
        .onAppear {
            withAnimation(Animation.easeInOut(duration: 6).repeatForever(autoreverses: true)) {
                isPulsing = true
            }
        }
    }
}

#Preview {
    NightSkyBackgroundView()
}
