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
/// Two blocks — "My preferences" and "Usually true for me" — with Privacy and
/// Developer Tools at the bottom. The reference board sketches a "Your
/// Packing Habits" block of learned data; there is no learned habit data in
/// the product, so this screen shows the preferences that exist.
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
                myPreferences
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
        .background(PackWiseColor.screen)
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

    private var myPreferences: some View {
        section("My preferences") {
            HStack(spacing: PackWiseSpacing.regular) {
                PackWiseIconBadge(symbol: "house", tint: PackWiseColor.accent)
                Text("Home country")
                Spacer()
                TextField("US", text: $prefs.homeCountryCode)
                    .frame(width: 64)
                    .multilineTextAlignment(.trailing)
                    .textInputAutocapitalization(.characters)
                    .onChange(of: prefs.homeCountryCode) { _, value in
                        prefs.homeCountryCode = value.uppercased()
                    }
            }
            if prefs.homeCountrySourceRaw != HomeCountrySource.userConfirmed.rawValue {
                Text("Suggested from this iPhone. Confirm before PackWise treats trips as international.")
                    .font(.footnote)
                    .foregroundStyle(PackWiseColor.textSecondary)
                Button("This is my home country") {
                    prefs.homeCountrySourceRaw = HomeCountrySource.userConfirmed.rawValue
                }
                .buttonStyle(SecondaryButtonStyle())
            }
            PackWiseRowDivider()
            HStack(spacing: PackWiseSpacing.regular) {
                PackWiseIconBadge(symbol: packingStyle.symbol, tint: packingStyle.tint)
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
            PackWiseRowDivider()
            HStack(spacing: PackWiseSpacing.regular) {
                PackWiseIconBadge(symbol: preferredBag.symbol, tint: preferredBag.tint)
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
            PackWiseRowDivider()
            // One summary row, as the sheet draws it — but the model keeps
            // two settings, so the row pushes to a screen with both controls.
            NavigationLink {
                UnitsDetailView(prefs: prefs)
            } label: {
                HStack(spacing: PackWiseSpacing.regular) {
                    PackWiseIconBadge(symbol: "ruler", tint: .teal)
                    Text("Units")
                        .foregroundStyle(PackWiseColor.textPrimary)
                    Spacer()
                    Text(unitsSummary)
                        .font(.subheadline)
                        .foregroundStyle(PackWiseColor.textSecondary)
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(PackWiseColor.textTertiary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    private var unitsSummary: String {
        let temperature = prefs.usesFahrenheit ? "Fahrenheit" : "Celsius"
        let distance = prefs.usesImperial ? "Miles" : "Kilometers"
        return "\(temperature) · \(distance)"
    }

    private var usuallyTrue: some View {
        section("Usually true for me") {
            Toggle("I usually work out while traveling", isOn: $prefs.usuallyWorkOut)
            PackWiseRowDivider(inset: 0)
            Toggle("I usually bring a laptop", isOn: $prefs.usuallyBringLaptop)
            PackWiseRowDivider(inset: 0)
            Toggle("I wear contacts", isOn: $prefs.wearContacts)
            PackWiseRowDivider(inset: 0)
            Toggle("I always bring medication", isOn: $prefs.alwaysBringMedication)
        }
    }

    private var privacy: some View {
        section("Privacy") {
            HStack(spacing: PackWiseSpacing.regular) {
                PackWiseIconBadge(symbol: "lock", tint: .gray)
                Text("Trips and lists stay on this iPhone. PackWise does not need live location.")
                    .font(.footnote)
                    .foregroundStyle(PackWiseColor.textSecondary)
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
                        .foregroundStyle(PackWiseColor.textPrimary)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(PackWiseColor.textTertiary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }
    #endif
}

/// Both unit preferences, spelled out — the Me row shows one combined
/// summary, but temperature and distance & weight are separate settings.
private struct UnitsDetailView: View {
    @Bindable var prefs: PackingPreferenceRecord

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: PackWiseSpacing.loose) {
                VStack(alignment: .leading, spacing: PackWiseSpacing.snug) {
                    PackWiseSectionHeader(title: "Temperature")
                    PackWiseCard {
                        Picker("Temperature", selection: $prefs.usesFahrenheit) {
                            Text("Fahrenheit").tag(true)
                            Text("Celsius").tag(false)
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                    }
                }
                VStack(alignment: .leading, spacing: PackWiseSpacing.snug) {
                    PackWiseSectionHeader(title: "Distance & weight")
                    PackWiseCard {
                        Picker("Distance & weight", selection: $prefs.usesImperial) {
                            Text("Imperial").tag(true)
                            Text("Metric").tag(false)
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                    }
                }
            }
            .padding(PackWiseSpacing.comfortable)
        }
        .background(PackWiseColor.screen)
        .navigationTitle("Units")
        .navigationBarTitleDisplayMode(.inline)
    }
}
