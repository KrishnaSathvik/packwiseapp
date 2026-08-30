import SwiftUI

@main
struct PackWiseApp: App {
    private let dependencies: AppDependencies

    init() {
        do {
            dependencies = try AppDependencies.live()
        } catch {
            fatalError("PackWise failed to load catalog or data store: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(dependencies)
                .tint(PackWiseColor.accent)
        }
        .modelContainer(dependencies.modelContainer)
    }
}
