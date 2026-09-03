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

    @Test func knownActivitiesAreClassifiedKnown() throws {
        var context = baseContext()
        context.activities = ["sightseeing", "hiking"]
        let snapshot = TripContextCompiler.compile(context, rules: try rules())
        #expect(Set(snapshot.knownActivityIDs) == ["sightseeing", "hiking"])
        #expect(snapshot.unknownActivityIDs.isEmpty)
        #expect(!snapshot.diagnostics.contains { $0.field == "activities" })
    }

    @Test func unrecognizedActivityIsPreservedAndFlaggedUnsupportedButSafe() throws {
        var context = baseContext()
        context.activities = ["sightseeing", "cosplayConvention"]
        let snapshot = TripContextCompiler.compile(context, rules: try rules())
        #expect(snapshot.knownActivityIDs == ["sightseeing"])
        #expect(snapshot.unknownActivityIDs == ["cosplayConvention"]) // preserved verbatim, never dropped
        // Assert kind + a substring of the reason, not full string equality — a
        // later wording polish to the reason text should not break this test.
        let activityDiagnostic = snapshot.diagnostics.first { $0.field == "activities" }
        #expect(activityDiagnostic?.outcome.isUnsupportedButSafe == true)
        if case .unsupportedButSafe(let reason) = activityDiagnostic?.outcome {
            #expect(reason.contains("cosplayConvention"))
        }
    }

    @Test func campingIsHonestlyClassifiedUnknownLikeAnyOtherRulelessActivity() throws {
        // Matches the published Phase 1 finding: camping has no rules.activities
        // entry. The compiler does not special-case it — this is the exact
        // "advertised input with no effect" pattern, and hiding it behind a
        // hardcoded exception would be exactly what the Phase 1 plan forbade
        // ("do not relabel a broken control as context-only to make the report
        // green"). See docs/engine-audits/2026-09-03-engine-findings.md.
        var context = baseContext()
        context.activities = ["hiking", "camping"]
        let snapshot = TripContextCompiler.compile(context, rules: try rules())
        #expect(snapshot.unknownActivityIDs == ["camping"])
    }

    @Test func notSureBagAppliesNoConstraint() throws {
        var context = baseContext()
        context.bagType = .notSure
        let snapshot = TripContextCompiler.compile(context, rules: try rules())
        #expect(snapshot.bagType == .notSure)
        #expect(snapshot.appliesBagConstraint == false)
        #expect(!snapshot.diagnostics.contains { $0.field == "bagType" }) // notSure is valid, not a fallback
    }

    @Test func packingStylePassesThroughUnchanged() throws {
        var context = baseContext()
        context.packingStyle = .prepared
        let snapshot = TripContextCompiler.compile(context, rules: try rules())
        #expect(snapshot.packingStyle == .prepared)
    }

    @Test func laundryPlanMatchesExistingTripContextEquivalenceForEveryLegacyPath() throws {
        let r = try rules()
        var explicit = baseContext(); explicit.laundryAccess = .planned
        var chip = baseContext(); chip.contextChips = [.laundryAvailable]
        var notes = baseContext(); notes.userNotes = "I'll do laundry halfway through"
        let none = baseContext()
        for context in [explicit, chip, notes, none] {
            let snapshot = TripContextCompiler.compile(context, rules: r)
            #expect(snapshot.laundryPlan == context.laundryPlan, "snapshot must never diverge from TripContext.laundryPlan")
        }
    }

    @Test func legacyLaundrySignalIsNormalizedNotJustPassedThrough() throws {
        var context = baseContext()
        context.contextChips = [.laundryAvailable] // legacy chip, no explicit laundryAccess
        let snapshot = TripContextCompiler.compile(context, rules: try rules())
        #expect(snapshot.laundryPlan == .possible)
        #expect(snapshot.diagnostics.contains { $0.field == "laundry" && $0.outcome.isNormalized })
    }

    @Test func missingWeatherIsClassifiedMissing() throws {
        var context = baseContext(); context.weather = nil
        let snapshot = TripContextCompiler.compile(context, rules: try rules())
        #expect(snapshot.weatherQuality == .missing)
    }

    @Test func seasonalWeatherIsClassifiedSeasonalOnly() throws {
        var context = baseContext(); context.weather = .seasonal()
        let snapshot = TripContextCompiler.compile(context, rules: try rules())
        #expect(snapshot.weatherQuality == .seasonalOnly)
    }

    @Test func partialForecastDoesNotClaimWholeTripCoverage() throws {
        var context = baseContext(days: 30)
        var weather = TripWeatherContext.seasonal()
        weather.source = .fixture
        weather.isPreciseForecast = true
        weather.dailyForecast = (0..<10).map { i in
            DailyForecast(date: Calendar.current.date(byAdding: .day, value: i, to: context.startDate)!, symbol: "sun.max", highF: 70, lowF: 50, rainProbability: 0, uvIndex: 3, windMph: 5, snowExpected: false, summary: "")
        }
        weather.forecastAvailableForPartialTrip = true
        weather.forecastAvailableForWholeTrip = false
        context.weather = weather
        let snapshot = TripContextCompiler.compile(context, rules: try rules())
        #expect(snapshot.weatherQuality == .partial(coveredDays: 10, tripDays: 30))
    }

    @Test func wholeTripForecastIsClassifiedComplete() throws {
        var context = baseContext(days: 5)
        var weather = TripWeatherContext.seasonal()
        weather.source = .fixture
        weather.isPreciseForecast = true
        weather.dailyForecast = (0..<5).map { i in
            DailyForecast(date: Calendar.current.date(byAdding: .day, value: i, to: context.startDate)!, symbol: "sun.max", highF: 70, lowF: 50, rainProbability: 0, uvIndex: 3, windMph: 5, snowExpected: false, summary: "")
        }
        weather.forecastAvailableForWholeTrip = true
        context.weather = weather
        let snapshot = TripContextCompiler.compile(context, rules: try rules())
        #expect(snapshot.weatherQuality == .complete)
    }
}
