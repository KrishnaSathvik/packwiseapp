import Foundation
import Testing
@testable import PackWise

/// Reason copy quality — Engine V2 plan, Step 4.
///
/// The fallback ladder is specific template → category template → generic
/// fallback, and a generic string rendering on a weather- or activity-driven
/// item is a bug, not acceptable degradation. The matrix test walks the
/// committed goldens — which the golden test guarantees match engine output —
/// so the ban is enforced against every fixture, and erosion shows up as a
/// test failure rather than a slow drift.
struct ReasonQualityTests {
    private static let goldensDirectory = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .appendingPathComponent("Goldens")

    /// The strings the round-2 review called out, banned from any item that
    /// carries a weather or activity signal.
    private static let bannedOnSignaledItems = [
        "Based on what you'll be doing.",
        "A core item for almost every trip."
    ]

    private static let genericCodes: Set<String> = [
        "", "activity.generic", "base.essential", "preference.generic", "trip_type.generic"
    ]

    private struct GoldenFile: Codable {
        struct Item: Codable {
            var canonicalItemID: String
            var signals: [String]
            var reason: String
            var reasonCode: String
        }
        var fixture: String
        var items: [Item]
    }

    private func goldenFiles() throws -> [GoldenFile] {
        let urls = try FileManager.default.contentsOfDirectory(
            at: Self.goldensDirectory,
            includingPropertiesForKeys: nil
        ).filter { $0.pathExtension == "json" }
        #expect(urls.count == 15)
        return try urls.map { try JSONDecoder().decode(GoldenFile.self, from: Data(contentsOf: $0)) }
    }

    /// No item carrying a weather or activity signal may render generic copy,
    /// across the entire fixture matrix.
    @Test func noGenericCopyOnWeatherOrActivityItems() throws {
        for golden in try goldenFiles() {
            for item in golden.items {
                guard item.signals.contains("weather") || item.signals.contains("activity") else { continue }
                #expect(
                    !Self.genericCodes.contains(item.reasonCode),
                    "\(golden.fixture): \(item.canonicalItemID) carries \(item.signals) but renders generic code '\(item.reasonCode)'"
                )
                for banned in Self.bannedOnSignaledItems {
                    #expect(
                        item.reason != banned,
                        "\(golden.fixture): \(item.canonicalItemID) renders banned copy '\(banned)'"
                    )
                }
            }
        }
    }

    /// Every reason code shipped in the goldens has a real template — the
    /// ladder's lower rungs are insurance, not a rendering path we ship.
    @Test func everyShippedReasonCodeHasTemplate() throws {
        let templates = try SharedLibrary.rules().reasons.templates
        for golden in try goldenFiles() {
            for item in golden.items where !item.reasonCode.isEmpty {
                #expect(
                    templates[item.reasonCode] != nil,
                    "\(golden.fixture): \(item.canonicalItemID) code '\(item.reasonCode)' has no template"
                )
            }
        }
    }

    /// Every activity id in the rule file has a specific template, so no new
    /// activity can silently ship with generic copy.
    @Test func everyActivityRuleHasSpecificTemplate() throws {
        let rules = try SharedLibrary.rules()
        for activity in rules.activities.keys {
            #expect(
                rules.reasons.templates["activity.\(activity)"] != nil,
                "activity '\(activity)' has no reason template"
            )
        }
        for chip in ContextChip.allCases {
            #expect(
                rules.reasons.templates["preference.\(chip.rawValue)"] != nil,
                "chip '\(chip.rawValue)' has no reason template"
            )
        }
    }

    /// The ladder resolves in order: specific, then category, then fallback.
    @Test func fallbackLadderResolvesInOrder() {
        let templates = [
            "activity.swimming": "You'll be swimming on this trip.",
            "category.clothing": "Clothing matched to this trip."
        ]
        #expect(
            ReasonRenderer.render(code: "activity.swimming", arguments: [:], templates: templates, category: "clothing", fallback: "generic")
                == "You'll be swimming on this trip."
        )
        #expect(
            ReasonRenderer.render(code: "activity.unknown", arguments: [:], templates: templates, category: "clothing", fallback: "generic")
                == "Clothing matched to this trip."
        )
        #expect(
            ReasonRenderer.render(code: "activity.unknown", arguments: [:], templates: templates, category: "electronics", fallback: "generic")
                == "generic"
        )
    }

    /// More specific signals take over an item's reason; equals keep the
    /// incumbent so output stays deterministic.
    @Test func reasonTiersOrderSpecificity() {
        #expect(ReasonRenderer.tier("weather.rain_days") > ReasonRenderer.tier("activity.swimming"))
        #expect(ReasonRenderer.tier("activity.swimming") > ReasonRenderer.tier("trip_type.generic"))
        #expect(ReasonRenderer.tier("trip_type.generic") > ReasonRenderer.tier("base.essential"))
        #expect(ReasonRenderer.tier("substitution.running_covers_walking") == ReasonRenderer.tier("activity.running"))
    }
}
