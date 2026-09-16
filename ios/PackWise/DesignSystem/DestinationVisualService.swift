import MapKit
import SwiftUI
import UIKit

/// What a destination image is being used for. Each purpose renders at one
/// fixed nominal size so a cached image serves every layout width.
enum DestinationVisualPurpose: String, Sendable, CaseIterable {
    /// Compact square on a trip row and the confirmed destination in setup.
    case tripThumbnail
    /// The wide band on the Trips Home hero card and the setup Review hero.
    case tripCard
    /// Full-bleed hero at the top of Trip Detail.
    case tripHero

    var size: CGSize {
        switch self {
        case .tripThumbnail: CGSize(width: 160, height: 160)
        case .tripCard: CGSize(width: 444, height: 180)
        case .tripHero: CGSize(width: 420, height: 300)
        }
    }

    /// Where the destination sits vertically in a map snapshot, as a fraction
    /// of the height: inside each surface's decoration band, so at the
    /// standard size the marker shows between hero controls and the text
    /// safe region.
    var markerHeightFraction: Double {
        switch self {
        case .tripThumbnail: 0.5
        case .tripCard: 0.28
        case .tripHero: 0.45
        }
    }
}

/// The resolved visual (Task 9). `graphical` is a designed state, never a
/// broken image. The view adds a fifth state, loading, before any of these.
enum DestinationVisual: Sendable, Equatable {
    /// Curated imagery shipped in the asset catalog: correct by construction.
    case trusted(UIImage)
    /// Apple Look Around imagery, used only when the policy allows it.
    case lookAround(UIImage)
    /// An `MKMapSnapshotter` image of the destination's region.
    case map(UIImage)
    case graphical

    var image: UIImage? {
        switch self {
        case .trusted(let image), .lookAround(let image), .map(let image): image
        case .graphical: nil
        }
    }

    /// The tier name, for tests and diagnostics.
    var tier: String {
        switch self {
        case .trusted: "trusted"
        case .lookAround: "lookAround"
        case .map: "map"
        case .graphical: "graphical"
        }
    }
}

/// Asset-catalog lookup for curated destination photography.
///
/// Name an imageset `Destination-<city>` or `Destination-<country>`, lowercased,
/// diacritics stripped, spaces as dashes (`Destination-chicago`). A photo is
/// only ever added for the place it shows — never a stand-in.
enum BundledDestinationPhotos {
    static func image(for destination: Destination) -> UIImage? {
        for key in [destination.city, destination.displayName, destination.country] {
            let normalized = normalize(key)
            guard !normalized.isEmpty else { continue }
            if let image = UIImage(named: "Destination-\(normalized)") {
                return image
            }
        }
        return nil
    }

    static func normalize(_ name: String) -> String {
        name.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()
            .replacingOccurrences(of: " ", with: "-")
    }
}

// MARK: - Map request

/// How much of the world a map snapshot shows, from the destination's own
/// granularity: a city is a street grid, a region is a state, a country is a
/// country.
enum DestinationMapScale: String, Sendable, CaseIterable {
    case city
    case region
    case country

    static func of(_ destination: Destination) -> DestinationMapScale {
        let city = destination.city.trimmingCharacters(in: .whitespaces)
        if !city.isEmpty, city.caseInsensitiveCompare(destination.country) != .orderedSame,
           city.caseInsensitiveCompare(destination.region) != .orderedSame {
            return .city
        }
        if !destination.region.trimmingCharacters(in: .whitespaces).isEmpty,
           destination.region.caseInsensitiveCompare(destination.country) != .orderedSame {
            return .region
        }
        return .country
    }

    /// Latitude degrees across the snapshot's height.
    var latitudeDelta: Double {
        switch self {
        case .city: 0.16
        case .region: 3.5
        case .country: 16
        }
    }
}

/// Everything a map snapshot depends on. Two equal requests draw the same
/// image, which is what makes the cache key deterministic.
struct DestinationMapRequest: Hashable, Sendable {
    var latitude: Double
    var longitude: Double
    var scale: DestinationMapScale
    var purpose: DestinationVisualPurpose

    init(destination: Destination, purpose: DestinationVisualPurpose) {
        latitude = destination.latitude
        longitude = destination.longitude
        scale = .of(destination)
        self.purpose = purpose
    }

