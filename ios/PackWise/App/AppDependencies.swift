import Foundation
import Observation
import SwiftData

@Observable
@MainActor
final class AppDependencies {
    let modelContainer: ModelContainer
    let catalog: PackingCatalog
    let rules: PackingRulesFile
    let engine: PackingEngine
    let weatherService: any WeatherService
    let intelligence: any ContextIntelligenceService
    let destinationSearch: any DestinationSearching
    let testDestinations: [Destination]

    init(
        modelContainer: ModelContainer,
        catalog: PackingCatalog,
        rules: PackingRulesFile,
        weatherService: any WeatherService,
        intelligence: any ContextIntelligenceService,
        destinationSearch: any DestinationSearching,
        testDestinations: [Destination]
    ) {
        self.modelContainer = modelContainer
        self.catalog = catalog
        self.rules = rules
        self.engine = PackingEngine(catalog: catalog, rules: rules)
        self.weatherService = weatherService
        self.intelligence = intelligence
        self.destinationSearch = destinationSearch
        self.testDestinations = testDestinations
    }

    static func live() throws -> AppDependencies {
        let destinations = (try? SharedLibrary.testDestinations()) ?? []
        let catalog = try SharedLibrary.catalog()
        return AppDependencies(
            modelContainer: try PackWisePersistence.container(),
            catalog: catalog,
            rules: try SharedLibrary.rules(),
            weatherService: WeatherKitWeatherService(),
            intelligence: Self.intelligence(catalog: catalog),
            destinationSearch: MapKitDestinationSearch(),
            testDestinations: destinations
        )
    }

    /// No configured API base URL means no remote intelligence. The packing
    /// list is built by the deterministic engine either way, so the fallback is
    /// silent by design.
    static func intelligence(catalog: PackingCatalog) -> any ContextIntelligenceService {
        guard let configuration = IntelligenceConfiguration.fromBundle() else {
            return MockContextIntelligenceService()
        }
        return RemoteContextIntelligenceService(
            client: IntelligenceHTTPClient(
                configuration: configuration,
                integrity: configuration.integrityProvider()
            ),
            catalog: catalog
        )
    }

    static func preview() -> AppDependencies {
        let destinations = (try? SharedLibrary.testDestinations()) ?? []
        return AppDependencies(
            modelContainer: try! PackWisePersistence.container(inMemory: true),
            catalog: try! SharedLibrary.catalog(),
            rules: try! SharedLibrary.rules(),
            weatherService: try! MockWeatherService.bundled(),
            intelligence: MockContextIntelligenceService(),
            destinationSearch: FixtureDestinationSearch(destinations: destinations),
            testDestinations: destinations
        )
    }
}
