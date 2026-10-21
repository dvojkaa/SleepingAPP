import SwiftUI
import SwiftData
import AVFoundation

struct RecordingView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var audioMonitor = AudioMonitorService()
    @State private var currentNight: Night?
    @State private var isRequestingPermission = false
    @State private var showPermissionDeniedAlert = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 32) {
                Spacer()

                VolumeMeterView(powerLevelDB: audioMonitor.currentPowerLevel)
                    .frame(height: 24)
                    .padding(.horizontal, 32)

                Text(statusText)
                    .font(.headline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                Button(action: toggleRecording) {
                    Text(audioMonitor.isRecordingNight ? "Ukončit noc" : "Začít noc")
                        .font(.title2.bold())
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(audioMonitor.isRecordingNight ? Color.red : Color.accentColor)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                }
                .padding(.horizontal, 32)
                .disabled(isRequestingPermission)

                if audioMonitor.isRecordingNight {
                    Label(
                        audioMonitor.isCapturingClip ? "Nahrávám klip…" : "Naslouchám…",
                        systemImage: audioMonitor.isCapturingClip ? "waveform" : "ear"
                    )
                    .font(.footnote)
                    .foregroundStyle(audioMonitor.isCapturingClip ? .red : .secondary)
                }

                Spacer()
            }
            .padding()
            .navigationTitle("Nová noc")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Zavřít") {
                        if audioMonitor.isRecordingNight {
                            finishNight()
                        }
                        dismiss()
                    }
                }
            }
            .alert("Přístup k mikrofonu", isPresented: $showPermissionDeniedAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("SleepTracker potřebuje povolení k mikrofonu, aby mohl přes noc nahrávat zvuky. Povol ho v Nastavení > SleepTracker > Mikrofon.")
            }
            .alert("Chyba nahrávání", isPresented: errorAlertBinding) {
                Button("OK", role: .cancel) { audioMonitor.lastErrorMessage = nil }
            } message: {
                Text(audioMonitor.lastErrorMessage ?? "")
            }
            .onChange(of: audioMonitor.newlyFinishedClips) { _, _ in
                saveFinishedClips()
            }
            .onDisappear {
                // Pokud uživatel zavře obrazovku systémovým gestem místo
                // tlačítka "Zavřít", noc se přesto korektně ukončí a uloží.
                if audioMonitor.isRecordingNight {
                    finishNight()
                }
            }
        }
    }

    private var statusText: String {
        if audioMonitor.isRecordingNight, let night = currentNight {
            return "Noc probíhá od \(night.startedAt.formatted(date: .omitted, time: .shortened)). Appka nahrává jen úseky, kdy je slyšet zvuk."
        }
        return "Appka bude přes noc naslouchat a nahraje jen úseky, kdy zaslechne zvuk (chrápání, mluvení apod.)."
    }

    private var errorAlertBinding: Binding<Bool> {
        Binding(
            get: { audioMonitor.lastErrorMessage != nil },
            set: { isPresented in
                if !isPresented { audioMonitor.lastErrorMessage = nil }
            }
        )
    }

    private func toggleRecording() {
        if audioMonitor.isRecordingNight {
            finishNight()
        } else {
            requestPermissionAndStart()
        }
    }

    private func requestPermissionAndStart() {
        isRequestingPermission = true
        AVAudioApplication.requestRecordPermission { granted in
            DispatchQueue.main.async {
                isRequestingPermission = false
                if granted {
                    startNight()
                } else {
                    showPermissionDeniedAlert = true
                }
            }
        }
    }

    private func startNight() {
        do {
            let nightID = try audioMonitor.startNight()
            let night = Night(id: nightID, startedAt: .now)
            modelContext.insert(night)
            currentNight = night
            // Appka běží na pozadí klidně 8 hodin a systém ji teoreticky může
            // kdykoliv ukončit (jetsam) – explicitní save hned po vytvoření
            // noci minimalizuje riziko, že by se po pádu appky ztratil i
            // samotný záznam o noci, ke kterému by jinak osiřelé .m4a
            // soubory na disku neměly žádnou vazbu.
            try? modelContext.save()
        } catch {
            audioMonitor.lastErrorMessage = error.localizedDescription
        }
    }

    private func finishNight() {
        audioMonitor.stopNight()
        saveFinishedClips()
        currentNight?.endedAt = .now
        try? modelContext.save()
        currentNight = nil
    }

    /// Vyprázdní frontu klipů z `AudioMonitorService` a zapíše je jako
    /// `SoundClip` do SwiftData, navázané na aktuálně běžící noc.
    private func saveFinishedClips() {
        guard let night = currentNight else { return }
        let clips = audioMonitor.drainFinishedClips()
        guard !clips.isEmpty else { return }

        for clip in clips {
            let soundClip = SoundClip(
                timestamp: clip.timestamp,
                duration: clip.duration,
                peakPower: clip.peakPower,
                relativePath: clip.relativePath,
                night: night
            )
            modelContext.insert(soundClip)
        }
        // Appka může běžet na pozadí celou noc a teoreticky být systémem
        // kdykoliv ukončena – explicitní save po každé dávce klipů zajistí,
        // že uložené .m4a soubory vždy mají odpovídající SwiftData záznam
        // (jinak by autosave mohl proběhnout až s velkým zpožděním).
        try? modelContext.save()
    }
}

/// Jednoduchý horizontální ukazatel hlasitosti napojený na dBFS hodnotu
/// z `AudioMonitorService`.
private struct VolumeMeterView: View {
    let powerLevelDB: Float

    private static let minDB: Float = -80

    private var normalizedLevel: Double {
        let clamped = max(Self.minDB, min(0, powerLevelDB))
        return Double((clamped - Self.minDB) / -Self.minDB)
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.secondary.opacity(0.2))
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.accentColor)
                    .frame(width: proxy.size.width * normalizedLevel)
            }
        }
        .animation(.easeOut(duration: 0.2), value: powerLevelDB)
    }
}

#Preview {
    RecordingView()
        .modelContainer(for: [Night.self, SoundClip.self], inMemory: true)
}
