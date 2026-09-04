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
        let manifestIDs = Set(file.fixtures.map(\.id))
        let goldenIDs = Set(
            try FileManager.default.contentsOfDirectory(at: Self.goldensDirectory, includingPropertiesForKeys: nil)
                .filter { $0.pathExtension == "json" }
                .map { $0.deletingPathExtension().lastPathComponent }
        )
        #expect(
            manifestIDs == goldenIDs,
            "Fixture manifest and golden files must match 1:1. Manifest-only: \(manifestIDs.subtracting(goldenIDs)); golden-only: \(goldenIDs.subtracting(manifestIDs))."
        )
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

    /// The schema carries stable evidence beyond the rendered reason string:
    /// who is on the hook to carry an item (distinct from who owns it), and
    /// the structured arguments the reason template was filled with.
    @Test func goldenSchemaCapturesCarrierReasonsAndClothingQuantityEvidence() throws {
        let output = try renderFixture(id: "11-couple-5d-rain")
        // Fixture 11 is a couple trip where every personal item is
        // self-carried; sorted-first non-shared item is the partner's
        // daypack, so the golden slug must resolve to "partner" exactly —
        // not merely "non-empty", which a hardcoded "unassigned" would
        // also satisfy.
        let firstOwned = try #require(output.items.first { $0.owner != "shared" })
        #expect(firstOwned.owner == "partner")
        #expect(firstOwned.carrier == "partner")
        #expect(output.items.contains { !$0.reasonArguments.isEmpty })
        #expect(output.items.contains { $0.category == "clothing" && $0.quantityEvidence != nil })
    }

    @Test func phase3RequiredFixturesHoldClothingQuantityContracts() throws {
        func item(_ id: String, owner: String = "primary", in output: GoldenOutput) throws -> GoldenItem {
            try #require(output.items.first { $0.owner == owner && $0.canonicalItemID == id })
        }

        let planned15 = try renderFixture(id: "02b-tokyo-15d-light-laundry-planned")
        let none15 = try renderFixture(id: "03-tokyo-15d-light-laundry-none")
        let planned30 = try renderFixture(id: "05-tokyo-30d-light-laundry-planned")
        for id in ["clothing.pants", "clothing.sleepwear", "clothing.socks", "clothing.tshirt", "clothing.underwear"] {
            let fifteen = try item(id, in: planned15)
            let thirty = try item(id, in: planned30)
            let noLaundry = try item(id, in: none15)
            #expect(abs(thirty.quantity - fifteen.quantity) <= 1, "\(id) must plateau once the planned wash cycle dominates")
            #expect(fifteen.quantity <= noLaundry.quantity, "\(id) planned laundry must not exceed no laundry")
            #expect(fifteen.quantityEvidence?.laundryPlan == .planned)
            if id != "clothing.sleepwear" {
                #expect(fifteen.quantityEvidence?.laundryReduced == true)
            }
        }

        let longPlanned = try renderFixture(id: "18-reykjavik-64d-roadtrip-camping-seasonal")
        #expect(try item("clothing.underwear", in: longPlanned).quantity == 8)
        #expect(try item("clothing.tshirt", in: longPlanned).quantity == 7)

        let oneDay = try renderFixture(id: "10-one-day-trip")
        #expect(try item("clothing.underwear", in: oneDay).quantity == 2)
        #expect(try item("clothing.tshirt", in: oneDay).quantity == 2)

        let miami = try renderFixture(id: "06-miami-5d-beach-personal-item")
        let swimsuit = try item("clothing.swimsuit", in: miami)
        #expect(swimsuit.quantity == 2)
        #expect(swimsuit.quantityEvidence?.basis == "dryingRotation")

        let chicago = try renderFixture(id: "07-chicago-5d-business-checked")
        let businessTop = try item("clothing.tshirt", in: chicago)
        #expect(businessTop.quantity == 4)
        #expect(businessTop.quantityEvidence?.appearanceOffsetUses == 3)

        let runningBusiness = try renderFixture(id: "22-chicago-5d-business-running-overlap")
        #expect(try item("clothing.workout_top", in: runningBusiness).quantity == 2)
        #expect(try item("clothing.workout_bottom", in: runningBusiness).quantity == 2)

        let family = try renderFixture(id: "12-family-toddler-7d-seasonal")
        #expect(try item("clothing.tshirt", owner: "child", in: family).quantityEvidence?.ageMultiplier == 1.75)

        let manual = try renderFixture(id: "14-manual-quantity-survives-refresh")
        let manualTop = try item("clothing.tshirt", in: manual)
        #expect(manualTop.quantity == 3)
        #expect(manualTop.userModified == true)
        #expect(manualTop.quantityEvidence == nil)
    }

    @Test func phase4RequiredFixturesHoldCoverageContracts() throws {
        func ids(_ output: GoldenOutput) -> Set<String> {
            Set(output.items.map(\.canonicalItemID))
        }
        func coverage(_ suppressed: String, in output: GoldenOutput) throws -> GoldenCoverageEntry {
            try #require(output.coverage?.first { $0.suppressed == suppressed })
        }

        let running = try renderFixture(id: "08-running-sightseeing-footwear")
        #expect(ids(running).contains("footwear.running_shoes"))
        #expect(!ids(running).contains("footwear.walking_shoes"))
        #expect(try coverage("footwear.walking_shoes", in: running).coveredCapabilities == [
            PackingCapability.everydayWalking.rawValue: "footwear.running_shoes"
        ])

        let hiking = try renderFixture(id: "18-reykjavik-64d-roadtrip-camping-seasonal")
        #expect(ids(hiking).contains("footwear.hiking_shoes"))
        #expect(!ids(hiking).contains("footwear.walking_shoes"))
        #expect(try coverage("footwear.walking_shoes", in: hiking).coveredCapabilities == [
            PackingCapability.everydayWalking.rawValue: "footwear.hiking_shoes"
        ])

        let business = try renderFixture(id: "07-chicago-5d-business-checked")
        #expect(ids(business).isSuperset(of: ["footwear.dress_shoes", "footwear.walking_shoes"]))

        let rain = try renderFixture(id: "09-seattle-rain-layering")
        #expect(ids(rain).isSuperset(of: ["clothing.rain_jacket", "clothing.light_sweater"]))
        #expect(ids(rain).isDisjoint(with: ["clothing.windbreaker", "clothing.light_jacket"]))

        let ski = try renderFixture(id: "21-aspen-5d-skisnow-checked-prepared-snow")
        #expect(ids(ski).isSuperset(of: [
            "activities.ski_gloves", "clothing.winter_coat", "clothing.light_sweater", "footwear.boots"
        ]))
        #expect(!ids(ski).contains("clothing.gloves"))
        #expect(try coverage("clothing.gloves", in: ski).coveredCapabilities == [
            PackingCapability.coldHands.rawValue: "activities.ski_gloves"
        ])

        let existingShell = try renderFixture(id: "26-seattle-5d-existing-rain-shell")
        let shellRows = existingShell.items.filter { $0.canonicalItemID == "clothing.rain_jacket" }
        #expect(shellRows.count == 1)
        #expect(shellRows.first?.userModified == true)
        #expect(!ids(existingShell).contains("clothing.windbreaker"))
    }

    /// Full-ledger proof that `TripContextCompiler` compiles every real,
    /// fixture-derived trip in the golden ledger deterministically and
    /// without crashing. Every one of the 27 fixtures is a real, well-formed
    /// trip, so none should produce an "unsupportedButSafe" `dates` or
    /// `party` diagnostic. Fixtures 18 and 25 (camping, cosplayConvention)
    /// are EXPECTED to carry an "activities" diagnostic — that's the honest,
    /// already-published Phase 1 finding (see
    /// docs/engine-audits/2026-09-03-engine-findings.md), not a defect this
    /// test introduces.
    @Test func everyGoldenFixtureCompilesToADeterministicSnapshot() throws {
        let file = try JSONDecoder().decode(
            GoldenFixtureFile.self,
            from: Data(contentsOf: Self.fixturesFile)
        )
        let rules = try SharedLibrary.rules()
        let destinations = try SharedLibrary.testDestinations()
        let weatherFixtures = try SharedLibrary.weatherFixtures()

        for fixture in file.fixtures {
            let context = try buildContext(fixture: fixture, destinations: destinations, weatherFixtures: weatherFixtures)
            let first = TripContextCompiler.compile(context, rules: rules)
            let second = TripContextCompiler.compile(context, rules: rules)
            #expect(first == second, "\(fixture.id): compilation must be deterministic")
            let unexpectedDiagnostics = first.diagnostics.filter { $0.field != "activities" }
            #expect(unexpectedDiagnostics.isEmpty, "\(fixture.id): unexpected diagnostic \(unexpectedDiagnostics)")
        }
    }

    /// Renders one fixture by ID, decoded back into the golden schema — for
    /// schema-focused tests that don't need the full matrix comparison.
    private func renderFixture(id: String) throws -> GoldenOutput {
        let file = try JSONDecoder().decode(
            GoldenFixtureFile.self,
            from: Data(contentsOf: Self.fixturesFile)
        )
        guard let fixture = file.fixtures.first(where: { $0.id == id }) else {
            throw ResourceError.missing("fixture \(id)")
        }
        let engine = PackingEngine(catalog: try SharedLibrary.catalog(), rules: try SharedLibrary.rules())
        let destinations = try SharedLibrary.testDestinations()
        let weatherFixtures = try SharedLibrary.weatherFixtures()
        let json = try render(
            fixture: fixture,
            engineVersion: file.engineVersion,
            engine: engine,
            destinations: destinations,
            weatherFixtures: weatherFixtures
        )
        return try JSONDecoder().decode(GoldenOutput.self, from: Data(json.utf8))
    }

    // MARK: - Context construction

    /// Builds the `TripContext` a given fixture describes — the same
    /// construction `render` feeds into `engine.generateDetailed`, factored
    /// out so other tests (e.g. the full-ledger snapshot-compilation test)
    /// can reuse it without duplicating destination/weather/party resolution.
    private func buildContext(
        fixture: GoldenFixture,
        destinations: [Destination],
        weatherFixtures: [String: WeatherFixture]
    ) throws -> TripContext {
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
        return TripContext(
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
    }

    private func render(
        fixture: GoldenFixture,
        engineVersion: String,
        engine: PackingEngine,
        destinations: [Destination],
        weatherFixtures: [String: WeatherFixture]
    ) throws -> String {
        let context = try buildContext(fixture: fixture, destinations: destinations, weatherFixtures: weatherFixtures)

        let existing = (fixture.existing ?? []).map { row in
            PackingItemDraft(
                canonicalItemID: row.canonicalItemID,
                displayName: row.displayName,
                category: PackingCategory(rawValue: row.category) ?? .miscellaneous,
                quantity: row.quantity,
                importance: .normal,
                sourceSignals: [],
                reason: "",
                isUserAdded: row.isUserAdded ?? false,
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
        /// Who is responsible for bringing the item — distinct from `owner`,
        /// which is whose item it is. "unassigned" when no traveler is
        /// assigned (e.g. shared items); "unknown" if a traveler is
        /// assigned but the ID doesn't resolve to a slug — a dangling
        /// reference that should surface in the diff, not be silently
        /// folded into "unassigned". Never a raw UUID.
        var carrier: String
        var canonicalItemID: String
        var displayName: String
        var category: String
        var quantity: Int
        var importance: String
        var signals: [String]
        var reasonCode: String
        /// The structured values the reason template was filled with (e.g.
        /// rain day counts). Empty when the reason carries no arguments.
        var reasonArguments: [String: String]
        var reason: String
        var quantityReason: String
        var quantityEvidence: ClothingQuantityEvidence?
        var userModified: Bool?
    }

    /// One coverage suppression: the needs the item would have covered and
    /// what covered them instead (empty `coveredBy` = the need was absent).
    private struct GoldenCoverageEntry: Codable {
        var owner: String
        var suppressed: String
        var capabilities: [String]
        var coveredBy: [String]
        var coveredCapabilities: [String: String]?
        var refutedCapabilities: [String]?
    }

    /// One recorded constraint resolution: the machine key, the one-sentence
    /// user-terms summary, and the canonical IDs it removed.
    private struct GoldenConstraintEntry: Codable {
        var owner: String
        var constraint: String
        var summary: String
        var items: [String]
    }

    private struct GoldenOutput: Codable {
        var fixture: String
        var engineVersion: String
        var items: [GoldenItem]
        var coverage: [GoldenCoverageEntry]?
        var constraints: [GoldenConstraintEntry]?
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

        func carrier(_ item: PackingItemDraft) -> String {
            guard let id = item.assignedTravelerID else { return "unassigned" }
            return slugs[id] ?? "unknown"
        }

        let golden = GoldenOutput(
            fixture: fixtureID,
            engineVersion: engineVersion,
            items: items
                .map { item in
                    GoldenItem(
                        owner: owner(item),
                        carrier: carrier(item),
                        canonicalItemID: item.canonicalItemID ?? "custom:\(item.displayName)",
                        displayName: item.displayName,
                        category: item.category.rawValue,
                        quantity: item.quantity,
                        importance: item.importance.rawValue,
                        signals: item.sourceSignals.map(\.rawValue).sorted(),
                        reasonCode: item.reasonCode,
                        reasonArguments: item.reasonArguments,
                        reason: item.reason,
                        quantityReason: item.quantityReason,
                        quantityEvidence: item.quantityEvidence,
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
                        coveredBy: suppression.coveredBy,
                        coveredCapabilities: suppression.covered.isEmpty ? nil : Dictionary(
                            uniqueKeysWithValues: suppression.covered.map {
                                ($0.capability.rawValue, $0.coveringItemID)
                            }
                        ),
                        refutedCapabilities: suppression.refutedCapabilities.isEmpty ? nil : suppression
                            .refutedCapabilities.map(\.rawValue).sorted()
                    )
                }
                .sorted {
                    if $0.owner != $1.owner { return $0.owner < $1.owner }
                    return $0.suppressed < $1.suppressed
                },
            constraints: generation.constraintDecisions.isEmpty ? nil : generation.constraintDecisions
                .map { decision in
                    GoldenConstraintEntry(
                        owner: decision.travelerID.flatMap { slugs[$0] } ?? "primary",
                        constraint: decision.constraint,
                        summary: decision.summary,
                        items: decision.items
                    )
                }
                .sorted {
                    if $0.owner != $1.owner { return $0.owner < $1.owner }
                    return $0.constraint < $1.constraint
                }
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let data = try! encoder.encode(golden)
        return String(decoding: data, as: UTF8.self) + "\n"
    }
}
