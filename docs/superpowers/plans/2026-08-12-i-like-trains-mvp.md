# I Like Trains MVP Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a polished dependency-free SwiftUI iOS 17 rail map with protocol-backed mock data, previews, tests, documentation, and a reviewable Xcode project.

**Architecture:** A portable domain/data module defines models and three async provider protocols. A main-actor observable view model composes providers and owns map state, while small SwiftUI views render MapKit overlays and tactile controls. Feed adapters can later replace the mock service through initializer injection.

**Tech Stack:** Swift 5.9, SwiftUI, MapKit, Observation, XCTest, Xcode project format 60.

## Global Constraints

- Product name: `I Like Trains`.
- Deployment target: iOS 17.0 or newer.
- Dependencies: Apple frameworks only; no third-party packages.
- Freight data must be described as sightings with age and confidence, not verified live GPS.
- All feed access must cross `TrainProviding`, `RailInfrastructureProviding`, or `FreightSightingProviding`.

---

### Task 1: Portable domain and mock feed

**Files:**
- Create: `Package.swift`
- Create: `I Like Trains/Models/RailCoordinate.swift`
- Create: `I Like Trains/Models/Train.swift`
- Create: `I Like Trains/Models/RailSegment.swift`
- Create: `I Like Trains/Models/FreightSighting.swift`
- Create: `I Like Trains/Services/RailDataProviding.swift`
- Create: `I Like Trains/Services/MockRailDataService.swift`
- Test: `I Like TrainsTests/MockRailDataServiceTests.swift`

**Interfaces:**
- Produces: `TrainProviding.trains() async throws -> [Train]`, `RailInfrastructureProviding.railSegments() async throws -> [RailSegment]`, and `FreightSightingProviding.freightSightings() async throws -> [FreightSighting]`.

- [ ] **Step 1: Write tests for non-empty, uniquely identified, geographically valid fixtures and meaningful freshness/confidence metadata.**
- [ ] **Step 2: Run `swift test` and confirm it fails because the production types do not exist.**
- [ ] **Step 3: Implement immutable `Sendable`, `Codable`, `Identifiable`, and `Equatable` domain values plus deterministic mock providers.**
- [ ] **Step 4: Run `swift test` and confirm all portable data tests pass.**

### Task 2: View-model behavior

**Files:**
- Create: `I Like Trains/ViewModels/RailMapViewModel.swift`
- Test: `I Like TrainsTests/RailMapViewModelTests.swift`

**Interfaces:**
- Consumes: the three provider protocols from Task 1.
- Produces: `load()`, `refresh()`, `selectTrain(_:)`, `filteredTrains`, `visibleSegments`, `visibleSightings`, `searchQuery`, `selectedOperator`, and layer visibility state.

- [ ] **Step 1: Write tests proving load composition, search/operator filtering, layer visibility, selection, and preservation of prior snapshots after a refresh error.**
- [ ] **Step 2: Run the relevant tests and confirm expected failures for the missing view model.**
- [ ] **Step 3: Implement the minimal `@MainActor @Observable` state model with concurrent provider loading and injected dependencies.**
- [ ] **Step 4: Run all tests and keep the domain target free of MapKit/CoreLocation.**

### Task 3: Conventional iOS project and app shell

**Files:**
- Create: `I Like Trains.xcodeproj/project.pbxproj`
- Create: `I Like Trains/I_Like_TrainsApp.swift`
- Create: `I Like Trains/Resources/Assets.xcassets/**/Contents.json`
- Create: `I Like Trains/Resources/Preview Content/Preview Assets.xcassets/Contents.json`

**Interfaces:**
- Consumes: `RailMapViewModel` initialized with `MockRailDataService`.
- Produces: an iOS application target and unit-test target under shared scheme `I Like Trains`.

- [ ] **Step 1: Create the source/resource groups and target memberships with iOS 17 deployment settings.**
- [ ] **Step 2: Add the `@main` app entry point and inject the root view model.**
- [ ] **Step 3: Parse and audit the project graph for missing file references, duplicate object IDs, and absent target membership.**

### Task 4: Map experience and tactile components

**Files:**
- Create: `I Like Trains/Views/RailMapView.swift`
- Create: `I Like Trains/Views/Components/BrandBar.swift`
- Create: `I Like Trains/Views/Components/MapControls.swift`
- Create: `I Like Trains/Views/Components/TrainMarker.swift`
- Create: `I Like Trains/Views/Components/TrainDetailCard.swift`
- Create: `I Like Trains/Views/Components/PressableButtonStyle.swift`
- Create: `I Like Trains/Support/RailCoordinate+MapKit.swift`
- Create: `I Like Trains/Support/Theme.swift`

**Interfaces:**
- Consumes: observable properties and actions from `RailMapViewModel`.
- Produces: an edge-to-edge `Map`, polyline/annotation layers, camera animation, selection card, native search/filter sheets, tactile controls, and previews.

- [ ] **Step 1: Implement semantic theme tokens and a 44-point springy button style.**
- [ ] **Step 2: Render route geometry, station points, train annotations, and confidence-coded freight sightings with accessibility labels.**
- [ ] **Step 3: Add branded top chrome, layer menu, locate/refresh controls, animated selection, and train detail card.**
- [ ] **Step 4: Add search/filter sheets, loading/error/empty states, previews, haptics, Dynamic Type, and reduced-motion behavior.**

### Task 5: Documentation and static acceptance checks

**Files:**
- Create: `README.md`
- Create: `.gitignore`
- Create: `scripts/validate_project.py`

**Interfaces:**
- Produces: setup instructions, architecture map, real-feed integration plan, data caveats, and a repeatable non-Xcode structural validator.

- [ ] **Step 1: Document requirements, run/test commands, architecture, accessibility, data provenance, and adapter roadmap.**
- [ ] **Step 2: Implement a read-only validator for deployment target, placeholders, missing project references, target source membership, and forbidden package dependencies.**
- [ ] **Step 3: Run `python3 scripts/validate_project.py` and inspect `git diff --check`.**
- [ ] **Step 4: On macOS, run `xcodebuild test -project "I Like Trains.xcodeproj" -scheme "I Like Trains" -destination 'platform=iOS Simulator,name=iPhone 16 Pro'`; if unavailable, report that limitation exactly.**

### Task 6: Publish and review

**Files:**
- Modify: only files created in Tasks 1–5.

**Interfaces:**
- Produces: branch `agent/build-i-like-trains-mvp` and a draft pull request into `main`.

- [ ] **Step 1: Review the complete diff against every MVP requirement and fix Critical/Important findings.**
- [ ] **Step 2: Re-run the structural validator and whitespace audit from a clean snapshot.**
- [ ] **Step 3: Commit the complete scoped tree to the feature branch and create a draft PR summarizing behavior, validation evidence, and real-time integration gaps.**