    var size: CGSize { purpose.size }

    /// The region whose center is offset south so the destination itself
    /// lands at `purpose.markerHeightFraction` of the height.
    var region: MKCoordinateRegion {
        let latitudeDelta = scale.latitudeDelta
        let aspect = size.width / size.height
        let longitudeDelta = min(360, latitudeDelta * aspect / max(0.2, cos(latitude * .pi / 180)))
        let centerLatitude = latitude - (0.5 - purpose.markerHeightFraction) * latitudeDelta
        return MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: max(-85, min(85, centerLatitude)), longitude: longitude),
            span: MKCoordinateSpan(latitudeDelta: latitudeDelta, longitudeDelta: longitudeDelta)
        )
    }

    /// Stable across launches and devices: rounded coordinates, scale,
    /// purpose, and size. Versioned so a rendering change invalidates the
    /// disk cache instead of mixing styles.
    var cacheKey: String {
        String(format: "map-v4_%.4f_%.4f_", latitude, longitude)
            + "\(scale.rawValue)_\(purpose.rawValue)_\(Int(size.width))x\(Int(size.height))"
    }
}

// MARK: - Providers

protocol DestinationMapSnapshotting: Sendable {
    /// Throws when the map cannot be drawn (offline, provider failure) and
    /// `CancellationError` when the calling task is cancelled.
    func snapshot(for request: DestinationMapRequest) async throws -> UIImage
}

protocol DestinationStreetImagery: Sendable {
    /// Street-level imagery worth showing for the coordinate, or nil.
    func image(latitude: Double, longitude: Double, size: CGSize) async -> UIImage?
}

/// Whether a street-level tier runs at all.
///
/// Off in production (Task 9). The only street-level evidence so far is
/// Checkpoint V's Chicago hero: landmark-gated Look Around returned glass
/// office doors, which says nothing about the destination. Until a
/// usefulness rule is proven on real destinations, the map states where the
/// trip is and street imagery stays out.
struct DestinationVisualPolicy: Sendable, Hashable {
    var usesStreetImagery: Bool

    static let production = DestinationVisualPolicy(usesStreetImagery: false)
}

// MARK: - Service

protocol DestinationVisualService: Sendable {
    func visual(for destination: Destination, purpose: DestinationVisualPurpose) async -> DestinationVisual
    /// Fetch and cache ahead of display, so opening a trip does not wait on
    /// the network.
    func prewarm(_ destination: Destination, purposes: [DestinationVisualPurpose]) async
}

