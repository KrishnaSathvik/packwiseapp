import Foundation
import SwiftData
import Testing
@testable import PackWise

struct WeatherChangeTests {
    private func rules() throws -> PackingRulesFile { try SharedLibrary.rules() }
    private func engine() throws -> PackingEngine {
        PackingEngine(catalog: try SharedLibrary.catalog(), rules: try rules())
    }

    private func destination(_ name: String) throws -> Destination {
        try SharedLibrary.testDestinations().first { $0.city == name }!
    }

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Chicago")!
        return calendar
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }

    private func forecast(
        start: Date,
        days: Int,
        high: Double,
        low: Double,
        rain: Double,
        rainOnDay: Int? = nil,
        uv: Double = 4,
        wind: Double = 8,
        snow: Bool = false
    ) -> TripWeatherContext {
        let daily: [DailyForecast] = (0..<days).map { index in
            let day = calendar.date(byAdding: .day, value: index, to: start)!
            let raining = rainOnDay == index ? rain : (rainOnDay == nil ? rain : 0.1)
            return DailyForecast(
                date: calendar.startOfDay(for: day),
                symbol: raining >= 0.35 ? "cloud.rain" : "sun.max",
                highF: high,
                lowF: low,
                rainProbability: raining,
                uvIndex: uv,
                windMph: wind,
                snowExpected: snow,
                summary: raining >= 0.35 ? "Rain" : "Sunny"
            )
        }
        let rainDays = daily.filter { $0.rainProbability >= 0.35 }.count
        return TripWeatherContext(
            minTemperatureF: daily.map(\.lowF).min() ?? low,
            maxTemperatureF: daily.map(\.highF).max() ?? high,
            dailyForecast: daily,
            rainDays: rainDays,
            heavyRainDays: daily.filter { $0.rainProbability >= 0.6 }.count,
            snowDays: daily.filter(\.snowExpected).count,
            outdoorRainOverlapDays: rainDays,
            maxDailyTemperatureSwing: daily.map(\.swingF).max() ?? 0,
            uvRange: daily.map(\.uvIndex).max() ?? 0,
            windRange: daily.map(\.windMph).max() ?? 0,
            weatherSummary: "Test",
            fetchedAt: start,
            providerFetchedAt: start,
            providerExpiresAt: calendar.date(byAdding: .hour, value: 1, to: start),
            coverageStart: daily.first?.date,
            coverageEnd: daily.last?.date,
            forecastAvailableForWholeTrip: true,
            forecastAvailableForPartialTrip: false,
            isPreciseForecast: true,
            source: .fixture,
            fixtureID: "test",
            alerts: [],
            attribution: nil
        )
    }

    private func context(weather: TripWeatherContext?, days: Int = 5) throws -> TripContext {
        let start = date(2026, 9, 12)
        let end = calendar.date(byAdding: .day, value: days - 1, to: start)!
        var prefs = TravelerPreferences.deviceDefaults()
        prefs.homeCountryCode = "US"
        prefs.homeCountrySource = .userConfirmed
        let math = TripDateMath.daysAndNights(from: start, to: end, calendar: calendar)
        return TripContext(
            destination: try destination("Chicago"),
            startDate: start,
            endDate: end,
            durationDays: math.days,
            durationNights: math.nights,
            tripType: .cityBreak,
            activities: ["sightseeing", "walking"],
            datedActivities: ["sightseeing", "walking"].map { DatedActivity(activityID: $0, date: nil) },
            bagType: .carryOn,
            packingStyle: .light,
            transportation: .unknown,
            laundryAccess: .planned,
            travelerCount: 1,
            userNotes: "",
            contextChips: [.laundryAvailable],
            weather: weather,
            preferences: prefs
        )
    }

    private func reconcile(
        old: TripWeatherContext?,
        new: TripWeatherContext,
        existing: [PackingItemDraft],
        overrides: [RecommendationOverrideDraft] = [],
        ctx: TripContext
    ) throws -> WeatherRefreshOutcome {
        var next = ctx
        next.weather = new
        let rules = try rules()
        return WeatherChangeReconciler.reconcile(
            tripID: UUID(),
            oldWeather: old,
            newWeather: new,
            context: next,
            existing: existing,
            overrides: overrides,
            engine: try engine(),
            thresholds: rules.weather.thresholds,
            templates: rules.reasons.templates,
            now: date(2026, 8, 29)
        )
    }

    @Test func twoDegreeDropIsNotAPackingChange() throws {
        let start = date(2026, 9, 12)
        let warmer = forecast(start: start, days: 5, high: 72, low: 64, rain: 0.1)
        let cooler = forecast(start: start, days: 5, high: 69, low: 64, rain: 0.1)
        let existing = try engine().generate(context: context(weather: warmer))
        let outcome = try reconcile(old: warmer, new: cooler, existing: existing, ctx: context(weather: cooler))
        #expect(outcome == .snapshotOnly)
        let oldSignals = WeatherSignalDiffer.packingConditions(
            weather: warmer,
            tripDays: 5,
            outdoorActivities: true,
            thresholds: try rules().weather.thresholds
        ).signals
        let newSignals = WeatherSignalDiffer.packingConditions(
            weather: cooler,
            tripDays: 5,
            outdoorActivities: true,
            thresholds: try rules().weather.thresholds
        ).signals
        #expect(oldSignals == newSignals)
    }

    @Test func rainAppearingCreatesPendingAddProposal() throws {
        let start = date(2026, 9, 12)
        let dry = forecast(start: start, days: 5, high: 75, low: 64, rain: 0.1)
        let wet = forecast(start: start, days: 5, high: 75, low: 64, rain: 0.7, rainOnDay: 0)
        let existing = try engine().generate(context: context(weather: dry))
        #expect(!existing.contains { $0.canonicalItemID == "clothing.rain_jacket" })
        let outcome = try reconcile(old: dry, new: wet, existing: existing, ctx: context(weather: wet))
        guard case .proposal(let proposal) = outcome else {
            Issue.record("Expected a weather-change proposal")
            return
        }
        #expect(proposal.status == .pending)
        #expect(proposal.signalChanges.contains { $0.signal == .meaningfulRain && $0.appeared })
        #expect(proposal.diff.add.contains { $0.canonicalItemID == "clothing.rain_jacket" })
        #expect(proposal.headline.localizedCaseInsensitiveContains("rain"))
        #expect(proposal.diff.removeCandidates.isEmpty || proposal.status == .pending)
    }

    @Test func extraRainDayWithoutNewSignalDoesNotPropose() throws {
        let start = date(2026, 9, 12)
        let oneRain = forecast(start: start, days: 5, high: 75, low: 64, rain: 0.7, rainOnDay: 0)
        var twoRain = oneRain
        twoRain.dailyForecast[1].rainProbability = 0.7
        twoRain.rainDays = 2
        let existing = try engine().generate(context: context(weather: oneRain))
        let outcome = try reconcile(old: oneRain, new: twoRain, existing: existing, ctx: context(weather: twoRain))
        #expect(outcome == .snapshotOnly)
    }

    @Test func notNeededRainJacketIsNotRestored() throws {
        let start = date(2026, 9, 12)
        let dry = forecast(start: start, days: 5, high: 75, low: 64, rain: 0.1)
        let wet = forecast(start: start, days: 5, high: 75, low: 64, rain: 0.7, rainOnDay: 0)
        let existing = try engine().generate(context: context(weather: dry))
        let overrides = [RecommendationOverrideDraft(canonicalItemID: "clothing.rain_jacket", action: "removed")]
        let outcome = try reconcile(old: dry, new: wet, existing: existing, overrides: overrides, ctx: context(weather: wet))
        guard case .proposal(let proposal) = outcome else {
            Issue.record("Expected a proposal for remaining rain items")
            return
        }
        #expect(!proposal.diff.add.contains { $0.canonicalItemID == "clothing.rain_jacket" })
    }

    @Test func customPackedAndModifiedItemsArePreserved() throws {
        let start = date(2026, 9, 12)
        let dry = forecast(start: start, days: 5, high: 75, low: 64, rain: 0.1)
        let wet = forecast(start: start, days: 5, high: 75, low: 64, rain: 0.7, rainOnDay: 0)
        var existing = try engine().generate(context: context(weather: dry))
        if let index = existing.firstIndex(where: { $0.canonicalItemID == "clothing.tshirt" }) {
            existing[index].packedQuantity = existing[index].quantity
        }
        if let index = existing.firstIndex(where: { $0.canonicalItemID == "clothing.pants" }) {
            existing[index].isUserModified = true
            existing[index].quantity = 9
        }
        existing.append(
            PackingItemDraft(
                canonicalItemID: nil,
                displayName: "Portable fan",
                category: .travelComfort,
                quantity: 1,
                packedQuantity: 1,
                importance: .optional,
                sourceSignals: [.userPreference],
                reason: "Added by you",
                isUserAdded: true
            )
        )
        let outcome = try reconcile(old: dry, new: wet, existing: existing, ctx: context(weather: wet))
        guard case .proposal(let proposal) = outcome else {
            Issue.record("Expected a proposal")
            return
        }
        #expect(!proposal.diff.removeCandidates.contains { $0.displayName == "Portable fan" })
        #expect(!proposal.diff.quantityChanges.contains { $0.existing.canonicalItemID == "clothing.pants" })
        #expect(existing.contains { $0.canonicalItemID == "clothing.tshirt" && $0.isPacked })
    }

    @Test func removalsStaySuggestionsNotAutoApplied() throws {
        let start = date(2026, 9, 12)
        let wetCool = forecast(start: start, days: 5, high: 60, low: 48, rain: 0.7, rainOnDay: 0)
        let dryWarm = forecast(start: start, days: 5, high: 85, low: 70, rain: 0.1)
        let existing = try engine().generate(context: context(weather: wetCool))
        #expect(existing.contains { $0.canonicalItemID == "clothing.rain_jacket" })
        let outcome = try reconcile(old: wetCool, new: dryWarm, existing: existing, ctx: context(weather: dryWarm))
        guard case .proposal(let proposal) = outcome else {
            Issue.record("Expected a removal suggestion proposal")
            return
        }
        #expect(proposal.diff.removeCandidates.contains { $0.canonicalItemID == "clothing.rain_jacket" })
        #expect(proposal.status == .pending)
        #expect(existing.contains { $0.canonicalItemID == "clothing.rain_jacket" })
    }

    @Test func seasonalToForecastCanPropose() throws {
        let start = date(2026, 9, 12)
        let seasonal = TripWeatherContext.seasonal(fetchedAt: start)
        let wet = forecast(start: start, days: 5, high: 75, low: 64, rain: 0.7, rainOnDay: 0)
        let existing = try engine().generate(context: context(weather: nil))
        let outcome = try reconcile(old: seasonal, new: wet, existing: existing, ctx: context(weather: wet))
        guard case .proposal(let proposal) = outcome else {
            Issue.record("Expected a proposal when a seasonal trip gains a rain forecast")
            return
        }
        #expect(proposal.signalChanges.contains { $0.appeared })
        #expect(proposal.status == .pending)
    }

    @Test func completedTripsDoNotRefresh() {
        let start = date(2026, 9, 12)
        let weather = forecast(start: start, days: 5, high: 75, low: 64, rain: 0.1)
        #expect(
            !WeatherRefreshPolicy.shouldFetch(
                existing: weather,
                tripStart: start,
                tripStatus: .completed,
                now: date(2026, 8, 29)
            )
        )
        #expect(
            WeatherRefreshPolicy.shouldFetch(
                existing: nil,
                tripStart: start,
                tripStatus: .packing,
                now: date(2026, 8, 29)
            )
        )
        #expect(
            !WeatherRefreshPolicy.shouldFetch(
                existing: weather,
                tripStart: start,
                tripStatus: .packing,
                now: date(2026, 8, 29)
            )
        )
    }

    @Test func proposalCarriesTripContextSignature() throws {
        let start = date(2026, 9, 12)
        let dry = forecast(start: start, days: 5, high: 75, low: 64, rain: 0.1)
        let wet = forecast(start: start, days: 5, high: 75, low: 64, rain: 0.7, rainOnDay: 0)
        let ctx = try context(weather: wet)
        let existing = try engine().generate(context: try context(weather: dry))
        let outcome = try reconcile(old: dry, new: wet, existing: existing, ctx: ctx)
        guard case .proposal(let proposal) = outcome else {
            Issue.record("Expected a proposal")
            return
        }
        #expect(!proposal.tripContextSignature.isEmpty)
        #expect(proposal.tripContextSignature == WeatherChangeProposalLifecycle.tripContextSignature(ctx))
        #expect(proposal.newSnapshotID == WeatherChangeProposalLifecycle.snapshotID(for: wet))
    }

    @Test func staleTripContextInvalidatesProposal() throws {
        let item = dummyItem("clothing.rain_jacket", "Rain jacket")
        var proposal = dummyProposal(add: [item], signature: "original-trip")
        let stillValid = WeatherChangeProposalLifecycle.evaluate(
            proposal,
            tripContextSignature: "original-trip",
            existing: [],
            overrides: []
        )
        guard case .pending = stillValid else {
            Issue.record("Matching trip context should stay pending")
            return
        }
        #expect(
            WeatherChangeProposalLifecycle.evaluate(
                proposal,
                tripContextSignature: "edited-trip",
                existing: [],
                overrides: []
            ) == .invalidated
        )
        proposal.tripContextSignature = ""
        #expect(
            WeatherChangeProposalLifecycle.evaluate(
                proposal,
                tripContextSignature: "edited-trip",
                existing: [],
                overrides: []
            ) != .invalidated
        )
    }

    @Test func addingSuggestedItemPrunesAndCanInvalidateProposal() throws {
        let jacket = dummyItem("clothing.rain_jacket", "Rain jacket")
        let umbrella = dummyItem("accessories.umbrella", "Compact umbrella")
        let proposal = dummyProposal(add: [jacket, umbrella], signature: "trip")
        let pruned = WeatherChangeProposalLifecycle.evaluate(
            proposal,
            tripContextSignature: "trip",
            existing: [jacket],
            overrides: []
        )
        guard case .pending(let current) = pruned else {
            Issue.record("Remaining umbrella should keep the proposal pending")
            return
        }
        #expect(!current.diff.add.contains { $0.canonicalItemID == "clothing.rain_jacket" })
        #expect(current.diff.add.contains { $0.canonicalItemID == "accessories.umbrella" })
        #expect(
            WeatherChangeProposalLifecycle.evaluate(
                proposal,
                tripContextSignature: "trip",
                existing: [jacket, umbrella],
                overrides: []
            ) == .invalidated
        )
    }

    @Test @MainActor func dismissingProposalDoesNotCreateNotNeeded() throws {
        let start = date(2026, 9, 12)
        let dry = forecast(start: start, days: 5, high: 75, low: 64, rain: 0.1)
        let wet = forecast(start: start, days: 5, high: 75, low: 64, rain: 0.7, rainOnDay: 0)
        let existing = try engine().generate(context: try context(weather: dry))
        let outcome = try reconcile(old: dry, new: wet, existing: existing, ctx: try context(weather: wet))
        guard case .proposal(let proposal) = outcome else {
            Issue.record("Expected a proposal")
            return
        }
        let container = try PackWisePersistence.container(inMemory: true)
        let model = ModelContext(container)
        let trip = try makeTrip(in: model)
        let repo = TripRepository(context: model)
        repo.storeWeather(wet, on: trip)
        repo.replacePendingWeatherChange(proposal, on: trip)
        repo.dismissWeatherChange(proposal, on: trip)
        #expect(trip.overrides.isEmpty)
        #expect(trip.items.isEmpty)
        #expect(trip.weatherSnapshots.first?.weatherContext?.fetchedAt == wet.fetchedAt)
        #expect(trip.weatherChangeProposals.contains { $0.status == .dismissed })
        #expect(!trip.weatherChangeProposals.contains { $0.status == .pending })
    }

    @Test @MainActor func newerRefreshSupersedesPendingProposal() throws {
        let container = try PackWisePersistence.container(inMemory: true)
        let model = ModelContext(container)
        let trip = try makeTrip(in: model)
        let repo = TripRepository(context: model)
        let rain = dummyProposal(
            add: [dummyItem("clothing.rain_jacket", "Rain jacket")],
            signature: WeatherChangeProposalLifecycle.tripContextSignature(
                trip.context(preferences: .deviceDefaults(), weather: nil)
            )
        )
        let snow = dummyProposal(
            add: [
                dummyItem("clothing.rain_jacket", "Rain jacket"),
                dummyItem("clothing.insulated_jacket", "Insulated jacket")
            ],
            signature: rain.tripContextSignature
        )
        repo.replacePendingWeatherChange(rain, on: trip)
        repo.replacePendingWeatherChange(snow, on: trip)
        #expect(trip.weatherChangeProposals.filter { $0.status == .pending }.count == 1)
        #expect(trip.weatherChangeProposals.contains { $0.status == .superseded && $0.id == rain.id })
        #expect(repo.pendingWeatherChange(on: trip)?.id == snow.id)
        repo.replacePendingWeatherChange(snow, on: trip)
        #expect(trip.weatherChangeProposals.filter { $0.status == .pending }.count == 1)
        #expect(repo.pendingWeatherChange(on: trip)?.id == snow.id)
    }

    @Test @MainActor func tripEditInvalidatesPendingWeatherProposal() throws {
        let container = try PackWisePersistence.container(inMemory: true)
        let model = ModelContext(container)
        let trip = try makeTrip(in: model)
        let repo = TripRepository(context: model)
        let signature = WeatherChangeProposalLifecycle.tripContextSignature(
            trip.context(preferences: .deviceDefaults(), weather: nil)
        )
        let proposal = dummyProposal(
            add: [dummyItem("clothing.rain_jacket", "Rain jacket")],
            signature: signature
        )
        repo.replacePendingWeatherChange(proposal, on: trip)
        #expect(repo.pendingWeatherChange(on: trip) != nil)
        repo.apply(
            destination: trip.destination,
            startDate: calendar.date(byAdding: .day, value: 3, to: trip.startDate)!,
            endDate: calendar.date(byAdding: .day, value: 3, to: trip.endDate)!,
            durationDays: trip.durationDays,
            durationNights: trip.durationNights,
            tripType: trip.tripType,
            activities: trip.activities,
            bagType: trip.bagType,
            packingStyle: trip.packingStyle,
            laundryAccess: trip.laundryAccess,
            userNotes: trip.userNotes,
            contextChips: trip.contextChips,
            party: trip.party,
            on: trip
        )
        #expect(repo.pendingWeatherChange(on: trip) == nil)
        #expect(trip.weatherChangeProposals.contains { $0.status == .invalidated })
    }

    @Test @MainActor func manuallyAddingSuggestedItemInvalidatesThatProposalRow() throws {
        let container = try PackWisePersistence.container(inMemory: true)
        let model = ModelContext(container)
        let trip = try makeTrip(in: model)
        let repo = TripRepository(context: model)
        let jacket = dummyItem("clothing.rain_jacket", "Rain jacket")
        let umbrella = dummyItem("accessories.umbrella", "Compact umbrella")
        let signature = WeatherChangeProposalLifecycle.tripContextSignature(
            trip.context(preferences: .deviceDefaults(), weather: nil)
        )
        repo.replacePendingWeatherChange(
            dummyProposal(add: [jacket, umbrella], signature: signature),
            on: trip
        )
        repo.addItem(jacket, to: trip)
        let pending = try #require(repo.pendingWeatherChange(on: trip))
        #expect(!pending.diff.add.contains { $0.canonicalItemID == "clothing.rain_jacket" })
        #expect(pending.diff.add.contains { $0.canonicalItemID == "accessories.umbrella" })
        repo.addItem(umbrella, to: trip)
        #expect(repo.pendingWeatherChange(on: trip) == nil)
        #expect(trip.weatherChangeProposals.contains { $0.status == .invalidated })
        #expect(trip.overrides.isEmpty)
    }

    @Test @MainActor func snapshotStaysCurrentWhenProposalIsDismissed() throws {
        let container = try PackWisePersistence.container(inMemory: true)
        let model = ModelContext(container)
        let trip = try makeTrip(in: model)
        let repo = TripRepository(context: model)
        let start = date(2026, 9, 12)
        let dry = forecast(start: start, days: 5, high: 75, low: 64, rain: 0.1)
        var wet = forecast(start: start, days: 5, high: 75, low: 64, rain: 0.7, rainOnDay: 0)
        wet.fetchedAt = calendar.date(byAdding: .hour, value: 2, to: start)!
        repo.storeWeather(dry, on: trip)
        repo.storeWeather(wet, on: trip)
        let proposal = dummyProposal(
            add: [dummyItem("clothing.rain_jacket", "Rain jacket")],
            signature: WeatherChangeProposalLifecycle.tripContextSignature(
                trip.context(preferences: .deviceDefaults(), weather: nil)
            )
        )
        repo.replacePendingWeatherChange(proposal, on: trip)
        repo.dismissWeatherChange(proposal, on: trip)
        #expect(trip.weatherSnapshots.count == 1)
        #expect(trip.weatherSnapshots.first?.weatherContext?.fetchedAt == wet.fetchedAt)
        #expect(trip.items.isEmpty)
        #expect(trip.overrides.isEmpty)
    }

    // MARK: - Task 4: weather lifecycle

    /// No weather at all still generates a full, sane list — the engine
    /// never depends on a forecast being present.
    @Test func noWeatherStillGenerates() throws {
        let items = try engine().generate(context: try context(weather: nil))
        #expect(!items.isEmpty)
        #expect(!items.contains { $0.canonicalItemID == "clothing.rain_jacket" }, "no forecast means no rain signal to react to")
    }

    // MARK: - Phase 6: cached/failed weather generation-equivalence

    /// A cached forecast is structurally the same data as a live one, just
    /// tagged stale (`WeatherDomain.swift:163`) — generation must not depend on
    /// `source`, only on the daily data and coverage flags it already reads.
    @Test func cachedForecastGeneratesIdenticallyToTheSameDataFresh() throws {
        let fresh = forecast(start: date(2026, 10, 5), days: 5, high: 57, low: 48, rain: 0.6)
        let cached = fresh.markingAsCache()
        #expect(cached.source == .cache)

        let freshItems = try engine().generate(context: try context(weather: fresh, days: 5))
        let cachedItems = try engine().generate(context: try context(weather: cached, days: 5))
        #expect(Set(freshItems.compactMap(\.canonicalItemID)) == Set(cachedItems.compactMap(\.canonicalItemID)))
    }

    /// A failed fetch with no usable cache falls back to `.unavailable` in
    /// `TripWeatherResolver`, which the engine already treats as no weather at
    /// all (`noWeatherStillGenerates`). This test exercises that path through
    /// the resolver directly rather than re-deriving the assumption.
    @Test func failedFetchWithNoCacheDegradesToNoWeatherGeneration() async throws {
        let failing = MockWeatherService(fixtures: [:], forceUnavailable: true)
        let resolved = await TripWeatherResolver.resolve(
            using: failing, destination: try destination("Seattle"),
            start: date(2026, 10, 5), end: date(2026, 10, 9), cached: nil
        )
        #expect(resolved.state == .unavailable)
        #expect(resolved.engineWeather == nil)
        let items = try engine().generate(context: try context(weather: resolved.engineWeather, days: 5))
        #expect(!items.contains { $0.canonicalItemID == "clothing.rain_jacket" })
        #expect(!items.isEmpty)
    }

    /// A forecast that only covers part of a 30-day trip is flagged as
    /// partial, not silently treated as whole-trip coverage — the ~10-day
    /// provider horizon genuinely leaves the back half of a long trip
    /// uncovered.
    @Test func partialForecastDoesNotCoverA30DayTrip() throws {
        let start = date(2026, 9, 12)
        let end = calendar.date(byAdding: .day, value: 29, to: start)!
        // Only the first 10 days come back from the provider.
        let rawDays: [DailyForecast] = (0..<10).map { index in
            let day = calendar.date(byAdding: .day, value: index, to: start)!
            return DailyForecast(
                date: calendar.startOfDay(for: day),
                symbol: "sun.max",
                highF: 70,
                lowF: 55,
                rainProbability: 0.1,
                uvIndex: 4,
                windMph: 8,
                snowExpected: false,
                summary: "Sunny"
            )
        }
        let weather = WeatherForecastNormalizer.context(
            days: rawDays,
            tripStart: start,
            tripEnd: end,
            fetchedAt: start,
            providerFetchedAt: start,
            providerExpiresAt: calendar.date(byAdding: .hour, value: 1, to: start),
            source: .fixture,
            fixtureID: "partial-30d",
            calendar: calendar
        )
        #expect(weather.forecastAvailableForPartialTrip)
        #expect(!weather.forecastAvailableForWholeTrip)
        #expect(weather.dailyForecast.count == 10, "coverage stops at the provider horizon, not the trip length")
        #expect(weather.coverageEnd != nil && weather.coverageEnd! < end)
        #expect(weather.state() == .forecastPartial)
        // Once its TTL expires, a partial forecast is refetched exactly
        // like a whole-trip one would be — `shouldFetch` reads only
        // `providerExpiresAt` here, not `forecastAvailableForPartialTrip`.
        // Whether partial coverage should be retried *before* expiry is a
        // separate question this policy does not currently answer either
        // way (see the audit report).
        #expect(
            WeatherRefreshPolicy.shouldFetch(
                existing: weather,
                tripStart: start,
                tripStatus: .planning,
                now: calendar.date(byAdding: .hour, value: 2, to: start)!
            )
        )
    }

    /// Coverage the user already has (a rain jacket and umbrella already on
    /// the list) means a fresh rain signal produces no packing consequence
    /// to propose — the diff is empty, so no duplicate proposal is created.
    @Test func existingUserRainCoveragePreventsADuplicateProposal() throws {
        let start = date(2026, 9, 12)
        let dry = forecast(start: start, days: 5, high: 75, low: 64, rain: 0.1)
        let wet = forecast(start: start, days: 5, high: 75, low: 64, rain: 0.7, rainOnDay: 0)
        var existing = try engine().generate(context: context(weather: dry))
        #expect(!existing.contains { $0.canonicalItemID == "clothing.rain_jacket" })
        // The user proactively packed rain gear before the forecast caught up.
        existing.append(
            PackingItemDraft(
                canonicalItemID: "clothing.rain_jacket",
                displayName: "Rain jacket",
                category: .clothing,
                quantity: 1,
                importance: .important,
                sourceSignals: [.userPreference],
                reason: "Added by you",
                isUserAdded: true
            )
        )
        existing.append(
            PackingItemDraft(
                canonicalItemID: "essentials.umbrella_compact",
                displayName: "Compact umbrella",
                category: .essentials,
                quantity: 1,
                importance: .optional,
                sourceSignals: [.userPreference],
                reason: "Added by you",
                isUserAdded: true
            )
        )
        let outcome = try reconcile(old: dry, new: wet, existing: existing, ctx: context(weather: wet))
        #expect(outcome == .snapshotOnly, "rain coverage the user already has must not trigger a duplicate add proposal")
    }

    @Test func acceptedStatusDecodesAsApplied() throws {
        let decoded = try JSONDecoder().decode(
            WeatherChangeProposalStatus.self,
            from: Data(#""accepted""#.utf8)
        )
        #expect(decoded == .applied)
        #expect(
            try JSONDecoder().decode(WeatherChangeProposalStatus.self, from: Data(#""applied""#.utf8)) == .applied
        )
    }

    private func dummyItem(_ canonicalID: String, _ name: String) -> PackingItemDraft {
        PackingItemDraft(
            canonicalItemID: canonicalID,
            displayName: name,
            category: .clothing,
            quantity: 1,
            importance: .important,
            sourceSignals: [.weather],
            reason: "Test"
        )
    }

    private func dummyProposal(add: [PackingItemDraft], signature: String) -> WeatherChangeProposal {
        WeatherChangeProposal(
            id: UUID(),
            tripID: UUID(),
            oldSnapshotID: UUID(),
            newSnapshotID: UUID(),
            createdAt: date(2026, 8, 29),
            status: .pending,
            signalChanges: [],
            headline: "Weather changed",
            diff: RecommendationDiff(add: add, removeCandidates: [], quantityChanges: []),
            tripContextSignature: signature
        )
    }

    @MainActor
    private func makeTrip(in model: ModelContext) throws -> TripRecord {
        let trip = TripRecord(
            destination: try destination("Chicago"),
            startDate: date(2026, 9, 12),
            endDate: date(2026, 9, 16),
            durationDays: 5,
            durationNights: 4,
            tripType: .cityBreak,
            activities: ["sightseeing", "walking"],
            bagType: .carryOn,
            packingStyle: .light,
            status: .packing
        )
        model.insert(trip)
        return trip
    }
}
