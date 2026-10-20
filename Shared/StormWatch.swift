import Foundation
import UserNotifications

/// Storm alerts for where you are. Looks at the next hours of six weather centres' forecasts;
/// when at least 3 of them show a thunderstorm, it sends one alert with Axiom's storm sound.
/// Run by the Weather widget each time it refreshes, by the app when it opens, and by the app's background refresh.
enum StormWatch {
    static let models = ["ecmwf_ifs025", "gfs_seamless", "icon_seamless", "jma_seamless", "meteofrance_seamless", "ukmo_seamless"]
    static let need = 3                      // forecasts that must agree
    static let ahead: TimeInterval = 2.5 * 3600
    static let quiet: TimeInterval = 3 * 3600 // no second alert this soon
    static let sound = "axiom-storm.wav"

    struct Hit: Equatable {
        let at: Date      // the hour the storm is expected
        let agree: Int
        let of: Int
    }

    private struct State: Codable { var last: Double }
    private static var stateURL: URL? { Shared.container?.appendingPathComponent("axiom-storm.json") }

    private static let utc: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd'T'HH:mm"
        return f
    }()

    static func url(lat: Double, lon: Double) -> URL? {
        var c = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        c.queryItems = [
            URLQueryItem(name: "latitude", value: String(lat)),
            URLQueryItem(name: "longitude", value: String(lon)),
            URLQueryItem(name: "hourly", value: "weather_code"),
            URLQueryItem(name: "models", value: models.joined(separator: ",")),
            URLQueryItem(name: "timezone", value: "GMT"),
            URLQueryItem(name: "past_hours", value: "1"),
            URLQueryItem(name: "forecast_hours", value: "4")
        ]
        return c.url
    }

    /// The first hour from now (this hour included) within `ahead` where enough forecasts show a thunderstorm (codes 95–99).
    static func find(_ json: [String: Any], now: Date) -> Hit? {
        guard let h = json["hourly"] as? [String: Any], let times = h["time"] as? [String] else { return nil }
        let codes = models.map { h["weather_code_\($0)"] as? [Any] ?? [] }
        for (k, s) in times.enumerated() {
            guard let at = utc.date(from: s), at.addingTimeInterval(3600) > now, at < now.addingTimeInterval(ahead) else { continue }
            let vals = codes.compactMap { k < $0.count ? ($0[k] as? NSNumber)?.intValue : nil }
            let storm = vals.filter { $0 >= 95 }.count
            if vals.count >= 2 && storm >= need { return Hit(at: at, agree: storm, of: vals.count) }
        }
        return nil
    }

    /// In the air: between report and off-duty on a flight duty. No alerts then.
    static func flying(_ p: Payload, now: Date) -> Bool {
        let ms = now.timeIntervalSince1970 * 1000
        return p.duties.contains { $0.type == "FDP" && $0.rep <= ms && ms <= $0.off }
    }

    /// Where to watch: where you are if the phone knows (within a day), otherwise the first weather city.
    static func place(_ p: Payload, now: Date) -> (name: String, lat: Double, lon: Double, tz: String)? {
        if let h = Here.load(), now.timeIntervalSince1970 * 1000 - h.at < 24 * 3600e3 { return (h.name, h.lat, h.lon, h.tz) }
        if let c = p.wx?.cities.first(where: { $0.code != "HERE" }) { return (c.name, c.lat, c.lon, c.tz) }
        return nil
    }

    static func message(_ hit: Hit, name: String, tz: String, now: Date) -> (title: String, body: String) {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_GB")
        f.timeZone = TimeZone(identifier: tz) ?? .current
        f.dateFormat = "HH:mm"
        let when = hit.at <= now ? "now" : "around \(f.string(from: hit.at))"
        return ("⚡ Storm incoming · \(name)", "Thunderstorm likely \(when). \(hit.agree) of \(hit.of) forecasts agree.")
    }

    static func run(_ payload: Payload?, now: Date = Date()) async {
        guard let p = payload, p.notify?.storm == true, !p.demo, !flying(p, now: now) else { return }
        if let u = stateURL, let d = try? Data(contentsOf: u), let s = try? JSONDecoder().decode(State.self, from: d),
           now.timeIntervalSince1970 - s.last < quiet { return }
        let center = UNUserNotificationCenter.current()
        guard [UNAuthorizationStatus.authorized, .provisional, .ephemeral].contains(await center.notificationSettings().authorizationStatus),
              let where_ = place(p, now: now), let url = url(lat: where_.lat, lon: where_.lon) else { return }
        var req = URLRequest(url: url)
        req.timeoutInterval = 8
        guard let res = try? await URLSession.shared.data(for: req), (res.1 as? HTTPURLResponse)?.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: res.0) as? [String: Any],
              let hit = find(json, now: now) else { return }

        let m = message(hit, name: where_.name, tz: where_.tz, now: now)
        let c = UNMutableNotificationContent()
        c.title = m.title
        c.body = m.body
        c.sound = UNNotificationSound(named: UNNotificationSoundName(sound))
        c.threadIdentifier = "axiom.storm"
        c.interruptionLevel = .active   // a Sleep or other Focus keeps it quiet
        let id = "axiom.storm." + String(Int(hit.at.timeIntervalSince1970))
        try? await center.add(UNNotificationRequest(identifier: id, content: c, trigger: nil))
        if let u = stateURL, let d = try? JSONEncoder().encode(State(last: now.timeIntervalSince1970)) { try? d.write(to: u, options: .atomic) }
    }

    /// Notification sounds are looked for in the shared container too, so the widget's alerts find them as well.
    static func installSounds() {
        guard let dir = Shared.container?.appendingPathComponent("Library/Sounds") else { return }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        for name in [sound, "axiom-bip.wav"] {
            guard let src = Bundle.main.url(forResource: name, withExtension: nil) else { continue }
            let dst = dir.appendingPathComponent(name)
            try? FileManager.default.removeItem(at: dst)
            try? FileManager.default.copyItem(at: src, to: dst)
        }
    }
}
