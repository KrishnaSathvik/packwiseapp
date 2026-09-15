import SwiftUI

/// The one chrome every setup step shares (design Section 11): native
/// Cancel/Back in the navigation bar, a compact progress indicator, the 28pt
/// question and gray helper, scrollable content, and the primary action
/// pinned to the bottom safe area — never a top-right Next.
///
/// The bottom action sits in `safeAreaInset`, so it rides above the keyboard
/// and the scroll content always clears it.
struct TripSetupShell<Content: View>: View {
    enum Leading {
        case cancel
        case back
    }

    var step: SetupStep
    var leading: Leading
    var primaryTitle: String
    var primaryEnabled: Bool
    var onLeading: () -> Void
    var onPrimary: () -> Void
    /// Optional line above the action explaining why it is disabled.
    var primaryHint: String? = nil
    @ViewBuilder var content: () -> Content

    /// Debug capture only: where the scroll view starts, so the harness can
    /// photograph content below the fold. Nil in the app.
    @Environment(\.setupCaptureScrollAnchor) private var captureScrollAnchor

    var body: some View {
        VStack(spacing: 0) {
            progressTrack
            ScrollView {
                VStack(alignment: .leading, spacing: PackWiseSpacing.comfortable) {
                    heading
                    content()
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, PackWiseSpacing.comfortable)
                .padding(.top, PackWiseSpacing.regular)
                .padding(.bottom, PackWiseSpacing.section)
            }
            .scrollDismissesKeyboard(.interactively)
            .defaultScrollAnchor(captureScrollAnchor)
        }
        .background(PackWiseColor.screen)
        .safeAreaInset(edge: .bottom, spacing: 0) { actionBar }
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbarBackground(PackWiseColor.screen, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbar { leadingToolbarItem }
    }

    /// A thin track under the bar, plus the step count read once by
    /// VoiceOver ("Step 3 of 9").
    private var progressTrack: some View {
        GeometryReader { proxy in
            Rectangle()
                .fill(PackWiseColor.accent)
                .frame(width: proxy.size.width * Double(step.number) / Double(SetupStep.count))
        }
        .frame(height: 2)
        .background(PackWiseColor.border)
        .accessibilityHidden(true)
    }

    private var heading: some View {
        VStack(alignment: .leading, spacing: PackWiseSpacing.snug) {
            Text("Step \(step.number) of \(SetupStep.count)")
                .font(PackWiseFont.rowSubtitle.weight(.semibold))
                .foregroundStyle(PackWiseColor.accent)
                .accessibilityLabel("Step \(step.number) of \(SetupStep.count)")
            Text(step.title)
                .font(PackWiseFont.screenTitle)
                .foregroundStyle(PackWiseColor.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            Text(step.subtitle)
                .font(PackWiseFont.screenSubtitle)
                .foregroundStyle(PackWiseColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.bottom, PackWiseSpacing.tight)
    }

    private var actionBar: some View {
        VStack(spacing: PackWiseSpacing.snug) {
            if let primaryHint, !primaryEnabled {
                Text(primaryHint)
                    .font(PackWiseFont.rowSubtitle)
                    .foregroundStyle(PackWiseColor.textSecondary)
                    .multilineTextAlignment(.center)
            }
            Button(primaryTitle, action: onPrimary)
                .buttonStyle(PrimaryButtonStyle())
                .disabled(!primaryEnabled)
        }
        .padding(.horizontal, PackWiseSpacing.comfortable)
        .padding(.top, PackWiseSpacing.regular)
        .padding(.bottom, PackWiseSpacing.snug)
        .background(PackWiseColor.screen)
        .overlay(alignment: .top) {
            Rectangle().fill(PackWiseColor.border).frame(height: 1)
        }
    }

    // On iOS 26 a toolbar item is wrapped in Liquid Glass by default, and
    // `.buttonStyle(.plain)` does not opt out; `sharedBackgroundVisibility`
    // on the item does. Without `fixedSize` the bar truncates the label.
    @ToolbarContentBuilder
    private var leadingToolbarItem: some ToolbarContent {
        if #available(iOS 26.0, *) {
            ToolbarItem(placement: .cancellationAction) { leadingButton }
                .sharedBackgroundVisibility(.hidden)
        } else {
            ToolbarItem(placement: .cancellationAction) { leadingButton }
        }
    }

    @ViewBuilder
    private var leadingButton: some View {
        switch leading {
        case .cancel:
            Button("Cancel", action: onLeading)
                .buttonStyle(.plain)
                .foregroundStyle(PackWiseColor.accent)
                .lineLimit(1)
                .fixedSize()
        case .back:
            Button(action: onLeading) {
                Label("Back", systemImage: "chevron.left")
                    .labelStyle(.titleAndIcon)
                    .fixedSize()
            }
            .buttonStyle(.plain)
            .foregroundStyle(PackWiseColor.accent)
        }
    }
}

extension EnvironmentValues {
    /// Set only by the Debug preview scene; see `TripSetupShell`.
    @Entry var setupCaptureScrollAnchor: UnitPoint? = nil
}
