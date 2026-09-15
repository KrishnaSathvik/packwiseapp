import Foundation

/// Engine output plus the coverage decisions behind it. `items` is what the
/// product consumes; `coverageSuppressions` is the record of what the
/// resolver removed and why, kept from the start so the golden ledger shows
/// reasoning rather than rules silently not firing.
struct EngineGeneration: Sendable {
    var items: [PackingItemDraft]
    var coverageSuppressions: [CoverageSuppression]
    var constraintDecisions: [ConstraintDecision]
    /// The one normalized luggage decision this generation ran under —
    /// recorded even when it trimmed nothing, so "checked capacity, no trim
    /// applied" is evidence rather than an absence. Items it didn't affect
    /// carry no constraint fact.
    var luggage: LuggageContext
    /// Diagnostics from compiling a `TripContextSnapshot` for this
    /// generation — validation/observability only. No decision logic in this
    /// file reads from the snapshot; it is compiled purely to attach these
    /// diagnostics to the return value. Not serialized into golden JSON.
    var contextDiagnostics: [ContextDiagnostic]
}

/// Raw constraint drops collected during resolution, aggregated into
/// `ConstraintDecision` records at the end of a generation.
typealias ConstraintDrops = [(travelerID: UUID?, canonicalItemID: String, key: String)]

struct PackingEngine: Sendable {
    var catalog: PackingCatalog
    var rules: PackingRulesFile

    func generate(
        context: TripContext,
        existing: [PackingItemDraft] = [],
        overrides: [RecommendationOverrideDraft] = []
    ) -> [PackingItemDraft] {
        generateDetailed(context: context, existing: existing, overrides: overrides).items
    }

    func generateDetailed(
        context: TripContext,
        existing: [PackingItemDraft] = [],
        overrides: [RecommendationOverrideDraft] = []
    ) -> EngineGeneration {
        // Compiled once. Phase 3 passes the normalized snapshot only to the
        // clothing quantity family; every other decision family remains on
        // raw TripContext until its own hardening phase.
        let snapshot = TripContextCompiler.compile(context, rules: rules)
        let party = context.effectiveParty
        let generated = party.usesSimpleList
            ? generateSimple(context: context, snapshot: snapshot, existing: existing, overrides: overrides)
            : generateForParty(context: context, snapshot: snapshot, existing: existing, overrides: overrides)
        return EngineGeneration(
            items: generated.items.map { item in
                // Ambiguous explicit party items stay unassigned. Coverage
                // has already isolated them from every traveler group; do
                // not undo that fail-safe by guessing the primary here.
                if !party.usesSimpleList,
                   item.ownershipType == .personal,
                   item.travelerID == nil,
                   (item.isUserAdded || item.isUserModified) {
                    return item
                }
                return PartyInvariants.normalize(item, in: party)
            },
            coverageSuppressions: generated.suppressions,
            constraintDecisions: ConstraintResolver.decisions(from: generated.drops, luggage: snapshot.luggage),
            luggage: snapshot.luggage,
            contextDiagnostics: snapshot.diagnostics
        )
    }

    func recommendationDiff(
        context: TripContext,
        existing: [PackingItemDraft],
        overrides: [RecommendationOverrideDraft]
    ) -> RecommendationDiff {
        // Merge-aware baseline (Phase 8, Task 3): reuses resolve()'s
        // already-correct existing-item merge branch instead of diffing
        // against a from-scratch generation that discards it. This is not
        // new decision logic — every other caller of generate() already
        // passes real existing drafts; recommendationDiff was the one place
        // that wasn't.
        let generated = generate(context: context, existing: existing, overrides: overrides)
        if context.effectiveParty.usesSimpleList {
            return simpleDiff(generated: generated, existing: existing)
        }
        let existingKeys = Set(existing.map(\.recommendationKey))
        let generatedKeys = Set(generated.map(\.recommendationKey))
        let add = generated.filter { !existingKeys.contains($0.recommendationKey) && $0.canonicalItemID != nil }
        let generatedByKey = Dictionary(uniqueKeysWithValues: generated.map { ($0.recommendationKey, $0) })
        var removeCandidates: [PackingItemDraft] = []
        var quantityChanges: [QuantityChangeSuggestion] = []
        for item in existing where !item.isUserAdded && !item.isUserModified {
            if !generatedKeys.contains(item.recommendationKey) {
                removeCandidates.append(item)
            } else if let fresh = generatedByKey[item.recommendationKey], item.causallyDiffers(from: fresh) {
                quantityChanges.append(QuantityChangeSuggestion(existing: item, fresh: fresh))
            }
        }
        return RecommendationDiff(add: add, removeCandidates: removeCandidates, quantityChanges: quantityChanges)
    }

    private func simpleDiff(
        generated: [PackingItemDraft],
        existing: [PackingItemDraft]
    ) -> RecommendationDiff {
        let existingIDs = Set(existing.compactMap(\.canonicalItemID))
        let generatedIDs = Set(generated.compactMap(\.canonicalItemID))
        let add = generated.filter { draft in
            guard let id = draft.canonicalItemID else { return false }
            return !existingIDs.contains(id)
        }
        var generatedByID: [String: PackingItemDraft] = [:]
        for draft in generated {
            guard let id = draft.canonicalItemID else { continue }
            generatedByID[id] = draft
        }
        var removeCandidates: [PackingItemDraft] = []
        var quantityChanges: [QuantityChangeSuggestion] = []
        for item in existing where !item.isUserAdded && !item.isUserModified {
            guard let id = item.canonicalItemID else { continue }
            if !generatedIDs.contains(id) {
                removeCandidates.append(item)
            } else if let fresh = generatedByID[id], item.causallyDiffers(from: fresh) {
                quantityChanges.append(QuantityChangeSuggestion(existing: item, fresh: fresh))
            }
        }
        return RecommendationDiff(add: add, removeCandidates: removeCandidates, quantityChanges: quantityChanges)
    }

