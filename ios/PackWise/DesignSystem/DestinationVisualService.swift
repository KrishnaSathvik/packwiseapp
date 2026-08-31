import MapKit
import SwiftUI
import UIKit

/// What a destination image is being used for. Policy differs per surface.
///
/// Destination search deliberately prefers the map: that screen answers "did I
/// select the right Chicago?", and a map answers it better than a street-level
/// view of an arbitrary intersection.
enum DestinationVisualPurpose: String, Sendable, CaseIterable {
    /// Compact square on a trip card.
    case tripThumbnail
    /// Confirmation image under destination search.
    case destinationPreview
    /// Full-bleed image at the top of Trip Detail.
    case tripHero

    var sources: [DestinationVisualSource] {
        switch self {
        case .tripThumbnail: [.lookAround, .map]
        case .destinationPreview: [.map]
        case .tripHero: [.lookAround, .map]
        }
    }

    /// Nominal point size. Fixed per purpose rather than measured per device so
    /// one cached image serves every layout width.
    var size: CGSize {
        switch self {
        case .tripThumbnail: CGSize(width: 160, height: 160)
        case .destinationPreview: CGSize(width: 380, height: 160)
        case .tripHero: CGSize(width: 420, height: 260)
        }
    }

    /// How much ground the map fallback covers.
    var mapSpanMeters: CLLocationDistance {
        switch self {
        case .tripThumbnail: 14_000
        case .destinationPreview: 9_000
        case .tripHero: 11_000
        }
    }

    /// Whether the map fallback should mark the exact coordinate.
    ///
    /// `MKMapSnapshotter` does not render annotations, so the pin is drawn by
    /// hand. Only the confirmation surface needs one.
    var marksCoordinate: Bool { self == .destinationPreview }
}

enum DestinationVisualSource: Sendable {
    case lookAround
    case map
}

/// The three tiers. `graphical` is a designed state, not a failure state — it
/// renders as a tinted gradient with a glyph, never as a broken image.
enum DestinationVisual: Sendable, Equatable {
    case lookAround(UIImage)
    case map(UIImage)
    case graphical

    var image: UIImage? {
        switch self {
        case .lookAround(let image), .map(let image): image
        case .graphical: nil
        }
    }
}

protocol DestinationVisualService: Sendable {
    func visual(for destination: Destination, purpose: DestinationVisualPurpose) async -> DestinationVisual
    /// Fetch and cache ahead of display, so opening a trip does not wait on
    /// the network.
    func prewarm(_ destination: Destination, purposes: [DestinationVisualPurpose]) async
}

/// Look Around first, then a map snapshot, then the graphical tier.
///
/// Both snapshotters require the network, so a cold cache offline resolves to
/// `.graphical` immediately rather than leaving a spinner on screen. Results
/// are cached to the Caches directory: this is derived presentation data and
/// the system may purge it at will.
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

    private static func render(
        coordinate: CLLocationCoordinate2D,
        purpose: DestinationVisualPurpose
    ) async -> DestinationVisual {
        for source in purpose.sources {
            switch source {
            case .lookAround:
                if let image = await lookAround(coordinate: coordinate, purpose: purpose) {
                    return .lookAround(image)
                }
            case .map:
                if let image = await map(coordinate: coordinate, purpose: purpose) {
                    return .map(image)
                }
            }
        }
        return .graphical
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

    @MainActor
    private static func map(
        coordinate: CLLocationCoordinate2D,
        purpose: DestinationVisualPurpose
    ) async -> UIImage? {
        let options = MKMapSnapshotter.Options()
        options.region = MKCoordinateRegion(
            center: coordinate,
            latitudinalMeters: purpose.mapSpanMeters,
            longitudinalMeters: purpose.mapSpanMeters
        )
        options.size = purpose.size
        options.pointOfInterestFilter = .includingAll

        do {
            let snapshot = try await MKMapSnapshotter(options: options).start()
            guard purpose.marksCoordinate else { return snapshot.image }
            return marked(snapshot, coordinate: coordinate)
        } catch {
            return nil
        }
    }

    /// `MKMapSnapshotter` output contains no annotations, so the destination
    /// pin is composited on afterwards.
    @MainActor
    private static func marked(
        _ snapshot: MKMapSnapshotter.Snapshot,
        coordinate: CLLocationCoordinate2D
    ) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: snapshot.image.size)
        return renderer.image { context in
            snapshot.image.draw(at: .zero)

            let point = snapshot.point(for: coordinate)
            let radius: CGFloat = 7
            let dot = CGRect(
                x: point.x - radius,
                y: point.y - radius,
                width: radius * 2,
                height: radius * 2
            )
            context.cgContext.setFillColor(UIColor.white.cgColor)
            context.cgContext.fillEllipse(in: dot.insetBy(dx: -2.5, dy: -2.5))
            context.cgContext.setFillColor(UIColor(PackWiseColor.accent).cgColor)
            context.cgContext.fillEllipse(in: dot)
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
        // First byte records which tier produced the image, so a map snapshot
        // is never mistaken for real Look Around imagery.
        guard let marker = data.first, let image = UIImage(data: data.dropFirst()) else { return nil }
        return marker == 1 ? .lookAround(image) : .map(image)
    }

    private func writeDisk(_ visual: DestinationVisual, key: String) {
        guard let url = fileURL(key), let image = visual.image else { return }
        guard let png = image.pngData() else { return }
        var data = Data([visual.isLookAround ? 1 : 0])
        data.append(png)
        try? data.write(to: url, options: .atomic)
    }
}

private extension DestinationVisual {
    var isLookAround: Bool {
        if case .lookAround = self { return true }
        return false
    }
}

extension EnvironmentValues {
    @Entry var destinationVisuals: any DestinationVisualService = MapKitDestinationVisualService.shared
}
