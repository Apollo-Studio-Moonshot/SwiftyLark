import SwiftUI
import AppKit

// Lets the empty parts of our custom title bar drag the window.
struct WindowDragArea: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { DragView() }
    func updateNSView(_ nsView: NSView, context: Context) {}

    final class DragView: NSView {
        override var mouseDownCanMoveWindow: Bool { true }
        override func mouseDown(with event: NSEvent) {
            window?.performDrag(with: event)
        }
    }
}

struct WindowAccessor: NSViewRepresentable {
    var onWindow: (NSWindow) -> Void
    func makeNSView(context: Context) -> NSView {
        let v = NSView()
        DispatchQueue.main.async { if let w = v.window { onWindow(w) } }
        return v
    }
    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async { if let w = nsView.window { onWindow(w) } }
    }
}

struct RootView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.colorScheme) private var systemScheme

    private var isDark: Bool {
        switch model.prefs.theme {
        case "light": return false
        case "system": return systemScheme == .dark
        default: return true
        }
    }

    var body: some View {
        let p = Palette(dark: isDark)
        VStack(spacing: 0) {
            TitleBar()
            Rectangle().fill(p.borderSoft).frame(height: 1)
            HStack(spacing: 0) {
                Rail()
                switch model.tab {
                case .messages:
                    MessagesScreen()
                case .calendar:
                    CalendarScreen()
                case .docs:
                    DocsScreen()
                case .contacts:
                    ContactsScreen()
                case .tasks:
                    TasksScreen()
                }
            }
        }
        .background(p.content)
        .environment(\.palette, p)
        .preferredColorScheme(model.prefs.theme == "system" ? nil : (isDark ? .dark : .light))
        .overlay {
            if model.searchOpen {
                SearchOverlay()
            }
        }
        .sheet(isPresented: $model.showSettings) {
            SettingsSheet()
                .environment(\.palette, p)
                .environmentObject(model)
        }
        .background(WindowAccessor { window in
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.isMovableByWindowBackground = false
            window.backgroundColor = NSColor(p.content)
        })
        // Lark's notifySetting.showUnreadNumber defaults to true; badgeStyle WEAK_REMIND (1)
        // means the dock badge only carries the unread count.
        .onAppear { updateDockBadge(model.unreadTotal) }
        .onChange(of: model.unreadTotal) { total in updateDockBadge(total) }
    }

    private func updateDockBadge(_ total: Int) {
        NSApp.dockTile.badgeLabel = total > 0 ? "\(total)" : nil
    }
}

// MARK: - Title bar

struct TitleBar: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.palette) private var p
    @State private var hoverSearch = false

    var body: some View {
        ZStack {
            WindowDragArea()
            HStack(spacing: 0) {
                HStack(spacing: 8) {
                    AvatarView(text: model.workspace?.name.prefix(2).uppercased() ?? "AS", hue: 214, size: 22, rounded: true)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(model.workspace?.name ?? "Workspace")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(p.textPrimary)
                        Text("\(model.workspace?.plan ?? "Team") · \(model.workspace?.members ?? 0) members")
                            .font(.system(size: 10))
                            .foregroundColor(p.textMuted)
                    }
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(p.textMuted)
                }
                .padding(.leading, 78)

                Spacer(minLength: 12)

                Button {
                    model.searchOpen = true
                } label: {
                    HStack(spacing: 7) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 11.5, weight: .medium))
                            .foregroundColor(p.textMuted)
                        Text("Search messages, people and docs")
                            .font(.system(size: 11.5))
                            .foregroundColor(p.textMuted)
                        Spacer(minLength: 4)
                        Text("⌘K")
                            .font(.system(size: 10, weight: .medium, design: .rounded))
                            .foregroundColor(p.textMuted)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(RoundedRectangle(cornerRadius: 4).fill(p.dark ? Color.white.opacity(0.06) : Color.black.opacity(0.05)))
                    }
                    .padding(.horizontal, 10)
                    .frame(width: 400, height: 28)
                    .background(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(hoverSearch ? p.hover : (p.dark ? Color.white.opacity(0.05) : Color.black.opacity(0.04)))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .strokeBorder(p.borderSoft, lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
                .onHover { hoverSearch = $0 }

                Spacer(minLength: 12)

                HStack(spacing: 2) {
                    IconButton(symbol: "bell", help: "Notifications") {}
                    IconButton(symbol: "plus.square", help: "Create") {}
                    IconButton(symbol: "gearshape", help: "Settings") { model.showSettings = true }
                    AvatarView(text: model.user?.avatarText ?? "W", hue: model.user?.hue ?? 214, size: 24, rounded: false)
                        .padding(.leading, 6)
                }
                .padding(.trailing, 14)
            }
        }
        .frame(height: 46)
        .background(p.rail)
    }
}

// MARK: - Rail

struct Rail: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.palette) private var p

    var body: some View {
        VStack(spacing: 8) {
            VStack(spacing: 4) {
                ForEach(SidebarTab.allCases) { tab in
                    RailButton(tab: tab, selected: model.tab == tab, unread: tab == .messages ? model.unreadTotal : 0) {
                        model.tab = tab
                    }
                }
            }
            .padding(.top, 8)

            Rectangle().fill(p.borderSoft).frame(width: 24, height: 1).padding(.vertical, 2)

            RailIcon(symbol: "square.grid.2x2", help: "Apps") {}
            RailIcon(symbol: "headphones", help: "Help") {}

            Spacer()

            RailIcon(symbol: "gearshape", help: "Settings") { model.showSettings = true }

            Button {
                model.showSettings = true
            } label: {
                AvatarView(text: model.user?.avatarText ?? "W", hue: model.user?.hue ?? 214, size: 30, rounded: false)
            }
            .buttonStyle(.plain)
            .help(model.user?.name ?? "")
            .padding(.bottom, 12)
        }
        .frame(width: 60)
        .frame(maxHeight: .infinity)
        .background(p.rail)
    }
}

struct RailButton: View {
    var tab: SidebarTab
    var selected: Bool
    var unread: Int
    var action: () -> Void
    @Environment(\.palette) private var p
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            ZStack(alignment: .topTrailing) {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(selected ? p.accentSoft : (hovering ? p.hover : Color.clear))
                    .frame(width: 40, height: 40)
                    .overlay(
                        Image(systemName: tab.symbol)
                            .font(.system(size: 17, weight: .regular))
                            .foregroundColor(selected ? p.accent : p.textSecondary)
                    )
                if unread > 0 {
                    Text(unread > 9 ? "9+" : "\(unread)")
                        .font(.system(size: 8.5, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, unread > 9 ? 3.5 : 4)
                        .frame(minWidth: 14, minHeight: 14)
                        .background(Capsule().fill(p.danger))
                        .offset(x: 2, y: -2)
                }
            }
            .frame(width: 40, height: 40)
        }
        .buttonStyle(.plain)
        .help(tab.title)
        .onHover { hovering = $0 }
    }
}

struct RailIcon: View {
    var symbol: String
    var help: String
    var action: () -> Void
    @Environment(\.palette) private var p
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(hovering ? p.hover : Color.clear)
                .frame(width: 40, height: 34)
                .overlay(
                    Image(systemName: symbol)
                        .font(.system(size: 15))
                        .foregroundColor(p.textMuted)
                )
        }
        .buttonStyle(.plain)
        .help(help)
        .onHover { hovering = $0 }
    }
}
