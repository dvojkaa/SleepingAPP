import SwiftUI
import SwiftData
import Charts
import AVFoundation

struct NightDetailView: View {
    let night: Night

    private var sortedClips: [SoundClip] {
        night.clips.sorted { $0.timestamp < $1.timestamp }
    }

    var body: some View {
        List {
            Section {
                summaryHeader
            }

            if !sortedClips.isEmpty {
                Section("Hlasitost v čase") {
                    activityChart
                        .frame(height: 220)
                        .padding(.vertical, 8)
                }
            }

            Section("Klipy (\(sortedClips.count))") {
                if sortedClips.isEmpty {
                    Text("Během této noci nebyl zaznamenán žádný zvuk.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(sortedClips) { clip in
                        ClipRow(clip: clip)
                    }
                }
            }
        }
        .navigationTitle(night.startedAt.formatted(date: .abbreviated, time: .omitted))
        .navigationBarTitleDisplayMode(.inline)
    }

    private var activityChart: some View {
        Chart(sortedClips) { clip in
            BarMark(
                x: .value("Čas", clip.timestamp),
                y: .value("Hlasitost nad tichem (dB)", max(0, clip.peakPower - AudioLevelScale.floorDB)),
                width: .fixed(4)
            )
            .foregroundStyle(Color.accentColor)
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

/// Jeden řádek se seznamem klipu, obsahuje vlastní play/pause tlačítko.
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
