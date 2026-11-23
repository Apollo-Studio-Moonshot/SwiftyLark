import SwiftUI

extension Color {
    init(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        var v: UInt64 = 0
        Scanner(string: s).scanHexInt64(&v)
        let r = Double((v >> 16) & 0xFF) / 255
        let g = Double((v >> 8) & 0xFF) / 255
        let b = Double(v & 0xFF) / 255
        self.init(.sRGB, red: r, green: g, blue: b, opacity: 1)
    }

    init(hue: Int, sat: Double = 0.52, bright: Double = 0.62) {
        self.init(hue: Double(hue) / 360.0, saturation: sat, brightness: bright)
    }
}

struct Palette {
    let dark: Bool

    /// Colours and metrics come from app/mechanics.json (shipped in the bundle),
    /// so the sheet drives the interface rather than just describing it.
    private var m: MechanicsSheet { .shared }

    var deep: Color { dark ? Color(hex: "#0d0e10") : Color(hex: "#eef0f3") }
    var rail: Color { dark ? Color(hex: "#161718") : Color(hex: "#f2f3f5") }
    var list: Color { dark ? Color(hex: m.text("dark panel background", "#1a1a1a")) : Color(hex: "#ffffff") }
    var content: Color { dark ? Color(hex: m.text("dark content background", "#121212")) : Color(hex: "#f8f9fa") }
    var elevated: Color { dark ? Color(hex: "#26282b") : Color(hex: "#ffffff") }
    var hover: Color { dark ? Color(hex: "#2a2c30") : Color(hex: "#eef0f3") }
    var selected: Color { dark ? Color(hex: "#2c3550") : Color(hex: m.text("selected row background (light)", "#f0f4ff")) }
    var border: Color { dark ? Color(hex: "#2c2e31") : Color(hex: m.text("light divider", "#dee0e3")) }
    var borderSoft: Color { dark ? Color(hex: "#232528") : Color(hex: "#e9ebed") }
    var textPrimary: Color {
        dark ? Color(hex: m.text("dark primary text", "#ebebeb"))
             : Color(hex: m.text("light primary text", "#1f2329"))
    }
    var textSecondary: Color {
        dark ? Color(hex: m.text("dark secondary text", "#a6a6a6"))
             : Color(hex: "#646a73")
    }
    var textMuted: Color { dark ? Color(hex: "#75797f") : Color(hex: "#8f959e") }
    var accent: Color { dark ? Color(hex: "#4a86ff") : Color(hex: m.text("primary accent", "#3370ff")) }
    var accentSoft: Color { accent.opacity(dark ? 0.18 : 0.12) }
    var bubbleMine: Color { dark ? Color(hex: "#2f62d4") : Color(hex: m.text("primary accent", "#3370ff")) }
    var bubbleMineText: Color { .white }
    var bubbleOther: Color { dark ? Color(hex: "#26282b") : Color(hex: "#ffffff") }
    var bubbleOtherText: Color { textPrimary }
    var online: Color { Color(hex: "#34c724") }
    var away: Color { Color(hex: "#ffb400") }
    var offline: Color { dark ? Color(hex: "#5f6368") : Color(hex: "#bbbfc4") }
    var danger: Color { dark ? Color(hex: "#f54a45") : Color(hex: m.text("unread badge", "#fa1f41")) }

    /// Metrics shared with the sheet.
    var cornerRadius: CGFloat { CGFloat(m.number("corner radius", 8)) }
    var messageTextSize: CGFloat { CGFloat(m.number("message text size", 14)) }
    var conversationListWidth: CGFloat { CGFloat(m.number("conversation list width", 320)) }

    func eventColor(_ key: String) -> Color {
        switch key {
        case "violet": return Color(hex: dark ? "#9a7bff" : "#7d5bff")
        case "green": return Color(hex: dark ? "#3fbf7f" : "#2ea871")
        case "orange": return Color(hex: dark ? "#ff9f45" : "#f07b24")
        case "red": return Color(hex: dark ? "#ff6b6b" : "#e5484d")
        case "blue": return Color(hex: dark ? "#4a86ff" : "#3370ff")
        default: return accent
        }
    }
}

