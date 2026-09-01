import Foundation

/// Engine output plus the coverage decisions behind it. `items` is what the
/// product consumes; `coverageSuppressions` is the record of what the
/// resolver removed and why, kept from the start so the golden ledger shows
/// reasoning rather than rules silently not firing.
struct EngineGeneration: Sendable {
    var items: [PackingItemDraft]
    var coverageSuppressions: [CoverageSuppression]
}

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
        let party = context.effectiveParty
        let generated = party.usesSimpleList
            ? generateSimple(context: context, existing: existing, overrides: overrides)
            : generateForParty(context: context, existing: existing, overrides: overrides)
        return EngineGeneration(
            items: generated.items.map { PartyInvariants.normalize($0, in: party) },
            coverageSuppressions: generated.suppressions
        )
    }

    func recommendationDiff(
        context: TripContext,
        existing: [PackingItemDraft],
        overrides: [RecommendationOverrideDraft]
    ) -> RecommendationDiff {
        let generated = generate(context: context, existing: [], overrides: overrides)
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
            } else if let fresh = generatedByKey[item.recommendationKey], fresh.quantity != item.quantity {
                quantityChanges.append(QuantityChangeSuggestion(item: item, suggestedQuantity: fresh.quantity))
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
            } else if let fresh = generatedByID[id], fresh.quantity != item.quantity {
                quantityChanges.append(QuantityChangeSuggestion(item: item, suggestedQuantity: fresh.quantity))
            }
        }
        return RecommendationDiff(add: add, removeCandidates: removeCandidates, quantityChanges: quantityChanges)
    }

    private func generateSimple(
        context: TripContext,
        existing: [PackingItemDraft],
        overrides: [RecommendationOverrideDraft]
    ) -> (items: [PackingItemDraft], suppressions: [CoverageSuppression]) {
        let suggestions = ruleSuggestions(for: context)
        let resolved = resolve(
            suggestions: suggestions,
            context: context,
            existing: existing,
            overrides: overrides,
            ownership: .personal,
            travelerID: context.effectiveParty.primary.id,
            assignedTravelerID: context.effectiveParty.primary.id
        )
        let (covered, suppressions) = applyCoverage(resolved, context: context)
        return (applyQuantities(covered, context: context), suppressions)
    }

    private func generateForParty(
        context: TripContext,
        existing: [PackingItemDraft],
        overrides: [RecommendationOverrideDraft]
    ) -> (items: [PackingItemDraft], suppressions: [CoverageSuppression]) {
        let party = context.effectiveParty
        let sharedIDs = Set(rules.party.sharedByDefault)
        // Weather and trip-wide activity signals are computed once, then split
        // into personal vs shared effects so rain does not become 4 umbrellas.
        let tripSuggestions = ruleSuggestions(for: tripWideContext(context))
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
                if sharedIDs.contains(suggestion.canonicalItemID) {
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
                assignedTravelerID: traveler.carrierID
            ))
        }

        result.append(contentsOf: resolve(
            suggestions: Array(sharedCollected.values),
            context: context,
            existing: existing,
            overrides: overrides,
            ownership: .shared,
            travelerID: nil,
            assignedTravelerID: nil
        ))

        var seen = Set<UUID>()
        result = result.filter { seen.insert($0.id).inserted }
        let (covered, suppressions) = applyCoverage(result, context: context)
        return (applyQuantities(covered, context: context), suppressions)
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
        context: TripContext,
        into collected: inout [String: RuleSuggestion]
    ) {
        for id in ids {
            guard let item = catalog.item(id: id) else { continue }
            if item.travelRestrictionReviewRequired && context.bagType.isSpaceConstrained { continue }
            let reason = render(code, arguments, category: item.category.rawValue, fallback: fallback)
            if var existing = collected[id] {
                if !existing.signals.contains(signal) {
                    existing.signals.append(signal)
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
                    reason: reason
                )
            }
        }
    }

    private func mergeSuggestion(_ suggestion: RuleSuggestion, into collected: inout [String: RuleSuggestion]) {
        if var existing = collected[suggestion.canonicalItemID] {
            for signal in suggestion.signals where !existing.signals.contains(signal) {
                existing.signals.append(signal)
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

    private func ruleSuggestions(for context: TripContext) -> [RuleSuggestion] {
        var collected: [String: RuleSuggestion] = [:]

        func add(_ ids: [String], signal: RecommendationSignal, code: String, arguments: [String: String] = [:], fallback: String) {
            addIDs(ids, signal: signal, code: code, arguments: arguments, fallback: fallback, context: context, into: &collected)
        }

        add(rules.baseEssentials, signal: .baseEssential, code: "base.essential", fallback: "A core item for almost every trip.")

        if let typeRule = rules.tripTypes[context.tripType.rawValue] {
            add(
                typeRule.add,
                signal: .tripType,
                code: "trip_type.generic",
                arguments: ["tripType": context.tripType.title.lowercased()],
                fallback: "Suggested for a \(context.tripType.title.lowercased()) trip."
            )
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

        addWeather(context: context, into: &collected)

        if context.bagType == .carryOn || context.bagType == .personalItem || context.transportation == .flight {
            add(
                ["travel_comfort.empty_security_bottle"],
                signal: .tripType,
                code: "flight.empty_bottle",
                fallback: "Useful after airport security."
            )
        }

        return Array(collected.values)
    }

    private func addWeather(context: TripContext, into collected: inout [String: RuleSuggestion]) {
        guard let weather = context.weather, weather.isPreciseForecast || !weather.dailyForecast.isEmpty else {
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
            for id in ids {
                guard let item = catalog.item(id: id) else { continue }
                let reason = render(code, arguments, category: item.category.rawValue, fallback: fallback)
                if var existing = collected[id] {
                    if !existing.signals.contains(.weather) {
                        existing.signals.append(.weather)
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
                        reason: reason
                    )
                }
            }
        }

        let rainArgs = ["rainDays": "\(conditions.rainDays)", "tripDays": "\(conditions.tripDays)"]
        if conditions.signals.contains(.meaningfulRain) || conditions.signals.contains(.persistentRain) {
            let weekday = weather.dailyForecast.first(where: { $0.rainProbability >= rules.weather.thresholds.rainProbabilityAdd })?
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
                    reason: render("weather.seasonal_layer", [:], fallback: "Seasonal conditions suggest a warmer layer.")
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
                    reason: render("weather.seasonal_sun", [:], fallback: "Seasonal sun is likely.")
                )
            }
        }
    }

    private func resolve(
        suggestions: [RuleSuggestion],
        context: TripContext,
        existing: [PackingItemDraft],
        overrides: [RecommendationOverrideDraft],
        ownership: PackingOwnership,
        travelerID: UUID?,
        assignedTravelerID: UUID?
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
            if isRemoved(suggestion.canonicalItemID, ownership: ownership, travelerID: travelerID, overrides: overrides) {
                continue
            }
            let key = recommendationKey(canonical: suggestion.canonicalItemID, ownership: ownership, travelerID: travelerID)
            let existingItem = existingByKey[key] ?? existingByKey["canonical:\(suggestion.canonicalItemID)"]
            if let existingItem {
                if existingItem.isUserModified || existingItem.isUserAdded {
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
            if shouldSkipOptional(catalogItem, context: context) { continue }

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
                    ownershipType: ownership,
                    travelerID: travelerID,
                    assignedTravelerID: assignedTravelerID
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

    private func isRemoved(
        _ canonicalItemID: String,
        ownership: PackingOwnership,
        travelerID: UUID?,
        overrides: [RecommendationOverrideDraft]
    ) -> Bool {
        overrides.contains { override in
            guard override.action == "removed", override.canonicalItemID == canonicalItemID else { return false }
            if let overrideTraveler = override.travelerID, overrideTraveler != travelerID { return false }
            if let overrideOwnership = override.ownershipType, overrideOwnership != ownership { return false }
            return true
        }
    }

    private func shouldSkipOptional(_ item: CatalogItem, context: TripContext) -> Bool {
        if item.travelRestrictionReviewRequired && context.bagType.isSpaceConstrained { return true }
        guard item.importance == .optional else { return false }
        guard context.bagType.appliesBagConstraint, context.bagType.isSpaceConstrained else { return false }
        if context.packingStyle == .prepared { return false }
        if context.packingStyle == .light {
            return !item.tags.contains(where: { ["base", "rain", "cold", "medication"].contains($0) })
        }
        return item.tags.contains("optional_luxury")
    }

    /// Capability coverage for footwear and outerwear, per traveler.
    /// Generalizes the old one-off substitution rules: the resolver decides
    /// from derived needs and an explicit priority order, and every
    /// suppression is recorded rather than silently dropped.
    private func applyCoverage(
        _ items: [PackingItemDraft],
        context: TripContext
    ) -> ([PackingItemDraft], [CoverageSuppression]) {
        let needs = CoverageResolver.needs(context: context, thresholds: rules.weather.thresholds)
        // A solo list has one owner, so user-added items (nil travelerID)
        // fold into the primary's group and can claim coverage. In a party
        // list an unassigned item stays its own group — guessing whose it is
        // would be inference, and ambiguous inference resolves to don't.
        let primaryID = context.effectiveParty.primary.id
        let groups = Dictionary(grouping: items) { (item: PackingItemDraft) -> String in
            if item.ownershipType == .shared { return "shared" }
            let owner = item.travelerID ?? (context.effectiveParty.usesSimpleList ? primaryID : nil)
            return "personal:\(owner?.uuidString ?? "unassigned")"
        }
        var keptAll: [PackingItemDraft] = []
        var suppressionsAll: [CoverageSuppression] = []
        for key in groups.keys.sorted() {
            var (kept, suppressions) = CoverageResolver.resolve(items: groups[key] ?? [], needs: needs)
            // The versatile shoe that absorbed the walking need keeps V1's
            // substitution copy until Step 4's trace-driven reasons land.
            for suppression in suppressions where suppression.canonicalItemID == "footwear.walking_shoes" {
                guard let coverer = suppression.coveredBy.first,
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

    private func applyQuantities(_ items: [PackingItemDraft], context: TripContext) -> [PackingItemDraft] {
        let engine = QuantityEngine(policies: rules.quantities.policies, reasons: rules.reasons)
        let clothingEngine = ClothingQuantityEngine(reasons: rules.reasons)
        let party = context.effectiveParty
        return items.map { item in
            var copy = item
            guard let canonical = item.canonicalItemID, let catalogItem = catalog.item(id: canonical) else {
                return copy
            }
            if item.isUserModified { return copy }

            if item.ownershipType == .shared {
                let policy = rules.party.sharingPolicies[canonical]
                    ?? SharingPolicyRule(policy: .singlePerParty, per: nil, min: 1, value: 1)
                if policy.policy != .personalOnly {
                    copy.quantity = sharedQuantity(policy, context: context, party: party)
                    copy.quantityReason = sharedQuantityReason(canonical, quantity: copy.quantity, context: context, party: party)
                    return copy
                }
            }

            let traveler = party.travelers.first { $0.id == item.travelerID }
            let multipliers = traveler.flatMap { rules.party.ageGroups[$0.ageGroup.rawValue]?.quantityMultipliers } ?? [:]
            // The clothing family runs on the needs-based V2 model; every
            // other kind stays on the legacy policy file untouched.
            let result = ClothingQuantityEngine.handles(catalogItem.quantityKind)
                ? clothingEngine.quantity(
                    kind: catalogItem.quantityKind,
                    context: context,
                    itemName: catalogItem.displayName,
                    traveler: traveler,
                    multipliers: multipliers
                )
                : engine.quantity(
                    kind: catalogItem.quantityKind,
                    context: context,
                    itemName: catalogItem.displayName,
                    traveler: traveler,
                    multipliers: multipliers
                )
            copy.quantity = result.value
            copy.quantityReason = result.reason
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

    private func sharedQuantity(_ rule: SharingPolicyRule, context: TripContext, party: TripParty) -> Int {
        let minimum = rule.min ?? 1
        let per = max(1, rule.per ?? 1)
        switch rule.policy {
        case .singlePerParty, .personalOnly:
            return rule.value ?? 1
        case .scaleByParty:
            return max(minimum, Int((Double(party.travelers.count) / Double(per)).rounded(.up)))
        case .scaleByDevices:
            return max(minimum, Int((Double(max(1, party.adults.count)) / Double(per)).rounded(.up)))
        case .scaleByDurationAndParty:
            return max(minimum, Int((Double(party.travelers.count * context.durationDays) / Double(per)).rounded(.up)))
        }
    }

    private func sharedQuantityReason(_ canonical: String, quantity: Int, context: TripContext, party: TripParty) -> String {
        if canonical == "essentials.umbrella_compact", let weather = context.weather, weather.rainDays > 0 {
            return render(
                "party.shared_umbrella",
                ["quantity": "\(quantity)", "rainDays": "\(weather.rainDays)"],
                fallback: "Rain is expected on \(weather.rainDays) days. \(quantity) umbrellas should cover your family without packing one per person."
            )
        }
        return render(
            "party.shared",
            ["quantity": "\(quantity)", "partySize": "\(party.travelers.count)"],
            fallback: quantity == 1
                ? "One for the group — not one per person."
                : "\(quantity) for the group — not one per person."
        )
    }

    private func activityReason(_ activity: String, destination: String) -> String {
        switch activity {
        case "hiking": "Hiking is on your plans."
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
