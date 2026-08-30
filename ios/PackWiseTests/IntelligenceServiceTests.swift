import Foundation
import Testing

@testable import PackWise

/// URLProtocol stub so the client is exercised end to end without a server.
final class StubURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var responder: (@Sendable (URLRequest) -> (Int, Data))?
    nonisolated(unsafe) static var lastRequestBody: Data?
    nonisolated(unsafe) static var lastHeaders: [String: String]?

    static func reset() {
        responder = nil
        lastRequestBody = nil
        lastHeaders = nil
    }

    static func session() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        // URLProtocol strips httpBody, so read it back off the stream.
        if let stream = request.httpBodyStream {
            stream.open()
            var data = Data()
            var buffer = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable {
                let read = stream.read(&buffer, maxLength: buffer.count)
                if read <= 0 { break }
                data.append(buffer, count: read)
            }
            stream.close()
            Self.lastRequestBody = data
        } else {
            Self.lastRequestBody = request.httpBody
        }
        Self.lastHeaders = request.allHTTPHeaderFields

        let (status, body) = Self.responder?(request) ?? (500, Data())
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: status,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

@Suite(.serialized)
struct IntelligenceServiceTests {
    private func makeService(
        status: Int = 200,
        json: String
    ) throws -> RemoteContextIntelligenceService {
        StubURLProtocol.reset()
        StubURLProtocol.responder = { _ in (status, Data(json.utf8)) }
        return RemoteContextIntelligenceService(
            client: IntelligenceHTTPClient(
                configuration: IntelligenceConfiguration(baseURL: URL(string: "https://api.test")!),
                integrity: DevelopmentAppIntegrityProvider(installIdentifier: "test-install-token"),
                session: StubURLProtocol.session()
            ),
            catalog: try SharedLibrary.catalog(),
            safetyIdentifier: "test-install-token"
        )
    }

    private func context() throws -> TripContext {
        let destinations = try SharedLibrary.testDestinations()
        let destination = destinations.first { $0.city == "Tokyo" }!
        let start = Calendar.current.startOfDay(for: Date.now)
        let end = Calendar.current.date(byAdding: .day, value: 5, to: start)!
        let math = TripDateMath.daysAndNights(from: start, to: end)
        return TripContext(
            destination: destination,
            startDate: start,
            endDate: end,
            durationDays: math.days,
            durationNights: math.nights,
            tripType: .cityBreak,
            activities: ["sightseeing", "walking"],
            datedActivities: [],
            bagType: .carryOn,
            packingStyle: .balanced,
            transportation: .flight,
            laundryAccess: .none,
            travelerCount: 1,
            userNotes: "",
            contextChips: [],
            weather: nil,
            preferences: .deviceDefaults()
        )
    }

    private let metaJSON = """
    "meta": {
      "requestID": "req-1",
      "generatedAt": "2026-08-29T00:00:00Z",
      "model": "fake",
      "promptVersion": "interpret/1",
      "schemaVersion": "2026-08-29"
    }
    """

    @Test func interpretMapsChipsAndDropsUnknownVocabulary() async throws {
        let service = try makeService(json: """
        { \(metaJSON),
          "inferredActivities": ["walking", "niceDinner"],
          "inferredChips": ["getColdEasily", "hatesMornings"],
          "noteSummary": "Tokyo walking trip" }
        """)

        let enrichment = try await service.interpretTripNote("lots of walking", context: try context())
        #expect(enrichment.inferredActivities == ["walking", "niceDinner"])
        #expect(enrichment.inferredChips == [.getColdEasily])
        #expect(enrichment.noteSummary == "Tokyo walking trip")
    }

    @Test func interpretSendsTheNoteAndAnOpaqueIdentifier() async throws {
        let service = try makeService(json: """
        { \(metaJSON), "inferredActivities": [], "inferredChips": [] }
        """)
        _ = try await service.interpretTripNote("one fancy dinner", context: try context())

        let body = try #require(StubURLProtocol.lastRequestBody)
        let json = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        #expect(json["note"] as? String == "one fancy dinner")
        #expect(json["safetyIdentifier"] as? String == "test-install-token")
        #expect(StubURLProtocol.lastHeaders?["X-PackWise-Assertion"] == "test-install-token")
        #expect(StubURLProtocol.lastHeaders?["X-Request-ID"] != nil)
    }

    @Test func emptyNoteNeverReachesTheNetwork() async throws {
        let service = try makeService(json: "{}")
        StubURLProtocol.responder = { _ in (500, Data()) }
        let enrichment = try await service.interpretTripNote("   ", context: try context())
        #expect(enrichment.inferredActivities.isEmpty)
        #expect(enrichment.inferredChips.isEmpty)
        #expect(StubURLProtocol.lastRequestBody == nil)
    }

    @Test func tripContextPayloadOmitsFreeFormNotes() async throws {
        let service = try makeService(json: """
        { \(metaJSON), "suggestions": [] }
        """)
        var trip = try context()
        trip.userNotes = "my partner's medication details"
        _ = try await service.findPackingGaps(context: trip, items: [])

        let body = try #require(StubURLProtocol.lastRequestBody)
        let text = String(decoding: body, as: UTF8.self)
        #expect(!text.contains("medication details"))
    }

