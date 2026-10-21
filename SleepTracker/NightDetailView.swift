import SwiftUI
import SwiftData
import Charts
import AVFoundation

struct NightDetailView: View {
    let night: Night

    @Environment(\.modelContext) private var modelContext
    /// Pro dohánění klipů zaseknutých ve stavu `.pending` – viz
    /// `resumeStuckClassifications()`.
    @State private var classifier = SoundClassifierService()

    /// Řídí jemný fade-in grafu a seznamu klipů při otevření obrazovky.
    @State private var hasAppeared = false

    private var sortedClips: [SoundClip] {
        night.clips.sorted { $0.timestamp < $1.timestamp }
    }

    var body: some View {
        ZStack {
            NightSkyBackgroundView()

            List {
                Section {
                    summaryHeader
                        .listRowBackground(Color.white.opacity(0.06))
                }

                if !sortedClips.isEmpty {
                    Section("Hlasitost v čase") {
                        activityChart
                            .frame(height: 220)
                            .padding(.vertical, 8)
                            .listRowBackground(Color.white.opacity(0.06))
                    }
                }

                Section("Klipy (\(sortedClips.count))") {
                    if sortedClips.isEmpty {
                        Text("Během této noci nebyl zaznamenán žádný zvuk.")
                            .foregroundStyle(.secondary)
                            .listRowBackground(Color.white.opacity(0.06))
                    } else {
                        ForEach(sortedClips) { clip in
                            ClipRow(clip: clip)
                                .listRowBackground(Color.white.opacity(0.06))
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .opacity(hasAppeared ? 1 : 0)
            .onAppear {
                withAnimation(.easeOut(duration: 0.5)) {
                    hasAppeared = true
                }
            }
        }
        .navigationTitle(night.startedAt.formatted(date: .abbreviated, time: .omitted))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            resumeStuckClassifications()
        }
    }

    /// Klasifikace klipu se normálně spouští jen jednou, hned po jeho vzniku
    /// (`RecordingView.classifyAndStore`). Pokud appku systém nebo uživatel
    /// ukončí dřív, než asynchronní klasifikace doběhne, klip by jinak zůstal
    /// navždy ve stavu `.pending` ("Zpracovává se…") bez způsobu, jak to
    /// opravit. Při každém otevření detailu noci proto appka takové klipy
    /// zkusí doklasifikovat znovu.
    private func resumeStuckClassifications() {
        let pendingClips = sortedClips.filter { $0.category == .pending }
        guard !pendingClips.isEmpty else { return }

        // Stejný důvod jako v `RecordingView.classifyAndStore`: `modelContext`
        // se vytáhne do lokální konstanty hned, dokud je view nainstalované,
        // a zápis z completion closure se jistí přes `clip.modelContext != nil`
        // pro případ, že by klip mezitím zmizel (smazaná noc apod.).
        let context = modelContext
        for clip in pendingClips {
            guard let fileURL = clip.fileURL else {
                clip.category = .other
                try? context.save()
                continue
            }
            classifier.classify(fileURL: fileURL) { outcome in
                DispatchQueue.main.async {
                    guard clip.modelContext != nil else { return }
                    clip.category = outcome.category
                    clip.classificationConfidence = outcome.confidence
                    try? context.save()
                }
            }
        }
    }

    private var activityChart: some View {
        Chart(sortedClips) { clip in
            BarMark(
                x: .value("Čas", clip.timestamp),
                y: .value("Hlasitost nad tichem (dB)", max(0, clip.peakPower - AudioLevelScale.floorDB)),
                width: .fixed(4)
            )
            .foregroundStyle(Color.sleepTrackerAccent)
        }
        .chartXAxis {
            AxisMarks(values: .stride(by: .hour)) { _ in
                AxisGridLine()
                AxisTick()
                AxisValueLabel(format: .dateTime.hour())
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading)
        }
    }

    private var summaryHeader: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(night.startedAt.formatted(date: .long, time: .shortened), systemImage: "bed.double.fill")
            if let endedAt = night.endedAt {
                Label("Konec: \(endedAt.formatted(date: .omitted, time: .shortened))", systemImage: "alarm")
            } else {
                Label("Noc nebyla ukončena", systemImage: "exclamationmark.circle")
                    .foregroundStyle(.orange)
            }
            if let duration = night.duration {
                let totalMinutes = Int(duration) / 60
                let hours = totalMinutes / 60
                let minutes = totalMinutes % 60
                Label("Délka spánku: \(hours) h \(minutes) min", systemImage: "clock")
            }
        }
        .font(.subheadline)
    }
}

private enum AudioLevelScale {
    /// Stejná hodnota jako "klidová" hladina v `AudioMonitorService`, použitá
    /// jen pro vizuální posun grafu tak, aby sloupce začínaly od nuly.
    static let floorDB: Float = -80
}

/// Jeden řádek se seznamem klipu – play/pause tlačítko, čas/délka klipu a
/// barevný badge s rozpoznaným typem zvuku.
private struct ClipRow: View {
    let clip: SoundClip
    @State private var playback = ClipPlaybackController()

