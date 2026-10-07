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
        let saved = Shared.loadWeather()
        let demo = Shared.load()?.demo ?? false
        let next = Date().addingTimeInterval(45 * 60)
        guard let cities = saved?.cities, !cities.isEmpty else {
            completion(Timeline(entries: [WxEntry(date: Date(), wx: saved, demo: demo)], policy: .after(next)))
            return
        }
        fetch(cities) { fresh in
            let wx = fresh ?? saved
            if let f = fresh { Shared.saveWeather(f) }
            completion(Timeline(entries: [WxEntry(date: Date(), wx: wx, demo: demo)], policy: .after(next)))
        }
    }

    /// One Open-Meteo request for all the cities; keeps the saved forecast if there's no signal.
    private func fetch(_ cities: [WxCity], done: @escaping (Weather?) -> Void) {
        let list = Array(cities.prefix(8))
        var c = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        c.queryItems = [
            URLQueryItem(name: "latitude", value: list.map { String($0.lat) }.joined(separator: ",")),
            URLQueryItem(name: "longitude", value: list.map { String($0.lon) }.joined(separator: ",")),
            URLQueryItem(name: "current", value: "temperature_2m,weather_code"),
            URLQueryItem(name: "daily", value: "weather_code,temperature_2m_max,temperature_2m_min,precipitation_probability_max"),
            URLQueryItem(name: "timezone", value: "auto"),
            URLQueryItem(name: "forecast_days", value: "6")
        ]
        guard let url = c.url else { done(nil); return }
        var req = URLRequest(url: url)
        req.timeoutInterval = 12
        URLSession.shared.dataTask(with: req) { data, _, _ in
            guard let data = data, let json = try? JSONSerialization.jsonObject(with: data) else { done(nil); return }
            let arr: [[String: Any]] = (json as? [[String: Any]]) ?? ((json as? [String: Any]).map { [$0] } ?? [])
            guard arr.count == list.count else { done(nil); return }
            var out: [WxCity] = []
            for (i, x) in arr.enumerated() {
                var city = list[i]
                if let cur = x["current"] as? [String: Any], let t = (cur["temperature_2m"] as? NSNumber)?.doubleValue {
                    let code = (cur["weather_code"] as? NSNumber)?.intValue ?? 3
                    let m = WMO.map(code)
                    city.current = WxNow(t: t, cond: m.0, text: m.1)
                }
                if let d = x["daily"] as? [String: Any], let days = d["time"] as? [String] {
                    let hi = d["temperature_2m_max"] as? [Any] ?? [], lo = d["temperature_2m_min"] as? [Any] ?? []
                    let pp = d["precipitation_probability_max"] as? [Any] ?? [], wc = d["weather_code"] as? [Any] ?? []
                    city.daily = days.enumerated().map { k, day in
                        let num: ([Any], Int) -> Double = { a, j in j < a.count ? ((a[j] as? NSNumber)?.doubleValue ?? 0) : 0 }
                        return WxDay(d: day, hi: num(hi, k), lo: num(lo, k), p: num(pp, k), cond: WMO.map(Int(num(wc, k))).0)
                    }
                }
                out.append(city)
            }
            let iso = ISO8601DateFormatter().string(from: Date())
            done(Weather(updatedAt: iso, cities: out))
        }.resume()
    }
}

struct WeatherView: View {
    @Environment(\.widgetFamily) private var family
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

    private func today(_ c: WxCity) -> WxDay? {
        let t = Shared.todayISO(entry.date)
        return c.daily.first(where: { $0.d >= t })
    }

    private func small(_ c: WxCity) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Caption(text: "\(c.code) · \(c.name)")
                Spacer(minLength: 0)
            }
            Spacer(minLength: 0)
            HStack(alignment: .center, spacing: 8) {
                WxDots(cond: c.current?.cond ?? today(c)?.cond ?? "cloud", size: 40)
                DotText(text: "\(Int((c.current?.t ?? today(c)?.hi ?? 0).rounded()))°", height: 26)
            }
            Spacer(minLength: 0)
            Text(c.current?.text ?? "").font(Ax.mono(11, .semibold)).lineLimit(1).minimumScaleFactor(0.7)
            if let d = today(c) {
                Caption(text: "H \(Int(d.hi.rounded()))° L \(Int(d.lo.rounded()))° · rain \(Int(d.p))%")
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
                    WxDots(cond: c.current?.cond ?? today(c)?.cond ?? "cloud", size: 26)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(c.code).font(Ax.mono(13, .bold))
                        Text(c.name).font(Ax.mono(10)).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    if let d = today(c) {
                        Text("rain \(Int(d.p))%").font(Ax.mono(10)).foregroundStyle(.secondary)
                    }
                    Text("\(Int((c.current?.t ?? today(c)?.hi ?? 0).rounded()))°").font(Ax.mono(20, .bold)).frame(width: 52, alignment: .trailing)
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
        .description("Your base and roster cities in dot pictures. Updates by itself every 45 minutes or so.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

// MARK: - Sun: sunrise and sunset in local time

struct SunView: View {
    @Environment(\.widgetFamily) private var family
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
