import SwiftUI

/// Why the list looks the way it does.
///
/// This is one of PackWise's signature ideas — the app explaining its own
/// decisions — and it previously rendered as a column of grey help text. Each
/// impact now leads with a tinted glyph, states the condition in the headline,
/// and says how many items it moved, so the block reads as a finding rather
/// than a footnote.
struct PackingImpactCard: View {
    var impacts: [PackingImpact]
    @Binding var expandedID: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(impacts.enumerated()), id: \.element.id) { index, impact in
                if index > 0 {
                    PackWiseRowDivider(inset: 0)
                        .padding(.leading, PackWiseSize.badge + PackWiseSpacing.regular)
                        .padding(.vertical, PackWiseSpacing.regular)
                }
                row(impact)
            }
        }
    }

    private func row(_ impact: PackingImpact) -> some View {
        let isExpanded = expandedID == impact.id
        let count = impact.affectedItems.count

        return VStack(alignment: .leading, spacing: PackWiseSpacing.snug) {
            HStack(alignment: .top, spacing: PackWiseSpacing.regular) {
                PackWiseIconBadge(symbol: impact.symbol, tint: impact.tint)

                VStack(alignment: .leading, spacing: PackWiseSpacing.hairline) {
                    Text(impact.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(impact.summary)
                        .font(.subheadline)
                        .foregroundStyle(PackWiseColor.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: PackWiseSpacing.snug)

                if count > 0 {
                    HStack(spacing: PackWiseSpacing.tight) {
                        Text("\(count)")
                            .font(.caption.weight(.semibold))
                            .monospacedDigit()
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.caption2.weight(.bold))
                    }
                    .foregroundStyle(PackWiseColor.textSecondary)
                }
            }

            if isExpanded, count > 0 {
                PackWiseFlowLayout(spacing: PackWiseSpacing.snug, lineSpacing: PackWiseSpacing.snug) {
                    ForEach(impact.affectedItems) { item in
                        HStack(spacing: PackWiseSpacing.tight) {
                            if let owner = item.ownerLabel {
                                Text(owner)
                                    .foregroundStyle(PackWiseColor.textSecondary)
                            }
                            Text(item.displayName)
                            if item.quantity > 1 {
                                Text("×\(item.quantity)")
                                    .foregroundStyle(PackWiseColor.textSecondary)
                                    .monospacedDigit()
                            }
                        }
                        .font(.caption.weight(.medium))
                        .padding(.horizontal, PackWiseSpacing.snug)
                        .padding(.vertical, PackWiseSpacing.tight)
                        .background(PackWiseColor.surfaceAlt, in: Capsule())
                    }
                }
                .padding(.leading, PackWiseSize.badge + PackWiseSpacing.regular)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            guard count > 0 else { return }
            expandedID = isExpanded ? nil : impact.id
        }
        .accessibilityElement(children: .combine)
        .accessibilityHint(count > 0 ? "Shows affected items" : "")
    }
}

/// Presentation only. `PackingImpact` already carries its glyph; the hue is
/// what separates "rain expected" from "high UV" at a glance, and it has no
/// business in `Domain/`.
private extension PackingImpact {
    var tint: Color {
        switch signal {
        case .meaningfulRain, .persistentRain: .blue
        case .coldEvenings: .indigo
        case .highUVExposure, .hotOutdoorExposure: .orange
        case .highWindExposure: .mint
        case .snowExposure: .teal
        case .largeTemperatureSwing: .purple
        case .seasonal: .gray
        }
    }
}
