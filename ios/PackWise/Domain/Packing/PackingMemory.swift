import Foundation

/// Packing Memory event vocabulary — Engine V2, Step 6.
///
/// An immutable, write-only event log. Nothing reads it yet; the Packing
/// Memory features that will ("when laundry is available, you usually reduce
/// shirts by ~40%") become group-bys over these events, which is why the
/// context is a structured fingerprint and never an opaque hash.
///
/// **Retention (decided 2026-09-01):** events deliberately survive trip
/// deletion — they carry no relationship to `TripRecord`, only its UUID.
/// Deleting a trip removes the trip; the packing history it produced is the
/// user's accumulated memory and is the entire point of collecting events.
/// The data is local-first and never leaves the device. A "Clear packing
/// history" control belongs in Me when memory ships a user-visible feature;
/// until something reads the log, there is nothing user-visible to clear.
/// This is recorded in `docs/lifecycle-memory-and-me.md`.

enum DurationBucket: String, Codable, CaseIterable, Sendable {
    case short      // 1–3 days
    case medium     // 4–7
    case long       // 8–14
    case extended   // 15+

    static func from(days: Int) -> DurationBucket {
        switch days {
        case ..<4: .short
        case 4...7: .medium
        case 8...14: .long
        default: .extended
        }
    }
}

enum PackingMemoryEventKind: String, Codable, CaseIterable, Sendable {
    case suggested
    case userAdded
    case notNeeded
    case packed
    case quantityChanged
}

/// The trip conditions an event happened under. Structured so later queries
/// are a group-by, not a research project — a hash here would collect
/// unqueryable data for months.
struct ContextFingerprint: Hashable, Codable, Sendable {
    var durationBucket: DurationBucket
    var laundryPlan: LaundryAccess
    var packingStyle: PackingStyle
    var bag: BagType
    var tripType: TripType
    var partySize: Int
}

struct PackingMemoryEvent: Hashable, Sendable {
    var tripID: UUID
    var travelerID: UUID?
    var canonicalItemID: String
    var kind: PackingMemoryEventKind
    var value: Int?
    var timestamp: Date
    var context: ContextFingerprint
}
