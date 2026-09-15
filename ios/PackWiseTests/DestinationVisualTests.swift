import Foundation
import Testing
import UIKit
@testable import PackWise

/// Task 9 — the destination visual policy, map snapshot cache, destination
/// step states, and onboarding copy. Providers are injected; nothing here
/// touches Apple's network services.
struct DestinationVisualTests {
    // MARK: Fixtures

    static let chicago = Destination(displayName: "Chicago", city: "Chicago", region: "IL", country: "United States", countryCode: "US",
                                     latitude: 41.8781, longitude: -87.6298, timeZone: "America/Chicago", mapKitIdentifier: nil, fixtureID: nil)
    static let khammam = Destination(displayName: "Khammam", city: "Khammam", region: "Telangana", country: "India", countryCode: "IN",
                                     latitude: 17.2473, longitude: 80.1514, timeZone: "Asia/Kolkata", mapKitIdentifier: nil, fixtureID: nil)
    static let longName = Destination(displayName: "Saint-Rémy-de-Provence", city: "Saint-Rémy-de-Provence", region: "Provence-Alpes-Côte d'Azur",
                                      country: "France", countryCode: "FR", latitude: 43.7888, longitude: 4.8317, timeZone: "Europe/Paris",
                                      mapKitIdentifier: nil, fixtureID: nil)
    static let iceland = Destination(displayName: "Iceland", city: "", region: "", country: "Iceland", countryCode: "IS",
                                     latitude: 64.9631, longitude: -19.0208, timeZone: "Atlantic/Reykjavik", mapKitIdentifier: nil, fixtureID: nil)

