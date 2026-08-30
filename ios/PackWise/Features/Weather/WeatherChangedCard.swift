import SwiftUI

struct WeatherChangedCard: View {
    var proposal: WeatherChangeProposal
    var onReview: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Weather changed")
                .font(.subheadline.weight(.semibold))
            Text(proposal.headline)
                .font(.subheadline)
            if !proposal.previewNames.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(proposal.previewNames.enumerated()), id: \.offset) { _, name in
                        Text(name)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            Button("Review changes", action: onReview)
                .font(.subheadline.weight(.medium))
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}
