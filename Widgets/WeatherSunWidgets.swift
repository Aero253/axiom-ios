import SwiftUI
import WidgetKit

// MARK: - Weather: the dashboard's cities, refreshed by the widget itself

struct WxEntry: TimelineEntry {
    let date: Date
    let wx: Weather?
    let demo: Bool
}

enum WMO {
    /// Open-Meteo weather codes to the dashboard's picture names and words.
    static func map(_ c: Int) -> (String, String) {
        if c <= 1 { return ("sun", c == 0 ? "Clear" : "Mainly clear") }
        if c == 2 { return ("partly", "Partly cloudy") }
        if c == 3 { return ("cloud", "Overcast") }
        if c <= 48 { return ("cloud", "Fog") }
        if c <= 57 { return ("rain", "Drizzle") }
        if c <= 67 { return ("rain", c >= 65 ? "Heavy rain" : "Rain") }
        if c <= 77 { return ("cloud", "Snow") }
        if c <= 82 { return ("rain", c == 82 ? "Violent showers" : "Rain showers") }
        if c <= 86 { return ("cloud", "Snow showers") }
        return ("storm", "Thunderstorm")
    }
}

struct WxProvider: TimelineProvider {
    func placeholder(in context: Context) -> WxEntry { WxEntry(date: Date(), wx: nil, demo: false) }

    func getSnapshot(in context: Context, completion: @escaping (WxEntry) -> Void) {
        completion(WxEntry(date: Date(), wx: Shared.loadWeather(), demo: Shared.load()?.demo ?? false))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<WxEntry>) -> Void) {
        Task { @MainActor in
            let saved = Shared.loadWeather()
            let payload = Shared.load()
            let demo = payload?.demo ?? false
            let next = Date().addingTimeInterval(45 * 60)
            // the cities set in Axiom (newest list from the dashboard), with where you are now in front
            var cities = (payload?.wx?.cities ?? saved?.cities ?? []).filter { $0.code != "HERE" }
            // where you are: a fix the phone already has, without waiting long (a slow widget gets no update at all)
            var here = await Here.refresh(timeout: 2)
            if let h = here, Date().timeIntervalSince1970 * 1000 - h.at > 24 * 3600e3 { here = nil }   // a day-old place is no use
            if let h = here { cities.insert(h.city, at: 0) }
            guard !cities.isEmpty else {
                completion(Timeline(entries: [WxEntry(date: Date(), wx: saved, demo: demo)], policy: .after(next)))
                return
            }
            fetch(cities) { fresh in
                let wx = fresh ?? saved
                if let f = fresh { Shared.saveWeather(f) }
                completion(Timeline(entries: [WxEntry(date: Date(), wx: wx, demo: demo)], policy: .after(next)))
            }
        }
    }

    /// Six forecasts for all the cities in one request, combined; the single best forecast if that fails.
    private func fetch(_ cities: [WxCity], done: @escaping (Weather?) -> Void) {
        let list = Array(cities.prefix(8))
        // six forecasts combined, and the usual single one beside it: its chance of rain (from many runs) and the fallback
        let g = DispatchGroup(), lock = NSLock()
        var mix: Weather?, one: Weather?
        g.enter(); WxMix.load(list, combined: true) { w in lock.lock(); mix = w; lock.unlock(); g.leave() }
        g.enter(); WxMix.load(list, combined: false) { w in lock.lock(); one = w; lock.unlock(); g.leave() }
        g.notify(queue: .global()) {
            guard var m = mix else { done(one); return }
            if let o = one {
                for i in m.cities.indices where i < o.cities.count {
                    for k in m.cities[i].daily.indices {
                        if let s = o.cities[i].daily.first(where: { $0.d == m.cities[i].daily[k].d }) { m.cities[i].daily[k].p = s.p }
                    }
                }
            }
            done(m)
        }
    }
}

/// Six weather centres' forecasts (Europe, USA, Germany, Japan, France, UK) made into the most likely one.
enum WxMix {
    static let models = ["ecmwf_ifs025", "gfs_seamless", "icon_seamless", "jma_seamless", "meteofrance_seamless", "ukmo_seamless"]

