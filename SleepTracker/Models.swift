import Foundation
import SwiftData

/// Jedna zaznamenaná noc. Appka vytvoří jeden `Night` při stisku "Začít noc"
/// a uzavře ho (nastaví `endedAt`) při stisku "Ukončit noc".
@Model
final class Night {
    @Attribute(.unique) var id: UUID
    var startedAt: Date
    var endedAt: Date?

    @Relationship(deleteRule: .cascade, inverse: \SoundClip.night)
    var clips: [SoundClip] = []

    init(id: UUID = UUID(), startedAt: Date = .now, endedAt: Date? = nil) {
        self.id = id
        self.startedAt = startedAt
        self.endedAt = endedAt
    }

    /// Délka spánku, pokud už noc skončila.
    var duration: TimeInterval? {
        guard let endedAt else { return nil }
        return endedAt.timeIntervalSince(startedAt)
    }
}

/// Jeden detekovaný úsek zvuku (chrápání, mluvení ze spánku apod.) uložený
/// jako samostatný `.m4a` soubor v Documents/Nights/<night-id>/.
@Model
final class SoundClip {
    @Attribute(.unique) var id: UUID
    /// Absolutní čas vzniku klipu (ne relativní offset – snadnější pro graf i zobrazení).
    var timestamp: Date
    var duration: TimeInterval
    /// Nejvyšší naměřená hlasitost (dBFS, typicky v rozsahu -80…0) během klipu.
    var peakPower: Float
    /// Cesta k souboru relativní k Documents adresáři aplikace, např.
    /// "Nights/<night-id>/clip-2026-10-21T02-14-03.m4a".
    var relativePath: String

    var night: Night?

    init(
        id: UUID = UUID(),
        timestamp: Date,
        duration: TimeInterval,
        peakPower: Float,
        relativePath: String,
        night: Night? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.duration = duration
        self.peakPower = peakPower
        self.relativePath = relativePath
        self.night = night
    }
}

extension SoundClip {
    /// Absolutní URL klipu v souborovém systému zařízení, odvozená z `relativePath`.
    /// Vrací `nil`, pokud se nepodaří zjistit Documents adresář (prakticky se nestává).
    var fileURL: URL? {
        guard let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return nil
        }
        return documents.appendingPathComponent(relativePath)
    }
}
