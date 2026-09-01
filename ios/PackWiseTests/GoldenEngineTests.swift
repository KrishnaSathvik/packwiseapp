import Foundation
import Testing
@testable import PackWise

/// Golden-file harness for the packing engine — Engine V2 plan, Step 1.
///
/// Runs the engine over each fixture in `shared/fixtures/golden/` and compares
/// the serialized output against the committed golden in `Goldens/`. The
/// goldens are a regression ledger, not truth: today's wrong behavior is
/// committed deliberately so every engine change produces a reviewable diff.
///
/// To regenerate after an intentional change:
///
///     TEST_RUNNER_PACKWISE_RECORD_GOLDENS=1 xcodebuild test \
///         -project PackWise.xcodeproj -scheme PackWise \
///         -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
///         -only-testing:PackWiseTests/GoldenEngineTests
///
/// Recording rewrites the golden files and then *fails* the test, so a
/// re-record can never slip through CI unnoticed — review the diff, commit,
/// and run again without the variable.
///
/// Determinism rules the harness enforces or relies on:
/// - Fixture dates are frozen absolute values; nothing resolves against `.now`.
/// - Weather comes from `MockWeatherService.context(from:)` on a named fixture
///   or is `nil` for the seasonal path — never fetched.
/// - Items are sorted by owner, then canonical ID; signal arrays are sorted;
///   UUIDs, timestamps, and packing state are excluded from serialization.
/// - Weekday names in reasons come from frozen forecast dates, but render via
///   the machine locale; goldens assume en_US.
struct GoldenEngineTests {
    // MARK: - Repo paths (via #filePath so no bundle plumbing is needed)

    private static let testsDirectory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    private static let goldensDirectory = testsDirectory.appendingPathComponent("Goldens")
    private static let fixturesFile = testsDirectory
        .deletingLastPathComponent()  // ios/PackWiseTests -> ios
        .deletingLastPathComponent()  // ios -> repo root
        .appendingPathComponent("shared/fixtures/golden/golden-fixtures.json")

    private static var isRecording: Bool {
        ProcessInfo.processInfo.environment["PACKWISE_RECORD_GOLDENS"] == "1"
    }

    // MARK: - Fixture schema

    struct GoldenFixtureFile: Codable {
        var engineVersion: String
        var fixtures: [GoldenFixture]
    }

    struct GoldenFixture: Codable {
        var id: String
        var proves: String
        var destination: String
        var weatherFixture: String?
        var startDate: String
        var days: Int
        var tripType: String
        var activities: [String]
        var bag: String
        var style: String
        var laundry: String
        var homeCountryCode: String
        var party: PartyEval?
        var overrides: [OverrideEval]?
        var existing: [ExistingEval]?
    }

    // MARK: - Test

    @Test func engineOutputMatchesGoldens() throws {
        let file = try JSONDecoder().decode(
            GoldenFixtureFile.self,
            from: Data(contentsOf: Self.fixturesFile)
        )
        #expect(file.fixtures.count == 15)
        let engine = PackingEngine(catalog: try SharedLibrary.catalog(), rules: try SharedLibrary.rules())
        let destinations = try SharedLibrary.testDestinations()
        let weatherFixtures = try SharedLibrary.weatherFixtures()

        if Self.isRecording {
            try FileManager.default.createDirectory(at: Self.goldensDirectory, withIntermediateDirectories: true)
        }

        for fixture in file.fixtures {
            let rendered = try render(
                fixture: fixture,
                engineVersion: file.engineVersion,
                engine: engine,
                destinations: destinations,
                weatherFixtures: weatherFixtures
            )
            let goldenURL = Self.goldensDirectory.appendingPathComponent("\(fixture.id).json")

            if Self.isRecording {
                try rendered.write(to: goldenURL, atomically: true, encoding: .utf8)
                continue
            }

            guard let golden = try? String(contentsOf: goldenURL, encoding: .utf8) else {
                Issue.record("No golden for \(fixture.id). Record with TEST_RUNNER_PACKWISE_RECORD_GOLDENS=1, review, commit.")
                continue
            }
            #expect(
                rendered == golden,
                "\(fixture.id) diverged from its golden. If intentional, re-record with TEST_RUNNER_PACKWISE_RECORD_GOLDENS=1 and review the diff of \(goldenURL.path)."
            )
        }