/// The one destination visual policy (Task 9):
///
///     trusted imagery → street imagery (policy-gated) → map snapshot → graphical
///
/// Rendering runs off the main actor. Map and street results are cached in
/// memory and in Caches (derived data the system may purge). A failure is
/// not persisted: it resolves to `graphical` at once and is retried after
/// `retryInterval`, so an offline launch never waits on a spinner and a
/// reconnect recovers. Cancelling the caller cancels the snapshot and caches
/// nothing.
actor MapKitDestinationVisualService: DestinationVisualService {
    static let shared = MapKitDestinationVisualService()

    private let directory: URL?
    private let trusted: @Sendable (Destination) -> UIImage?
    private let streetImagery: any DestinationStreetImagery
    private let mapSnapshots: any DestinationMapSnapshotting
    private let policy: DestinationVisualPolicy
    private let retryInterval: TimeInterval

    private var memory: [String: DestinationVisual] = [:]
    private var inFlight: [String: Task<DestinationVisual?, Never>] = [:]
    private var failures: [String: Date] = [:]

    init(
        directory: URL? = MapKitDestinationVisualService.defaultDirectory(),
        trusted: @escaping @Sendable (Destination) -> UIImage? = { BundledDestinationPhotos.image(for: $0) },
        streetImagery: any DestinationStreetImagery = LandmarkLookAroundImagery(),
        mapSnapshots: any DestinationMapSnapshotting = MapKitDestinationMapSnapshots(),
        policy: DestinationVisualPolicy = .production,
        retryInterval: TimeInterval = 60
    ) {
        self.directory = directory
        self.trusted = trusted
        self.streetImagery = streetImagery
        self.mapSnapshots = mapSnapshots
        self.policy = policy
        self.retryInterval = retryInterval
    }

    static func defaultDirectory() -> URL? {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
        let resolved = caches?.appending(path: "DestinationVisuals", directoryHint: .isDirectory)
        if let resolved {
            try? FileManager.default.createDirectory(at: resolved, withIntermediateDirectories: true)
        }
        return resolved
    }

    func visual(for destination: Destination, purpose: DestinationVisualPurpose) async -> DestinationVisual {
        // Curated imagery wins over everything, the cache included: instant,
        // offline, and correct for the place.
        if let image = trusted(destination) { return .trusted(image) }

        let request = DestinationMapRequest(destination: destination, purpose: purpose)
        let key = Self.cacheKey(request, policy: policy)
        if let cached = memory[key] { return cached }
        if let onDisk = readDisk(key) {
            memory[key] = onDisk
            return onDisk
        }
        if let failedAt = failures[key], Date.now.timeIntervalSince(failedAt) < retryInterval {
            return .graphical
        }

        let task: Task<DestinationVisual?, Never>
        if let existing = inFlight[key] {
            task = existing
        } else {
            let street = streetImagery
            let maps = mapSnapshots
            let usesStreet = policy.usesStreetImagery
            task = Task.detached(priority: .userInitiated) {
                await Self.render(request, usesStreet: usesStreet, street: street, maps: maps)
            }
            inFlight[key] = task
        }
        let result = await withTaskCancellationHandler {
            await task.value
        } onCancel: {
            task.cancel()
        }
        if inFlight[key] == task { inFlight[key] = nil }

        guard let result else { return .graphical } // cancelled: nothing recorded
        switch result {
        case .graphical:
            failures[key] = .now
        default:
            failures[key] = nil
            memory[key] = result
            writeDisk(result, key: key)
        }
        return result
    }

    func prewarm(_ destination: Destination, purposes: [DestinationVisualPurpose]) async {
        for purpose in purposes {
            _ = await visual(for: destination, purpose: purpose)
        }
    }

    /// Nil only when cancelled.
    private static func render(
        _ request: DestinationMapRequest,
        usesStreet: Bool,
        street: any DestinationStreetImagery,
        maps: any DestinationMapSnapshotting
    ) async -> DestinationVisual? {
        if usesStreet, let image = await street.image(latitude: request.latitude, longitude: request.longitude, size: request.size) {
            return .lookAround(image)
        }
        if Task.isCancelled { return nil }
        do {
            return .map(try await maps.snapshot(for: request))
        } catch {
            return Task.isCancelled || error is CancellationError ? nil : .graphical
        }
    }

    // MARK: Cache

    static func cacheKey(_ request: DestinationMapRequest, policy: DestinationVisualPolicy) -> String {
        (policy.usesStreetImagery ? "street+" : "") + request.cacheKey
    }

    private func fileURL(_ key: String) -> URL? {
        directory?.appending(path: "\(key).cache", directoryHint: .notDirectory)
    }

    /// First byte records the tier: 2 street imagery, 3 map. Anything else —
    /// including the pre-Task 9 files, whose keys no longer match — refetches.
    private func readDisk(_ key: String) -> DestinationVisual? {
        guard let url = fileURL(key), let data = try? Data(contentsOf: url), let marker = data.first,
              let image = UIImage(data: data.dropFirst()) else { return nil }
        switch marker {
        case 2 where policy.usesStreetImagery: return .lookAround(image)
        case 3: return .map(image)
        default: return nil
        }
    }

    private func writeDisk(_ visual: DestinationVisual, key: String) {
        let marker: UInt8
        switch visual {
        case .lookAround: marker = 2
        case .map: marker = 3
        case .trusted, .graphical: return
        }
        guard let url = fileURL(key), let png = visual.image?.pngData() else { return }
        var data = Data([marker])
        data.append(png)
        try? data.write(to: url, options: .atomic)
    }
}

// MARK: - MapKit providers

