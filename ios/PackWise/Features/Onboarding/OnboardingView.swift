import SwiftUI

struct OnboardingView: View {
    var onFinished: () -> Void
    @State private var page = 0

    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $page) {
                welcome.tag(0)
                howItWorks.tag(1)
                personal.tag(2)
            }
            .tabViewStyle(.page(indexDisplayMode: .always))

            Button(page == 2 ? "Create My First Trip" : "Get Started") {
                if page < 2 {
                    withAnimation { page += 1 }
                } else {
                    onFinished()
                }
            }
            .buttonStyle(PrimaryButtonStyle())
            .padding(.horizontal, 24)
            .padding(.bottom, 28)
        }
        .background(Color(.systemBackground))
    }

    private var welcome: some View {
        ZStack {
            LinearGradient(
                colors: [PackWiseColor.accent.opacity(0.18), Color(.systemBackground)],
                startPoint: .top,
                endPoint: .bottom
            )
            VStack(spacing: 16) {
                Spacer()
                Image(systemName: "suitcase.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(PackWiseColor.accent)
                    .accessibilityHidden(true)
                Text("PackWise")
                    .font(.largeTitle.bold())
                Text("Pack what this trip actually needs.")
                    .font(.title2.weight(.semibold))
                    .multilineTextAlignment(.center)
                Text("Weather, activities, trip length and the way you travel — all considered.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 12)
                Spacer()
            }
            .padding(28)
        }
    }

    private var howItWorks: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Built around your trip")
                .font(.largeTitle.bold())
            PackWiseCard {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Chicago")
                        .font(.title3.bold())
                    Text("5 days · City trip")
                        .foregroundStyle(.secondary)
                    Text("Rain Saturday")
                        .foregroundStyle(.secondary)
                }
            }
            Image(systemName: "arrow.down")
                .frame(maxWidth: .infinity)
                .foregroundStyle(PackWiseColor.accent)
            VStack(alignment: .leading, spacing: 10) {
                labeledItem("Rain jacket", "Added for expected rain")
                labeledItem("Light layer", "Cool evenings")
                labeledItem("Walking shoes", "Sightseeing days")
            }
            Spacer()
        }
        .padding(24)
    }

    private var personal: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("It gets more personal")
                .font(.largeTitle.bold())
            Text("PackWise remembers what you bring, skip and actually use so future trips fit you better.")
                .font(.title3)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 12) {
                labeledItem("Brought vs skipped", "Learned from your lists")
                labeledItem("Packing style", "Light, Balanced, or Prepared")
                labeledItem("How you travel", "Carry-on, checked, or backpack")
            }
            Spacer()
        }
        .padding(24)
    }

    private func labeledItem(_ title: String, _ subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.headline)
            Text(subtitle).font(.subheadline).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

}