    private func generateSimple(
        context: TripContext,
        snapshot: TripContextSnapshot,
        existing: [PackingItemDraft],
        overrides: [RecommendationOverrideDraft]
    ) -> (items: [PackingItemDraft], suppressions: [CoverageSuppression], drops: ConstraintDrops) {
        var drops: ConstraintDrops = []
        let suggestions = ruleSuggestions(for: context, snapshot: snapshot)
        let resolved = resolve(
            suggestions: suggestions,
            context: context,
            existing: existing,
            overrides: overrides,
            ownership: .personal,
            travelerID: context.effectiveParty.primary.id,
            assignedTravelerID: context.effectiveParty.primary.id,
            drops: &drops
        )
        let (covered, suppressions) = applyCoverage(resolved, snapshot: snapshot)
        let completed = addCompanions(covered, context: context, overrides: overrides)
        return (applyQuantities(completed, context: context, snapshot: snapshot), suppressions, drops)
    }

    private func generateForParty(
        context: TripContext,
        snapshot: TripContextSnapshot,
        existing: [PackingItemDraft],
        overrides: [RecommendationOverrideDraft]
    ) -> (items: [PackingItemDraft], suppressions: [CoverageSuppression], drops: ConstraintDrops) {
        var drops: ConstraintDrops = []
        let party = context.effectiveParty
        // Weather and trip-wide activity signals are computed once, then split
        // into personal vs shared effects so rain does not become 4 umbrellas.
        // Activities are trip-scoped, so the trip-wide snapshot is compiled
        // once here and never per traveler.
        let tripContext = tripWideContext(context)
        let tripSuggestions = ruleSuggestions(
            for: tripContext,
            snapshot: TripContextCompiler.compile(tripContext, rules: rules)
        )
        var sharedCollected: [String: RuleSuggestion] = [:]
        var result: [PackingItemDraft] = existing.filter(\.isUserAdded)

        for traveler in party.travelers {
            var collected = Dictionary(uniqueKeysWithValues: tripSuggestions.map { ($0.canonicalItemID, $0) })
            addTravelerSuggestions(traveler, context: context, into: &collected)
            addAgeGroupSuggestions(traveler, context: context, into: &collected)
            addPartyActivitySuggestions(traveler, context: context, into: &collected)

            var personal: [RuleSuggestion] = []
            for suggestion in collected.values {
                if shouldSkip(suggestion.canonicalItemID, for: traveler) { continue }
                if ConstraintResolver.sharingResolution(for: suggestion.canonicalItemID, rules: rules.party, context: context, party: party).isShared {
                    mergeSuggestion(suggestion, into: &sharedCollected)
                } else {
                    personal.append(suggestion)
                }
            }

            result.append(contentsOf: resolve(
                suggestions: personal,
                context: context,
                existing: existing,
                overrides: overrides,
                ownership: .personal,
                travelerID: traveler.id,
                assignedTravelerID: traveler.carrierID,
                drops: &drops
            ))
        }

        result.append(contentsOf: resolve(
            suggestions: Array(sharedCollected.values),
            context: context,
            existing: existing,
            overrides: overrides,
            ownership: .shared,
            travelerID: nil,
            assignedTravelerID: nil,
            drops: &drops
        ))

        var seen = Set<UUID>()
        result = result.filter { seen.insert($0.id).inserted }
        let (covered, suppressions) = applyCoverage(result, snapshot: snapshot)
        let completed = addCompanions(covered, context: context, overrides: overrides)
        return (applyQuantities(completed, context: context, snapshot: snapshot), suppressions, drops)
    }

    private func tripWideContext(_ context: TripContext) -> TripContext {
        var copy = context
        copy.contextChips = context.contextChips.intersection(ContextChip.tripLevel)
        copy.preferences.usuallyWorkOut = false
        copy.preferences.usuallyBringLaptop = false
        copy.preferences.wearContacts = false
        copy.preferences.alwaysBringMedication = false
        return copy
    }

    private func travelerChips(_ traveler: Traveler, context: TripContext) -> Set<ContextChip> {
        var chips = traveler.chips
        if traveler.role == .self {
            chips.formUnion(context.contextChips.subtracting(ContextChip.tripLevel))
            if context.preferences.usuallyWorkOut { chips.insert(.usuallyWorkOut) }
            if context.preferences.usuallyBringLaptop { chips.insert(.bringingLaptop) }
            if context.preferences.wearContacts { chips.insert(.wearContacts) }
            if context.preferences.alwaysBringMedication { chips.insert(.dailyMedication) }
        }
        return chips
    }

    private func addTravelerSuggestions(_ traveler: Traveler, context: TripContext, into collected: inout [String: RuleSuggestion]) {
        for chip in travelerChips(traveler, context: context) {
            guard let ids = rules.contextChips[chip.rawValue] else { continue }
            addIDs(
                ids,
                signal: .userPreference,
                code: "preference.\(chip.rawValue)",
                arguments: [:],
                fallback: chipReason(chip),
                context: context,
                into: &collected
            )
        }
    }

    private func addAgeGroupSuggestions(_ traveler: Traveler, context: TripContext, into collected: inout [String: RuleSuggestion]) {
        guard let rule = rules.party.ageGroups[traveler.ageGroup.rawValue] else { return }
        let arguments = ["name": traveler.displayName, "ageGroup": traveler.ageGroup.title.lowercased()]
        addIDs(
            rule.add,
            signal: .party,
            code: "party.age_group",
            arguments: arguments,
            fallback: "Suggested for \(traveler.displayName) (\(traveler.ageGroup.title.lowercased())).",
            context: context,
            into: &collected
        )
        var confirmed: [String] = []
        for need in traveler.needs {
            confirmed.append(contentsOf: rule.candidates[need.rawValue] ?? [])
        }
        addIDs(
            confirmed,
            signal: .userPreference,
            code: "party.age_group",
            arguments: arguments,
            fallback: "Suggested for \(traveler.displayName) (\(traveler.ageGroup.title.lowercased())).",
            context: context,
            into: &collected
        )
    }

