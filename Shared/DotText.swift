import SwiftUI

struct DotCell: Hashable {
    let x: Int
    let y: Int
}

/// Lays text out on the 5×7 dot grid: which dots are lit, which are dark, and how many columns wide it is.
struct DotLayout {
    var lit: [DotCell] = []
    var unlit: [DotCell] = []
    var columns: Int = 1

    init(_ text: String) {
        var x = 0
        for ch in text.uppercased() {
            let rows = DotGlyphs.map[ch] ?? DotGlyphs.map["?"] ?? ["0", "0", "0", "0", "0", "0", "0"]
            let w = rows.first?.count ?? 1
            for (y, row) in rows.enumerated() {
                for (i, c) in row.enumerated() {
                    if c == "1" { lit.append(DotCell(x: x + i, y: y)) } else { unlit.append(DotCell(x: x + i, y: y)) }
                }
            }
            x += w + 1
        }
        columns = max(1, x - 1)
    }
}

/// Round dots drawn into whatever space SwiftUI gives, keeping the 7-row grid square.
struct DotShape: Shape {
    let cells: [DotCell]
    let columns: Int
    var size: CGFloat = 0.86   // dot diameter as a share of the grid step

    func path(in rect: CGRect) -> Path {
        let step = min(rect.height / 7, rect.width / CGFloat(columns))
        let r = step * size / 2
        let ox = rect.minX + (rect.width - step * CGFloat(columns)) / 2
        let oy = rect.minY + (rect.height - step * 7) / 2
        var p = Path()
        for c in cells {
            let cx = ox + (CGFloat(c.x) + 0.5) * step
            let cy = oy + (CGFloat(c.y) + 0.5) * step
            p.addEllipse(in: CGRect(x: cx - r, y: cy - r, width: r * 2, height: r * 2))
        }
        return p
    }
}

/// Axiom's dot-matrix lettering. Give it a height; it shrinks to fit the width if it has to.
struct DotText: View {
    let text: String
    var height: CGFloat = 20
    var showUnlit: Bool = false
    var color: Color = .primary

    var body: some View {
        let l = DotLayout(text)
        ZStack {
            if showUnlit {
                DotShape(cells: l.unlit, columns: l.columns).fill(color.opacity(0.13))
            }
            DotShape(cells: l.lit, columns: l.columns).fill(color)
        }
        .aspectRatio(CGFloat(l.columns) / 7, contentMode: .fit)
        .frame(maxHeight: height)
        .accessibilityElement()
        .accessibilityLabel(Text(text))
    }
}
