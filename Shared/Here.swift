import Foundation
import CoreLocation

/// Where the phone is, roughly (to the town), for the weather. Kept in the shared storage so the app and the widget agree.
struct HerePlace: Codable, Equatable {
    var lat: Double
    var lon: Double
    var name: String          // the district (Lak Si, Mueang Chiang Mai), or the town
    var tz: String
    var at: Double            // when it was found, ms since 1970
    var province: String? = nil

    var city: WxCity { WxCity(code: "HERE", name: name, lat: lat, lon: lon, tz: tz, current: nil, daily: [], sub: province) }
}

enum Here {
    private static var url: URL? { Shared.container?.appendingPathComponent("axiom-here.json") }

    static func load() -> HerePlace? {
        guard let url = url, let d = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(HerePlace.self, from: d)
    }

    static func save(_ h: HerePlace) {
        guard let url = url, let d = try? JSONEncoder().encode(h) else { return }
        try? d.write(to: url, options: .atomic)
    }

    /// Location is allowed: in the app ("While Using"), or for the widgets.
    static var allowed: Bool {
        let m = CLLocationManager()
        switch m.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse: return true
        default: return false
        }
    }

    /// District and province in English, without the "Khet" / "Amphoe" / "Chang Wat" words: ("Lak Si", "Bangkok").
    static func names(_ pm: CLPlacemark) -> (String?, String?) {
        func clean(_ s: String?) -> String? {
            guard var t = s?.trimmingCharacters(in: .whitespaces), !t.isEmpty else { return nil }
            for p in ["Khet ", "Amphoe ", "Chang Wat ", "Changwat "] where t.hasPrefix(p) { t.removeFirst(p.count) }
            for x in [" District", " Province"] where t.hasSuffix(x) { t.removeLast(x.count) }
            if t == "Krung Thep Maha Nakhon" || t == "Bangkok Metropolis" { t = "Bangkok" }
            return t
        }
        let district = clean(pm.subAdministrativeArea) ?? clean(pm.locality) ?? clean(pm.subLocality)
        var province = clean(pm.administrativeArea)
        if province == district { province = nil }
        return (district ?? province ?? clean(pm.name), district == nil ? nil : province)
    }

    /// Find the phone once (town-level accuracy, a few seconds at most), name the place, and keep it.
    @MainActor
    static func refresh(timeout: TimeInterval = 8) async -> HerePlace? {
        guard let loc = await OneShot().locate(timeout: timeout) else { return load() }
        // the same place as last time (within 3 km): keep its names and skip the lookup
        let old = load().flatMap { o in CLLocation(latitude: o.lat, longitude: o.lon).distance(from: loc) < 3000 && o.province != nil ? o : nil }
        var name = old?.name, province = old?.province
        var tz = old?.tz ?? TimeZone.current.identifier
        if old == nil, let pm = try? await CLGeocoder().reverseGeocodeLocation(loc, preferredLocale: Locale(identifier: "en_US")).first {
            (name, province) = names(pm)
            if let z = pm.timeZone { tz = z.identifier }
        }
        let h = HerePlace(lat: (loc.coordinate.latitude * 100).rounded() / 100,       // about 1 km: enough for weather
                          lon: (loc.coordinate.longitude * 100).rounded() / 100,
                          name: name ?? "Here", tz: tz, at: Date().timeIntervalSince1970 * 1000, province: province)
        save(h)
        return h
    }
}

/// One location fix, then stop. Never keeps GPS running.
@MainActor
private final class OneShot: NSObject, CLLocationManagerDelegate {
    private let m = CLLocationManager()
    private var done: ((CLLocation?) -> Void)?

    func locate(timeout: TimeInterval) async -> CLLocation? {
        let st = m.authorizationStatus
        let widgetOK: Bool = Bundle.main.bundleURL.pathExtension == "appex" ? m.isAuthorizedForWidgetUpdates : true
        guard (st == .authorizedWhenInUse || st == .authorizedAlways) && widgetOK else { return nil }
        if let last = m.location, -last.timestamp.timeIntervalSinceNow < 10 * 60 { return last }   // a recent fix is good enough
        return await withCheckedContinuation { (c: CheckedContinuation<CLLocation?, Never>) in
            var finished = false
            done = { loc in
                guard !finished else { return }
                finished = true
                c.resume(returning: loc)
            }
            m.delegate = self
            m.desiredAccuracy = kCLLocationAccuracyKilometer
            m.requestLocation()
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                self.done?(self.m.location)   // out of time: use whatever the phone last knew
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let loc = locations.last
        Task { @MainActor in self.done?(loc) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in self.done?(nil) }
    }
}