    private func addPartyActivitySuggestions(_ traveler: Traveler, context: TripContext, into collected: inout [String: RuleSuggestion]) {
        for activity in context.activities {
            guard let ids = rules.party.activityAdds[activity] else { continue }
            let matching = ids.filter { id in
                guard let item = catalog.item(id: id) else { return false }
                return item.tags.contains(traveler.ageGroup.rawValue) || item.tags.contains("shared_ok")
            }
            addIDs(
                matching,
                signal: .party,
                code: "party.age_group",
                arguments: ["name": traveler.displayName, "ageGroup": traveler.ageGroup.title.lowercased()],
                fallback: "Suggested for \(traveler.displayName).",
                context: context,
                into: &collected
            )
        }
    }

    private func addIDs(
        _ ids: [String],
        signal: RecommendationSignal,
        code: String,
        arguments: [String: String],
        fallback: String,
        provenance fact: RecommendationProvenance? = nil,
        context: TripContext,
        into collected: inout [String: RuleSuggestion]
    ) {
        let fact = fact ?? RecommendationProvenance(reasonCode: code, reasonArguments: arguments, sourceSignals: [signal])
        for id in ids {
            guard let item = catalog.item(id: id) else { continue }
            if item.travelRestrictionReviewRequired && context.luggage.appliesCapacityConstraint { continue }
            let reason = render(code, arguments, category: item.category.rawValue, fallback: fallback)
            if var existing = collected[id] {
                if !existing.signals.contains(signal) {
                    existing.signals.append(signal)
                }
                if !existing.provenance.contains(fact) {
                    existing.provenance.append(fact)
                }
                // The more trip-specific reason wins the row: walking shoes
                // suggested as a base essential and for sightseeing should
                // say sightseeing, not "a core item for almost every trip."
                if ReasonRenderer.tier(code) > ReasonRenderer.tier(existing.reasonCode) {
                    existing.reason = reason
                    existing.reasonCode = code
                    existing.reasonArguments = arguments
                }
                collected[id] = existing
            } else {
                collected[id] = RuleSuggestion(
                    canonicalItemID: id,
                    signals: [signal],
                    reasonCode: code,
                    reasonArguments: arguments,
                    reason: reason,
                    provenance: [fact]
                )
            }
        }
    }

    private func mergeSuggestion(_ suggestion: RuleSuggestion, into collected: inout [String: RuleSuggestion]) {
        if var existing = collected[suggestion.canonicalItemID] {
            for signal in suggestion.signals where !existing.signals.contains(signal) {
                existing.signals.append(signal)
            }
            for fact in suggestion.provenance where !existing.provenance.contains(fact) {
                existing.provenance.append(fact)
            }
            if ReasonRenderer.tier(suggestion.reasonCode) > ReasonRenderer.tier(existing.reasonCode) {
                existing.reason = suggestion.reason
                existing.reasonCode = suggestion.reasonCode
                existing.reasonArguments = suggestion.reasonArguments
            }
            collected[suggestion.canonicalItemID] = existing
        } else {
            collected[suggestion.canonicalItemID] = suggestion
        }
    }

    private func shouldSkip(_ id: String, for traveler: Traveler) -> Bool {
        let ageRule = rules.party.ageGroups[traveler.ageGroup.rawValue]
        if rules.party.skipForYoungChildren.contains(id), traveler.ageGroup.isYoungChild {
            return true
        }
        if rules.party.skipForInfantsAndToddlers.contains(id), traveler.ageGroup.skipsAdultPersonalEssentials {
            return true
        }
        if ageRule?.skipAdultClothing == true, id.hasPrefix("clothing.") {
            return true
        }
        if traveler.ageGroup.skipsAdultPersonalEssentials,
           ["essentials.wallet", "essentials.phone", "essentials.keys", "essentials.home_keys", "essentials.watch"].contains(id) {
            return true
        }
        return false
    }

    func interpretFreeTextActivities(_ note: String, selected: [String]) -> [String] {
        var result = selected
        let lowered = note.lowercased()
        for (keyword, activity) in rules.freeTextKeywords where lowered.contains(keyword) {
            if !result.contains(activity) {
                result.append(activity)
            }
        }
        return result
    }

    private func render(_ code: String, _ arguments: [String: String], category: String? = nil, fallback: String) -> String {
        ReasonRenderer.render(code: code, arguments: arguments, templates: rules.reasons.templates, category: category, fallback: fallback)
    }

