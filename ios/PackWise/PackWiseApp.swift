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
                // The reference sheet is drawn light-only; the app matches it
                // exactly. Dark mode is a later project with its own sheet.
                .preferredColorScheme(.light)
        }
        .modelContainer(dependencies.modelContainer)
    }
}
