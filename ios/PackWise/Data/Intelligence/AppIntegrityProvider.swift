import CryptoKit
import DeviceCheck
import Foundation

/// Proof that a request came from a real PackWise install.
///
/// The headers are computed over the exact request body, so an assertion cannot
/// be lifted onto a different request. `DevelopmentAppIntegrityProvider` is for
/// local work; `AppAttestIntegrityProvider` is what a TestFlight or App Store
/// build must use.
protocol AppIntegrityProvider: Sendable {
    /// Header fields to attach to an outgoing intelligence request.
    /// - Throws: when integrity cannot be established. The caller falls back to
    ///   the deterministic list rather than sending an unattested request.
    func assertionHeaders(for body: Data) async throws -> [String: String]
}

/// Local development and tests. Sends a stable per-install token so rate limits
/// behave the way they will in production, without claiming to be attested.
struct DevelopmentAppIntegrityProvider: AppIntegrityProvider {
    private let installIdentifier: String

    init(installIdentifier: String = InstallIdentity.shared.identifier) {
        self.installIdentifier = installIdentifier
    }

    func assertionHeaders(for body: Data) async throws -> [String: String] {
        _ = body
        return ["X-PackWise-Assertion": installIdentifier]
    }
}

/// Selected when attestation is required but the device cannot provide it.
/// Refusing is the safe failure: it must never quietly become development trust.
struct UnavailableAppIntegrityProvider: AppIntegrityProvider {
    func assertionHeaders(for body: Data) async throws -> [String: String] {
        _ = body
        throw IntelligenceError.unavailable
    }
}

/// A per-install random token, stored locally. It identifies an install so the
/// server can scope rate limits and derive an opaque provider-side identifier;
/// it is not derived from the device, the user, or anything that identifies a
/// person, and the server HMACs it before it reaches any external service.
struct InstallIdentity: Sendable {
    static let shared = InstallIdentity()

    private static let defaultsKey = "com.packwise.installIdentifier"

    let identifier: String

    init(defaults: UserDefaults = .standard) {
        if let existing = defaults.string(forKey: Self.defaultsKey), Self.isValid(existing) {
            identifier = existing
        } else {
            let generated = Self.generate()
            defaults.set(generated, forKey: Self.defaultsKey)
            identifier = generated
        }
    }

    private static func generate() -> String {
        UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
    }

    /// Matches the server's `safetyIdentifier` rule: an opaque URL-safe token.
    static func isValid(_ value: String) -> Bool {
        guard (8...128).contains(value.count) else { return false }
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-")
        return value.unicodeScalars.allSatisfy(allowed.contains)
    }
}

/// Talks to `DCAppAttestService`.
///
/// Registration happens once per install: generate a Secure Enclave key, bind
/// it to a one-time server challenge, and hand the attestation to the API.
/// Every later request carries an assertion over its own body.
///
/// An actor because registration must happen once even if several requests race
/// on first launch.
actor AppAttestIntegrityProvider: AppIntegrityProvider {
    private static let keyIDDefaultsKey = "com.packwise.appAttestKeyID"

    private let service = DCAppAttestService.shared
    private let baseURL: URL
    private let session: URLSession
    private let defaults: UserDefaults
    private var registration: Task<String, Error>?

    init(baseURL: URL, session: URLSession = .shared, defaults: UserDefaults = .standard) {
        self.baseURL = baseURL
        self.session = session
        self.defaults = defaults
    }

    static var isSupported: Bool { DCAppAttestService.shared.isSupported }

    func assertionHeaders(for body: Data) async throws -> [String: String] {
        let keyID = try await registeredKeyID()
        let assertion = try await service.generateAssertion(keyID, clientDataHash: Data(SHA256.hash(data: body)))
        return [
            "X-PackWise-Key-ID": keyID,
            "X-PackWise-Assertion": assertion.base64EncodedString(),
        ]
    }

    private func registeredKeyID() async throws -> String {
        if let stored = defaults.string(forKey: Self.keyIDDefaultsKey) { return stored }
        if let inFlight = registration { return try await inFlight.value }

        let task = Task { try await register() }
        registration = task
        defer { registration = nil }
        let keyID = try await task.value
        defaults.set(keyID, forKey: Self.keyIDDefaultsKey)
        return keyID
    }

    private func register() async throws -> String {
        guard service.isSupported else { throw IntelligenceError.unavailable }

        let keyID = try await service.generateKey()
        let challenge = try await requestChallenge()
        let attestation = try await service.attestKey(
            keyID,
            clientDataHash: Data(SHA256.hash(data: Data(challenge.utf8)))
        )

        try await post(
            path: "/v1/integrity/attest",
            body: AttestBody(
                keyID: keyID,
                attestation: attestation.base64EncodedString(),
                challenge: challenge
            )
        )
        return keyID
    }

    private func requestChallenge() async throws -> String {
        var request = URLRequest(url: baseURL.appending(path: "/v1/integrity/challenge"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw IntelligenceError.unavailable
        }
        struct ChallengeResponse: Decodable { var challenge: String }
        return try JSONDecoder().decode(ChallengeResponse.self, from: data).challenge
    }

    private struct AttestBody: Encodable {
        var keyID: String
        var attestation: String
        var challenge: String
    }

    private func post(path: String, body: some Encodable) async throws {
        var request = URLRequest(url: baseURL.appending(path: path))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)

        let (_, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw IntelligenceError.unavailable
        }
    }
}