    private func ruleSuggestions(
        for context: TripContext,
        snapshot: TripContextSnapshot
    ) -> [RuleSuggestion] {
        var collected: [String: RuleSuggestion] = [:]

        func add(
            _ ids: [String],
            signal: RecommendationSignal,
            code: String,
            arguments: [String: String] = [:],
            fallback: String,
            provenance: RecommendationProvenance? = nil
        ) {
            addIDs(ids, signal: signal, code: code, arguments: arguments, fallback: fallback, provenance: provenance, context: context, into: &collected)
        }

        // One warm line per category beats twenty rows of "a core item for
        // almost every trip". The code stays specific-tier so the template
        // test keeps guarding it.
        let skips = rules.base.shortTripSkips
        for id in rules.baseEssentials {
            if let skips, context.durationDays <= skips.maxDays, skips.ids.contains(id) { continue }
            let category = catalog.item(id: id)?.category.rawValue ?? "essentials"
            add(
                [id],
                signal: .baseEssential,
                code: "base.essential.\(category)",
                fallback: "A core item for almost every trip."
            )
        }

        addTripTypeNeeds(snapshot: snapshot) { ids, signal, code, arguments, fallback, provenance in
            add(ids, signal: signal, code: code, arguments: arguments, fallback: fallback, provenance: provenance)
        }

        for activity in context.activities {
            if let ids = rules.activities[activity] {
                // Every activity carries its own code; the template catalog
                // has one entry per activity id, so the generic string never
                // renders on an activity-driven item.
                add(
                    ids,
                    signal: .activity,
                    code: "activity.\(activity)",
                    arguments: ["destination": context.destination.displayName],
                    fallback: activityReason(activity, destination: context.destination.displayName)
                )
            }
        }

        // Phase 5: typed activity contracts. Needs and the JSON `add` rows
        // above flow into the same `collected` dictionary, so composition and
        // de-duplication are structural rather than asserted afterwards.
        addActivityNeeds(context: context, snapshot: snapshot, into: &collected)

        for chip in context.contextChips {
            if let ids = rules.contextChips[chip.rawValue] {
                add(ids, signal: .userPreference, code: "preference.\(chip.rawValue)", fallback: chipReason(chip))
            }
        }

        if context.preferences.usuallyWorkOut {
            add(rules.contextChips[ContextChip.usuallyWorkOut.rawValue] ?? [], signal: .userPreference, code: "preference.usuallyWorkOut", fallback: "You usually work out while traveling.")
        }
        if context.preferences.usuallyBringLaptop {
            add(rules.contextChips[ContextChip.bringingLaptop.rawValue] ?? [], signal: .userPreference, code: "preference.bringingLaptop", fallback: "You usually bring a laptop.")
        }
        if context.preferences.wearContacts {
            add(rules.contextChips[ContextChip.wearContacts.rawValue] ?? [], signal: .userPreference, code: "preference.wearContacts", fallback: "You wear contacts.")
        }
        if context.preferences.alwaysBringMedication {
            add(rules.contextChips[ContextChip.dailyMedication.rawValue] ?? [], signal: .userPreference, code: "preference.dailyMedication", fallback: "You take daily medication.")
        }

        if context.isInternationalConfirmed {
            add(
                rules.internationalAdds,
                signal: .destination,
                code: "destination.international",
                fallback: "You're traveling internationally. Check the entry requirements that apply to you."
            )
            add(
                ["documents.visa"],
                signal: .destination,
                code: "documents.visa_check",
                fallback: "Check the entry requirements that apply to you."
            )
        }

        addWeather(context: context, snapshot: snapshot, into: &collected)

        if snapshot.luggage.hasCabinAccessibleBag || context.transportation == .flight {
            add(
                ["travel_comfort.empty_security_bottle"],
                signal: .tripType,
                code: "flight.empty_bottle",
                fallback: "Useful after airport security."
            )
        }

        return Array(collected.values)
    }

    /// Product Experience V2, Task 4: every selected trip type contributes.
    ///
    /// The full `tripTypes` set resolved to normalized needs once, in the
    /// snapshot (identical needs merge, every provenance fact kept); each
    /// need's central candidates then join the one `collected` map, so an
    /// item several trip types share is a single suggestion carrying one fact
    /// per contributing type. Its reason names all of them in stable order.
    /// No type is primary. Coverage reads the same snapshot needs.
    private func addTripTypeNeeds(
        snapshot: TripContextSnapshot,
        add: (_ ids: [String], _ signal: RecommendationSignal, _ code: String,
              _ arguments: [String: String], _ fallback: String, _ provenance: RecommendationProvenance?) -> Void
    ) {
        var order: [String] = []
        var contributors: [String: Set<TripType>] = [:]
        for normalized in snapshot.packingNeeds {
            let sources = Set(normalized.provenance.compactMap(\.tripType))
            for id in rules.tripTypeContracts.needDefinitions[normalized.need]?.candidateItemIDs ?? [] {
                if contributors[id] == nil { order.append(id) }
                contributors[id, default: []].formUnion(sources)
            }
        }
        for id in order {
            let sources = contributors[id] ?? []
            let phrase = TripType.reasonPhrase(sources)
            for tripType in TripType.stableOrder where sources.contains(tripType) {
                add([id], .tripType, "trip_type.generic", ["tripType": phrase],
                    "Suggested for a \(phrase) trip.", .tripType(tripType))
            }
        }
    }

    /// Resolves the trip's composed `Set<ActivityNeed>` into candidate items.
    ///
    /// The weather boundary lives here: an activity may participate in
    /// existing weather logic but may never manufacture weather, so a
    /// weather-gated need resolves to nothing unless the projection already
    /// carries a cold signal. Needs are emitted in sorted order so emission
    /// never depends on set iteration.
    private func addActivityNeeds(
        context: TripContext,
        snapshot: TripContextSnapshot,
        into collected: inout [String: RuleSuggestion]
    ) {
        let ordered = snapshot.knownActivityIDs
        let activityNeeds = ActivityContracts.needs(for: ordered)
        guard !activityNeeds.isEmpty else { return }

        let coverageContext = CoverageContext(snapshot: snapshot, thresholds: rules.weather.thresholds)
        let coldSignals: Set<WeatherSignal> = [.snowExposure, .sustainedCold, .freezingCold, .coldEvenings]
        let hasColdSignal = !coverageContext.weatherSignals.isDisjoint(with: coldSignals)

        for need in activityNeeds.sorted(by: { $0.rawValue < $1.rawValue }) {
            // The weather boundary: a gated need never creates its own weather.
            if need.isWeatherGated && !hasColdSignal { continue }
            guard let origin = ActivityContracts.originatingActivity(for: need, in: ordered) else { continue }
            addIDs(
                ActivityContracts.needCandidates[need] ?? [],
                signal: .activity,
                code: "activity.\(origin)",
                arguments: ["destination": context.destination.displayName],
                fallback: activityReason(origin, destination: context.destination.displayName),
                context: context,
                into: &collected
            )
        }
    }