private struct PaletteKey: EnvironmentKey {
    static let defaultValue = Palette(dark: true)
}

extension EnvironmentValues {
    var palette: Palette {
        get { self[PaletteKey.self] }
        set { self[PaletteKey.self] = newValue }
    }
}

// MARK: - Small building blocks

struct AvatarView: View {
    var text: String
    var hue: Int
    var size: CGFloat = 36
    var rounded: Bool = true
    @Environment(\.palette) private var p

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: rounded ? size * 0.28 : size / 2, style: .continuous)
        ZStack {
            shape.fill(
                LinearGradient(
                    colors: [Color(hue: hue, sat: 0.58, bright: 0.72), Color(hue: hue, sat: 0.66, bright: 0.46)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            Text(text.uppercased())
                .font(.system(size: size * (text.count > 1 ? 0.34 : 0.42), weight: .semibold, design: .rounded))
                .foregroundColor(.white.opacity(0.96))
        }
        .frame(width: size, height: size)
        .overlay(
            shape.strokeBorder(Color.white.opacity(p.dark ? 0.06 : 0.16), lineWidth: 0.5)
        )
    }
}

struct StatusDot: View {
    var status: String
    @Environment(\.palette) private var p
    var body: some View {
        let color: Color = status == "online" ? p.online : (status == "away" ? p.away : p.offline)
        Circle()
            .fill(color)
            .frame(width: 9, height: 9)
            .overlay(Circle().stroke(p.list, lineWidth: 2))
    }
}

struct IconButton: View {
    var symbol: String
    var help: String = ""
    var active: Bool = false
    var size: CGFloat = 30
    var action: () -> Void
    @Environment(\.palette) private var p
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13.5, weight: .medium))
                .foregroundColor(active ? p.accent : p.textSecondary)
                .frame(width: size, height: size)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(hovering ? p.hover : Color.clear)
                )
        }
        .buttonStyle(.plain)
        .help(help)
        .onHover { hovering = $0 }
    }
}

struct DividerLine: View {
    @Environment(\.palette) private var p
    var body: some View {
        Rectangle().fill(p.borderSoft).frame(height: 1)
    }
}

enum TimeFmt {
    static func clock(_ ts: Double) -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f.string(from: Date(timeIntervalSince1970: ts))
    }

    static func short(_ ts: Double) -> String {
        let date = Date(timeIntervalSince1970: ts)
        let cal = Calendar.current
        if cal.isDateInToday(date) { return clock(ts) }
        if cal.isDateInYesterday(date) { return "Yesterday" }
        let days = cal.dateComponents([.day], from: date, to: Date()).day ?? 0
        if days < 7 {
            let f = DateFormatter(); f.dateFormat = "EEE"
            return f.string(from: date)
        }
        let f = DateFormatter(); f.dateFormat = "dd/MM/yy"
        return f.string(from: date)
    }

    static func dayHeader(_ date: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(date) { return "Today" }
        if cal.isDateInYesterday(date) { return "Yesterday" }
        let f = DateFormatter(); f.dateFormat = "EEEE, d MMMM"
        return f.string(from: date)
    }

    static func ago(minutes: Double) -> String {
        let m = max(0, minutes)
        if m < 1 { return "just now" }
        if m < 60 { return "\(Int(m))m ago" }
        if m < 60 * 24 { return "\(Int(m / 60))h ago" }
        return "\(Int(m / (60 * 24)))d ago"
    }

    static func relative(_ ts: Double) -> String {
        let diff = Date().timeIntervalSince1970 - ts
        if diff < 60 { return "now" }
        if diff < 3600 { return "\(Int(diff / 60))m" }
        if diff < 86400 { return "\(Int(diff / 3600))h" }
        return "\(Int(diff / 86400))d"
    }
}
