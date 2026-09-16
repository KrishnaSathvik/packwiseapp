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
            tripTypes: [.cityBreak],
            activities: ["sightseeing", "walking"],
            datedActivities: [],
            bagTypes: [.carryOn],
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

    @Test func coverageInputsPassThroughWithoutWeatherReinterpretation() throws {
        var context = baseContext()
        context.contextChips = [.runWhileTraveling, .needFormalOutfit]
        let weatherFixture = try #require(try SharedLibrary.weatherFixtures()["ChicagoRainyFall"])
        context.weather = MockWeatherService.context(
            from: weatherFixture,
            start: context.startDate,
            end: context.endDate,
            fixtureID: weatherFixture.id
        )

        let first = TripContextCompiler.compile(context, rules: try rules())
        let second = TripContextCompiler.compile(context, rules: try rules())

        #expect(first.contextChips == context.contextChips)
        #expect(first.weather == context.weather)
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

    @Test func knownDatedActivitiesCountDistinctTripDates() throws {
        var context = baseContext()
        let secondDate = Calendar.current.date(byAdding: .day, value: 2, to: context.startDate)!
        context.activities = ["running"]
        context.datedActivities = [
            DatedActivity(activityID: "running", date: context.startDate),
            DatedActivity(activityID: "running", date: context.startDate),
            DatedActivity(activityID: "running", date: secondDate)
        ]

        let snapshot = TripContextCompiler.compile(context, rules: try rules())

        #expect(snapshot.knownDatedActivityUses["running"] == 2)
    }

    @Test func undatedAndOutOfTripActivitiesDoNotManufactureUses() throws {
        var context = baseContext()
        let outsideTrip = Calendar.current.date(byAdding: .day, value: 10, to: context.startDate)!
        context.activities = ["running"]
        context.datedActivities = [
            DatedActivity(activityID: "running", date: nil),
            DatedActivity(activityID: "running", date: outsideTrip)
        ]

        let snapshot = TripContextCompiler.compile(context, rules: try rules())

        #expect(snapshot.knownDatedActivityUses["running"] == nil)
    }

    @Test func unknownDatedActivityNeverEntersKnownUseCounts() throws {
        var context = baseContext()
        context.activities = ["cosplayConvention"]
        context.datedActivities = [
            DatedActivity(activityID: "cosplayConvention", date: context.startDate)
        ]

        let snapshot = TripContextCompiler.compile(context, rules: try rules())

        #expect(snapshot.knownDatedActivityUses["cosplayConvention"] == nil)
        #expect(snapshot.unknownActivityIDs == ["cosplayConvention"])
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

    /// Phase 5 gives camping a real contract, so it joins the known
    /// vocabulary. A genuinely unknown id must still degrade inertly — the
    /// Phase 1 finding was closed by giving camping an effect, not by
    /// special-casing the classifier.
    @Test func campingIsKnownWhileGenuinelyUnknownActivitiesStayUnknown() throws {
        var context = baseContext()
        context.activities = ["hiking", "camping", "cosplayConvention"]
        let snapshot = TripContextCompiler.compile(context, rules: try rules())

        #expect(snapshot.knownActivityIDs == ["hiking", "camping"])
        #expect(snapshot.unknownActivityIDs == ["cosplayConvention"])
        #expect(snapshot.diagnostics.contains(ContextDiagnostic(
            field: "activities",
            outcome: .unsupportedButSafe(reason: "cosplayConvention: no rule in the engine's activity vocabulary")
        )))
    }

    @Test func notSureBagAppliesNoConstraint() throws {
        var context = baseContext()
        context.bagTypes = [] // "Not sure yet" is the empty bag set
        let snapshot = TripContextCompiler.compile(context, rules: try rules())
        #expect(snapshot.bagTypes.isEmpty)
        #expect(snapshot.luggage.capacity == .unspecified)
        #expect(snapshot.luggage.appliesCapacityConstraint == false)
        #expect(!snapshot.diagnostics.contains { $0.field.hasPrefix("bag") }) // not sure is valid, not a fallback
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

    @Test func cacheSourceDoesNotChangeWeatherQualityFromLiveCoverage() throws {
        // Pins the deliberate divergence from `TripWeatherContext.state()`:
        // `.cache` is produced by `markingAsCache()` from a real prior fetch,
        // so it always carries that fetch's actual coverage data.
        // `weatherQuality` tracks structural coverage only, not staleness —
        // flipping the source to `.cache` must not change the classification
        // `state()`'s unconditional `.cache` -> `.failedUsingCache` mapping
        // would otherwise suggest.
        var context = baseContext(days: 5)
        var weather = TripWeatherContext.seasonal()
        weather.source = .fixture
        weather.isPreciseForecast = true
        weather.dailyForecast = (0..<5).map { i in
            DailyForecast(date: Calendar.current.date(byAdding: .day, value: i, to: context.startDate)!, symbol: "sun.max", highF: 70, lowF: 50, rainProbability: 0, uvIndex: 3, windMph: 5, snowExpected: false, summary: "")
        }
        weather.forecastAvailableForWholeTrip = true
        context.weather = weather
        let liveSnapshot = TripContextCompiler.compile(context, rules: try rules())
        #expect(liveSnapshot.weatherQuality == .complete)

        context.weather = weather.markingAsCache()
        let cachedSnapshot = TripContextCompiler.compile(context, rules: try rules())
        #expect(cachedSnapshot.weatherQuality == .complete) // unchanged by the source flip
    }

    @Test func emptyPartyIsAlreadySafeViaEffectiveParty() throws {
        var context = baseContext()
        context.party = TripParty(travelMode: .solo, travelers: [])
        let snapshot = TripContextCompiler.compile(context, rules: try rules())
        #expect(snapshot.party.travelers.count == 1)
        #expect(snapshot.party.travelers.first?.role == .self)
    }

    @Test func childWithGuardianOutsidePartyLosesTheReferenceRatherThanGuessing() throws {
        var context = baseContext()
        let ghostGuardianID = UUID() // not a real party member
        let child = Traveler(role: .child, ageGroup: .child, packingResponsibility: .guardian, guardianTravelerID: ghostGuardianID)
        context.party = TripParty(travelMode: .family, travelers: [.primarySelf(), child])
        let snapshot = TripContextCompiler.compile(context, rules: try rules())
        let normalizedChild = snapshot.party.travelers.first { $0.role == .child }
        #expect(normalizedChild?.guardianTravelerID == nil) // dropped, never reassigned to a guessed adult
        #expect(snapshot.diagnostics.contains { $0.field == "party" && $0.outcome.isUnsupportedButSafe })
    }

    @Test func ambiguousGuardianAmongMultipleAdultsIsNeverInferred() throws {
        var context = baseContext()
        let child = Traveler(role: .child, ageGroup: .child, packingResponsibility: .guardian, guardianTravelerID: nil)
        let extraAdult = Traveler(role: .otherAdult, ageGroup: .adult)
        context.party = TripParty(travelMode: .family, travelers: [.primarySelf(), extraAdult, child])
        let snapshot = TripContextCompiler.compile(context, rules: try rules())
        let normalizedChild = snapshot.party.travelers.first { $0.role == .child }
        #expect(normalizedChild?.guardianTravelerID == nil) // still nil — the compiler must not default to "the first adult"
        #expect(!snapshot.diagnostics.contains { $0.field == "party" }) // nil guardian is not itself a violation
    }

    @Test func validPartyPassesThroughWithNoDiagnostic() throws {
        var context = baseContext()
        let primary = Traveler.primarySelf()
        let child = Traveler(role: .child, ageGroup: .child, packingResponsibility: .guardian, guardianTravelerID: primary.id)
        context.party = TripParty(travelMode: .family, travelers: [primary, child])
        let snapshot = TripContextCompiler.compile(context, rules: try rules())
        #expect(snapshot.party.travelers.count == 2)
        #expect(snapshot.party.travelers.first { $0.role == .child }?.guardianTravelerID == primary.id)
        #expect(!snapshot.diagnostics.contains { $0.field == "party" })
    }

    @Test func guardianNotAllowedOnAdultTravelerIsAlsoDropped() throws {
        // An adult with a (structurally nonsensical) guardianTravelerID set —
        // AgeGroup.allowsGuardian is false for .adult, so this is the
        // guardianNotAllowed violation, not guardianNotInParty. Must be
        // stripped just like the other two guardian violation kinds.
        var context = baseContext()
        let primary = Traveler.primarySelf()
        var strangeAdult = Traveler(role: .otherAdult, ageGroup: .adult)
        strangeAdult.guardianTravelerID = primary.id
        context.party = TripParty(travelMode: .family, travelers: [primary, strangeAdult])
        let snapshot = TripContextCompiler.compile(context, rules: try rules())
        let normalized = snapshot.party.travelers.first { $0.id == strangeAdult.id }
        #expect(normalized?.guardianTravelerID == nil)
        #expect(snapshot.diagnostics.contains { $0.field == "party" && $0.outcome.isUnsupportedButSafe })
    }

    @Test func guardianNotAdultIsDroppedNotReassigned() throws {
        // Guardian reference points at a real party member who is not an
        // adult (e.g. a teen sibling) — guardianNotAdult violation.
        var context = baseContext()
        let primary = Traveler.primarySelf()
        let teenSibling = Traveler(role: .otherAdult, ageGroup: .teen)
        let child = Traveler(role: .child, ageGroup: .child, packingResponsibility: .guardian, guardianTravelerID: teenSibling.id)
        context.party = TripParty(travelMode: .family, travelers: [primary, teenSibling, child])
        let snapshot = TripContextCompiler.compile(context, rules: try rules())
        let normalizedChild = snapshot.party.travelers.first { $0.role == .child }
        #expect(normalizedChild?.guardianTravelerID == nil) // never reassigned to `primary`, either
        #expect(snapshot.diagnostics.contains { $0.field == "party" && $0.outcome.isUnsupportedButSafe })
    }

    @Test func partyCompilationIsDeterministicAcrossRepeatedRuns() throws {
        var context = baseContext()
        let ghostGuardianID = UUID()
        let child = Traveler(role: .child, ageGroup: .child, packingResponsibility: .guardian, guardianTravelerID: ghostGuardianID)
        context.party = TripParty(travelMode: .family, travelers: [.primarySelf(), child])
        let r = try rules()
        let first = TripContextCompiler.compile(context, rules: r)
        let second = TripContextCompiler.compile(context, rules: r)
        #expect(first == second)
    }
}