    private func addWeather(context: TripContext, snapshot: TripContextSnapshot, into collected: inout [String: RuleSuggestion]) {
        switch snapshot.weatherQuality {
        case .missing, .seasonalOnly:
            addSeasonal(context: context, into: &collected)
            return
        case .partial, .complete:
            break
        }
        guard let weather = context.weather else {
            addSeasonal(context: context, into: &collected)
            return
        }

        let conditions = WeatherSignalExtractor.extract(
            weather: weather,
            thresholds: rules.weather.thresholds,
            outdoorActivities: context.outdoorActivities,
            tripDays: context.durationDays
        )

        func add(_ ids: [String], code: String, arguments: [String: String], fallback: String) {
            let fact = RecommendationProvenance(reasonCode: code, reasonArguments: arguments, sourceSignals: [.weather])
            for id in ids {
                guard let item = catalog.item(id: id) else { continue }
                let reason = render(code, arguments, category: item.category.rawValue, fallback: fallback)
                if var existing = collected[id] {
                    if !existing.signals.contains(.weather) {
                        existing.signals.append(.weather)
                    }
                    if !existing.provenance.contains(fact) {
                        existing.provenance.append(fact)
                    }
                    if ReasonRenderer.tier(code) > ReasonRenderer.tier(existing.reasonCode) {
                        existing.reason = reason
                        existing.reasonCode = code
                        existing.reasonArguments = arguments
                    }
                    collected[id] = existing
                } else {
                    collected[id] = RuleSuggestion(
                        canonicalItemID: id,
                        signals: [.weather],
                        reasonCode: code,
                        reasonArguments: arguments,
                        reason: reason,
                        provenance: [fact]
                    )
                }
            }
        }

        let rainArgs = ["rainDays": "\(conditions.rainDays)", "tripDays": "\(conditions.tripDays)"]
        if conditions.signals.contains(.meaningfulRain) || conditions.signals.contains(.persistentRain) {
            // Sub-freezing precip days were reclassified as snow upstream;
            // keep the named rain day consistent with that count.
            let weekday = weather.dailyForecast.first(where: {
                $0.rainProbability >= rules.weather.thresholds.rainProbabilityAdd
                    && $0.highF > rules.weather.thresholds.freezingMaxF
            })?
            .date.formatted(.dateTime.weekday(.wide))
            if conditions.rainDays >= 2 {
                add(rules.weather.signalAdds["persistentRain"] ?? [], code: "weather.rain_days", arguments: rainArgs, fallback: "Rain is expected on \(conditions.rainDays) of your \(conditions.tripDays) travel days.")
            } else if let weekday {
                add(rules.weather.signalAdds["meaningfulRain"] ?? [], code: "weather.rain_weekday", arguments: ["weekday": weekday], fallback: "Rain is expected \(weekday).")
            } else {
                add(rules.weather.signalAdds["meaningfulRain"] ?? [], code: "weather.rain_days", arguments: rainArgs, fallback: "Rain is expected during your trip.")
            }
        }
        if conditions.signals.contains(.coldRain) {
            add(rules.weather.signalAdds["coldRain"] ?? [], code: "weather.rain_days", arguments: rainArgs, fallback: "Cold rain is expected.")
        }
        if conditions.signals.contains(.snowExposure) {
            add(rules.weather.signalAdds["snowExposure"] ?? [], code: "weather.snow", arguments: [:], fallback: "Snow is expected during your trip.")
        }
        if conditions.signals.contains(.coldEvenings) && weather.minTemperatureF <= rules.weather.thresholds.coldMaxF {
            add(rules.weather.signalAdds["coldEvenings"] ?? rules.weather.signalAdds["snowExposure"] ?? [], code: "weather.cold", arguments: [:], fallback: "Cold temperatures are expected.")
        } else if conditions.signals.contains(.coldEvenings) {
            add(rules.weather.signalAdds["coldEvenings"] ?? [], code: "weather.cool_evenings", arguments: [:], fallback: "Evenings look cool.")
        }
        if conditions.signals.contains(.sustainedCold) {
            add(rules.weather.signalAdds["sustainedCold"] ?? [], code: "weather.sustained_cold", arguments: [:], fallback: "Cold through your whole trip — plan to layer.")
        }
        if conditions.signals.contains(.freezingCold) {
            add(rules.weather.signalAdds["freezingCold"] ?? [], code: "weather.freezing", arguments: [:], fallback: "Sub-freezing temperatures are expected.")
        }
        if conditions.signals.contains(.hotOutdoorExposure) {
            add(rules.weather.signalAdds["hotOutdoorExposure"] ?? [], code: "weather.hot", arguments: [:], fallback: "Hot weather is expected.")
        }
        if conditions.signals.contains(.highUVExposure) {
            add(rules.weather.signalAdds["highUVExposure"] ?? [], code: "weather.uv", arguments: [:], fallback: "Sun exposure looks high.")
        }
        if conditions.signals.contains(.highWindExposure) {
            add(rules.weather.signalAdds["highWindExposure"] ?? [], code: "weather.wind", arguments: [:], fallback: "It looks windy at your destination.")
        }
        if conditions.signals.contains(.largeTemperatureSwing) {
            add(
                rules.weather.signalAdds["largeTemperatureSwing"] ?? [],
                code: "weather.temperature_swing",
                arguments: ["swing": "\(conditions.swing)"],
                fallback: "Temperatures may drop more than \(conditions.swing)° between afternoon and evening."
            )
        }

        // Task 2: a partial forecast's uncovered remainder gets the same
        // conservative seasonal check a fully-unforecast trip already gets.
        // Safe by construction — addSeasonal only fills `collected[id] == nil`
        // gaps, so it can never overwrite or duplicate a precise-day item.
        if case .partial = snapshot.weatherQuality {
            addSeasonal(context: context, into: &collected)
        }
    }

