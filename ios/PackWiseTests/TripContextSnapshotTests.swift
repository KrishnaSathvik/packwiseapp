import Foundation
import Testing
@testable import PackWise

struct TripContextSnapshotTests {
    private func rules() throws -> PackingRulesFile { try SharedLibrary.rules() }

    private func baseContext(
        start: Date = Calendar.current.startOfDay(for: .now),
        days: Int = 5
    ) -> TripContext {
        let end = Calendar.current.date(byAdding: .day, value: days - 1, to: start)!
        let math = TripDateMath.daysAndNights(from: start, to: end)
        return TripContext(
            destination: Destination(
                displayName: "Chicago",
                city: "Chicago",
                region: "IL",
                country: "United States",
                countryCode: "US",
                latitude: 41.8,
                longitude: -87.6,
                timeZone: "America/Chicago",
                mapKitIdentifier: nil,
                fixtureID: nil
            ),
            startDate: start,
            endDate: end,
            durationDays: math.days,
            durationNights: math.nights,
            tripType: .cityBreak,
            activities: ["sightseeing", "walking"],
            datedActivities: [],
            bagType: .carryOn,
            packingStyle: .balanced,
            transportation: .unknown,
            laundryAccess: .none,
            travelerCount: 1,
            userNotes: "",
            contextChips: [],
            weather: nil,
            preferences: .deviceDefaults()
        )
    }

    @Test func validDatesCompileWithNoDiagnostic() throws {
        let snapshot = TripContextCompiler.compile(baseContext(), rules: try rules())
        #expect(snapshot.durationDays == 5)
        #expect(snapshot.durationNights == 4)
        #expect(!snapshot.diagnostics.contains { $0.field == "dates" })
    }

    @Test func mismatchedStoredDurationIsRecomputedAndNormalized() throws {
        var context = baseContext()
        context.durationDays = 999 // stale/incorrect stored value
        let snapshot = TripContextCompiler.compile(context, rules: try rules())
        #expect(snapshot.durationDays == 5) // recomputed from real dates, not trusted verbatim
        #expect(snapshot.diagnostics.contains { $0.field == "dates" && $0.outcome.isNormalized })
    }

    @Test func reversedDatesAreUnsupportedButSafe() throws {
        var context = baseContext()
        let start = context.startDate
        context.endDate = Calendar.current.date(byAdding: .day, value: -3, to: start)!
        let snapshot = TripContextCompiler.compile(context, rules: try rules())
        #expect(snapshot.durationDays == 1) // TripDateMath's existing safe clamp, not a new invention
        #expect(snapshot.durationNights == 0)
        #expect(snapshot.diagnostics.contains { $0.field == "dates" && $0.outcome.isUnsupportedButSafe })
    }

    @Test func compilationIsDeterministicAcrossRepeatedRuns() throws {
        let context = baseContext()
        let r = try rules()
        let first = TripContextCompiler.compile(context, rules: r)
        let second = TripContextCompiler.compile(context, rules: r)
        #expect(first == second)
    }
}
