import SwiftData
import SwiftUI

struct MeView: View {
    @Query private var preferenceRecords: [PackingPreferenceRecord]
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        NavigationStack {
            if let prefs = preferenceRecords.first {
                MeForm(prefs: prefs)
                    .onDisappear { try? modelContext.save() }
            } else {
                ContentUnavailableView("Preferences unavailable", systemImage: "person.crop.circle")
            }
        }
    }
}

private struct MeForm: View {
    @Bindable var prefs: PackingPreferenceRecord

    var body: some View {
        Form {
            Section("Home country") {
                TextField("Country code", text: $prefs.homeCountryCode)
                    .textInputAutocapitalization(.characters)
                    .onChange(of: prefs.homeCountryCode) { _, value in
                        prefs.homeCountryCode = value.uppercased()
                    }
                if prefs.homeCountrySourceRaw != HomeCountrySource.userConfirmed.rawValue {
                    Button("This is my home country") {
                        prefs.homeCountrySourceRaw = HomeCountrySource.userConfirmed.rawValue
                    }
                    Text("Suggested from this iPhone. Confirm before PackWise treats trips as international.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Confirmed. International trips are destinations outside this country.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            Section("Defaults") {
                Picker("Packing style", selection: $prefs.packingStyleRaw) {
                    ForEach(PackingStyle.allCases) { style in
                        Text(style.title).tag(style.rawValue)
                    }
                }
                Picker("Preferred bag", selection: $prefs.preferredBagRaw) {
                    ForEach(BagType.allCases) { bag in
                        Text(bag.title).tag(bag.rawValue)
                    }
                }
            }
            Section("Units") {
                Toggle("Fahrenheit", isOn: $prefs.usesFahrenheit)
                Toggle("Imperial (lb / miles)", isOn: $prefs.usesImperial)
            }
            Section("Usually true for me") {
                Toggle("I usually work out while traveling", isOn: $prefs.usuallyWorkOut)
                Toggle("I usually bring a laptop", isOn: $prefs.usuallyBringLaptop)
                Toggle("I wear contacts", isOn: $prefs.wearContacts)
                Toggle("I always bring medication", isOn: $prefs.alwaysBringMedication)
            }
            Section("Privacy") {
                Text("Trips and lists stay on this iPhone. PackWise does not need live location.")
                    .foregroundStyle(.secondary)
            }
            #if DEBUG
            // Compiled out of Release, TestFlight, and App Store builds along
            // with everything it links to.
            Section {
                NavigationLink("Developer Tools") {
                    DeveloperToolsView()
                }
            }
            #endif
        }
        .navigationTitle("Me")
    }
}
