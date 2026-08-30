import SwiftUI

struct PackingImpactCard: View {
    var impacts: [PackingImpact]
    @Binding var expandedID: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(impacts) { impact in
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: impact.symbol)
                            .foregroundStyle(impact.isSeasonal ? Color.secondary : PackWiseColor.accent)
                            .frame(width: 22)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(impact.title)
                                .font(.subheadline.weight(.semibold))
                            Text(impact.summary)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            if expandedID == impact.id {
                                VStack(alignment: .leading, spacing: 4) {
                                    ForEach(impact.affectedItems) { item in
                                        HStack(spacing: 6) {
                                            if let owner = item.ownerLabel {
                                                Text(owner)
                                                    .foregroundStyle(.secondary)
                                            }
                                            Text(item.displayName)
                                            if item.quantity > 1 {
                                                Text("×\(item.quantity)")
                                                    .foregroundStyle(.secondary)
                                            }
                                        }
                                        .font(.caption)
                                    }
                                }
                                .padding(.top, 4)
                            }
                        }
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    expandedID = expandedID == impact.id ? nil : impact.id
                }
                .accessibilityHint(impact.affectedItems.count > 1 ? "Shows affected items" : "")
            }
        }
        .padding(.vertical, 4)
    }
}
