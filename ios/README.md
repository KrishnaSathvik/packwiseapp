# PackWise iOS

iOS 18, SwiftUI, SwiftData. Bundle ID `com.packwiseapp.app`.

```sh
brew install xcodegen   # if needed; project.yml pins the minimum version
cd ios
xcodegen generate
open PackWise.xcodeproj
```

The committed `PackWise.xcodeproj` is xcodegen 2.45.4 output. Regenerating with a different generator version produces pbxproj churn that drowns the real diff — if your regeneration diff touches more than the files you added or removed, check `xcodegen version` before committing it.

Set your Apple Developer Team under Signing & Capabilities. Enable **WeatherKit** on the App ID in [Certificates, Identifiers & Profiles](https://developer.apple.com/account/resources/identifiers/list). The `com.apple.developer.weatherkit` entitlement is in `PackWise.entitlements`.

```sh
xcodebuild -scheme PackWise -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test
```

Production weather is `WeatherKitWeatherService` (M2A, closed). Real forecasts require a physical device with a WeatherKit-enabled App ID. `MockWeatherService` remains for tests, previews, and fixtures. M2B Packing Impact and M2C weather-change diffs are shipped. A newer snapshot never silently rewrites the list.