/// `MKMapSnapshotter` satellite imagery of the destination's region, with the
/// destination at `purpose.markerHeightFraction`. The marker is not baked in:
/// `DestinationVisualView` draws it only where it cannot cover text. The
/// snapshot keeps Apple's attribution; `DestinationHero` reserves room for it.
struct MapKitDestinationMapSnapshots: DestinationMapSnapshotting {
    func snapshot(for request: DestinationMapRequest) async throws -> UIImage {
        let snapshotter = await Self.makeSnapshotter(for: request)
        let once = ResumeOnce<UIImage>()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                once.install(continuation)
                if Task.isCancelled {
                    once.resume(throwing: CancellationError())
                    return
                }
                snapshotter.value.start(with: .global(qos: .userInitiated)) { snapshot, error in
                    if let snapshot {
                        once.resume(returning: snapshot.image)
                    } else {
                        once.resume(throwing: error ?? CancellationError())
                    }
                }
            }
        } onCancel: {
            snapshotter.value.cancel()
            once.resume(throwing: CancellationError())
        }
    }

    /// Configuring trait collections is main-actor work; only the setup runs
    /// there, and the snapshot itself renders on a background queue.
    @MainActor
    private static func makeSnapshotter(for request: DestinationMapRequest) -> SnapshotterBox {
        let options = MKMapSnapshotter.Options()
        options.region = request.region
        options.size = request.size
        // Flat satellite imagery: it shows the place without map labels,
        // which would otherwise sit under the destination title, and it is
        // dark enough for white text under the shared scrim.
        options.preferredConfiguration = MKImageryMapConfiguration(elevationStyle: .flat)
        options.traitCollection = UITraitCollection { traits in
            traits.userInterfaceStyle = .light
            traits.displayScale = 3
        }
        return SnapshotterBox(MKMapSnapshotter(options: options))
    }
}

/// Look Around, gated on a recognized landmark near the coordinate. Kept as
/// the street-imagery provider; `DestinationVisualPolicy.production` does not
/// run it.
struct LandmarkLookAroundImagery: DestinationStreetImagery {
    private static let landmarkCategories: [MKPointOfInterestCategory] = [
        .landmark, .castle, .fortress, .nationalMonument,
        .museum, .stadium, .nationalPark, .amusementPark, .beach
    ]

    func image(latitude: Double, longitude: Double, size: CGSize) async -> UIImage? {
        let request = MKLocalPointsOfInterestRequest(
            center: CLLocationCoordinate2D(latitude: latitude, longitude: longitude),
            radius: 500
        )
        request.pointOfInterestFilter = MKPointOfInterestFilter(including: Self.landmarkCategories)
        guard let anchor = try? await MKLocalSearch(request: request).start().mapItems.first?.placemark.coordinate else {
            return nil
        }
        do {
            guard let scene = try await MKLookAroundSceneRequest(coordinate: anchor).scene else { return nil }
            let options = MKLookAroundSnapshotter.Options()
            options.size = size
            return try await MKLookAroundSnapshotter(scene: scene, options: options).snapshot.image
        } catch {
            return nil
        }
    }
}

/// `MKMapSnapshotter` is not `Sendable`; it is only started once and
/// cancelled, both of which it documents as safe from any thread.
private final class SnapshotterBox: @unchecked Sendable {
    let value: MKMapSnapshotter
    init(_ value: MKMapSnapshotter) { self.value = value }
}

/// Resumes a continuation exactly once, whichever of completion and
/// cancellation arrives first.
private final class ResumeOnce<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Value, Error>?
    private var pending: Result<Value, Error>?
    private var finished = false

    func install(_ continuation: CheckedContinuation<Value, Error>) {
        lock.lock()
        if let pending {
            finished = true
            lock.unlock()
            continuation.resume(with: pending)
            return
        }
        self.continuation = continuation
        lock.unlock()
    }

    func resume(returning value: Value) { finish(.success(value)) }
    func resume(throwing error: Error) { finish(.failure(error)) }

    private func finish(_ result: Result<Value, Error>) {
        lock.lock()
        guard !finished else { lock.unlock(); return }
        guard let continuation else {
            // Cancelled before the continuation existed.
            if pending == nil { pending = result }
            lock.unlock()
            return
        }
        finished = true
        self.continuation = nil
        lock.unlock()
        continuation.resume(with: result)
    }
}

extension EnvironmentValues {
    @Entry var destinationVisuals: any DestinationVisualService = MapKitDestinationVisualService.shared
}
