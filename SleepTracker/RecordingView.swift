import SwiftUI
import SwiftData
import AVFoundation
import Foundation

struct RecordingView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var audioMonitor = AudioMonitorService()
    @State private var classifier = SoundClassifierService()
    @State private var currentNight: Night?
    @State private var isRequestingPermission = false
    @State private var showPermissionDeniedAlert = false

    var body: some View {
        NavigationStack {
            ZStack {
                NightSkyBackgroundView()

                VStack(spacing: 36) {
                    Spacer()

                    WaveformMeterView(powerLevelDB: audioMonitor.currentPowerLevel)
                        .frame(height: 56)
                        .padding(.horizontal, 32)

                    Text(statusText)
                        .font(.headline)
                        .foregroundStyle(.white.opacity(0.85))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)

                    RecordButton(isRecording: audioMonitor.isRecordingNight, isDisabled: isRequestingPermission, action: toggleRecording)

                    if audioMonitor.isRecordingNight {
                        Label(
                            audioMonitor.isCapturingClip ? "Nahrávám klip…" : "Naslouchám…",
                            systemImage: audioMonitor.isCapturingClip ? "waveform" : "ear"
                        )
                        .font(.footnote)
                        .foregroundStyle(audioMonitor.isCapturingClip ? Color.red : Color.white.opacity(0.6))
                    }

                    Spacer()
                }
                .padding()
            }
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
        // RecordingView se otevírá jako `.sheet` z `NightsListView` – sheet
        // je samostatná prezentace a SwiftUI do ní `.preferredColorScheme`
        // nastavené výš (na `WindowGroup` v `SleepTrackerApp`) historicky
        // spolehlivě nepropaguje. Appka má vlastní tmavé pozadí i tak, ale
        // bez tohohle řádku by mohl zůstat světlý navigation bar.
        .preferredColorScheme(.dark)
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
        // `audioMonitor.startNight` je asynchronní (nastavuje AVAudioSession
        // na vlastní frontě, ne na hlavním vlákně) – `modelContext` se proto
        // vytáhne do lokální konstanty hned, dokud je RecordingView ještě
        // nainstalované ve view hierarchii, stejně jako u klasifikace
        // v `classifyAndStore`. V praxi completion dorazí prakticky okamžitě
        // (jeden rychlý XPC round-trip), ale stejná opatrnost nic nestojí.
        let context = modelContext
        audioMonitor.startNight { result in
            switch result {
            case .success(let nightID):
                let night = Night(id: nightID, startedAt: .now)
                context.insert(night)
                currentNight = night
                // Appka běží na pozadí klidně 8 hodin a systém ji teoreticky
                // může kdykoliv ukončit (jetsam) – explicitní save hned po
                // vytvoření noci minimalizuje riziko, že by se po pádu appky
                // ztratil i samotný záznam o noci, ke kterému by jinak
                // osiřelé .m4a soubory na disku neměly žádnou vazbu.
                try? context.save()
            case .failure(let error):
                audioMonitor.lastErrorMessage = error.localizedDescription
            }
        }
    }

    private func finishNight() {
        audioMonitor.stopNight()
        saveFinishedClips()
        currentNight?.endedAt = .now
        try? modelContext.save()
        currentNight = nil
    }

    /// Vyprázdní frontu klipů z `AudioMonitorService`, zapíše je jako
    /// `SoundClip` do SwiftData (ve stavu `.pending`), navázané na aktuálně
    /// běžící noc, a pro každý z nich hned spustí asynchronní rozpoznání typu
    /// zvuku (viz `classifyAndStore`).
    private func saveFinishedClips() {
        guard let night = currentNight else { return }
        let clips = audioMonitor.drainFinishedClips()
        guard !clips.isEmpty else { return }

        var savedClips: [SoundClip] = []
        for clip in clips {
            let soundClip = SoundClip(
                timestamp: clip.timestamp,
                duration: clip.duration,
                peakPower: clip.peakPower,
                relativePath: clip.relativePath,
                night: night
            )
            modelContext.insert(soundClip)
            savedClips.append(soundClip)
        }
        // Appka může běžet na pozadí celou noc a teoreticky být systémem
        // kdykoliv ukončena – explicitní save po každé dávce klipů zajistí,
        // že uložené .m4a soubory vždy mají odpovídající SwiftData záznam
        // (jinak by autosave mohl proběhnout až s velkým zpožděním).
        try? modelContext.save()

        for soundClip in savedClips {
            classifyAndStore(soundClip)
        }
    }

    /// Spustí on-device rozpoznání typu zvuku (`SoundClassifierService`) nad
    /// hotovým souborem klipu a po dokončení zapíše výsledek zpět do
    /// SwiftData. Do té doby zůstává klip ve stavu `.pending`
    /// ("Zpracovává se…"), appka na klasifikaci nijak nečeká.
    private func classifyAndStore(_ soundClip: SoundClip) {
        guard let fileURL = soundClip.fileURL else {
            soundClip.category = .other
            try? modelContext.save()
            return
        }

        // `modelContext` se vytáhne do lokální konstanty HNED, dokud je
        // RecordingView ještě nainstalované ve view hierarchii – čtení
        // `@Environment` property wrapperu mimo nainstalované view je podle
        // SwiftUI nedefinované chování. Klasifikace běží asynchronně a její
        // `completion` v praxi skoro vždy doběhne až po zavření téhle
        // obrazovky (uživatel zavře "Novou noc" krátce po "Ukončit noc"), kdy
        // by `modelContext` čtené přes `@Environment` uvnitř closure už
        // nemuselo být bezpečné. Samotná `ModelContext` instance ale žije
        // s `ModelContainer` appky (viz `SleepTrackerApp`), takže ji takhle
        // držet dál je v pořádku.
        let context = modelContext

        classifier.classify(fileURL: fileURL) { outcome in
            // `classify` dokončuje na vlastní background frontě – SwiftData
            // `ModelContext` ani `@Model` instance nejsou thread-safe, proto
            // se zápisu vždy vracíme zpátky na hlavní vlákno.
            DispatchQueue.main.async {
                // Klip mohl mezitím zmizet (smazaná noc apod.) – zápis do
                // odpojené/smazané `@Model` instance by appku shodil.
                // `modelContext == nil` je spolehlivější signál "objekt už
                // neexistuje" než `isDeleted`, které se po uložení kontextu
                // resetuje zpátky na `false`, i když je objekt už opravdu pryč.
                guard soundClip.modelContext != nil else { return }
                soundClip.category = outcome.category
                soundClip.classificationConfidence = outcome.confidence
                try? context.save()
            }
        }
    }
}

