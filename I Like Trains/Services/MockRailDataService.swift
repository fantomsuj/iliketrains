import Foundation

public struct MockRailDataService: TrainProviding, RailInfrastructureProviding, FreightSightingProviding {
    private let referenceDate: Date
    private let shouldFail: Bool

    public init(referenceDate: Date = .now, shouldFail: Bool = false) {
        self.referenceDate = referenceDate
        self.shouldFail = shouldFail
    }

    public func trains() async throws -> [Train] {
        try checkAvailability()
        return [
            train("amtrak-6", "6", "California Zephyr", .amtrak, "Emeryville", "Chicago",
                  39.7420, -104.9915, 72, 68, 12, "Fort Morgan", "FMG", 31, 2, .delayed),
            train("amtrak-171", "171", "Northeast Regional", .amtrak, "Boston", "Roanoke",
                  39.2904, -76.6122, 214, 74, 0, "BWI Airport", "BWI", 14, 1, .onTime),
            train("brightline-50", "50", "Brightline", .brightline, "Miami", "Orlando",
                  26.3683, -80.1289, 355, 79, -3, "Boca Raton", "BOC", 8, 1, .early),
            train("amtrak-774", "774", "Pacific Surfliner", .amtrak, "San Diego", "Goleta",
                  33.4269, -117.6119, 305, 51, 0, "San Juan Capistrano", "SNC", 11, 3, .onTime),
            train("amtrak-8", "8", "Empire Builder", .amtrak, "Seattle", "Chicago",
                  48.4106, -114.3353, 98, 62, 24, "Whitefish", "WFH", 18, 4, .delayed),
            train("amtrak-14", "14", "Coast Starlight", .amtrak, "Los Angeles", "Seattle",
                  37.8044, -122.2712, 340, 34, 0, "Emeryville", "EMY", 7, 1, .stopped),
            train("metrolink-708", "708", "Antelope Valley Line", .metrolink, "Los Angeles", "Lancaster",
                  34.2413, -118.5282, 326, 55, 4, "Chatsworth", "CWT", 6, 2, .delayed)
        ]
    }

    public func railSegments() async throws -> [RailSegment] {
        try checkAvailability()
        return [
            RailSegment(
                id: "northeast-corridor",
                name: "Northeast Corridor",
                railOperator: .amtrak,
                kind: .intercity,
                coordinates: coordinates([
                    (42.3601, -71.0589), (41.3083, -72.9279), (40.7128, -74.0060),
                    (39.9526, -75.1652), (39.2904, -76.6122), (38.9072, -77.0369)
                ]),
                stations: [
                    station("BOS", "South Station", "Boston", 42.3519, -71.0552),
                    station("NYP", "Moynihan Train Hall", "New York", 40.7506, -73.9935),
                    station("PHL", "William H. Gray III 30th St", "Philadelphia", 39.9557, -75.1820),
                    station("WAS", "Union Station", "Washington", 38.8971, -77.0064)
                ],
                trafficDensity: 95,
                electrified: true
            ),
            RailSegment(
                id: "california-zephyr",
                name: "California Zephyr",
                railOperator: .amtrak,
                kind: .intercity,
                coordinates: coordinates([
                    (37.7949, -122.2822), (39.5296, -119.8138), (40.7608, -111.8910),
                    (39.7392, -104.9903), (41.2565, -95.9345), (41.8781, -87.6298)
                ]),
                stations: [
                    station("EMY", "Emeryville", "Emeryville", 37.8405, -122.2917),
                    station("DEN", "Union Station", "Denver", 39.7527, -105.0008),
                    station("CHI", "Union Station", "Chicago", 41.8787, -87.6403)
                ],
                trafficDensity: 44,
                electrified: false
            ),
            RailSegment(
                id: "brightline-florida",
                name: "Brightline Florida",
                railOperator: .brightline,
                kind: .intercity,
                coordinates: coordinates([
                    (25.7617, -80.1918), (26.1224, -80.1373), (26.3683, -80.1289),
                    (26.7153, -80.0534), (27.2730, -80.3582), (28.4312, -81.3081)
                ]),
                stations: [
                    station("MIA", "MiamiCentral", "Miami", 25.7797, -80.1957),
                    station("WPB", "West Palm Beach", "West Palm Beach", 26.7126, -80.0560),
                    station("MCO", "Orlando Airport", "Orlando", 28.4312, -81.3081)
                ],
                trafficDensity: 62,
                electrified: false
            ),
            RailSegment(
                id: "bnsf-southern-transcon",
                name: "Southern Transcon",
                railOperator: .bnsf,
                kind: .freightMainline,
                coordinates: coordinates([
                    (34.8958, -117.0173), (34.4264, -117.3106), (35.1983, -111.6513),
                    (35.0844, -106.6504), (35.4676, -97.5164), (39.0997, -94.5786), (41.8781, -87.6298)
                ]),
                stations: [],
                trafficDensity: 88,
                electrified: false
            ),
            RailSegment(
                id: "up-sunset-route",
                name: "Sunset Route",
                railOperator: .unionPacific,
                kind: .freightMainline,
                coordinates: coordinates([
                    (34.0522, -118.2437), (33.4484, -112.0740), (32.2226, -110.9747),
                    (31.7619, -106.4850), (29.4241, -98.4936), (29.7604, -95.3698), (29.9511, -90.0715)
                ]),
                stations: [],
                trafficDensity: 79,
                electrified: false
            ),
            RailSegment(
                id: "pacific-surfliner",
                name: "LOSSAN Corridor",
                railOperator: .amtrak,
                kind: .intercity,
                coordinates: coordinates([
                    (32.7157, -117.1611), (33.1959, -117.3795), (33.5019, -117.6628),
                    (33.7701, -118.1937), (34.0522, -118.2437), (34.4208, -119.6982)
                ]),
                stations: [
                    station("SAN", "Santa Fe Depot", "San Diego", 32.7162, -117.1696),
                    station("LAX", "Union Station", "Los Angeles", 34.0562, -118.2365)
                ],
                trafficDensity: 70,
                electrified: false
            )
        ]
    }

