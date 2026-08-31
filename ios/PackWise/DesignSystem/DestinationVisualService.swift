import MapKit
import SwiftUI
import UIKit

/// What a destination image is being used for. Policy differs per surface.
///
/// Every surface wants photography: a bundled curated photo when the catalog
/// has one, Look Around imagery otherwise. There is no map tier anywhere —
/// a map snapshot is the wrong register for a travel product — and the last
/// resort is the branded panel, which is designed rather than apologetic.
enum DestinationVisualPurpose: String, Sendable, CaseIterable {
    /// Compact square on a trip card.
    case tripThumbnail
    /// Confirmation image under destination search.
    case destinationPreview
    /// Full-bleed image at the top of Trip Detail.
    case tripHero

    /// Nominal point size. Fixed per purpose rather than measured per device so
    /// one cached image serves every layout width.
    var size: CGSize {
        switch self {
        case .tripThumbnail: CGSize(width: 160, height: 160)
        case .destinationPreview: CGSize(width: 380, height: 160)
        case .tripHero: CGSize(width: 420, height: 260)
        }
    }
}

/// The three tiers. `graphical` is a designed state, not a failure state — it
/// renders as the branded panel, never as a broken image.
enum DestinationVisual: Sendable, Equatable {
    /// A curated photo shipped in the asset catalog.
    case bundled(UIImage)
    case lookAround(UIImage)
    case graphical

    var image: UIImage? {
        switch self {
        case .bundled(let image), .lookAround(let image): image
        case .graphical: nil
        }
    }
}

/// Asset-catalog lookup for curated destination photography.
///
/// Photos are keyed by a normalized destination ID so they can be added to
/// `Assets.xcassets` incrementally without touching any call site: name an
/// imageset `Destination-<city>` or `Destination-<country>`, lowercased,
/// diacritics stripped, spaces as dashes (e.g. `Destination-chicago`,
/// `Destination-japan`).
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

protocol DestinationVisualService: Sendable {
    func visual(for destination: Destination, purpose: DestinationVisualPurpose) async -> DestinationVisual
    /// Fetch and cache ahead of display, so opening a trip does not wait on
    /// the network.
    func prewarm(_ destination: Destination, purposes: [DestinationVisualPurpose]) async
}

