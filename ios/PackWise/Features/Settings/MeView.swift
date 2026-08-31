import SwiftData
import SwiftUI

struct MeView: View {
    @Query private var preferenceRecords: [PackingPreferenceRecord]
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        NavigationStack {
            if let prefs = preferenceRecords.first {
                MeContent(prefs: prefs)
                    .onDisappear { try? modelContext.save() }
            } else {
                ContentUnavailableView("Preferences unavailable", systemImage: "person.crop.circle")
            }
        }
    }
}

/// What PackWise knows about you, and only what it actually knows.
///
/// The reference board sketches a "Your Packing Habits" block — what you
/// usually bring, what you tend to skip. There is no learned habit data in the
/// product: these four switches are things you set yourself, and the post-trip
/// memory loop is outside MVP. Showing invented habits would be a lie about
/// what the app has observed, so this screen shows the preferences that exist.
private struct MeContent: View {
    @Bindable var prefs: PackingPreferenceRecord

    // The record stores raw values; these are just for the row glyphs.
    private var packingStyle: PackingStyle {
        PackingStyle(rawValue: prefs.packingStyleRaw) ?? .balanced
    }

    private var preferredBag: BagType {
        BagType(rawValue: prefs.preferredBagRaw) ?? .notSure
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: PackWiseSpacing.loose) {
                homeCountry
                defaults
                units
                usuallyTrue
                privacy
                #if DEBUG
                // Compiled out of Release, TestFlight, and App Store builds
                // along with everything it links to.
                developerTools
                #endif
            }
            .padding(PackWiseSpacing.comfortable)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Me")
    }

    private func section<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: PackWiseSpacing.snug) {
            PackWiseSectionHeader(title: title)
            PackWiseCard {
                VStack(alignment: .leading, spacing: PackWiseSpacing.regular) {
                    content()
                }
            }
        }
    }

    private var homeCountry: some View {
        section("Home country") {
            HStack(spacing: PackWiseSpacing.regular) {
                PackWiseIconBadge(symbol: "house", tint: .blue)
                TextField("Country code", text: $prefs.homeCountryCode)
                    .textInputAutocapitalization(.characters)
                    .onChange(of: prefs.homeCountryCode) { _, value in
                        prefs.homeCountryCode = value.uppercased()
                    }
            }
            if prefs.homeCountrySourceRaw != HomeCountrySource.userConfirmed.rawValue {
                Divider()
                Text("Suggested from this iPhone. Confirm before PackWise treats trips as international.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Button("This is my home country") {
                    prefs.homeCountrySourceRaw = HomeCountrySource.userConfirmed.rawValue
                }
                .buttonStyle(SecondaryButtonStyle())
            } else {
                Divider()
                Text("Confirmed. International trips are destinations outside this country.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var defaults: some View {
        section("Trip defaults") {
            HStack(spacing: PackWiseSpacing.regular) {
                PackWiseIconBadge(
                    symbol: packingStyle.symbol,
                    tint: packingStyle.tint
                )
                Text("Packing style")
                Spacer()
                Picker("Packing style", selection: $prefs.packingStyleRaw) {
                    ForEach(PackingStyle.allCases) { style in
                        Text(style.title).tag(style.rawValue)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
            }
            Divider()
            HStack(spacing: PackWiseSpacing.regular) {
                PackWiseIconBadge(
                    symbol: preferredBag.symbol,
                    tint: preferredBag.tint
                )
                Text("Preferred bag")
                Spacer()
                Picker("Preferred bag", selection: $prefs.preferredBagRaw) {
                    ForEach(BagType.allCases) { bag in
                        Text(bag.title).tag(bag.rawValue)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
            }
        }
    }

    private var units: some View {
        section("Units") {
            Toggle("Fahrenheit", isOn: $prefs.usesFahrenheit)
            Divider()
            Toggle("Imperial (lb / miles)", isOn: $prefs.usesImperial)
        }
    }

    private var usuallyTrue: some View {
        section("Usually true for me") {
            Toggle("I usually work out while traveling", isOn: $prefs.usuallyWorkOut)
            Divider()
            Toggle("I usually bring a laptop", isOn: $prefs.usuallyBringLaptop)
            Divider()
            Toggle("I wear contacts", isOn: $prefs.wearContacts)
            Divider()
            Toggle("I always bring medication", isOn: $prefs.alwaysBringMedication)
        }
    }

    private var privacy: some View {
        section("Privacy") {
            HStack(spacing: PackWiseSpacing.regular) {
                PackWiseIconBadge(symbol: "lock", tint: .gray)
                Text("Trips and lists stay on this iPhone. PackWise does not need live location.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    #if DEBUG
    private var developerTools: some View {
        PackWiseCard {
            NavigationLink {
                DeveloperToolsView()
            } label: {
                HStack(spacing: PackWiseSpacing.regular) {
                    PackWiseIconBadge(symbol: "hammer", tint: .gray)
                    Text("Developer Tools")
                        .foregroundStyle(.primary)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }
    #endif
}