    @Test func gapsRejectAnItemThatIsNotInTheCatalog() async throws {
        let service = try makeService(json: """
        { \(metaJSON),
          "suggestions": [
            { "canonicalItemID": "electronics.teleporter", "action": "recommend",
              "reasonCode": "context.gap_generic" },
            { "canonicalItemID": "electronics.power_bank", "action": "recommend",
              "reasonCode": "context.gap_activity",
              "reasonArguments": { "activity": "walking" },
              "confidence": 0.82, "signals": ["activity"] }
          ] }
        """)

        let suggestions = try await service.findPackingGaps(context: try context(), items: [])
        #expect(suggestions.count == 1)
        let suggestion = try #require(suggestions.first)
        #expect(suggestion.canonicalItemID == "electronics.power_bank")
        #expect(suggestion.action == .recommend)
        #expect(suggestion.reasonCode == "context.gap_activity")
        #expect(suggestion.reasonArguments == ["activity": "walking"])
        #expect(suggestion.confidence == 0.82)
        #expect(suggestion.signals == [.activity])
    }

    @Test func outOfRangeConfidenceIsDropped() async throws {
        let service = try makeService(json: """
        { \(metaJSON),
          "suggestions": [
            { "canonicalItemID": "electronics.power_bank", "action": "recommend",
              "reasonCode": "context.gap_generic", "confidence": 4.2 }
          ] }
        """)

        let suggestions = try await service.findPackingGaps(context: try context(), items: [])
        #expect(suggestions.first?.confidence == nil)
    }

    @Test func optimizationsDecodeAndValidate() async throws {
        let service = try makeService(json: """
        { \(metaJSON),
          "optimizations": [
            { "canonicalItemID": "clothing.tshirt", "reasonCode": "context.optimize_quantity",
              "reasonArguments": { "quantity": "5" }, "suggestedQuantity": 5 },
            { "canonicalItemID": "clothing.does_not_exist", "reasonCode": "context.optimize_generic" }
          ] }
        """)

        let optimizations = try await service.optimizePacking(context: try context(), items: [])
        #expect(optimizations.map(\.canonicalItemID) == ["clothing.tshirt"])
        #expect(optimizations.first?.suggestedQuantity == 5)
    }

    @Test func everyServerFailureCollapsesToUnavailable() async throws {
        for status in [401, 429, 500, 503] {
            let service = try makeService(status: status, json: "{\"error\":\"nope\",\"requestID\":\"r\"}")
            await #expect(throws: IntelligenceError.unavailable) {
                _ = try await service.findPackingGaps(context: try context(), items: [])
            }
        }
    }

    @Test func malformedResponseIsUnavailableRatherThanACrash() async throws {
        let service = try makeService(json: "{ \"unexpected\": true }")
        await #expect(throws: IntelligenceError.unavailable) {
            _ = try await service.interpretTripNote("hello", context: try context())
        }
    }

    @Test func installIdentifierMatchesTheServerSafetyIdentifierRule() {
        let identity = InstallIdentity(defaults: UserDefaults(suiteName: "packwise.tests.\(UUID().uuidString)")!)
        #expect(InstallIdentity.isValid(identity.identifier))
        #expect(!InstallIdentity.isValid("person@example.com"))
        #expect(!InstallIdentity.isValid("short"))
    }

    @Test func noConfiguredBaseURLMeansNoRemoteService() throws {
        let configuration = IntelligenceConfiguration.fromBundle(Bundle(for: StubURLProtocol.self))
        #expect(configuration == nil)
    }

    @Test func attestationIsRefusedRatherThanDowngradedWhenUnsupported() async throws {
        // The simulator cannot attest. Requiring it must refuse, never fall
        // back to sending an unattested request.
        let configuration = IntelligenceConfiguration(
            baseURL: URL(string: "https://api.test")!,
            requiresAttestation: true
        )
        let provider = configuration.integrityProvider()
        if AppAttestIntegrityProvider.isSupported {
            #expect(provider is AppAttestIntegrityProvider)
        } else {
            #expect(provider is UnavailableAppIntegrityProvider)
            await #expect(throws: IntelligenceError.unavailable) {
                _ = try await provider.assertionHeaders(for: Data())
            }
        }
    }

    @Test func developmentIntegrityIsSelectedOnlyWhenAttestationIsNotRequired() {
        let configuration = IntelligenceConfiguration(baseURL: URL(string: "https://api.test")!)
        #expect(configuration.requiresAttestation == false)
        #expect(configuration.integrityProvider() is DevelopmentAppIntegrityProvider)
    }

    @Test func aRefusedAssertionNeverSendsTheRequest() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.responder = { _ in (200, Data("{}".utf8)) }
        let service = RemoteContextIntelligenceService(
            client: IntelligenceHTTPClient(
                configuration: IntelligenceConfiguration(baseURL: URL(string: "https://api.test")!),
                integrity: UnavailableAppIntegrityProvider(),
                session: StubURLProtocol.session()
            ),
            catalog: try SharedLibrary.catalog(),
            safetyIdentifier: "test-install-token"
        )

        await #expect(throws: IntelligenceError.unavailable) {
            _ = try await service.findPackingGaps(context: try context(), items: [])
        }
        #expect(StubURLProtocol.lastRequestBody == nil)
    }
}
