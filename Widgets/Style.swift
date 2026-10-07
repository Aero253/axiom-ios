import SwiftUI
import WidgetKit

enum Ax {
    static let yellow = Color(red: 1.0, green: 0.769, blue: 0.0)      // #ffc400, the dashboard's caution yellow
    static let red = Color(red: 1.0, green: 0.255, blue: 0.212)       // #ff4136, the route and "go" red
    static let ink = Color.primary
    static var paper: Color { Color(uiColor: .systemBackground) }

    static func mono(_ size: CGFloat, _ weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
}

/// Small spaced capitals, like the labels on the dashboard.
struct Caption: View {
    let text: String
    var color: Color = .secondary

    var body: some View {
        Text(text.uppercased())
            .font(Ax.mono(10))
            .tracking(1)
            .foregroundStyle(color)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
    }
}

/// The caution badge: yellow from 2 h 30 min before report, red from 35 min.
struct AlertPill: View {
    let red: Bool
    let text: String

    var body: some View {
        Text(text.uppercased())
            .font(Ax.mono(10, .bold))
            .tracking(0.5)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(Capsule().fill(red ? Ax.red : Ax.yellow))
            .foregroundStyle(red ? Color.white : Color(white: 0.07))
    }
}

extension View {
    /// Plain black or white behind the widget, following the phone's light or dark mode.
    func axiomBackground() -> some View {
        containerBackground(for: .widget) { Ax.paper }
    }
}