        if Self.isRecording {
            Issue.record("Goldens recorded to \(Self.goldensDirectory.path). Review the diff, commit, and re-run without TEST_RUNNER_PACKWISE_RECORD_GOLDENS.")
        }
    }

    // MARK: - Context construction

    private func render(
        fixture: GoldenFixture,
        engineVersion: String,
        engine: PackingEngine,
        destinations: [Destination],
        weatherFixtures: [String: WeatherFixture]
    ) throws -> String {
        guard let destination = destinations.first(where: { $0.city == fixture.destination }) else {
            throw ResourceError.missing("destination \(fixture.destination)")
        }
        let start = Self.frozenDate(fixture.startDate)
        let end = Calendar.current.date(byAdding: .day, value: fixture.days - 1, to: start)!
        let math = TripDateMath.daysAndNights(from: start, to: end)

        var weather: TripWeatherContext?
        if let name = fixture.weatherFixture {
            guard let weatherFixture = weatherFixtures[name] else {
                throw ResourceError.missing("weather fixture \(name)")
            }
            weather = MockWeatherService.context(from: weatherFixture, start: start, end: end, fixtureID: weatherFixture.id)
        }

        var prefs = TravelerPreferences.deviceDefaults()
        prefs.homeCountryCode = fixture.homeCountryCode
        prefs.homeCountrySource = .userConfirmed

        let party = Self.party(from: fixture.party)
        let context = TripContext(
            destination: destination,
            startDate: start,
            endDate: end,
            durationDays: math.days,
            durationNights: math.nights,
            tripType: TripType(rawValue: fixture.tripType)!,
            activities: fixture.activities,
            datedActivities: fixture.activities.map { DatedActivity(activityID: $0, date: nil) },
            bagType: BagType(rawValue: fixture.bag)!,
            packingStyle: PackingStyle(rawValue: fixture.style)!,
            transportation: .unknown,
            laundryAccess: LaundryAccess(rawValue: fixture.laundry)!,
            travelerCount: party?.travelers.count ?? 1,
            userNotes: "",
            contextChips: [],
            weather: weather,
            preferences: prefs,
            party: party ?? .solo()
        )

        let existing = (fixture.existing ?? []).map { row in
            PackingItemDraft(
                canonicalItemID: row.canonicalItemID,
                displayName: row.displayName,
                category: PackingCategory(rawValue: row.category) ?? .miscellaneous,
                quantity: row.quantity,
                importance: .normal,
                sourceSignals: [],
                reason: "",
                isUserModified: row.isUserModified
            )
        }
        let overrides = (fixture.overrides ?? []).map {
            RecommendationOverrideDraft(canonicalItemID: $0.canonicalItemID, action: $0.action)
        }

        let generation = engine.generateDetailed(context: context, existing: existing, overrides: overrides)
        return Self.serialize(
            generation,
            fixtureID: fixture.id,
            engineVersion: engineVersion,
            party: context.effectiveParty
        )
    }

    /// "2026-04-06" -> local-midnight Date. Component-based so the frozen day
    /// survives any machine timezone.
    private static func frozenDate(_ value: String) -> Date {
        let parts = value.split(separator: "-").compactMap { Int($0) }
        precondition(parts.count == 3, "Fixture dates must be yyyy-MM-dd, got \(value)")
        return Calendar.current.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))!
    }

    private static func party(from eval: PartyEval?) -> TripParty? {
        guard let eval else { return nil }
        var travelers: [Traveler] = []
        for row in eval.travelers {
            travelers.append(
                Traveler(
                    role: TravelerRole(rawValue: row.role) ?? .otherAdult,
                    ageGroup: AgeGroup(rawValue: row.ageGroup) ?? .adult,
                    chips: Set((row.chips ?? []).compactMap(ContextChip.init(rawValue:))),
                    needs: Set((row.needs ?? []).compactMap(ChildNeed.init(rawValue:)))
                )
            )
        }
        let guardianID = travelers.first { $0.ageGroup.isAdult }?.id
        travelers = travelers.map { traveler in
            guard traveler.ageGroup.isYoungChild else { return traveler }
            var child = traveler
            child.guardianTravelerID = guardianID
            return child
        }
        return TripParty(travelMode: TravelMode(rawValue: eval.travelMode) ?? .family, travelers: travelers)
    }

    // MARK: - Serialization

    /// Everything the diff should see, nothing volatile. UUIDs become stable
    /// role-derived owner slugs; signals are sorted because the engine builds
    /// them in dictionary-iteration order.
    private struct GoldenItem: Codable {
        var owner: String
        var canonicalItemID: String
        var displayName: String
        var category: String
        var quantity: Int
        var importance: String
        var signals: [String]
        var reasonCode: String
        var reason: String
        var quantityReason: String
        var userModified: Bool?
    }

    /// One coverage suppression: the needs the item would have covered and
    /// what covered them instead (empty `coveredBy` = the need was absent).
    private struct GoldenCoverageEntry: Codable {
        var owner: String
        var suppressed: String
        var capabilities: [String]
        var coveredBy: [String]
    }

    private struct GoldenOutput: Codable {
        var fixture: String
        var engineVersion: String
        var items: [GoldenItem]
        var coverage: [GoldenCoverageEntry]?
    }

    private static func serialize(
        _ generation: EngineGeneration,
        fixtureID: String,
        engineVersion: String,
        party: TripParty
    ) -> String {
        let items = generation.items
        var slugs: [UUID: String] = [:]
        var counts: [String: Int] = [:]
        for traveler in party.travelers {
            let base = traveler.role == .self ? "primary" : traveler.role.rawValue
            counts[base, default: 0] += 1
            let count = counts[base]!
            slugs[traveler.id] = count == 1 ? base : "\(base)-\(count)"
        }

        func owner(_ item: PackingItemDraft) -> String {
            if item.ownershipType == .shared { return "shared" }
            guard let id = item.travelerID else { return "primary" }
            return slugs[id] ?? "unknown"
        }

        let golden = GoldenOutput(
            fixture: fixtureID,
            engineVersion: engineVersion,
            items: items
                .map { item in
                    GoldenItem(
                        owner: owner(item),
                        canonicalItemID: item.canonicalItemID ?? "custom:\(item.displayName)",
                        displayName: item.displayName,
                        category: item.category.rawValue,
                        quantity: item.quantity,
                        importance: item.importance.rawValue,
                        signals: item.sourceSignals.map(\.rawValue).sorted(),
                        reasonCode: item.reasonCode,
                        reason: item.reason,
                        quantityReason: item.quantityReason,
                        userModified: item.isUserModified ? true : nil
                    )
                }
                .sorted {
                    if $0.owner != $1.owner { return $0.owner < $1.owner }
                    return $0.canonicalItemID < $1.canonicalItemID
                },
            coverage: generation.coverageSuppressions.isEmpty ? nil : generation.coverageSuppressions
                .map { suppression in
                    GoldenCoverageEntry(
                        owner: suppression.travelerID.flatMap { slugs[$0] } ?? "primary",
                        suppressed: suppression.canonicalItemID,
                        capabilities: suppression.capabilities,
                        coveredBy: suppression.coveredBy
                    )
                }
                .sorted {
                    if $0.owner != $1.owner { return $0.owner < $1.owner }
                    return $0.suppressed < $1.suppressed
                }
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let data = try! encoder.encode(golden)
        return String(decoding: data, as: UTF8.self) + "\n"
    }
}
