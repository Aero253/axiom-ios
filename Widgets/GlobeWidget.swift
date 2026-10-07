import SwiftUI
import WidgetKit

// MARK: - The dashboard's dot-matrix globe, with your next route drawn in red

private final class LandBundleToken {}

/// Natural Earth land at 0.5° (public domain), the same bitmap the dashboard uses: 720 × 360 cells, one bit each.
enum LandMask {
    static let bits: [UInt8] = {
        guard let url = Bundle(for: LandBundleToken.self).url(forResource: "land05", withExtension: "dat"),
              let d = try? Data(contentsOf: url) else { return [] }
        return [UInt8](d)
    }()

    static func isLand(_ lat: Double, _ lon: Double) -> Bool {
        guard bits.count == 32400 else { return false }
        var lo = lon
        while lo < -180 { lo += 360 }
        while lo >= 180 { lo -= 360 }
        let r = min(359, max(0, Int(floor((90 - lat) / 0.5))))
        let c = min(719, max(0, Int(floor((lo + 180) / 0.5))))
        let i = r * 720 + c
        return (bits[i >> 3] >> (7 - (i & 7))) & 1 == 1
    }
}

/// Orthographic view of the globe: centre, radius and zoom on a given box.
struct Ortho {
    let lat0: Double
    let lon0: Double
    let radius: Double
    let cx: Double
    let cy: Double

    init(center: (Double, Double), stops: [(Double, Double)], in rect: CGRect) {
        lat0 = center.0 * .pi / 180
        lon0 = center.1 * .pi / 180
        cx = Double(rect.midX)
        cy = Double(rect.midY)
        let half = Double(min(rect.width, rect.height)) / 2
        let base = half - 3
        // zoom in until the route fills about 80% of the box (domestic hops are tiny on a whole globe)
        var maxAng = 0.0
        for s in stops {
            let la = s.0 * .pi / 180, lo = s.1 * .pi / 180
            let cosc = sin(lat0) * sin(la) + cos(lat0) * cos(la) * cos(lo - lon0)
            maxAng = max(maxAng, acos(max(-1, min(1, cosc))))
        }
        let want = maxAng > 0.001 ? (half * 0.78) / sin(min(maxAng, .pi / 2)) : base * 2.6
        radius = min(base * 9, max(base, want))
    }

    func project(_ latDeg: Double, _ lonDeg: Double) -> CGPoint? {
        let la = latDeg * .pi / 180, lo = lonDeg * .pi / 180
        let cosc = sin(lat0) * sin(la) + cos(lat0) * cos(la) * cos(lo - lon0)
        guard cosc > 0 else { return nil }
        let x = cos(la) * sin(lo - lon0)
        let y = cos(lat0) * sin(la) - sin(lat0) * cos(la) * cos(lo - lon0)
        return CGPoint(x: cx + radius * x, y: cy - radius * y)
    }

    func unproject(_ px: Double, _ py: Double) -> (Double, Double)? {
        let X = (px - cx) / radius, Y = (cy - py) / radius
        let rho = sqrt(X * X + Y * Y)
        guard rho <= 1 else { return nil }
        if rho < 1e-9 { return (lat0 * 180 / .pi, lon0 * 180 / .pi) }
        let c = asin(rho)
        let lat = asin(cos(c) * sin(lat0) + Y * sin(c) * cos(lat0) / rho)
        let lon = lon0 + atan2(X * sin(c), rho * cos(lat0) * cos(c) - Y * sin(lat0) * sin(c))
        return (lat * 180 / .pi, lon * 180 / .pi)
    }
}

/// The globe as a screen-space dot grid: every dot is land or sea, so it reads as a dot-matrix picture.
struct GlobeDots: Shape {
    let center: (Double, Double)
    let stops: [(Double, Double)]
    let land: Bool
    var step: CGFloat = 4