    var body: some View {
        HStack(spacing: 12) {
            Button(action: togglePlayback) {
                Image(systemName: playback.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.title2)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 2) {
                Text(clip.timestamp, format: .dateTime.hour().minute().second())
                    .font(.body)
                Text("\(formattedDuration) · špička \(Int(clip.peakPower)) dB")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            CategoryBadge(category: clip.category)
        }
        .padding(.vertical, 2)
        .alert("Přehrávání selhalo", isPresented: errorAlertBinding) {
            Button("OK", role: .cancel) { playback.errorMessage = nil }
        } message: {
            Text(playback.errorMessage ?? "")
        }
    }

    private var formattedDuration: String {
        let seconds = Int(clip.duration.rounded())
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    private var errorAlertBinding: Binding<Bool> {
        Binding(
            get: { playback.errorMessage != nil },
            set: { isPresented in
                if !isPresented { playback.errorMessage = nil }
            }
        )
    }

    private func togglePlayback() {
        guard let url = clip.fileURL, FileManager.default.fileExists(atPath: url.path) else {
            playback.errorMessage = "Soubor s klipem nebyl na zařízení nalezen."
            return
        }
        playback.toggle(url: url)
    }
}

/// Malý barevný "chip" s ikonou a českým názvem rozpoznaného typu zvuku
/// (viz `SoundCategory`/`SoundClassifierService`). Barvy jsou jen vizuální
/// odlišení v UI, nejsou nikde jinde v appce významové.
private struct CategoryBadge: View {
    let category: SoundCategory

    private var tintColor: Color {
        switch category {
        case .pending:
            return .gray
        case .snoring:
            return Color(red: 0.62, green: 0.56, blue: 0.95)
        case .speech:
            return .sleepTrackerAccent
        case .flatulence:
            return Color(red: 0.95, green: 0.75, blue: 0.30)
        case .other:
            return .gray
        }
    }

    var body: some View {
        Label(category.displayName, systemImage: category.symbolName)
            .font(.caption.weight(.semibold))
            .lineLimit(1)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .foregroundStyle(tintColor)
            .background(Capsule().fill(tintColor.opacity(0.18)))
    }
}

/// Malý ovladač přehrávání jednoho klipu. Je samostatný objekt (ne přímo
/// ve View struktuře), protože potřebuje být delegátem `AVAudioPlayer`
/// a reagovat na dohrání/chybu přehrávání.
@Observable
private final class ClipPlaybackController: NSObject, AVAudioPlayerDelegate {
    private(set) var isPlaying = false
    private var player: AVAudioPlayer?
    /// URL, pro kterou je `player` aktuálně vytvořený – aby šlo rozlišit
    /// "pokračuj v přehrávání téhož klipu" od "přehraj jiný klip" a v prvním
    /// případě recyklovat stávající `AVAudioPlayer` místo vytváření nového
    /// (což by klip vždy spustilo znovu od začátku).
    private var currentURL: URL?
    var errorMessage: String?

    func toggle(url: URL) {
        if isPlaying {
            pause()
        } else {
            play(url: url)
        }
    }

    private func play(url: URL) {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default)
            try session.setActive(true)

            if let existingPlayer = player, currentURL == url {
                // Navazujeme na pozastavené přehrávání téhož klipu.
                existingPlayer.play()
            } else {
                let newPlayer = try AVAudioPlayer(contentsOf: url)
                newPlayer.delegate = self
                newPlayer.prepareToPlay()
                newPlayer.play()
                player = newPlayer
                currentURL = url
            }
            isPlaying = true
        } catch {
            errorMessage = error.localizedDescription
            isPlaying = false
        }
    }

    private func pause() {
        player?.pause()
        isPlaying = false
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        isPlaying = false
        // Po dohrání klipu přetočíme na začátek, aby další klepnutí na "Play"
        // přehrálo klip znovu od začátku (ne pauzu na konci, kde by se nic
        // neozvalo). Pauzou uprostřed klipu tahle metoda vůbec neprochází.
        player.currentTime = 0
        if !flag {
            errorMessage = "Přehrávání se nedokončilo úspěšně."
        }
    }

    func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        isPlaying = false
        errorMessage = error?.localizedDescription ?? "Při přehrávání došlo k neznámé chybě."
    }
}

#Preview {
    NavigationStack {
        NightDetailView(night: Night(startedAt: .now.addingTimeInterval(-8 * 3600), endedAt: .now))
    }
    .modelContainer(for: [Night.self, SoundClip.self], inMemory: true)
}
