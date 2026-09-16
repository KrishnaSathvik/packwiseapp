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
            tripTypes: [.cityBreak],
            activities: ["sightseeing", "walking"],
            datedActivities: [],
            bagTypes: [.carryOn],
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

    // MARK: - Multi-value trip context contract (Task 15)

    private func encodedContext(_ context: TripContext) throws -> [String: Any] {
        let data = try JSONEncoder().encode(IntelligenceDTO.payload(for: context))
        return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    @Test func payloadSendsEveryTripTypeAndBagInStableOrderRegardlessOfInsertion() throws {
        var a = try context()
        a.tripTypes = [.beach, .vacation, .cityBreak]
        a.bagTypes = [.checked, .personalItem, .carryOn]
        var b = try context()
        b.tripTypes = [.cityBreak, .beach, .vacation]
        b.bagTypes = [.carryOn, .checked, .personalItem]

        let encodedA = try encodedContext(a)
        #expect(encodedA["tripTypes"] as? [String] == ["vacation", "cityBreak", "beach"])
        #expect(encodedA["bagTypes"] as? [String] == ["personalItem", "carryOn", "checked"])
        // Object key order is JSONEncoder's business; array order is ours.
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        #expect(try encoder.encode(IntelligenceDTO.payload(for: a))
            == encoder.encode(IntelligenceDTO.payload(for: b)))
    }

    @Test func payloadOrderComesFromTheSharedStableOrderAuthority() throws {
        var trip = try context()
        trip.tripTypes = [.skiSnow, .outdoor]
        trip.bagTypes = [.backpack, .checked]
        let payload = IntelligenceDTO.payload(for: trip)
        #expect(payload.tripTypes == StableRawValueSetCodec.orderedRawValues(trip.tripTypes, order: TripType.stableOrder))
        #expect(payload.bagTypes == StableRawValueSetCodec.orderedRawValues(trip.bagTypes, order: BagType.stableOrder))
    }

    @Test func emptyBagSetEncodesAsAnEmptyArray() throws {
        var trip = try context()
        trip.bagTypes = []
        #expect(try encodedContext(trip)["bagTypes"] as? [String] == [])
    }

    @Test func everyTripTypeSurvivesTheWireAndNoPrimaryIsInvented() throws {
        var all = try context()
        all.tripTypes = Set(TripType.stableOrder)
        #expect(try encodedContext(all)["tripTypes"] as? [String] == TripType.stableOrder.map(\.rawValue))

        var pair = try context()
        pair.tripTypes = [.business, .beach]
        let types = try #require(try encodedContext(pair)["tripTypes"] as? [String])
        #expect(types == ["beach", "business"])
        #expect(!types.contains("other"), "the compat fallback never reaches the wire")
    }

    /// Product V2 combination contexts in `shared/fixtures/contexts/`. Contract-
    /// only until Tasks 3–5 give them behavior: this proves each one survives
    /// the domain set → DTO round trip exactly, with no primary type invented.
    @Test func productV2CombinationFixturesRoundTripThroughTheDTOExactly() throws {
        struct File: Decodable {
            struct Row: Decodable {
                struct Context: Decodable {
                    struct Place: Decodable { var displayName: String }
                    var destination: Place
                    var tripTypes: [String]
                    var bagTypes: [String]
                }
                var id: String
                var context: Context
            }
            var contexts: [Row]
        }
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("shared/fixtures/contexts/product-v2-combinations.json")
        let rows = try JSONDecoder().decode(File.self, from: Data(contentsOf: url)).contexts
        #expect(rows.count == 10)
        let destinations = try SharedLibrary.testDestinations()

        for row in rows {
            let tripTypes = row.context.tripTypes.compactMap(TripType.init(rawValue:))
            let bagTypes = row.context.bagTypes.compactMap(BagType.init(rawValue:))
            #expect(tripTypes.count == row.context.tripTypes.count, "\(row.id) has an unknown trip type")
            #expect(bagTypes.count == row.context.bagTypes.count, "\(row.id) has an unknown bag")
            #expect(bagTypes.allSatisfy(BagType.stableOrder.contains), "\(row.id) has a non-physical bag")

            var trip = try context()
            trip.destination = try #require(destinations.first { $0.displayName == row.context.destination.displayName })
            trip.tripTypes = Set(tripTypes)
            trip.bagTypes = Set(bagTypes)
            let payload = IntelligenceDTO.payload(for: trip)
            #expect(payload.tripTypes == row.context.tripTypes, "\(row.id) trip types")
            #expect(payload.bagTypes == row.context.bagTypes, "\(row.id) bags")
            #expect(payload.tripTypes.count == tripTypes.count, "\(row.id) must not collapse to a primary trip type")
        }
    }

    @Test func legacyScalarContextFieldsAreAbsentFromTheRequest() async throws {
        let service = try makeService(json: """
        { \(metaJSON), "suggestions": [] }
        """)
        var trip = try context()
        trip.tripTypes = [.vacation, .beach]
        trip.bagTypes = []
        _ = try await service.findPackingGaps(context: trip, items: [])

        let body = try #require(StubURLProtocol.lastRequestBody)
        let json = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        let wireContext = try #require(json["context"] as? [String: Any])
        #expect(wireContext["tripType"] == nil)
        #expect(wireContext["bagType"] == nil)
        #expect(wireContext["tripTypes"] as? [String] == ["vacation", "beach"])
        #expect(wireContext["bagTypes"] as? [String] == [])
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

    @Test func attestationFlagAcceptsTheStringsBuildSettingsProduce() {
        // INFOPLIST_KEY_* values arrive as strings; reading only Bool? would
        // quietly leave every build unattested.
        #expect(IntelligenceConfiguration.flag("YES"))
        #expect(IntelligenceConfiguration.flag("yes"))
        #expect(IntelligenceConfiguration.flag("true"))
        #expect(IntelligenceConfiguration.flag("1"))
        #expect(IntelligenceConfiguration.flag(true))
        #expect(!IntelligenceConfiguration.flag("NO"))
        #expect(!IntelligenceConfiguration.flag(false))
        #expect(!IntelligenceConfiguration.flag(nil))
    }

    @Test func developmentIntegrityIsSelectedOnlyWhenAttestationIsNotRequired() {
        let configuration = IntelligenceConfiguration(baseURL: URL(string: "https://api.test")!)
        #expect(configuration.requiresAttestation == false)
        #expect(configuration.integrityProvider() is DevelopmentAppIntegrityProvider)
    }

    // MARK: - Task 4: deterministic generation is decoupled from intelligence

    /// The deterministic engine never consumes `ContextIntelligenceService` —
    /// `PackingEngine.generate` doesn't even take one as a parameter. Proving
    /// list generation succeeds right next to a service that just failed
    /// (rather than merely asserting the failure) documents that decoupling
    /// as current behavior, not just an API-shape observation.
    @Test func deterministicGenerationSucceedsWhileIntelligenceServiceThrows() async throws {
        let service = try makeService(status: 500, json: "{\"error\":\"down\",\"requestID\":\"r\"}")
        await #expect(throws: IntelligenceError.unavailable) {
            _ = try await service.findPackingGaps(context: try context(), items: [])
        }

        let engine = PackingEngine(catalog: try SharedLibrary.catalog(), rules: try SharedLibrary.rules())
        let items = engine.generate(context: try context())
        #expect(!items.isEmpty, "list generation must succeed even while the intelligence service is down")
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
