#if DEBUG
import SwiftData
import SwiftUI
import UIKit

/// The three things the physical-device pass cannot do by hand: prove that a
/// real assertion is rejected when replayed, prove that the body it signed is
/// bound to it, and move the weather without waiting for the sky to change.
///
/// Debug builds only — the whole file, not just the entry point, so none of it
/// exists in Release, TestFlight, or the App Store.
struct DeveloperToolsView: View {
    @Environment(AppDependencies.self) private var dependencies
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \TripRecord.startDate, order: .reverse) private var trips: [TripRecord]
    @Query private var preferenceRecords: [PackingPreferenceRecord]

    @State private var results: [Result] = []
    @State private var running = false
    @State private var selectedTripID: UUID?
    @State private var scenario: DebugWeatherInjection.Scenario = .rain
    @State private var diagnosticsText: String?
    @State private var diagnosticsCount = 0

    private struct Result: Identifiable {
        let id = UUID()
        let name: String
        let passed: Bool
        let detail: String
    }

    private var configuration: IntelligenceConfiguration? {
        IntelligenceConfiguration.fromBundle()
    }

    private var selectedTrip: TripRecord? {
        trips.first { $0.id == selectedTripID } ?? trips.first
    }

    var body: some View {
        List {
            Section("Endpoint") {
                if let configuration {
                    LabeledContent("API", value: configuration.baseURL.host() ?? "—")
                    LabeledContent("Attestation required", value: configuration.requiresAttestation ? "Yes" : "No")
                    LabeledContent(
                        "App Attest",
                        value: AppAttestIntegrityProvider.isSupported ? "Supported" : "Unsupported on this device"
                    )
                } else {
                    Text("No API base URL configured. The app is on the deterministic path only.")
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                button("Run happy path") { await probe()?.happyPath() }
                button("Replay last assertion") { await probe()?.replay() }
                button("Send tampered payload") { await probe()?.tamperedPayload() }
            } header: {
                Text("App Attest")
            } footer: {
                Text("Replay and tamper send deliberately invalid requests to the normal verifier. The server is never relaxed for these.")
            }

            Section {
                if trips.isEmpty {
                    Text("Create a trip first.").foregroundStyle(.secondary)
                } else {
                    Picker("Trip", selection: Binding(
                        get: { selectedTrip?.id ?? UUID() },
                        set: { selectedTripID = $0 }
                    )) {
                        ForEach(trips) { trip in
                            Text(trip.destination.displayName).tag(trip.id)
                        }
                    }
                    Picker("Test forecast", selection: $scenario) {
                        ForEach(DebugWeatherInjection.Scenario.allCases) { option in
                            Text(option.title).tag(option)
                        }
                    }
                    button("Inject Test Weather") { await injectWeather() }
                }
            } header: {
                Text("Test Forecast")
            } footer: {
                Text(
                    "Synthetic weather used only to test weather-change reconciliation. Not live WeatherKit data. The fixture snapshot is stored and reconciled through the same path as a real refresh, so the proposal is real but the forecast is not — weather screens show a TEST WEATHER badge while it is in place."
                )
            }

            if !results.isEmpty {
                Section("Results") {
                    ForEach(results) { result in
                        VStack(alignment: .leading, spacing: 4) {
                            Label(result.name, systemImage: result.passed ? "checkmark.circle.fill" : "xmark.circle.fill")
                                .foregroundStyle(result.passed ? .green : .red)
                            Text(result.detail)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Button("Clear", role: .destructive) { results.removeAll() }
                }
            }

            Section {
                if let diagnosticsText {
                    Text(diagnosticsText)
                        .font(.system(.footnote, design: .monospaced))
                        .textSelection(.enabled)
                } else {
                    Text("No weather refresh has run yet. Create a trip, open a trip's detail screen, or bring the app to the foreground while one is open to trigger a live attempt, then refresh here.")
                        .foregroundStyle(.secondary)
                }
                Button("Refresh") { Task { await loadLatestDiagnostics() } }
                Button("Copy latest") { copyLatestDiagnostics() }
                    .disabled(diagnosticsText == nil)
                Button("Copy all (\(diagnosticsCount))") { Task { await copyAllDiagnostics() } }
                    .disabled(diagnosticsCount == 0)
                Button("Clear log", role: .destructive) { Task { await clearDiagnostics() } }
            } header: {
                Text("Weather diagnostics")
            } footer: {
                Text(
                    "\(diagnosticsCount) recorded — the exact request/provider/cache/normalization boundary for the most recent refresh or injection. Coordinates, dates, and timezones only — no trip notes. Debug builds only."
                )
            }
        }
        .navigationTitle("Developer Tools")
        .navigationBarTitleDisplayMode(.inline)
        .disabled(running)
        .task { await loadLatestDiagnostics() }
    }

    private func button(_ title: String, action: @escaping () async -> DebugAttestProbe.Outcome?) -> some View {
        Button(title) {
            running = true
            Task {
                let outcome = await action()
                record(title, outcome)
                running = false
            }
        }
    }

    private func probe() -> DebugAttestProbe? {
        guard let configuration else { return nil }
        return DebugAttestProbe(
            configuration: configuration,
            integrity: configuration.integrityProvider()
        )
    }

    private func injectWeather() async -> DebugAttestProbe.Outcome? {
        guard let trip = selectedTrip else {
            return DebugAttestProbe.Outcome(passed: false, detail: "no trip selected")
        }
        let preferences = preferenceRecords.first?.preferences ?? .deviceDefaults()
        let outcome = await DebugWeatherInjection.inject(
            scenario,
            trip: trip,
            preferences: preferences,
            engine: dependencies.engine,
            rules: dependencies.rules,
            repository: TripRepository(context: modelContext)
        )
        await loadLatestDiagnostics()
        return DebugAttestProbe.Outcome(passed: outcome.passed, detail: outcome.detail)
    }

    private func record(_ name: String, _ outcome: DebugAttestProbe.Outcome?) {
        guard let outcome else {
            results.insert(Result(name: name, passed: false, detail: "no API configured"), at: 0)
            return
        }
        results.insert(Result(name: name, passed: outcome.passed, detail: outcome.detail), at: 0)
    }

    private func loadLatestDiagnostics() async {
        let store = WeatherRequestDiagnosticsStore.shared
        diagnosticsText = await store.latest()?.reportText
        diagnosticsCount = await store.all().count
    }

    private func copyLatestDiagnostics() {
        guard let diagnosticsText else { return }
        UIPasteboard.general.string = diagnosticsText
    }

    /// Every recorded entry, oldest first — for a repro that spans several
    /// refreshes (first open, backgrounding, pull-to-refresh) so nothing
    /// before the latest one is lost.
    private func copyAllDiagnostics() async {
        let text = await WeatherRequestDiagnosticsStore.shared.allReportText()
        guard !text.isEmpty else { return }
        UIPasteboard.general.string = text
    }

    private func clearDiagnostics() async {
        await WeatherRequestDiagnosticsStore.shared.clear()
        await loadLatestDiagnostics()
    }
}
#endif
