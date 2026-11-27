import Foundation

/// Where the Trains server lives. Info.plist key `TrainsServerURL` (set from TRAINS_SERVER_URL in project.yml),
/// overridable at runtime with the `serverURL` user default (Settings sheet).
struct AppConfig {
    var serverURL: URL
    /// Use the server's z/x/y tile endpoint instead of reading the PMTiles archive directly.
    var useXYZTiles: Bool

    static var current: AppConfig {
        let override = UserDefaults.standard.string(forKey: "serverURL").flatMap(URL.init(string:))
        let plist = (Bundle.main.object(forInfoDictionaryKey: "TrainsServerURL") as? String).flatMap(URL.init(string:))
        return AppConfig(serverURL: override ?? plist ?? URL(string: "http://localhost:8787")!,
                         useXYZTiles: UserDefaults.standard.object(forKey: "useXYZTiles") as? Bool ?? true)
    }

    var styleURL: URL {
        var c = URLComponents(url: serverURL.appendingPathComponent("style.json"), resolvingAgainstBaseURL: false)!
        if useXYZTiles { c.queryItems = [URLQueryItem(name: "tiles", value: "xyz")] }
        return c.url!
    }

    var liveURL: URL {
        var c = URLComponents(url: serverURL.appendingPathComponent("live"), resolvingAgainstBaseURL: false)!
        c.scheme = serverURL.scheme == "https" ? "wss" : "ws"
        return c.url!
    }
}