    private func addSeasonal(context: TripContext, into collected: inout [String: RuleSuggestion]) {
        let month = Calendar.current.component(.month, from: context.startDate)
        let lat = context.destination.latitude
        let isNorthern = lat >= 0
        let winter = isNorthern ? [12, 1, 2].contains(month) : [6, 7, 8].contains(month)
        let summer = isNorthern ? [6, 7, 8].contains(month) : [12, 1, 2].contains(month)

        if winter && abs(lat) > 30 {
            for id in (rules.weather.signalAdds["coldEvenings"] ?? []) + ["clothing.light_jacket"] {
                guard catalog.item(id: id) != nil, collected[id] == nil else { continue }
                collected[id] = RuleSuggestion(
                    canonicalItemID: id,
                    signals: [.weather],
                    reasonCode: "weather.seasonal_layer",
                    reasonArguments: [:],
                    reason: render("weather.seasonal_layer", [:], fallback: "Seasonal conditions suggest a warmer layer."),
                    provenance: [RecommendationProvenance(reasonCode: "weather.seasonal_layer", reasonArguments: [:], sourceSignals: [.weather])]
                )
            }
        }
        if summer && abs(lat) < 45 {
            for id in ["toiletries.sunscreen", "essentials.sunglasses"] {
                guard catalog.item(id: id) != nil, collected[id] == nil else { continue }
                collected[id] = RuleSuggestion(
                    canonicalItemID: id,
                    signals: [.weather],
                    reasonCode: "weather.seasonal_sun",
                    reasonArguments: [:],
                    reason: render("weather.seasonal_sun", [:], fallback: "Seasonal sun is likely."),
                    provenance: [RecommendationProvenance(reasonCode: "weather.seasonal_sun", reasonArguments: [:], sourceSignals: [.weather])]
                )
            }
        }
    }

    /// Decision hierarchy (see `ConstraintResolver`): explicit user state
    /// wins here — user-added and user-modified items pass through untouched,
    /// and removed-item overrides keep suggestions out. Trip requirements and
    /// constraints resolve below that, with every constraint drop recorded.
    private func resolve(
        suggestions: [RuleSuggestion],
        context: TripContext,
        existing: [PackingItemDraft],
        overrides: [RecommendationOverrideDraft],
        ownership: PackingOwnership,
        travelerID: UUID?,
        assignedTravelerID: UUID?,
        drops: inout ConstraintDrops
    ) -> [PackingItemDraft] {
        let includeUserAdded = context.effectiveParty.usesSimpleList
        var result: [PackingItemDraft] = includeUserAdded ? existing.filter(\.isUserAdded) : []

        var existingByKey: [String: PackingItemDraft] = [:]
        for draft in existing {
            existingByKey[draft.recommendationKey] = draft
            if context.effectiveParty.usesSimpleList, let id = draft.canonicalItemID {
                existingByKey["canonical:\(id)"] = draft
            }
        }

        for suggestion in suggestions {
            if ConstraintResolver.isExplicitlyRemoved(suggestion.canonicalItemID, ownership: ownership, travelerID: travelerID, overrides: overrides) {
                continue
            }
            let key = recommendationKey(canonical: suggestion.canonicalItemID, ownership: ownership, travelerID: travelerID)
            let existingItem = existingByKey[key] ?? existingByKey["canonical:\(suggestion.canonicalItemID)"]
            if let existingItem {
                if ConstraintResolver.hasUserAuthority(existingItem) {
                    if !result.contains(where: { $0.id == existingItem.id }) {
                        result.append(existingItem)
                    }
                    continue
                }
                var updated = existingItem
                updated.reason = suggestion.reason
                updated.reasonCode = suggestion.reasonCode
                updated.reasonArguments = suggestion.reasonArguments
                updated.sourceSignals = suggestion.signals
                updated.provenance = RecommendationProvenance.canonicalOrder(suggestion.provenance)
                updated.ownershipType = ownership
                updated.travelerID = travelerID
                if updated.assignedTravelerID == nil {
                    updated.assignedTravelerID = assignedTravelerID
                }
                if let already = result.firstIndex(where: { $0.recommendationKey == key || $0.id == existingItem.id }) {
                    result[already] = updated
                } else {
                    result.append(updated)
                }
                continue
            }

            guard let catalogItem = catalog.item(id: suggestion.canonicalItemID) else { continue }
            let luggage = context.luggage
            if catalogItem.travelRestrictionReviewRequired && luggage.appliesCapacityConstraint { continue }
            let ruling = ConstraintResolver.optionalRuling(
                importance: catalogItem.importance,
                tags: catalogItem.tags,
                luggage: luggage,
                style: context.packingStyle
            )
            if !ruling.keep {
                if let key = ruling.conflictKey {
                    drops.append((travelerID, catalogItem.id, key))
                }
                continue
            }

            result.append(
                PackingItemDraft(
                    canonicalItemID: catalogItem.id,
                    displayName: catalogItem.displayName,
                    category: catalogItem.category,
                    quantity: 1,
                    importance: catalogItem.importance,
                    sourceSignals: suggestion.signals,
                    reason: suggestion.reason,
                    reasonCode: suggestion.reasonCode,
                    reasonArguments: suggestion.reasonArguments,
                    bagStyleConstraintFact: ruling.wasConstraintLive
                        ? BagStyleConstraintFact(
                            survivedByEssentialTagProtection: ruling.essentialTagProtected,
                            wouldTrimUnderKey: ruling.wouldTrimUnderKey
                          )
                        : nil,
                    ownershipType: ownership,
                    travelerID: travelerID,
                    assignedTravelerID: assignedTravelerID,
                    provenance: RecommendationProvenance.canonicalOrder(suggestion.provenance)
                )
            )
        }

        return result
    }

    private func recommendationKey(canonical: String, ownership: PackingOwnership, travelerID: UUID?) -> String {
        switch ownership {
        case .shared: return "shared:\(canonical)"
        case .personal: return "personal:\(travelerID?.uuidString ?? "none"):\(canonical)"
        }
    }