    public func freightSightings() async throws -> [FreightSighting] {
        try checkAvailability()
        return [
            sighting("bnsf-cajon", .bnsf, 34.3117, -117.4665, "Westbound", "Double-stack intermodal", 0.91, 8, 4),
            sighting("up-maricopa", .unionPacific, 33.0581, -112.0476, "Eastbound", "Manifest freight", 0.76, 19, 2),
            sighting("ns-horseshoe", .norfolkSouthern, 40.4976, -78.4845, "Climbing west", "Mixed freight with helpers", 0.84, 13, 3),
            sighting("csx-selkirk", .csx, 42.5295, -73.8129, "Southbound", "Autorack train", 0.67, 27, 1),
            sighting("cpkc-la-plata", .canadianPacificKansasCity, 40.0234, -92.4910, "Eastbound", "Intermodal", 0.72, 22, 2)
        ]
    }

    private func checkAvailability() throws {
        if shouldFail { throw RailDataError.unavailable }
    }

    private func train(
        _ id: String, _ number: String, _ name: String, _ railOperator: RailOperator,
        _ origin: String, _ destination: String, _ latitude: Double, _ longitude: Double,
        _ heading: Double, _ speed: Int, _ delay: Int, _ nextStop: String, _ nextStopCode: String,
        _ etaMinutes: TimeInterval, _ updatedMinutesAgo: TimeInterval, _ status: Train.Status
    ) -> Train {
        Train(
            id: id,
            number: number,
            name: name,
            railOperator: railOperator,
            origin: origin,
            destination: destination,
            coordinate: .init(latitude: latitude, longitude: longitude),
            heading: heading,
            speedMPH: speed,
            delayMinutes: delay,
            nextStop: nextStop,
            nextStopCode: nextStopCode,
            nextStopETA: referenceDate.addingTimeInterval(etaMinutes * 60),
            updatedAt: referenceDate.addingTimeInterval(-updatedMinutesAgo * 60),
            status: status
        )
    }

    private func sighting(
        _ id: String, _ railOperator: RailOperator, _ latitude: Double, _ longitude: Double,
        _ direction: String, _ equipment: String, _ confidence: Double,
        _ minutesAgo: TimeInterval, _ reporterCount: Int
    ) -> FreightSighting {
        FreightSighting(
            id: id,
            railOperator: railOperator,
            coordinate: .init(latitude: latitude, longitude: longitude),
            direction: direction,
            equipment: equipment,
            confidence: confidence,
            observedAt: referenceDate.addingTimeInterval(-minutesAgo * 60),
            reporterCount: reporterCount
        )
    }

    private func station(
        _ code: String, _ name: String, _ city: String, _ latitude: Double, _ longitude: Double
    ) -> RailStation {
        RailStation(
            code: code,
            name: name,
            city: city,
            coordinate: .init(latitude: latitude, longitude: longitude)
        )
    }

    private func coordinates(_ values: [(Double, Double)]) -> [RailCoordinate] {
        values.map { RailCoordinate(latitude: $0.0, longitude: $0.1) }
    }
}
