import Foundation

struct IntelligenceConfiguration: Sendable {
    var baseURL: URL
    /// Deliberately shorter than the server's own budget: the app would rather
    /// fall back to the deterministic list than make the user wait.
    var timeout: TimeInterval = 10
    /// When true, an unattested request is never sent. TestFlight and App Store
    /// builds must set this.
    var requiresAttestation: Bool = false

    /// Reads `PACKWISE_API_BASE_URL` from the Info.plist, then the environment.
    /// Absent means the app stays on the deterministic path — no remote calls.
    static func fromBundle(_ bundle: Bundle = .main) -> IntelligenceConfiguration? {
        let raw = (bundle.object(forInfoDictionaryKey: "PACKWISE_API_BASE_URL") as? String)
            ?? ProcessInfo.processInfo.environment["PACKWISE_API_BASE_URL"]
        guard let raw, let url = URL(string: raw.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            return nil
        }
        let requires = (bundle.object(forInfoDictionaryKey: "PACKWISE_REQUIRE_ATTESTATION") as? Bool)
            ?? (ProcessInfo.processInfo.environment["PACKWISE_REQUIRE_ATTESTATION"] == "1")
        return IntelligenceConfiguration(baseURL: url, requiresAttestation: requires)
    }

    /// Explicit selection, never a silent downgrade: if attestation is required
    /// and the device cannot provide it, requests are refused rather than sent
    /// unattested.
    func integrityProvider() -> any AppIntegrityProvider {
        guard requiresAttestation else { return DevelopmentAppIntegrityProvider() }
        guard AppAttestIntegrityProvider.isSupported else { return UnavailableAppIntegrityProvider() }
        return AppAttestIntegrityProvider(baseURL: baseURL)
    }
}

/// Transport for the PackWise Intelligence API.
///
/// The OpenAI key lives on the server; this client only ever talks to PackWise.
/// Every failure collapses to `IntelligenceError.unavailable` because the app
/// has exactly one reaction to a failed intelligence call: carry on without it.
struct IntelligenceHTTPClient: Sendable {
    let configuration: IntelligenceConfiguration
    let integrity: any AppIntegrityProvider
    let session: URLSession

    init(
        configuration: IntelligenceConfiguration,
        integrity: any AppIntegrityProvider = DevelopmentAppIntegrityProvider(),
        session: URLSession = .shared
    ) {
        self.configuration = configuration
        self.integrity = integrity
        self.session = session
    }

    func send<Request: Encodable, Response: Decodable>(
        path: String,
        body: Request,
        as _: Response.Type
    ) async throws -> Response {
        var request = URLRequest(url: configuration.baseURL.appending(path: path))
        request.httpMethod = "POST"
        request.timeoutInterval = configuration.timeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(UUID().uuidString, forHTTPHeaderField: "X-Request-ID")

        let payload: Data
        do {
            payload = try JSONEncoder().encode(body)
        } catch {
            throw IntelligenceError.unavailable
        }
        request.httpBody = payload

        // The assertion is computed over the exact bytes being sent, so it
        // cannot be replayed onto a different request.
        do {
            for (field, value) in try await integrity.assertionHeaders(for: payload) {
                request.setValue(value, forHTTPHeaderField: field)
            }
        } catch {
            throw IntelligenceError.unavailable
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw IntelligenceError.unavailable
        }

        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw IntelligenceError.unavailable
        }

        do {
            return try JSONDecoder().decode(Response.self, from: data)
        } catch {
            throw IntelligenceError.unavailable
        }
    }
}