    static func image() -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: 4, height: 4)).image { context in
            UIColor.systemBlue.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 4, height: 4))
        }
    }

    static func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: "DestinationVisualTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    actor Counter {
        private(set) var requests: [DestinationMapRequest] = []
        private(set) var cancellations = 0
        func record(_ request: DestinationMapRequest) { requests.append(request) }
        func cancelled() { cancellations += 1 }
    }

    struct FakeMaps: DestinationMapSnapshotting {
        enum Mode { case succeed, fail, waitForCancellation }
        var mode: Mode
        var counter: Counter

        func snapshot(for request: DestinationMapRequest) async throws -> UIImage {
            await counter.record(request)
            switch mode {
            case .succeed:
                return DestinationVisualTests.image()
            case .fail:
                throw URLError(.notConnectedToInternet)
            case .waitForCancellation:
                do {
                    try await Task.sleep(for: .seconds(30))
                } catch {
                    await counter.cancelled()
                    throw CancellationError()
                }
                return DestinationVisualTests.image()
            }
        }
    }

    struct FakeStreet: DestinationStreetImagery {
        var result: UIImage?
        var counter: Counter
        func image(latitude: Double, longitude: Double, size: CGSize) async -> UIImage? {
            await counter.record(DestinationMapRequest(destination: DestinationVisualTests.chicago, purpose: .tripHero))
            return result
        }
    }

    static func service(
        maps: FakeMaps.Mode = .succeed,
        counter: Counter,
        directory: URL? = nil,
        trusted: @escaping @Sendable (Destination) -> UIImage? = { _ in nil },
        street: FakeStreet? = nil,
        policy: DestinationVisualPolicy = .production,
        retryInterval: TimeInterval = 60
    ) -> MapKitDestinationVisualService {
        MapKitDestinationVisualService(
            directory: directory,
            trusted: trusted,
            streetImagery: street ?? FakeStreet(result: nil, counter: Counter()),
            mapSnapshots: FakeMaps(mode: maps, counter: counter),
            policy: policy,
            retryInterval: retryInterval
        )
    }

    // MARK: Policy

    @Test func trustedImageryWinsWithoutTouchingAnyProvider() async {
        let counter = Counter()
        let street = Counter()
        let service = Self.service(counter: counter, trusted: { _ in Self.image() },
                                   street: FakeStreet(result: Self.image(), counter: street), policy: .init(usesStreetImagery: true))
        #expect(await service.visual(for: Self.chicago, purpose: .tripHero).tier == "trusted")
        let mapRequests = await counter.requests
        let streetRequests = await street.requests
        #expect(mapRequests.isEmpty && streetRequests.isEmpty)
    }

    @Test func chicagoAndKhammamResolveToAMapOnceThenFromCache() async throws {
        let directory = try Self.temporaryDirectory()
        let counter = Counter()
        let service = Self.service(counter: counter, directory: directory)
        for destination in [Self.chicago, Self.khammam] {
            #expect(await service.visual(for: destination, purpose: .tripCard).tier == "map", "\(destination.city)")
            #expect(await service.visual(for: destination, purpose: .tripCard).tier == "map")
        }
        #expect(await counter.requests.count == 2, "memory cache reused")

        // A fresh service (a later launch) reads the disk cache.
        let relaunchCounter = Counter()
        let relaunched = Self.service(counter: relaunchCounter, directory: directory)
        #expect(await relaunched.visual(for: Self.khammam, purpose: .tripCard).tier == "map")
        #expect(await relaunchCounter.requests.isEmpty, "disk cache reused")
    }

    @Test func productionPolicyNeverRunsStreetImageryAndAMissFallsThroughToTheMap() async {
        let street = Counter()
        let production = Self.service(counter: Counter(), street: FakeStreet(result: Self.image(), counter: street))
        #expect(await production.visual(for: Self.chicago, purpose: .tripHero).tier == "map")
        #expect(await street.requests.isEmpty)

        let noLookAround = Self.service(counter: Counter(), street: FakeStreet(result: nil, counter: Counter()), policy: .init(usesStreetImagery: true))
        #expect(await noLookAround.visual(for: Self.khammam, purpose: .tripHero).tier == "map", "no Look Around → map")

        let withLookAround = Self.service(counter: Counter(), street: FakeStreet(result: Self.image(), counter: Counter()), policy: .init(usesStreetImagery: true))
        #expect(await withLookAround.visual(for: Self.chicago, purpose: .tripHero).tier == "lookAround")
    }

    @Test func offlineMapFailureIsGraphicalUncachedAndRetriedLater() async throws {
        let directory = try Self.temporaryDirectory()
        let counter = Counter()
        let offline = Self.service(maps: .fail, counter: counter, directory: directory)
        #expect(await offline.visual(for: Self.longName, purpose: .tripHero) == .graphical)
        #expect(await offline.visual(for: Self.longName, purpose: .tripHero) == .graphical)
        #expect(await counter.requests.count == 1, "within the retry interval the failure is not re-requested")
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path).isEmpty, "a failure is never persisted")

        let reconnectCounter = Counter()
        let reconnected = Self.service(counter: reconnectCounter, directory: directory, retryInterval: 0)
        #expect(await reconnected.visual(for: Self.longName, purpose: .tripHero).tier == "map", "a reconnect recovers")
    }

    @Test func cancellationCancelsTheSnapshotAndCachesNothing() async {
        let counter = Counter()
        let service = Self.service(maps: .waitForCancellation, counter: counter)
        let task = Task { await service.visual(for: Self.khammam, purpose: .tripThumbnail) }
        while await counter.requests.isEmpty { await Task.yield() }
        task.cancel()
        #expect(await task.value == .graphical)
        for _ in 0..<50 where await counter.cancellations == 0 { try? await Task.sleep(for: .milliseconds(10)) }
        #expect(await counter.cancellations == 1, "the provider saw the cancellation")

        // Nothing was recorded as a failure or a result: the next call renders again.
        let next = Task { await service.visual(for: Self.khammam, purpose: .tripThumbnail) }
        while await counter.requests.count < 2 { await Task.yield() }
        next.cancel()
        _ = await next.value
    }

    // MARK: Map request

    @Test func mapRequestsHaveDeterministicKeysAndRegionalSpans() {
        let khammam = DestinationMapRequest(destination: Self.khammam, purpose: .tripCard)
        #expect(khammam.cacheKey == "map-v4_17.2473_80.1514_city_tripCard_444x180")
        #expect(khammam == DestinationMapRequest(destination: Self.khammam, purpose: .tripCard))
        #expect(Set(DestinationVisualPurpose.allCases.map { DestinationMapRequest(destination: Self.khammam, purpose: $0).cacheKey }).count == 3)
        #expect(!DestinationMapRequest(destination: Self.longName, purpose: .tripHero).cacheKey.contains("Rémy"),
                "names never reach a file name")

        #expect(DestinationMapScale.of(Self.chicago) == .city)
        #expect(DestinationMapScale.of(Self.longName) == .city)
        #expect(DestinationMapScale.of(Self.iceland) == .country)
        let region = Destination(displayName: "Tuscany", city: "", region: "Tuscany", country: "Italy", countryCode: "IT",
                                 latitude: 43.77, longitude: 11.25, timeZone: "Europe/Rome", mapKitIdentifier: nil, fixtureID: nil)
        #expect(DestinationMapScale.of(region) == .region)
        #expect(DestinationMapScale.city.latitudeDelta < DestinationMapScale.region.latitudeDelta)
        #expect(DestinationMapScale.region.latitudeDelta < DestinationMapScale.country.latitudeDelta)

        // The destination sits above center, clear of the text region.
        let hero = DestinationMapRequest(destination: Self.chicago, purpose: .tripHero).region
        let fromTop = (hero.center.latitude + hero.span.latitudeDelta / 2 - Self.chicago.latitude) / hero.span.latitudeDelta
        #expect(abs(fromTop - DestinationVisualPurpose.tripHero.markerHeightFraction) < 0.0001)
    }

    // MARK: Layout

    @Test func decorationNeverEntersTheTextSafeRegion() {
        let sizes = [CGSize(width: 402, height: 270), CGSize(width: 370, height: 150), CGSize(width: 402, height: 520), CGSize(width: 320, height: 150)]
        for size in sizes {
            for top: CGFloat in [0, PackWiseSize.heroControlTopInset + PackWiseSize.tapTarget] {
                let band = max(size.height * DestinationVisualLayout.decorationBandFraction, top + DestinationVisualLayout.minimumDecorationHeight)
                let decoration = DestinationVisualLayout.decorationRect(in: size, bandHeight: band, top: top)
                let text = DestinationVisualLayout.textSafeRect(in: size, bandHeight: band)
                #expect(!decoration.intersects(text), "\(size) top \(top)")
                #expect(decoration.minY >= top, "decoration stays below controls")
            }
        }
    }

    /// The map marker is a decoration too: it shows only in the band, so a
    /// hero that grows for large text hides it rather than covering the title.
    @Test func mapMarkerShowsOnlyInsideTheDecorationBand() {
        let image = DestinationVisualPurpose.tripCard.size
        let fraction = DestinationVisualPurpose.tripCard.markerHeightFraction
        let standard = CGSize(width: 370, height: 150)
        let band = standard.height * DestinationVisualLayout.decorationBandFraction
        let point = DestinationVisualLayout.markerPoint(imageSize: image, frame: standard, heightFraction: fraction)
        #expect(abs(point.x - 185) < 0.001)
        #expect(DestinationVisualLayout.showsMarker(at: point, bandHeight: band, top: 0), "standard card shows the destination")

        // Accessibility text grows the card; the marker would land in text.
        let grown = CGSize(width: 370, height: 260)
        let grownPoint = DestinationVisualLayout.markerPoint(imageSize: image, frame: grown, heightFraction: fraction)
        let grownBand = standard.height * DestinationVisualLayout.decorationBandFraction
        #expect(!DestinationVisualLayout.showsMarker(at: grownPoint, bandHeight: grownBand, top: 0))
        #expect(DestinationVisualLayout.showsMarker(at: CGPoint(x: 10, y: 400), bandHeight: nil, top: 0), "thumbnails carry no text")
        #expect(!DestinationVisualLayout.showsMarker(at: CGPoint(x: 10, y: 60), bandHeight: 200, top: 102), "never under hero controls")

        // Trip Detail at the standard size: between the controls and the text.
        let detail = CGSize(width: 402, height: 290)
        let top = PackWiseSize.heroControlTopInset + PackWiseSize.tapTarget
        let detailBand = max(PackWiseSize.heroHeight * DestinationVisualLayout.decorationBandFraction, top + DestinationVisualLayout.minimumDecorationHeight)
        let detailPoint = DestinationVisualLayout.markerPoint(imageSize: DestinationVisualPurpose.tripHero.size, frame: detail,
                                                              heightFraction: DestinationVisualPurpose.tripHero.markerHeightFraction)
        #expect(DestinationVisualLayout.showsMarker(at: detailPoint, bandHeight: detailBand, top: top), "\(detailPoint) band \(detailBand)")
    }

    // MARK: Destination step

    @Test func destinationStepShowsOneStateAtATime() {
        let recents = [Self.chicago]
        #expect(DestinationStepPhase.resolve(selected: Self.khammam, query: "Kham", isSearching: false, results: [Self.khammam], recents: recents)
                == .selected(Self.khammam), "a selection replaces the results — stated once")
        #expect(DestinationStepPhase.resolve(selected: nil, query: "  ", isSearching: false, results: [], recents: recents) == .empty(recents: recents))
        #expect(DestinationStepPhase.resolve(selected: nil, query: "", isSearching: false, results: [], recents: []) == .empty(recents: []))
        #expect(DestinationStepPhase.resolve(selected: nil, query: "Kham", isSearching: true, results: [], recents: recents) == .searching)
        #expect(DestinationStepPhase.resolve(selected: nil, query: "Chi", isSearching: false, results: [Self.chicago], recents: recents) == .results([Self.chicago]))
        #expect(DestinationStepPhase.resolve(selected: nil, query: " Zzq ", isSearching: false, results: [], recents: recents) == .noResults(query: "Zzq"),
                "offline search fails gracefully into the same message")
    }

    @Test func recentsComeOnlyFromTripsNewestFirstWithoutRepeats() {
        let now = Date.now
        let recents = DestinationRecents.recents(from: [
            (Self.chicago, now.addingTimeInterval(-300)),
            (Self.khammam, now),
            (Self.chicago, now.addingTimeInterval(-100)),
            (Self.longName, now.addingTimeInterval(-200)),
            (Self.iceland, now.addingTimeInterval(-400)),
        ])
        #expect(recents == [Self.khammam, Self.chicago, Self.longName])
        #expect(DestinationRecents.recents(from: []).isEmpty, "no trips, no invented destinations")
    }

    @Test func resultRowsReadAsPlaceThenGeography() {
        #expect(Self.chicago.presentationTitle == "Chicago")
        #expect(Self.chicago.presentationSubtitle == "Illinois, United States", "postal code expands at display time")
        #expect(Self.chicago.region == "IL", "the stored destination is untouched")
        #expect(Self.khammam.presentationSubtitle == "Telangana, India")
        #expect(Self.khammam.accessibilityName == "Khammam, Telangana, India")
        #expect(Self.iceland.presentationSubtitle == "", "a country is not its own subtitle")
    }

    // MARK: Onboarding

    @Test func onboardingMakesOnlyTruthfulClaims() {
        #expect(OnboardingPage.allCases.map(\.title) == [
            "Pack for the trip you're actually taking.",
            "One trip can be many things.",
            "Your choices stay yours.",
        ])
        #expect(OnboardingPage.allCases.map(\.subtitle) == [
            "Destination, dates, weather and plans shape your list.",
            "Beach, city, business, activities and luggage work together.",
            "Change quantities, skip items and add your own without losing your decisions.",
        ])
        let copy = OnboardingPage.allCases.flatMap { [$0.title, $0.subtitle, $0.primaryTitle, $0.heroAccessibilityLabel] }
        for text in copy {
            let words = Set(text.lowercased().split { !$0.isLetter }.map(String.init))
            #expect(words.isDisjoint(with: ["ai", "gpt", "llm", "model", "models", "remembers", "remember", "learns", "learning", "personalized"]), "\(text)")
            #expect(!text.localizedCaseInsensitiveContains("over time"), "\(text)")
        }
    }
}
