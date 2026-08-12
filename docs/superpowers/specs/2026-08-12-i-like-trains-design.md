# I Like Trains MVP Design

## Product intent

I Like Trains is a native iOS rail map for curious travelers and railfans. The MVP should feel like a focused instrument rather than a database browser: opening the app immediately reveals moving trains, rail corridors, and freight sightings; selecting a train produces a compact, tactile status card with the information needed to understand what is happening now.

## Experience

The primary surface is an edge-to-edge MapKit map with three independently toggleable layers: infrastructure, passenger trains, and freight sightings. A compact top bar provides brand, search, and filters. A floating locate control and layer control use native materials. Selecting a train animates the camera and presents a bottom card with service identity, endpoints, punctuality, speed, next stop, and data freshness. Search and filter controls appear in native sheets rather than inventing a custom navigation shell.

The visual language combines Flighty's information hierarchy with the playful physicality of Not Boring apps: warm parchment-adjacent surfaces, vivid signal orange, large condensed-feeling system typography, rounded continuous corners, spring animations, press scaling, subtle shadows, haptics, and SF Symbols. All important controls remain standard SwiftUI `Button`, `Menu`, `Sheet`, and MapKit interactions so accessibility and iOS conventions are preserved.

## Architecture

`RailMapViewModel` owns scene-level loading, selection, filters, and camera intent. It depends only on `TrainProviding`, `RailInfrastructureProviding`, and `FreightSightingProviding`. `MockRailDataService` implements all three protocols with deterministic, realistic fixtures. Domain models do not import MapKit or CoreLocation; they use a small `RailCoordinate` value type, making the data layer portable and easy to unit test. Views convert domain coordinates to `CLLocationCoordinate2D` at the presentation boundary.

The app is dependency-free and targets iOS 17. It uses SwiftUI, MapKit, Observation, and XCTest only. A small Swift package manifest exposes the portable data layer for non-Xcode CI environments without changing the Xcode app's conventional structure.

## Data flow and failure behavior

On launch, the view model requests all three feeds concurrently and publishes a single loading state. Mock results are immediate but the interface is asynchronous so later adapters can perform network requests. A failed refresh preserves the previous snapshot and displays a non-blocking error state with retry. Filters are applied locally to the current snapshot. Train freshness and sighting confidence are first-class model fields and are always visible where relevant.

Future adapters should normalize Amtrak/GTFS-Realtime vehicle positions into `Train`, OpenRailwayMap or FRA geometry into `RailSegment`, and community reports into `FreightSighting`. Feed-specific DTOs, authentication, polling, caching, reconciliation, and attribution stay outside the UI target.

## MVP scope

- Edge-to-edge interactive MapKit map with mock route polylines, stations, trains, and freight sightings.
- Search by service, train number, route, endpoint, or operator.
- Operator and layer filters.
- Animated train selection and a tactile detail card.
- Loading, empty, refresh, and error presentation.
- Dynamic Type, VoiceOver labels, reduced-motion-aware animations, light/dark semantic colors, and 44-point targets.
- Previews for the root map and key components.
- Unit tests for protocol-backed loading, filtering, layer visibility, fixture realism, and refresh failure behavior.

## Explicitly deferred

Live feed clients, background refresh, notifications, accounts, persistence, crowdsourced report submission, turn-by-turn trip planning, and a nationwide authoritative freight-position claim are deferred. Freight markers are labeled as sightings with confidence and age, never presented as verified real-time GPS.

## Verification

The project must have internally consistent Xcode target membership, deployment target 17.0, no third-party dependencies, no placeholder markers, and a passing portable data-layer test suite when Swift is available. On macOS, the final acceptance command is `xcodebuild test -project "I Like Trains.xcodeproj" -scheme "I Like Trains" -destination 'platform=iOS Simulator,name=iPhone 16 Pro'`.
