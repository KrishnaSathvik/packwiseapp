# PackWise

Personal packing intelligence for iPhone. Pack what this trip actually needs.

## Repo

```text
ios/          Native iOS 18 app (SwiftUI, SwiftData)
api/          PackWise Intelligence API (Vercel, Milestone 3)
shared/       Catalog, fixtures, schemas, contracts
docs/         Product and engineering source of truth
design/       Visual mocks
```

Do not share Swift business logic with TypeScript. `shared` is data and contracts only.

## Current milestone

**M3** — Context Intelligence (M3A API foundation → M3B trip-note enrichment → M3C packing gaps). M1 is closed. M2 is code-complete pending physical-device WeatherKit verification.

GPT enriches the deterministic engine; it does not replace it. No `/chat`. Pack lighter / Ask PackWise UI are V1+.

Production destinations come from MapKit. Bundled destinations exist only for tests, previews, and matching mock weather fixtures. Production weather uses WeatherKit, normalized into PackWise-owned models. Fixtures stay for tests/previews.

See `docs/implementation-decisions.md` and `AGENTS.md`.

## iOS

Requires Xcode 16+ and [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```sh
cd ios
xcodegen generate
open PackWise.xcodeproj
```

Set your Apple Developer Team in Xcode signing. Bundle ID is `com.packwiseapp.app`.

```sh
cd ios
xcodebuild -scheme PackWise -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test
```

## API

Local stub for Milestone 3. See `api/README.md`.
