import Foundation

enum WeatherChangeProposalStatus: String, Codable, Sendable {
    case pending
    case applied
    case dismissed
    case superseded
    case invalidated

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        switch raw {
        case "accepted":
            self = .applied
        default:
            self = WeatherChangeProposalStatus(rawValue: raw) ?? .pending
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

struct WeatherChangeProposal: Identifiable, Equatable, Codable, Sendable {
    var id: UUID
    var tripID: UUID
    var oldSnapshotID: UUID
    var newSnapshotID: UUID
    var createdAt: Date
    var status: WeatherChangeProposalStatus
    var signalChanges: [WeatherSignalChange]
    var headline: String
    var diff: RecommendationDiff
    var tripContextSignature: String

    var previewNames: [String] {
        let adds = diff.add.map(\.displayName)
        let quantities = diff.quantityChanges.map { change in
            "\(change.item.displayName) ×\(change.item.quantity) → ×\(change.suggestedQuantity)"
        }
        return Array((adds + quantities).prefix(4))
    }

    enum CodingKeys: String, CodingKey {
        case id, tripID, oldSnapshotID, newSnapshotID, createdAt, status
        case signalChanges, headline, diff, tripContextSignature
    }

    init(
        id: UUID,
        tripID: UUID,
        oldSnapshotID: UUID,
        newSnapshotID: UUID,
        createdAt: Date,
        status: WeatherChangeProposalStatus,
        signalChanges: [WeatherSignalChange],
        headline: String,
        diff: RecommendationDiff,
        tripContextSignature: String
    ) {
        self.id = id
        self.tripID = tripID
        self.oldSnapshotID = oldSnapshotID
        self.newSnapshotID = newSnapshotID
        self.createdAt = createdAt
        self.status = status
        self.signalChanges = signalChanges
        self.headline = headline
        self.diff = diff
        self.tripContextSignature = tripContextSignature
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        tripID = try container.decode(UUID.self, forKey: .tripID)
        oldSnapshotID = try container.decode(UUID.self, forKey: .oldSnapshotID)
        newSnapshotID = try container.decode(UUID.self, forKey: .newSnapshotID)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        status = try container.decode(WeatherChangeProposalStatus.self, forKey: .status)
        signalChanges = try container.decode([WeatherSignalChange].self, forKey: .signalChanges)
        headline = try container.decode(String.self, forKey: .headline)
        diff = try container.decode(RecommendationDiff.self, forKey: .diff)
        tripContextSignature = try container.decodeIfPresent(String.self, forKey: .tripContextSignature) ?? ""
    }
}

enum WeatherChangeProposalEvaluation: Equatable, Sendable {
    case pending(WeatherChangeProposal)
    case invalidated
}

enum WeatherRefreshOutcome: Equatable, Sendable {
    case skipped
    case snapshotOnly
    case proposal(WeatherChangeProposal)
}

enum WeatherRefreshPolicy {
    static func shouldFetch(
        existing: TripWeatherContext?,
        tripStart: Date,
        tripStatus: TripStatus,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> Bool {
        switch tripStatus {
        case .completed, .archived:
            return false
        case .draft, .planning, .packing, .traveling:
            break
        }
        guard let existing else { return true }
        if existing.source == .seasonal || !existing.isPreciseForecast {
            return !WeatherForecastNormalizer.isBeyondDailyHorizon(tripStart: tripStart, now: now, calendar: calendar)
        }
        if let expires = existing.providerExpiresAt, expires > now {
            return false
        }
        return true
    }
}

enum WeatherChangeProposalLifecycle {
    static func tripContextSignature(_ context: TripContext) -> String {
        let destination = [
            context.destination.countryCode,
            String(format: "%.4f", context.destination.latitude),
            String(format: "%.4f", context.destination.longitude),
            context.destination.timeZone
        ].joined(separator: ",")
        let activities = context.activities.sorted().joined(separator: ",")
        let chips = context.contextChips.map(\.rawValue).sorted().joined(separator: ",")
        let party = context.effectiveParty
        let travelers = party.travelers
            .map { "\($0.role.rawValue):\($0.ageGroup.rawValue):\($0.packingResponsibility.rawValue)" }
            .sorted()
            .joined(separator: ",")
        return [
            destination,
            String(context.startDate.timeIntervalSince1970),
            String(context.endDate.timeIntervalSince1970),
            context.tripType.rawValue,
            activities,
            context.bagType.rawValue,
            context.packingStyle.rawValue,
            context.userNotes,
            chips,
            party.travelMode.rawValue,
            String(party.travelers.count),
            travelers
        ].joined(separator: "|")
    }

    static func snapshotID(for weather: TripWeatherContext?) -> UUID {
        guard let weather else {
            return UUID(uuidString: "00000000-0000-0000-0000-000000000000")!
        }
        let stamp = "\(weather.source.rawValue)|\(weather.fetchedAt.timeIntervalSince1970)|\(weather.fixtureID ?? "")"
        return uuid(from: stamp)
    }

    static func prune(
        _ diff: RecommendationDiff,
        existing: [PackingItemDraft],
        overrides: [RecommendationOverrideDraft]
    ) -> RecommendationDiff {
        let existingKeys = Set(existing.map(\.recommendationKey))
        let existingIDs = Set(existing.map(\.id))
        let removed = Set(
            overrides
                .filter { $0.action == "removed" }
                .map(\.canonicalItemID)
        )
        let add = diff.add.filter { draft in
            guard !existingKeys.contains(draft.recommendationKey) else { return false }
            if let canonical = draft.canonicalItemID, removed.contains(canonical) {
                return false
            }
            return true
        }
        let removeCandidates = diff.removeCandidates.filter { existingIDs.contains($0.id) }
        let quantityChanges = diff.quantityChanges.filter { change in
            guard let current = existing.first(where: { $0.id == change.item.id }) else { return false }
            return !current.isUserModified && current.quantity != change.suggestedQuantity
        }
        return RecommendationDiff(
            id: diff.id,
            add: add,
            removeCandidates: removeCandidates,
            quantityChanges: quantityChanges
        )
    }

    static func evaluate(
        _ proposal: WeatherChangeProposal,
        tripContextSignature: String,
        existing: [PackingItemDraft],
        overrides: [RecommendationOverrideDraft]
    ) -> WeatherChangeProposalEvaluation {
        guard proposal.status == .pending else { return .invalidated }
        if !proposal.tripContextSignature.isEmpty, proposal.tripContextSignature != tripContextSignature {
            return .invalidated
        }
        let pruned = prune(proposal.diff, existing: existing, overrides: overrides)
        guard !pruned.isEmpty else { return .invalidated }
        var current = proposal
        current.diff = pruned
        return .pending(current)
    }

    static func hasSamePackingConsequence(_ lhs: WeatherChangeProposal, _ rhs: WeatherChangeProposal) -> Bool {
        packingConsequenceKey(lhs.diff) == packingConsequenceKey(rhs.diff)
    }

    static func actionable(
        _ proposal: WeatherChangeProposal,
        tripContextSignature: String,
        existing: [PackingItemDraft],
        overrides: [RecommendationOverrideDraft]
    ) -> WeatherChangeProposal? {
        if case .pending(let current) = evaluate(
            proposal,
            tripContextSignature: tripContextSignature,
            existing: existing,
            overrides: overrides
        ) {
            return current
        }
        return nil
    }

    private static func packingConsequenceKey(_ diff: RecommendationDiff) -> String {
        let adds = diff.add.map(\.recommendationKey).sorted().joined(separator: ",")
        let removes = diff.removeCandidates.map(\.recommendationKey).sorted().joined(separator: ",")
        let quantities = diff.quantityChanges
            .map { "\($0.item.recommendationKey):\($0.suggestedQuantity)" }
            .sorted()
            .joined(separator: ",")
        return [adds, removes, quantities].joined(separator: "|")
    }

    private static func uuid(from stamp: String) -> UUID {
        var digest = [UInt8](repeating: 0, count: 16)
        let utf8 = Array(stamp.utf8)
        for (index, byte) in utf8.enumerated() {
            digest[index % 16] ^= byte
            digest[(index + 7) % 16] = digest[(index + 7) % 16] &+ byte
        }
        digest[6] = (digest[6] & 0x0F) | 0x40
        digest[8] = (digest[8] & 0x3F) | 0x80
        return UUID(uuid: (
            digest[0], digest[1], digest[2], digest[3],
            digest[4], digest[5], digest[6], digest[7],
            digest[8], digest[9], digest[10], digest[11],
            digest[12], digest[13], digest[14], digest[15]
        ))
    }
}

enum WeatherChangeReconciler {
    static func reconcile(
        tripID: UUID,
        oldWeather: TripWeatherContext?,
        newWeather: TripWeatherContext,
        context: TripContext,
        existing: [PackingItemDraft],
        overrides: [RecommendationOverrideDraft],
        engine: PackingEngine,
        thresholds: WeatherThresholds,
        templates: [String: String],
        now: Date = .now
    ) -> WeatherRefreshOutcome {
        let tripDays = max(1, context.durationDays)
        let oldConditions = WeatherSignalDiffer.packingConditions(
            weather: oldWeather,
            tripDays: tripDays,
            outdoorActivities: context.outdoorActivities,
            thresholds: thresholds
        )
        let newConditions = WeatherSignalDiffer.packingConditions(
            weather: newWeather,
            tripDays: tripDays,
            outdoorActivities: context.outdoorActivities,
            thresholds: thresholds
        )
        let changes = WeatherSignalDiffer.changes(from: oldConditions, to: newConditions)
        guard !changes.isEmpty else { return .snapshotOnly }

        var nextContext = context
        nextContext.weather = newWeather.isPreciseForecast || !newWeather.dailyForecast.isEmpty ? newWeather : nil
        let diff = engine.recommendationDiff(context: nextContext, existing: existing, overrides: overrides)
        guard !diff.isEmpty else { return .snapshotOnly }

        let headline = WeatherChangeCopy.headline(
            changes: changes,
            newWeather: newWeather,
            rainThreshold: thresholds.rainProbabilityAdd,
            templates: templates
        )
        return .proposal(
            WeatherChangeProposal(
                id: UUID(),
                tripID: tripID,
                oldSnapshotID: WeatherChangeProposalLifecycle.snapshotID(for: oldWeather),
                newSnapshotID: WeatherChangeProposalLifecycle.snapshotID(for: newWeather),
                createdAt: now,
                status: .pending,
                signalChanges: changes,
                headline: headline,
                diff: diff,
                tripContextSignature: WeatherChangeProposalLifecycle.tripContextSignature(nextContext)
            )
        )
    }
}
