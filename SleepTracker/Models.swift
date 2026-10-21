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

/// Typ zvuku rozpoznaný appkou u jednoho klipu, přes Applem vestavěný
/// on-device klasifikátor (`SoundAnalysis` / `SNClassifySoundRequest`,
/// viz `SoundClassifierService`). Ukládá se na `SoundClip` jako prostý raw
/// String (viz `SoundClip.categoryRawValue`), ne jako tento enum přímo, aby
/// schéma SwiftData zůstalo jednoduché a odolné vůči budoucím změnám enumu.
enum SoundCategory: String, CaseIterable, Codable {
    /// Klasifikace ještě neproběhla (běží asynchronně na pozadí po uložení klipu).
    case pending
    case snoring
    case speech
    case flatulence
    /// Rozpoznaný zvuk nespadá do žádné ze sledovaných kategorií, nebo appka
    /// zvuk rozpoznala jen s nízkou jistotou.
    case other

    /// Český název pro zobrazení v UI.
    var displayName: String {
        switch self {
        case .pending: return "Zpracovává se…"
        case .snoring: return "Chrápání"
        case .speech: return "Mluvení"
        case .flatulence: return "Prdění"
        case .other: return "Jiný zvuk"
        }
    }

    /// SF Symbol pro zobrazení v UI. Volené jen z dlouhodobě stabilních,
    /// běžných symbolů, ať appka nikdy nezobrazí prázdnou ikonu.
    var symbolName: String {
        switch self {
        case .pending: return "hourglass"
        case .snoring: return "moon.zzz.fill"
        case .speech: return "bubble.left.and.bubble.right.fill"
        case .flatulence: return "wind"
        case .other: return "waveform"
        }
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

    /// Raw value `SoundCategory` rozpoznaného typu zvuku. Ukládá se jako
    /// String (ne enum přímo) – přistupuj přes computed `category`, které
    /// neplatnou/neznámou hodnotu bezpečně převede na `.other` místo pádu.
    /// Property-level default (ne jen v inicializátoru) kvůli lightweight
    /// migraci: kdyby appka s daty z předchozí verze schématu (bez téhle
    /// property) dostala aktualizaci, SwiftData potřebuje defaultní hodnotu,
    /// kterou může doplnit do existujících řádků, jinak store nejde otevřít.
    var categoryRawValue: String = SoundCategory.pending.rawValue
    /// Jistota klasifikace (0...1) z `SoundAnalysis`. 0, dokud klasifikace
    /// ještě neproběhla nebo appka nedokázala nic rozumného určit.
    var classificationConfidence: Double = 0

    var night: Night?

    init(
        id: UUID = UUID(),
        timestamp: Date,
        duration: TimeInterval,
        peakPower: Float,
        relativePath: String,
        category: SoundCategory = .pending,
        classificationConfidence: Double = 0,
        night: Night? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.duration = duration
        self.peakPower = peakPower
        self.relativePath = relativePath
        self.categoryRawValue = category.rawValue
        self.classificationConfidence = classificationConfidence
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

    /// Typ zvuku odvozený z `categoryRawValue`. Neznámá/poškozená hodnota
    /// (např. po budoucí změně enumu) se bezpečně mapuje na `.other` místo
    /// pádu appky.
    var category: SoundCategory {
        get { SoundCategory(rawValue: categoryRawValue) ?? .other }
        set { categoryRawValue = newValue.rawValue }
    }
}