    /// Companions are first-class dependencies: an item on the list pulls in
    /// what it can't work without (laptop → charger, contact solution → case),
    /// including for user-added triggers — with a reason naming the trigger,
    /// never silently. A removed-item override keeps a companion out for
    /// good, and a companion that is shared-by-default lands in the shared
    /// group rather than duplicating per traveler.
    private func addCompanions(
        _ items: [PackingItemDraft],
        context: TripContext,
        overrides: [RecommendationOverrideDraft]
    ) -> [PackingItemDraft] {
        var result = items
        var presentShared = Set(items.filter { $0.ownershipType == .shared }.compactMap(\.canonicalItemID))
        var presentByGroup = Dictionary(
            grouping: items.compactMap { item in item.canonicalItemID.map { (substitutionGroup(item), $0) } },
            by: \.0
        ).mapValues { Set($0.map(\.1)) }

        for item in items {
            guard let canonical = item.canonicalItemID,
                  let catalogItem = catalog.item(id: canonical) else { continue }
            for companionID in catalogItem.companions {
                guard let companion = catalog.item(id: companionID) else { continue }
                let sharedCompanion = !context.effectiveParty.usesSimpleList
                    && ConstraintResolver.sharingResolution(for: companionID, rules: rules.party, context: context, party: context.effectiveParty).isShared
                let ownership: PackingOwnership = sharedCompanion ? .shared : item.ownershipType
                let travelerID = sharedCompanion ? nil : item.travelerID
                let group = "\(ownership.rawValue):\(travelerID?.uuidString ?? "shared")"
                if presentShared.contains(companionID) || presentByGroup[group]?.contains(companionID) == true {
                    continue
                }
                if ConstraintResolver.isExplicitlyRemoved(companionID, ownership: ownership, travelerID: travelerID, overrides: overrides) {
                    continue
                }
                let arguments = ["item": item.displayName.lowercased()]
                result.append(
                    PackingItemDraft(
                        canonicalItemID: companion.id,
                        displayName: companion.displayName,
                        category: companion.category,
                        quantity: 1,
                        importance: companion.importance,
                        sourceSignals: item.sourceSignals,
                        reason: render(
                            "dependency.companion",
                            arguments,
                            category: companion.category.rawValue,
                            fallback: "Goes with the \(item.displayName.lowercased()) on your list."
                        ),
                        reasonCode: "dependency.companion",
                        reasonArguments: arguments,
                        ownershipType: ownership,
                        travelerID: travelerID,
                        assignedTravelerID: sharedCompanion ? nil : item.assignedTravelerID,
                        provenance: [RecommendationProvenance(
                            reasonCode: "dependency.companion",
                            reasonArguments: arguments,
                            sourceSignals: item.sourceSignals
                        )]
                    )
                )
                if sharedCompanion {
                    presentShared.insert(companionID)
                } else {
                    presentByGroup[group, default: []].insert(companionID)
                }
            }
        }
        return result
    }

    /// Capability coverage for footwear and outerwear, per traveler.
    /// Generalizes the old one-off substitution rules: the resolver decides
    /// from derived needs and an explicit priority order, and every
    /// suppression is recorded rather than silently dropped.
    private func applyCoverage(
        _ items: [PackingItemDraft],
        snapshot: TripContextSnapshot
    ) -> ([PackingItemDraft], [CoverageSuppression]) {
        let context = CoverageContext(snapshot: snapshot, thresholds: rules.weather.thresholds)
        let needs = CoverageResolver.needs(context: context)
        // A solo list has one owner, so user-added items (nil travelerID)
        // fold into the primary's group and can claim coverage. In a party
        // list an unassigned item stays its own group — guessing whose it is
        // would be inference, and ambiguous inference resolves to don't.
        let primaryID = context.party.primary.id
        let groups = Dictionary(grouping: items) { (item: PackingItemDraft) -> String in
            if item.ownershipType == .shared { return "shared" }
            let owner = item.travelerID ?? (context.party.usesSimpleList ? primaryID : nil)
            return "personal:\(owner?.uuidString ?? "unassigned")"
        }
        var keptAll: [PackingItemDraft] = []
        var suppressionsAll: [CoverageSuppression] = []
        for key in groups.keys.sorted() {
            var (kept, suppressions) = CoverageResolver.resolve(items: groups[key] ?? [], needs: needs)
            // The versatile shoe that absorbed the walking need keeps V1's
            // substitution copy until Step 4's trace-driven reasons land.
            for suppression in suppressions where suppression.canonicalItemID == "footwear.walking_shoes" {
                guard let coverer = suppression.covered.first(where: {
                    $0.capability == .everydayWalking
                })?.coveringItemID,
                      let index = kept.firstIndex(where: { $0.canonicalItemID == coverer })
                else { continue }
                let code = coverer == "footwear.hiking_shoes"
                    ? "substitution.hiking_covers_walking"
                    : "substitution.running_covers_walking"
                kept[index].reasonCode = code
                kept[index].reason = render(code, [:], fallback: kept[index].reason)
            }
            keptAll.append(contentsOf: kept)
            suppressionsAll.append(contentsOf: suppressions)
        }
        return (keptAll, suppressionsAll)
    }

    private func substitutionGroup(_ item: PackingItemDraft) -> String {
        "\(item.ownershipType.rawValue):\(item.travelerID?.uuidString ?? "shared")"
    }