    static func url(_ list: [WxCity], combined: Bool) -> URL? {
        var c = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        var q = [
            URLQueryItem(name: "latitude", value: list.map { String($0.lat) }.joined(separator: ",")),
            URLQueryItem(name: "longitude", value: list.map { String($0.lon) }.joined(separator: ",")),
            URLQueryItem(name: "current", value: "temperature_2m,weather_code"),
            URLQueryItem(name: "timezone", value: "auto"),
            URLQueryItem(name: "forecast_days", value: "6")
        ]
        if combined {
            q.append(URLQueryItem(name: "models", value: models.joined(separator: ",")))
            q.append(URLQueryItem(name: "hourly", value: "temperature_2m,weather_code"))
            q.append(URLQueryItem(name: "past_hours", value: "1"))
            q.append(URLQueryItem(name: "forecast_hours", value: "2"))
            q.append(URLQueryItem(name: "daily", value: "weather_code,temperature_2m_max,temperature_2m_min,precipitation_sum"))
        } else {
            q.append(URLQueryItem(name: "daily", value: "weather_code,temperature_2m_max,temperature_2m_min,precipitation_probability_max"))
        }
        c.queryItems = q
        return c.url
    }

    static func load(_ list: [WxCity], combined: Bool, done: @escaping (Weather?) -> Void) {
        guard !list.isEmpty, let url = url(list, combined: combined) else { done(nil); return }
        var req = URLRequest(url: url)
        req.timeoutInterval = 8
        URLSession.shared.dataTask(with: req) { data, resp, _ in
            guard let data = data, (resp as? HTTPURLResponse)?.statusCode ?? 200 == 200 else { done(nil); return }
            done(parse(data, list, combined: combined))
        }.resume()
    }

    static func parse(_ data: Data, _ list: [WxCity], combined: Bool) -> Weather? {
        guard let json = try? JSONSerialization.jsonObject(with: data) else { return nil }
        let arr: [[String: Any]] = (json as? [[String: Any]]) ?? ((json as? [String: Any]).map { [$0] } ?? [])
        guard arr.count == list.count else { return nil }
        var out: [WxCity] = []
        for (i, x) in arr.enumerated() {
            var city = list[i]
            if combined {
                guard let m = mix(x) else { return nil }
                city.current = m.0; city.daily = m.1
            } else {
                single(x, into: &city)
            }
            out.append(city)
        }
        return Weather(updatedAt: ISO8601DateFormatter().string(from: Date()), cities: out)
    }

    private static func num(_ v: Any?) -> Double? { (v as? NSNumber)?.doubleValue }

    static func median(_ a: [Double?]) -> Double? {
        let v = a.compactMap { $0 }.filter { $0.isFinite }.sorted()
        guard !v.isEmpty else { return nil }
        return v.count % 2 == 1 ? v[v.count / 2] : (v[v.count / 2 - 1] + v[v.count / 2]) / 2
    }

    private static let sev = ["sun": 0, "partly": 1, "cloud": 2, "rain": 3, "storm": 4]

    /// The picture most forecasts show (a tie goes to the wetter one), with its most common wording.
    static func vote(_ codes: [Int?]) -> (String, String)? {
        let cs = codes.compactMap { $0 }
        guard !cs.isEmpty else { return nil }
        var n: [String: Int] = [:]
        for c in cs { n[WMO.map(c).0, default: 0] += 1 }
        guard let best = n.keys.sorted(by: { (n[$0]!, sev[$0] ?? 0) > (n[$1]!, sev[$1] ?? 0) }).first else { return nil }
        var m: [Int: Int] = [:]
        for c in cs where WMO.map(c).0 == best { m[c, default: 0] += 1 }
        let code = m.keys.sorted(by: { (m[$0]!, $0) > (m[$1]!, $1) }).first!
        return WMO.map(code)
    }

