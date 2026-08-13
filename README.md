# I Like Trains

A tactile, map-first rail tracker for iOS. I Like Trains combines the live operational clarity of Flighty with the playful physicality of Not Boring apps: an edge-to-edge national rail map, bold typography, springy controls, and a compact status card that makes every train feel tangible.

> The first version uses realistic deterministic mock data. Passenger markers and freight sightings are clearly labeled as mock/community-style data and must not be used for travel or safety decisions.

## What is in the MVP

- MapKit-based national rail map with independently toggleable passenger, infrastructure, station, and freight-sighting layers
- Seven realistic train fixtures across Amtrak, Brightline, and Metrolink
- Six intercity/freight corridors with major stations and traffic-density styling
- Five freight sightings with explicit observation time, reporter count, and confidence
- Search by train number, service name, operator, endpoint, or next stop
- Operator and layer filters
- Spring-animated train selection and a status card with next stop, ETA, speed, delay, and freshness
- Native locate, compass, scale, sheets, menus, Dynamic Type, VoiceOver labels, reduced-motion behavior, and iOS 17 haptics
- SwiftUI previews and XCTest coverage for the provider and view-model layers
- Reproducible signal-orange app icon source

## Open and run

Requirements: Xcode 16 or newer and an iOS 17+ simulator/device.

1. Open **I Like Trains.xcodeproj**.
2. Choose the shared **I Like Trains** scheme.
3. Select an iPhone simulator and press Run.

The app has no third-party dependencies and does not require API keys.

Run the iOS tests on macOS:

```sh
xcodebuild test \
  -project "I Like Trains.xcodeproj" \
  -scheme "I Like Trains" \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro'
```

The domain layer also has a Swift Package test harness:

```sh
swift test
```

For a platform-independent project-graph audit:

```sh
python3 scripts/validate_project.py
```

## Architecture

| Area | Responsibility |
| --- | --- |
| `Models` | Portable, immutable rail values with no MapKit dependency |
| `Services` | Async provider protocols and deterministic mock implementation |
| `ViewModels` | Main-actor loading, refresh, selection, search, and layer state |
| `Views` | MapKit rendering and small SwiftUI interaction components |
| `Support` | Presentation-only coordinate conversion and semantic theme tokens |
| `I Like TrainsTests` | Data contracts, filtering, selection, and failure preservation |

Three narrow interfaces form the integration seam:

```swift
protocol TrainProviding {
    func trains() async throws -> [Train]
}

protocol RailInfrastructureProviding {
    func railSegments() async throws -> [RailSegment]
}

protocol FreightSightingProviding {
    func freightSightings() async throws -> [FreightSighting]
}
```

`RailMapViewModel` accepts each provider independently. One production adapter can implement several protocols, or each feed can have a separate client. Feed DTOs never need to leak into SwiftUI.

## Replacing mocks with real data

| Source | Adapter responsibility | Main product caveat |
| --- | --- | --- |
| Amtrak / GTFS-Realtime | Decode vehicles and trip updates; reconcile vehicle, trip, and schedule IDs; normalize delays and freshness | Coverage and field availability vary by agency |
| Static GTFS | Build station metadata, route names, and scheduled fallback positions | Schedules are not positions |
| OpenRailwayMap / OpenStreetMap | Tile or query rail geometry, yards, usage, gauge, electrification, and operator tags | Attribution, caching, and data-license compliance are required |
| FRA datasets | Add authoritative U.S. network and crossing context | Many datasets are not real-time |
| Crowdsourced freight sightings | Validate reports, deduplicate nearby sightings, decay confidence over time, and moderate abuse | There is no nationwide public freight GPS feed |

Before shipping a live version, add:

1. Feed-specific DTO and client modules that conform to the existing protocols.
2. Attribution and source timestamps in every detail surface.
3. Polling/backoff, local caching, stale-data thresholds, and snapshot reconciliation.
4. Location permission education before invoking nearby discovery.
5. A privacy and moderation model for community reports.
6. Background refresh and notifications only after data reliability is measurable.

## Design notes

The palette intentionally uses warm parchment surfaces over a muted Apple map, signal orange for primary emphasis, and operator colors only where identity matters. All controls remain native buttons, menus, sheets, and MapKit controls so the personality does not come at the expense of accessibility or familiar iOS behavior.

The product and implementation designs are recorded under `docs/superpowers/`.
