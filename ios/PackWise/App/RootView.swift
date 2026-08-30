import SwiftData
import SwiftUI

struct RootView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var preferenceRecords: [PackingPreferenceRecord]

    var body: some View {
        Group {
            if preferenceRecords.first?.hasCompletedOnboarding == true {
                MainTabView()
            } else {
                OnboardingView {
                    completeOnboarding()
                }
            }
        }
        .task {
            ensurePreferences()
        }
    }

    private func ensurePreferences() {
        if preferenceRecords.isEmpty {
            modelContext.insert(PackingPreferenceRecord(from: .deviceDefaults()))
            try? modelContext.save()
        }
    }

    private func completeOnboarding() {
        ensurePreferences()
        preferenceRecords.first?.hasCompletedOnboarding = true
        try? modelContext.save()
    }
}

struct MainTabView: View {
    var body: some View {
        TabView {
            Tab("Trips", systemImage: "suitcase") {
                TripsHomeView()
            }
            Tab("Me", systemImage: "person.crop.circle") {
                MeView()
            }
        }
    }
}