    private func applyQuantities(
        _ items: [PackingItemDraft],
        context: TripContext,
        snapshot: TripContextSnapshot
    ) -> [PackingItemDraft] {
        let engine = QuantityEngine(policies: rules.quantities.policies, reasons: rules.reasons)
        let clothingEngine = ClothingQuantityEngine(reasons: rules.reasons)
        let clothingContext = ClothingQuantityContext(snapshot: snapshot)
        let party = snapshot.party

        // Appearance garments satisfy daily-top uses. Resolve each canonical
        // garment once per owner group; overlapping source signals never add
        // phantom units.
        let outfitIDs: Set<String> = ["clothing.formal_outfit", "clothing.nice_outfit"]
        var appearanceUnits: [String: Int] = [:]
        for item in items {
            guard let canonical = item.canonicalItemID,
                  let catalogItem = catalog.item(id: canonical),
                  catalogItem.quantityKind == "formal_top" || outfitIDs.contains(canonical) else { continue }
            let value = item.isUserModified
                ? item.quantity
                : engine.quantity(kind: catalogItem.quantityKind, context: context, itemName: catalogItem.displayName).value
            appearanceUnits[substitutionGroup(item), default: 0] += value
        }
        return items.map { item in
            var copy = item
            guard let canonical = item.canonicalItemID, let catalogItem = catalog.item(id: canonical) else {
                return copy
            }
            if ConstraintResolver.hasUserAuthority(item) { return copy }

            if item.ownershipType == .shared {
                let resolution = ConstraintResolver.sharingResolution(for: canonical, rules: rules.party, context: context, party: party)
                if case .shared(let quantity, let fallback) = resolution {
                    copy.quantity = quantity
                    if canonical == "essentials.umbrella_compact", let weather = context.weather, weather.rainDays > 0 {
                        let rainDaysPhrase = weather.rainDays == 1 ? "1 day" : "\(weather.rainDays) days"
                        let umbrellaPhrase = quantity == 1 ? "One umbrella" : "\(quantity) umbrellas"
                        copy.quantityReason = render(
                            "party.shared_umbrella",
                            ["rainDaysPhrase": rainDaysPhrase, "umbrellaPhrase": umbrellaPhrase],
                            fallback: fallback
                        )
                        copy.quantityReasonArguments = ["quantity": "\(quantity)", "rainDays": "\(weather.rainDays)"]
                    } else {
                        let quantityPhrase = quantity == 1 ? "One" : "\(quantity)"
                        copy.quantityReason = render(
                            "party.shared",
                            ["quantityPhrase": quantityPhrase],
                            fallback: fallback
                        )
                        copy.quantityReasonArguments = ["quantity": "\(quantity)", "travelerCount": "\(party.travelers.count)"]
                    }
                    return copy
                }
            }

            let traveler = party.travelers.first { $0.id == item.travelerID }

            // Care items are consumed per use, not worn per day; they route
            // by id because the frozen catalog gives diapers and extra
            // outfits one shared kind.
            if let care = CareQuantityEngine.quantity(canonicalID: canonical, days: context.durationDays, traveler: traveler) {
                copy.quantity = care.value
                copy.quantityReason = render(care.reasonCode, care.arguments, fallback: care.fallback)
                copy.quantityReasonArguments = care.arguments
                return copy
            }

            // Warm layers rotate on sustained-cold trips instead of
            // appearing once beside a week of t-shirts.
            if let warm = WarmLayerQuantities.quantity(
                canonicalID: canonical,
                days: context.durationDays,
                weather: context.weather,
                thresholds: rules.weather.thresholds
            ) {
                copy.quantity = warm.value
                copy.quantityReason = render(warm.reasonCode, warm.arguments, fallback: warm.fallback)
                copy.quantityReasonArguments = warm.arguments
                return copy
            }

            let multipliers = traveler.flatMap { rules.party.ageGroups[$0.ageGroup.rawValue]?.quantityMultipliers } ?? [:]
            // The clothing family runs on the needs-based V2 model; every
            // other kind stays on the legacy policy file untouched.
            if ClothingQuantityEngine.handles(catalogItem.quantityKind) {
                let result = clothingEngine.quantity(
                    kind: catalogItem.quantityKind,
                    context: clothingContext,
                    itemName: catalogItem.displayName,
                    traveler: traveler,
                    multipliers: multipliers,
                    appearanceUnits: appearanceUnits[substitutionGroup(item)] ?? 0
                )
                copy.quantity = result.value
                copy.quantityReason = result.reason
                copy.quantityEvidence = result.evidence
            } else {
                let result = engine.quantity(
                    kind: catalogItem.quantityKind,
                    context: context,
                    itemName: catalogItem.displayName,
                    traveler: traveler,
                    multipliers: multipliers
                )
                copy.quantity = result.value
                copy.quantityReason = result.reason
            }
            // Diapers satisfy most underwear uses — partial coverage, keyed
            // to the explicit diapers need and never the age alone, and a
            // few pairs stay for the potty-training case.
            if catalogItem.quantityKind == "daily_underwear",
               let traveler,
               traveler.ageGroup.skipsAdultPersonalEssentials,
               traveler.needs.contains(.diapers),
               copy.quantity > CareQuantityEngine.diaperedUnderwearBackup {
                copy.quantity = CareQuantityEngine.diaperedUnderwearBackup
                copy.quantityReason = render(
                    "quantity.underwear_diapered",
                    ["quantity": "\(copy.quantity)", "name": traveler.displayName],
                    fallback: "\(traveler.displayName) is mostly in diapers — \(copy.quantity) pairs as backup."
                )
                if var evidence = copy.quantityEvidence {
                    evidence.basis = "diaperedBackup"
                    evidence.quantity = copy.quantity
                    copy.quantityEvidence = evidence
                }
            }
            return copy
        }
        .sorted {
            if $0.ownershipType != $1.ownershipType { return $0.ownershipType == .shared }
            if $0.travelerID != $1.travelerID {
                return ($0.travelerID?.uuidString ?? "") < ($1.travelerID?.uuidString ?? "")
            }
            if $0.category != $1.category { return $0.category.rawValue < $1.category.rawValue }
            return $0.displayName < $1.displayName
        }
    }


    private func activityReason(_ activity: String, destination: String) -> String {
        switch activity {
        case "hiking": "Hiking is on your plans."
        case "camping": "You're camping on this trip."
        case "running": "You plan to run."
        case "sightseeing": "You'll have sightseeing days in \(destination)."
        default: "Based on what you'll be doing."
        }
    }

    private func chipReason(_ chip: ContextChip) -> String {
        switch chip {
        case .dailyMedication: "You take daily medication."
        case .wearContacts: "You wear contacts."
        case .bringingLaptop: "You're bringing a laptop."
        case .usuallyWorkOut: "You usually work out while traveling."
        case .runWhileTraveling: "You run while traveling."
        case .needFormalOutfit: "You need a formal outfit."
        case .travelingInternationally: "You're traveling internationally."
        case .getColdEasily: "You get cold easily."
        case .laundryAvailable: "You expect to do laundry."
        }
    }
}