    func path(in rect: CGRect) -> Path {
        let o = Ortho(center: center, stops: stops, in: rect)
        var p = Path()
        let r = land ? step * 0.36 : step * 0.18
        var y = rect.minY + step / 2
        while y < rect.maxY {
            var x = rect.minX + step / 2
            while x < rect.maxX {
                if let ll = o.unproject(Double(x), Double(y)), LandMask.isLand(ll.0, ll.1) == land {
                    p.addEllipse(in: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2))
                }
                x += step
            }
            y += step
        }
        return p
    }
}

/// Great-circle legs between the stops.
struct GlobeRoute: Shape {
    let center: (Double, Double)
    let stops: [(Double, Double)]

    func path(in rect: CGRect) -> Path {
        let o = Ortho(center: center, stops: stops, in: rect)
        var p = Path()
        guard stops.count > 1 else { return p }
        for k in 0..<(stops.count - 1) {
            let a = stops[k], b = stops[k + 1]
            if a == b { continue }
            var started = false
            for i in 0...40 {
                let t = Double(i) / 40
                let ll = slerp(a, b, t)
                if let pt = o.project(ll.0, ll.1) {
                    if started { p.addLine(to: pt) } else { p.move(to: pt); started = true }
                } else { started = false }
            }
        }
        return p
    }

    private func slerp(_ a: (Double, Double), _ b: (Double, Double), _ t: Double) -> (Double, Double) {
        func vec(_ q: (Double, Double)) -> (Double, Double, Double) {
            let la = q.0 * .pi / 180, lo = q.1 * .pi / 180
            return (cos(la) * cos(lo), cos(la) * sin(lo), sin(la))
        }
        let va = vec(a), vb = vec(b)
        let dot = max(-1, min(1, va.0 * vb.0 + va.1 * vb.1 + va.2 * vb.2))
        let w = acos(dot)
        if w < 1e-6 { return a }
        let s1 = sin((1 - t) * w) / sin(w), s2 = sin(t * w) / sin(w)
        let x = s1 * va.0 + s2 * vb.0, y = s1 * va.1 + s2 * vb.1, z = s1 * va.2 + s2 * vb.2
        return (atan2(z, sqrt(x * x + y * y)) * 180 / .pi, atan2(y, x) * 180 / .pi)
    }
}

struct GlobePicture: View {
    let stops: [(String, Double, Double)]
    let base: (Double, Double)
    var step: CGFloat = 4

    var body: some View {
        let pts = stops.map { ($0.1, $0.2) }
        let center: (Double, Double) = pts.isEmpty ? base : (pts.map { $0.0 }.reduce(0, +) / Double(pts.count), pts.map { $0.1 }.reduce(0, +) / Double(pts.count))
        GeometryReader { g in
            let rect = CGRect(origin: .zero, size: g.size)
            let o = Ortho(center: center, stops: pts, in: rect)
            ZStack {
                GlobeDots(center: center, stops: pts, land: false, step: step).fill(Ax.ink.opacity(0.16))
                GlobeDots(center: center, stops: pts, land: true, step: step).fill(Ax.ink.opacity(0.85))
                GlobeRoute(center: center, stops: pts).stroke(Ax.red, style: StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round))
                ForEach(Array(uniqueStops.enumerated()), id: \.offset) { _, s in
                    if let pt = o.project(s.1, s.2) {
                        Circle().fill(Ax.paper).frame(width: 9, height: 9)
                            .overlay(Circle().fill(Ax.red).frame(width: 5, height: 5))
                            .position(pt)
                        Text(s.0)
                            .font(Ax.mono(9, .bold))
                            .padding(.horizontal, 3)
                            .background(RoundedRectangle(cornerRadius: 3).fill(Ax.paper.opacity(0.85)))
                            .position(x: pt.x, y: pt.y - 11)
                    }
                }
            }
        }
        .clipped()
    }

    private var uniqueStops: [(String, Double, Double)] {
        var seen = Set<String>(), out: [(String, Double, Double)] = []
        for s in stops where !seen.contains(s.0) { seen.insert(s.0); out.append(s) }
        return out
    }
}

struct GlobeView: View {
    @Environment(\.widgetFamily) var envFamily
    var forcedFamily: WidgetFamily? = nil
    private var family: WidgetFamily { forcedFamily ?? envFamily }
    let entry: DutyEntry