/// Velké kulaté Start/Stop tlačítko. Při nahrávání jemně pulzuje (glow za
/// tlačítkem), ať je na první pohled jasné, že appka aktivně běží.
private struct RecordButton: View {
    let isRecording: Bool
    let isDisabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                if isRecording {
                    PulsingGlow(color: .red)
                }

                Circle()
                    .fill(isRecording ? Color.red : Color.sleepTrackerAccent)
                    .shadow(color: (isRecording ? Color.red : Color.sleepTrackerAccent).opacity(0.55), radius: 18)

                VStack(spacing: 6) {
                    Image(systemName: isRecording ? "stop.fill" : "moon.fill")
                        .font(.system(size: 32, weight: .semibold))
                    Text(isRecording ? "Ukončit noc" : "Začít noc")
                        .font(.headline)
                }
                .foregroundStyle(.white)
            }
            .frame(width: 196, height: 196)
        }
        .buttonStyle(.plain)
        .opacity(isDisabled ? 0.5 : 1.0)
        .disabled(isDisabled)
        .animation(.easeOut(duration: 0.25), value: isRecording)
    }
}

/// Expandující, mizející "glow" kruh za tlačítkem, dokola opakovaný – jen po
/// dobu, kdy je vložený do hierarchie (tzn. jen při nahrávání, viz
/// `RecordButton`). Zmizením view animace sama přestane běžet.
private struct PulsingGlow: View {
    let color: Color
    @State private var isExpanded = false

    var body: some View {
        Circle()
            .fill(color.opacity(0.35))
            .scaleEffect(isExpanded ? 1.45 : 0.9)
            .opacity(isExpanded ? 0 : 0.7)
            .onAppear {
                withAnimation(Animation.easeOut(duration: 1.4).repeatForever(autoreverses: false)) {
                    isExpanded = true
                }
            }
    }
}

/// Živý ukazatel hlasitosti jako jednoduchý "waveform" – řada svislých
/// pruhů, co plynule mění výšku podle aktuální hlasitosti z
/// `AudioMonitorService`. Appka měří jen jednu souhrnnou hlasitost (ne
/// spektrum), takže pruhy mají pevně danou, ale nerovnoměrnou váhu, aby i
/// tak vypadaly přirozeně jako skutečný zvukový waveform.
private struct WaveformMeterView: View {
    let powerLevelDB: Float

    private static let minDB: Float = -80
    private static let barCount = 24
    /// Pevně dané váhy na pruh (konstantní pro celou appku, ne odvozené od
    /// instance) – ať se `sin()` pro všech 24 pruhů nepočítá znovu při každém
    /// vytvoření téhle view, což se při živém ukazateli hlasitosti děje i
    /// několikrát za sekundu po celou noc.
    private static let barWeights: [CGFloat] = (0..<WaveformMeterView.barCount).map { index in
        let phase = Double(index) / Double(WaveformMeterView.barCount) * .pi * 3
        return CGFloat(0.5 + 0.5 * abs(sin(phase)))
    }

    private var normalizedLevel: CGFloat {
        let clamped = max(Self.minDB, min(0, powerLevelDB))
        return CGFloat((clamped - Self.minDB) / -Self.minDB)
    }

    var body: some View {
        GeometryReader { proxy in
            HStack(alignment: .center, spacing: max(2, proxy.size.width / CGFloat(Self.barCount * 3))) {
                ForEach(0..<Self.barWeights.count, id: \.self) { index in
                    Capsule()
                        .fill(Color.sleepTrackerAccent)
                        .frame(height: max(4, proxy.size.height * normalizedLevel * Self.barWeights[index]))
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .center)
            .animation(.easeOut(duration: 0.2), value: powerLevelDB)
        }
    }
}

#Preview {
    RecordingView()
        .modelContainer(for: [Night.self, SoundClip.self], inMemory: true)
}
