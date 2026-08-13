import SwiftUI

@main
struct I_Like_TrainsApp: App {
    @State private var model: RailMapViewModel

    init() {
        let service = MockRailDataService()
        _model = State(initialValue: RailMapViewModel(
            trainProvider: service,
            infrastructureProvider: service,
            freightProvider: service
        ))
    }

    var body: some Scene {
        WindowGroup {
            RailMapView(model: model)
        }
    }
}