    static func mix(_ x: [String: Any]) -> (WxNow, [WxDay])? {
        // "now" from each forecast: its hour closest to the current time
        let cur = x["current"] as? [String: Any] ?? [:], hr = x["hourly"] as? [String: Any] ?? [:]
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.timeZone = TimeZone(identifier: "UTC"); f.dateFormat = "yyyy-MM-dd'T'HH:mm"
        let times = (hr["time"] as? [String] ?? []).map { f.date(from: $0) }
        let ref = (cur["time"] as? String).flatMap { f.date(from: $0) } ?? times.compactMap { $0 }.first ?? Date()
        let k0 = times.indices.min(by: { abs(times[$0]?.timeIntervalSince(ref) ?? .infinity) < abs(times[$1]?.timeIntervalSince(ref) ?? .infinity) })
        func now(_ v: String) -> [Double?] { models.map { m in guard let k = k0, let a = hr["\(v)_\(m)"] as? [Any], k < a.count else { return nil }; return num(a[k]) } }
        let ts = now("temperature_2m")
        let cc = now("weather_code").map { $0.map { Int($0) } }
        let have = models.indices.filter { ts[$0] != nil && cc[$0] != nil }
        guard have.count >= 2, let t = median(have.map { ts[$0] }), let now = vote(have.map { cc[$0] }) else { return nil }
        guard let d = x["daily"] as? [String: Any], let days = d["time"] as? [String] else { return nil }
        func per(_ v: String) -> [[Any]] { models.map { d["\(v)_\($0)"] as? [Any] ?? [] } }
        let hi = per("temperature_2m_max"), lo = per("temperature_2m_min"), pr = per("precipitation_sum"), wc = per("weather_code")
        func at(_ a: [[Any]], _ k: Int) -> [Double?] { a.map { k < $0.count ? num($0[k]) : nil } }
        let daily: [WxDay] = days.enumerated().compactMap { k, day in
            guard let h = median(at(hi, k)), let l = median(at(lo, k)), let v = vote(at(wc, k).map { $0.map { Int($0) } }) else { return nil }
            let ps = at(pr, k).compactMap { $0 }
            let p = ps.isEmpty ? 0 : (100 * Double(ps.filter { $0 >= 1 }.count) / Double(ps.count)).rounded()
            return WxDay(d: day, hi: h, lo: l, p: p, cond: v.0)
        }
        return (WxNow(t: t, cond: now.0, text: now.1), daily)
    }

    static func single(_ x: [String: Any], into city: inout WxCity) {
        if let cur = x["current"] as? [String: Any], let t = num(cur["temperature_2m"]) {
            let m = WMO.map(Int(num(cur["weather_code"]) ?? 3))
            city.current = WxNow(t: t, cond: m.0, text: m.1)
        }
        if let d = x["daily"] as? [String: Any], let days = d["time"] as? [String] {
            let hi = d["temperature_2m_max"] as? [Any] ?? [], lo = d["temperature_2m_min"] as? [Any] ?? []
            let pp = d["precipitation_probability_max"] as? [Any] ?? [], wc = d["weather_code"] as? [Any] ?? []
            city.daily = days.enumerated().map { k, day in
                let n: ([Any], Int) -> Double = { a, j in j < a.count ? (num(a[j]) ?? 0) : 0 }
                return WxDay(d: day, hi: n(hi, k), lo: n(lo, k), p: n(pp, k), cond: WMO.map(Int(n(wc, k))).0)
            }
        }
    }
}

struct WeatherView: View {
    @Environment(\.widgetFamily) var envFamily
    var forcedFamily: WidgetFamily? = nil
    private var family: WidgetFamily { forcedFamily ?? envFamily }
    let entry: WxEntry

    var body: some View {
        if let wx = entry.wx, let first = wx.cities.first {
            switch family {
            case .systemMedium: medium(first)
            case .systemLarge: large(wx)
            default: small(first)
            }
        } else {
            OpenAxiomNote(title: "Weather")
        }
    }

