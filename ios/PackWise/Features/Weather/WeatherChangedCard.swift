import SwiftUI

/// The forecast moved and the list would change with it.
///
/// A proposal, never an edit: nothing here has been applied. It sits above the
/// weather card on Trip Detail until the user reviews it or keeps the list as
/// it stands.
struct WeatherChangedCard: View {
    var proposal: WeatherChangeProposal
    var onReview: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: PackWiseSpacing.regular) {
            HStack(spacing: PackWiseSpacing.regular) {
                PackWiseIconBadge(symbol: "cloud.sun.rain", tint: .orange)
                VStack(alignment: .leading, spacing: PackWiseSpacing.hairline) {
                    Text("Weather changed")
                        .font(.headline)
                    Text(proposal.headline)
                        .font(.subheadline)
                        .foregroundStyle(PackWiseColor.textSecondary)
                }
            }

            if !proposal.previewNames.isEmpty {
                PackWiseRowDivider(inset: 0)
                VStack(alignment: .leading, spacing: PackWiseSpacing.tight) {
                    ForEach(Array(proposal.previewNames.enumerated()), id: \.offset) { _, name in
                        HStack(alignment: .firstTextBaseline, spacing: PackWiseSpacing.snug) {
                            Image(systemName: "circle.fill")
                                .font(.system(size: 5))
                                .foregroundStyle(PackWiseColor.textTertiary)
                            Text(name)
                                .font(.subheadline)
                                .foregroundStyle(PackWiseColor.textSecondary)
                        }
                    }
                }
            }

            Button("Review changes", action: onReview)
                .buttonStyle(SecondaryButtonStyle())
        }
        .accessibilityElement(children: .contain)
    }
}