    var body: some View {
        let p = entry.payload
        let st = flyingStatus(p)
        let d = st?.duty
        let stops: [(String, Double, Double)] = {
            guard let d = d, let coords = d.coords else { return [] }
            return zip(d.route, coords).compactMap { (code: String, c: [Double]?) -> (String, Double, Double)? in
                guard let c = c, c.count == 2 else { return nil }
                return (code, c[0], c[1])
            }
        }()
        let base = (13.91, 100.61)   // DMK
        switch family {
        case .systemMedium:
            HStack(spacing: 12) {
                GlobePicture(stops: stops, base: base, step: 3.6)
                    .aspectRatio(1, contentMode: .fit)
                info(p, st)
            }
        case .systemLarge:
            VStack(alignment: .leading, spacing: 10) {
                GlobePicture(stops: stops, base: base, step: 4.2)
                    .frame(maxHeight: .infinity)
                info(p, st)
                    .frame(height: 96)
            }
        default:
            ZStack(alignment: .bottomLeading) {
                GlobePicture(stops: stops, base: base, step: 3.4)
                if let d = d {
                    Text(d.route.isEmpty ? d.what : d.route.joined(separator: "›"))
                        .font(Ax.mono(9, .bold))
                        .lineLimit(1).minimumScaleFactor(0.5)
                        .padding(.horizontal, 4).padding(.vertical, 2)
                        .background(RoundedRectangle(cornerRadius: 4).fill(Ax.paper.opacity(0.9)))
                }
            }
        }
    }

    /// The duty you're on if it flies, otherwise the next one with a route (standby days have no route to draw).
    private func flyingStatus(_ p: Payload?) -> DutyStatus? {
        guard let p = p else { return nil }
        let ms = entry.date.timeIntervalSince1970 * 1000
        let hasRoute: (Duty) -> Bool = { !($0.coords ?? []).compactMap { $0 }.isEmpty }
        if let cur = p.duties.first(where: { $0.rep <= ms && $0.off > ms && hasRoute($0) }) {
            return DutyStatus(duty: cur, onDuty: true, target: cur.offDate)
        }
        if let nx = p.duties.filter({ $0.rep > ms && hasRoute($0) }).min(by: { $0.rep < $1.rep }) {
            return DutyStatus(duty: nx, onDuty: false, target: nx.repDate)
        }
        return p.status(at: entry.date)
    }

    @ViewBuilder
    private func info(_ p: Payload?, _ st: DutyStatus?) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            if let st = st {
                HStack {
                    Caption(text: st.onDuty ? "On duty now" : st.duty.route.isEmpty ? "Next duty" : "Next flight")
                    Spacer(minLength: 0)
                    ExampleTag(demo: p?.demo ?? false)
                }
                Text(st.duty.route.isEmpty ? st.duty.what : st.duty.route.joined(separator: " › "))
                    .font(Ax.mono(13, .bold)).lineLimit(2).minimumScaleFactor(0.6)
                Caption(text: "\(Fmt.day(st.duty.date)) · \(st.duty.what) \(st.duty.start ?? "")")
                if !st.duty.flts.isEmpty {
                    Text(st.duty.flts.joined(separator: " · ")).font(Ax.mono(10)).foregroundStyle(.secondary).lineLimit(2)
                }
                Spacer(minLength: 0)
                DotText(text: Fmt.countdown(st.target.timeIntervalSince(entry.date)), height: 16)
            } else {
                Caption(text: "Next duty")
                Spacer(minLength: 0)
                Text(p == nil ? "Open Axiom once to connect the widgets." : "Nothing ahead on your roster.")
                    .font(Ax.mono(11)).lineLimit(3)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct GlobeWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "AxiomGlobe", provider: DutyProvider()) { e in
            GlobeView(entry: e).axiomBackground()
        }
        .configurationDisplayName("Globe")
        .description("The dashboard's dot-matrix globe, zoomed to your next duty with the route in red.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}
