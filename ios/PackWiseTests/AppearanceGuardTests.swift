import Foundation
import Testing
@testable import PackWise

/// Light-only is an app-wide policy, set once by `UIUserInterfaceStyle =
/// Light` in `Info.plist` (Task 9.1). A root `.preferredColorScheme(.light)`
/// must not return: that window-wide preference pins the status bar to dark
/// glyphs and overrides Trip Detail's per-screen request over its hero.
struct AppearanceGuardTests {
    private static let appRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("PackWise")

    @Test func infoPlistIsTheOnlyLightModeAuthority() throws {
        let plist = try String(contentsOf: Self.appRoot.appendingPathComponent("Info.plist"), encoding: .utf8)
        let range = try #require(plist.range(of: "<key>UIUserInterfaceStyle</key>"))
        let value = plist[range.upperBound...].prefix(80)
        #expect(value.contains("<string>Light</string>"), "Info.plist must pin UIUserInterfaceStyle to Light")
    }

    @Test func noSourceFileSetsAColorSchemePreference() throws {
        let enumerator = try #require(FileManager.default.enumerator(at: Self.appRoot, includingPropertiesForKeys: nil))
        var offenders: [String] = []
        for case let url as URL in enumerator where url.pathExtension == "swift" {
            let source = try String(contentsOf: url, encoding: .utf8)
            for (index, line) in source.components(separatedBy: "\n").enumerated()
            where line.contains(".preferredColorScheme(") && !line.trimmingCharacters(in: .whitespaces).hasPrefix("//") {
                offenders.append("\(url.lastPathComponent):\(index + 1)")
            }
        }
        #expect(offenders.isEmpty, "a root color-scheme preference must not return: \(offenders)")
    }
}
