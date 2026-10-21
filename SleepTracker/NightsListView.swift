import SwiftUI
import SwiftData

struct NightsListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Night.startedAt, order: .reverse) private var nights: [Night]

    @State private var showingRecordingView = false

    var body: some View {
        NavigationStack {
            ZStack {
                NightSkyBackgroundView()

                Group {
                    if nights.isEmpty {
                        ContentUnavailableView(
                            "Zatím žádné noci",
                            systemImage: "moon.zzz",
                            description: Text("Začni novou noc tlačítkem vpravo nahoře. Appka bude přes noc nahrávat jen úseky, kdy zaslechne zvuk.")
                        )
                    } else {
                        List {
                            ForEach(nights) { night in
                                NavigationLink(value: night) {
                                    NightRow(night: night)
                                }
                                .listRowBackground(Color.clear)
                                .listRowSeparator(.hidden)
                                .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                            }
                            .onDelete(perform: deleteNights)
                        }
                        .listStyle(.plain)
                        .scrollContentBackground(.hidden)
                        .animation(.easeOut(duration: 0.3), value: nights)
                    }
                }
            }
            .navigationTitle("Historie nocí")
            .navigationDestination(for: Night.self) { night in
                NightDetailView(night: night)
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingRecordingView = true
                    } label: {
                        Label("Nová noc", systemImage: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingRecordingView) {
                RecordingView()
            }
        }
    }

    private func deleteNights(at offsets: IndexSet) {
        for index in offsets {
            let night = nights[index]
            removeFilesOnDisk(for: night)
            modelContext.delete(night)
        }
    }

    /// Smaže na disku celou složku noci (Documents/Nights/<id>), aby po
    /// odstranění noci z appky nezůstávaly osiřelé zvukové soubory.
    private func removeFilesOnDisk(for night: Night) {
        guard let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return
        }
        let folder = documents
            .appendingPathComponent("Nights", isDirectory: true)
            .appendingPathComponent(night.id.uuidString, isDirectory: true)
        try? FileManager.default.removeItem(at: folder)
    }
}

/// Jedna "karta" noci v historii – zaoblené rohy, jemný stín, tmavé pozadí
/// konzistentní s "noční obloha" tématem appky.
private struct NightRow: View {
    let night: Night

    private var durationText: String {
        guard let duration = night.duration else { return "Probíhá…" }
        let totalMinutes = Int(duration) / 60
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        return "\(hours) h \(minutes) min"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(night.startedAt, format: .dateTime.day().month().year())
                .font(.headline)
                .foregroundStyle(.white)
            HStack {
                Label(durationText, systemImage: "clock")
                Spacer()
                Label("\(night.clips.count) klipů", systemImage: "waveform")
            }
            .font(.subheadline)
            .foregroundStyle(.white.opacity(0.7))
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white.opacity(0.08))
        )
        .shadow(color: .black.opacity(0.25), radius: 8, x: 0, y: 4)
    }
}

#Preview {
    NightsListView()
        .modelContainer(for: [Night.self, SoundClip.self], inMemory: true)
}
