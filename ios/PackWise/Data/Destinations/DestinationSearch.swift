import Foundation
import MapKit

protocol DestinationSearching: Sendable {
    func search(query: String) async -> [Destination]
}

struct FixtureDestinationSearch: DestinationSearching {
    var destinations: [Destination]

    func search(query: String) async -> [Destination] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return Array(destinations.prefix(12)) }
        return destinations.filter {
            $0.displayName.localizedCaseInsensitiveContains(q)
                || $0.region.localizedCaseInsensitiveContains(q)
                || $0.country.localizedCaseInsensitiveContains(q)
        }
    }
}

enum DestinationNormalizer {
    /// MapKit / reverse-geocode timezone if present. Never fall back to the device zone.
    static func timeZoneIdentifier(mapItem: TimeZone?, placemark: TimeZone?) -> String {
        mapItem?.identifier ?? placemark?.identifier ?? ""
    }

    static func destination(
        city: String,
        region: String,
        country: String,
        countryCode: String,
        latitude: Double,
        longitude: Double,
        mapKitTimeZone: String?,
        placemarkTimeZone: String?,
        mapKitIdentifier: String?,
        displayName: String? = nil
    ) -> Destination {
        let zone = mapKitTimeZone?.trimmingCharacters(in: .whitespacesAndNewlines)
        let placeZone = placemarkTimeZone?.trimmingCharacters(in: .whitespacesAndNewlines)
        let timeZone = {
            if let zone, !zone.isEmpty { return zone }
            if let placeZone, !placeZone.isEmpty { return placeZone }
            return ""
        }()
        return Destination(
            displayName: displayName ?? city,
            city: city,
            region: region,
            country: country,
            countryCode: countryCode,
            latitude: latitude,
            longitude: longitude,
            timeZone: timeZone,
            mapKitIdentifier: mapKitIdentifier,
            fixtureID: nil
        )
    }

    static func destination(from item: MKMapItem, query: String) -> Destination? {
        let place = item.placemark
        guard let location = place.location else { return nil }
        let city = place.locality ?? item.name ?? place.name ?? query
        let trimmedCity = city.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedCity.isEmpty else { return nil }
        return destination(
            city: trimmedCity,
            region: place.administrativeArea ?? "",
            country: place.country ?? "",
            countryCode: place.isoCountryCode ?? "",
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude,
            mapKitTimeZone: timeZoneIdentifier(mapItem: item.timeZone, placemark: place.timeZone),
            placemarkTimeZone: nil,
            mapKitIdentifier: item.url?.absoluteString,
            displayName: trimmedCity
        )
    }
}

struct MapKitDestinationSearch: DestinationSearching {
    func search(query: String) async -> [Destination] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else { return [] }

        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = trimmed
        let search = MKLocalSearch(request: request)
        guard let response = try? await search.start() else { return [] }

        return response.mapItems.prefix(8).compactMap { item in
            DestinationNormalizer.destination(from: item, query: trimmed)
        }
    }
}