    /// The reading from the last few hours; an old one would show weather that's long gone.
    private func now(_ c: WxCity) -> WxNow? { entry.wx?.fresh(at: entry.date) == true ? c.current : nil }

    private func temp(_ c: WxCity) -> String {
        guard let t = now(c)?.t ?? today(c)?.hi else { return "—" }
        return "\(Int(t.rounded()))°"
    }

    private func today(_ c: WxCity) -> WxDay? {
        let t = Shared.todayISO(entry.date)
        return c.daily.first(where: { $0.d >= t })
    }

    private func small(_ c: WxCity) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                if c.code == "HERE" {
                    Image(systemName: "mappin.and.ellipse").font(.system(size: 9, weight: .bold)).foregroundStyle(.secondary)
                    Caption(text: c.name)   // the district; the large widget also shows the province
                } else {
                    Caption(text: "\(c.code) · \(c.name)")
                }
                Spacer(minLength: 0)
            }
            Spacer(minLength: 0)
            HStack(alignment: .center, spacing: 8) {
                WxDots(cond: now(c)?.cond ?? today(c)?.cond ?? "cloud", size: 40)
                DotText(text: temp(c), height: 26)
            }
            Spacer(minLength: 0)
            Text(now(c)?.text ?? (today(c) == nil ? "" : "Today's high")).font(Ax.mono(11, .semibold)).lineLimit(1).minimumScaleFactor(0.7)
            if let d = today(c) {
                HStack(spacing: 0) {
                    Caption(text: "H \(Int(d.hi.rounded()))° L \(Int(d.lo.rounded()))° · ")
                    Caption(text: "rain \(Int(d.p))%", color: d.p >= 30 ? Ax.rain : .secondary)
                }
            }
        }
    }

    private func medium(_ c: WxCity) -> some View {
        HStack(spacing: 12) {
            small(c).frame(width: 128, alignment: .leading)
            HStack(spacing: 4) {
                ForEach(c.daily.filter { $0.d >= Shared.todayISO(entry.date) }.prefix(5), id: \.self) { d in
                    VStack(spacing: 4) {
                        Text(dayParts(d.d).0.prefix(2)).font(Ax.mono(9, .bold)).foregroundStyle(.secondary)
                        WxDots(cond: d.cond, size: 22)
                        Text("\(Int(d.hi.rounded()))°").font(Ax.mono(12, .bold))
                        Text("\(Int(d.lo.rounded()))°").font(Ax.mono(10)).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
    }

    private func large(_ wx: Weather) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Caption(text: "Weather · your cities")
                Spacer(minLength: 0)
            }
            ForEach(wx.cities.prefix(6), id: \.self) { c in
                HStack(spacing: 10) {
                    WxDots(cond: now(c)?.cond ?? today(c)?.cond ?? "cloud", size: 26)
                    VStack(alignment: .leading, spacing: 0) {
                        if c.code == "HERE" {   // where you are: the town's name, with a pin
                            Text(c.name).font(Ax.mono(13, .bold)).lineLimit(1).minimumScaleFactor(0.7)
                            Label(c.sub ?? "Your location", systemImage: "mappin.and.ellipse").font(Ax.mono(10)).foregroundStyle(.secondary).labelStyle(.titleAndIcon).lineLimit(1)
                        } else {
                            Text(c.code).font(Ax.mono(13, .bold))
                            Text(c.name).font(Ax.mono(10)).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }
                    Spacer(minLength: 0)
                    if let d = today(c) {
                        Text("rain \(Int(d.p))%").font(Ax.mono(10)).foregroundStyle(d.p >= 30 ? Ax.rain : .secondary)
                    }
                    Text(temp(c)).font(Ax.mono(20, .bold)).frame(width: 52, alignment: .trailing)
                }
            }
            Spacer(minLength: 0)
        }
    }
}

struct WeatherWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "AxiomWeather", provider: WxProvider()) { e in
            WeatherView(entry: e).axiomBackground()
        }
        .configurationDisplayName("Weather")
        .description("The weather where you are, then your base and roster cities, in dot pictures. Updates by itself every 45 minutes or so.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

// MARK: - Sun: sunrise and sunset in local time

struct SunView: View {
    @Environment(\.widgetFamily) var envFamily
    var forcedFamily: WidgetFamily? = nil
    private var family: WidgetFamily { forcedFamily ?? envFamily }
    let entry: PayloadEntry

    var body: some View {
        if let cities = entry.payload?.sun, let first = cities.first {
            if family == .systemMedium {
                VStack(alignment: .leading, spacing: 7) {
                    Caption(text: "Sun · local time")
                    ForEach(cities.prefix(4), id: \.self) { c in
                        let d = day(c)
                        HStack(spacing: 8) {
                            Text(c.code).font(Ax.mono(13, .bold)).frame(width: 40, alignment: .leading)
                            Text(c.name).font(Ax.mono(10)).foregroundStyle(.secondary).lineLimit(1)
                            Spacer(minLength: 0)
                            Text("↑ \(TimeFmt.hm(ms: d?.rise, c.tz))").font(Ax.mono(12, .bold))
                            Text("↓ \(TimeFmt.hm(ms: d?.set, c.tz))").font(Ax.mono(12, .bold))
                        }
                    }
                    Spacer(minLength: 0)
                }
            } else {
                small(first)
            }
        } else {
            OpenAxiomNote(title: "Sun")
        }
    }

    private func day(_ c: SunCity) -> SunDay? {
        let t = Shared.todayISO(entry.date)
        return c.days.first(where: { $0.d == t }) ?? c.days.first
    }

    private func small(_ c: SunCity) -> some View {
        let d = day(c)
        let ms: Double = entry.date.timeIntervalSince1970 * 1000
        let rise: Double = d?.rise ?? 0
        let set: Double = d?.set ?? 0
        let up: Bool = rise <= ms && ms < set
        let daylight: Double = (set - rise) / 3_600_000
        let frac: Double = up ? (ms - rise) / max(1, set - rise) : 0
        return VStack(alignment: .leading, spacing: 5) {
            Caption(text: "Sun · \(c.code)")
            // the sun's path as an arc of dots, lit up to where it is now
            ZStack {
                SunArc(upTo: up ? frac : -1, lit: false).fill(Ax.ink.opacity(0.18))
                SunArc(upTo: up ? frac : -1, lit: true).fill(Ax.yellow)
            }
            .frame(height: 38)
            HStack {
                VStack(alignment: .leading, spacing: 0) {
                    Caption(text: "Rise")
                    Text(TimeFmt.hm(ms: d?.rise, c.tz)).font(Ax.mono(16, .bold))
                }
                Spacer(minLength: 0)
                VStack(alignment: .trailing, spacing: 0) {
                    Caption(text: "Set")
                    Text(TimeFmt.hm(ms: d?.set, c.tz)).font(Ax.mono(16, .bold))
                }
            }
            Caption(text: "\(TimeFmt.hours(daylight)) daylight")
        }
    }
}

/// Thirteen dots on a half-circle from sunrise to sunset; `lit` draws only the ones the sun has passed.
struct SunArc: Shape {
    let upTo: Double
    let lit: Bool

    func path(in rect: CGRect) -> Path {
        var p = Path()
        let n = 13
        let w = Double(rect.width), h = Double(rect.height)
        for i in 0..<n {
            let t = Double(i) / Double(n - 1)
            if (t <= upTo) != lit { continue }
            let a = Double.pi * t
            let x = w / 2 - cos(a) * (w / 2 - 6)
            let y = h - sin(a) * (h - 6) - 3
            p.addEllipse(in: CGRect(x: Double(rect.minX) + x - 2.5, y: Double(rect.minY) + y - 2.5, width: 5, height: 5))
        }
        return p
    }
}

struct SunWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "AxiomSun", provider: PayloadProvider(stepMinutes: 15, count: 16)) { e in
            SunView(entry: e).axiomBackground()
        }
        .configurationDisplayName("Sun")
        .description("Sunrise and sunset in local time for your base and roster cities, with the sun's path in dots.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
