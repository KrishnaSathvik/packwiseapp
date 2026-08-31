#if DEBUG
import Foundation

/// Deliberately malformed requests against the real verifier, for the
/// physical-device pass.
///
/// The server is never weakened to make these pass — the point is that a real
/// `DCAppAttestService` assertion is rejected when replayed or when the body it
/// signed is swapped. Both cases exist as synthetic-fixture tests on the
/// server; these prove the same properties against Apple's actual attestation
/// on real hardware.
///
/// Debug builds only. None of this compiles into Release, TestFlight, or the
/// App Store.
struct DebugAttestProbe: Sendable {
    let configuration: IntelligenceConfiguration
    let integrity: any AppIntegrityProvider
    let session: URLSession

    init(
        configuration: IntelligenceConfiguration,
        integrity: any AppIntegrityProvider,
        session: URLSession = .shared
    ) {
        self.configuration = configuration
        self.integrity = integrity
        self.session = session
    }

    struct Outcome: Sendable {
        var passed: Bool
        var detail: String
    }

    /// The chain the device pass has to prove before anything else is worth running.
    func happyPath() async -> Outcome {
        let payload = Self.body(note: "Five days in Chicago, walking the city and a few museums.")
        do {
            let headers = try await integrity.assertionHeaders(for: payload)
            let (status, message) = await send(payload, headers: headers)
            return Outcome(
                passed: status == 200,
                detail: status == 200
                    ? "200 — attestation registered and the assertion was accepted"
                    : "expected 200, got \(status) \(message)"
            )
        } catch {
            return Outcome(passed: false, detail: "could not produce an assertion: \(error)")
        }
    }

    /// One assertion, sent twice. The second must fail on the counter.
    func replay() async -> Outcome {
        let payload = Self.body(note: "Replay probe.")
        do {
            let headers = try await integrity.assertionHeaders(for: payload)

            let first = await send(payload, headers: headers)
            guard first.status == 200 else {
                return Outcome(passed: false, detail: "first request should have succeeded, got \(first.status) \(first.message)")
            }

            // Byte-identical resend: same body, same assertion, same counter.
            let second = await send(payload, headers: headers)
            let rejected = second.status == 401 && second.message == "counter_replay"
            return Outcome(
                passed: rejected,
                detail: rejected
                    ? "first 200, replay 401 counter_replay"
                    : "replay should have been rejected, got \(second.status) \(second.message)"
            )
        } catch {
            return Outcome(passed: false, detail: "could not produce an assertion: \(error)")
        }
    }

    /// An assertion signed over one body, sent with a different one.
    func tamperedPayload() async -> Outcome {
        let signed = Self.body(note: "Signed body.")
        let sent = Self.body(note: "A different body that was never signed.")
        do {
            let headers = try await integrity.assertionHeaders(for: signed)
            let (status, message) = await send(sent, headers: headers)
            let rejected = status == 401 && message == "assertion_signature_invalid"
            return Outcome(
                passed: rejected,
                detail: rejected
                    ? "401 assertion_signature_invalid — the body digest is bound"
                    : "tampered body should have been rejected, got \(status) \(message)"
            )
        } catch {
            return Outcome(passed: false, detail: "could not produce an assertion: \(error)")
        }
    }

    private func send(_ payload: Data, headers: [String: String]) async -> (status: Int, message: String) {
        var request = URLRequest(url: configuration.baseURL.appending(path: "/v1/trip/interpret"))
        request.httpMethod = "POST"
        request.timeoutInterval = configuration.timeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = payload
        for (field, value) in headers {
            request.setValue(value, forHTTPHeaderField: field)
        }

        do {
            let (data, response) = try await session.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? -1
            struct Failure: Decodable { var error: String?; var message: String? }
            let failure = try? JSONDecoder().decode(Failure.self, from: data)
            return (status, failure?.message ?? failure?.error ?? "")
        } catch {
            return (-1, "\(error)")
        }
    }

    /// A minimal valid request. The server validates it before integrity, so a
    /// malformed one would fail for the wrong reason.
    private static func body(note: String) -> Data {
        let payload: [String: Any] = [
            "note": note,
            "context": [
                "destination": ["displayName": "Chicago", "countryCode": "US"],
                "startDate": "2026-09-01",
                "endDate": "2026-09-05",
                "tripType": "cityBreak",
                "activities": ["walking"],
                "bagType": "carryOn",
                "packingStyle": "balanced",
            ],
            "safetyIdentifier": InstallIdentity.shared.identifier,
        ]
        return (try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])) ?? Data()
    }
}
#endif