/// Bundled photo first, then Look Around, then the branded panel.
///
/// The snapshotter requires the network, so a cold cache offline resolves to
/// the bundled photo or `.graphical` immediately rather than leaving a spinner
/// on screen. Look Around results are cached to the Caches directory: this is
/// derived presentation data and the system may purge it at will.
actor MapKitDestinationVisualService: DestinationVisualService {
    static let shared = MapKitDestinationVisualService()

    private var memory: [String: DestinationVisual] = [:]
    private var inFlight: [String: Task<DestinationVisual, Never>] = [:]
    private let directory: URL?

    init(directory: URL? = nil) {
        if let directory {
            self.directory = directory
        } else {
            let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            let resolved = caches?.appending(path: "DestinationVisuals", directoryHint: .isDirectory)
            if let resolved {
                try? FileManager.default.createDirectory(at: resolved, withIntermediateDirectories: true)
            }
            self.directory = resolved
        }
    }

    func visual(for destination: Destination, purpose: DestinationVisualPurpose) async -> DestinationVisual {
        // The curated catalog wins over everything, including the cache: it is
        // instant, offline, and always on-brand.
        if let bundled = BundledDestinationPhotos.image(for: destination) {
            return .bundled(bundled)
        }

        let key = cacheKey(destination, purpose)

        if let cached = memory[key] { return cached }
        if let existing = inFlight[key] { return await existing.value }
        if let onDisk = readDisk(key) {
            memory[key] = onDisk
            return onDisk
        }

        let coordinate = CLLocationCoordinate2D(
            latitude: destination.latitude,
            longitude: destination.longitude
        )
        let task = Task<DestinationVisual, Never> {
            await Self.render(coordinate: coordinate, purpose: purpose)
        }
        inFlight[key] = task
        let result = await task.value
        inFlight[key] = nil
        memory[key] = result
        if case .graphical = result {
            // Nothing to persist, and a later launch with a network deserves
            // another attempt.
        } else {
            writeDisk(result, key: key)
        }
        return result
    }

    func prewarm(_ destination: Destination, purposes: [DestinationVisualPurpose]) async {
        for purpose in purposes {
            _ = await visual(for: destination, purpose: purpose)
        }
    }

    // MARK: - Rendering

    /// Look Around is gated on a recognized landmark near the coordinate.
    ///
    /// A raw city centroid produces technically correct but visually boring
    /// imagery — glass office doors as a trip hero. Only when the point
    /// resolves to an actual landmark is street-level imagery worth showing;
    /// everything else falls through to the branded panel.
    private static func render(
        coordinate: CLLocationCoordinate2D,
        purpose: DestinationVisualPurpose
    ) async -> DestinationVisual {
        guard let anchor = await landmarkAnchor(near: coordinate) else {
            return .graphical
        }
        if let image = await lookAround(coordinate: anchor, purpose: purpose) {
            return .lookAround(image)
        }
        return .graphical
    }

    private static let landmarkCategories: [MKPointOfInterestCategory] = [
        .landmark, .castle, .fortress, .nationalMonument,
        .museum, .stadium, .nationalPark, .amusementPark, .beach
    ]

    private static func landmarkAnchor(near coordinate: CLLocationCoordinate2D) async -> CLLocationCoordinate2D? {
        let request = MKLocalPointsOfInterestRequest(center: coordinate, radius: 500)
        request.pointOfInterestFilter = MKPointOfInterestFilter(including: landmarkCategories)
        guard let response = try? await MKLocalSearch(request: request).start() else {
            return nil
        }
        return response.mapItems.first?.placemark.coordinate
    }

    private static func lookAround(
        coordinate: CLLocationCoordinate2D,
        purpose: DestinationVisualPurpose
    ) async -> UIImage? {
        do {
            let request = MKLookAroundSceneRequest(coordinate: coordinate)
            guard let scene = try await request.scene else { return nil }
            let options = MKLookAroundSnapshotter.Options()
            options.size = purpose.size
            let snapshotter = MKLookAroundSnapshotter(scene: scene, options: options)
            return try await snapshotter.snapshot.image
        } catch {
            return nil
        }
    }

    // MARK: - Cache

    private func cacheKey(_ destination: Destination, _ purpose: DestinationVisualPurpose) -> String {
        let latitude = String(format: "%.4f", destination.latitude)
        let longitude = String(format: "%.4f", destination.longitude)
        let size = "\(Int(purpose.size.width))x\(Int(purpose.size.height))"
        return "\(latitude)_\(longitude)_\(purpose.rawValue)_\(size)"
    }

    private func fileURL(_ key: String) -> URL? {
        directory?.appending(path: "\(key).cache", directoryHint: .notDirectory)
    }

    private func readDisk(_ key: String) -> DestinationVisual? {
        guard let url = fileURL(key), let data = try? Data(contentsOf: url) else { return nil }
        // First byte records which tier produced the image. Anything but
        // landmark-gated Look Around (old map snapshots and pre-gate
        // centroid grabs included) is stale and refetches.
        guard let marker = data.first, marker == 2, let image = UIImage(data: data.dropFirst()) else { return nil }
        return .lookAround(image)
    }

    private func writeDisk(_ visual: DestinationVisual, key: String) {
        guard case .lookAround(let image) = visual else { return }
        guard let url = fileURL(key), let png = image.pngData() else { return }
        var data = Data([2])
        data.append(png)
        try? data.write(to: url, options: .atomic)
    }
}

extension EnvironmentValues {
    @Entry var destinationVisuals: any DestinationVisualService = MapKitDestinationVisualService.shared
}
