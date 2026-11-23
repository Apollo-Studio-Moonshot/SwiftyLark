import SwiftUI
import AppKit
import WebKit

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
        Group {
            if model.signedIn {
                workspace(p)
            } else {
                SignInView()
            }
        }
        .background(p.content)
        .environment(\.palette, p)
        .preferredColorScheme(model.prefs.theme == "system" ? nil : (isDark ? .dark : .light))
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
        .onChange(of: model.signedIn) { _ in updateDockBadge(model.unreadTotal) }
    }

    private func workspace(_ p: Palette) -> some View {
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
    }

    private func updateDockBadge(_ total: Int) {
        NSApp.dockTile.badgeLabel = total > 0 ? "\(total)" : nil
    }
}

// MARK: - Sign in

/// Feishu's own web sign-in page, shown inside the app. Login happens on
/// Feishu's site; the app only waits for the session to land on the tenant
/// messenger, the same way MeloX logs in with its embedded web view.
enum FeishuSignIn {
    // Feishu rejects the bare /accounts/page/login route with error 4401, so the
    // link carries the same app_id and redirect back into Feishu's web messenger
    // that feishu.cn uses for its own "Log in" entry point.
    static let loginURL = URL(string: "https://accounts.feishu.cn/accounts/page/login?app_id=1&no_trap=1&redirect_uri=https%3A%2F%2Fwww.feishu.cn%2Fmessenger")!

    /// Once Feishu has accepted the login it moves the web view to the tenant's
    /// own host, e.g. icc.28kp7d5w3.feishu.cn/next/messenger/.
    static func isSignedIn(_ url: URL?) -> Bool {
        guard let url, let host = url.host?.lowercased() else { return false }
        guard host.hasSuffix(".feishu.cn") || host.hasSuffix(".larksuite.com") else { return false }
        return url.path.contains("/next/messenger")
    }
}

struct SignInView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.palette) private var p
    @State private var showLogin = CommandLine.arguments.contains("--login")

    var body: some View {
        ZStack {
            background
            WindowDragArea()
            VStack(spacing: 0) {
                Spacer(minLength: 24)
                card
                Spacer(minLength: 24)
            }
            .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .sheet(isPresented: $showLogin) {
            FeishuLoginSheet()
                .environmentObject(model)
                .environment(\.palette, p)
        }
    }

    private var card: some View {
        VStack(spacing: 18) {
            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(LinearGradient(
                        colors: [Color(hex: "#5b93ff"), Color(hex: "#2f62d4")],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ))
                    .frame(width: 66, height: 66)
                    .shadow(color: Color(hex: "#2f62d4").opacity(0.35), radius: 14, y: 6)
                Image(systemName: "bubble.left.and.bubble.right.fill")
                    .font(.system(size: 29, weight: .medium))
                    .foregroundColor(.white)
            }

            VStack(spacing: 6) {
                Text("Sign in to Feishu")
                    .font(.system(size: 19, weight: .bold))
                    .foregroundColor(p.textPrimary)
                Text("Feishu's own sign-in page opens right here, without leaving the app.")
                    .font(.system(size: 12))
                    .foregroundColor(p.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button { showLogin = true } label: {
                HStack(spacing: 8) {
                    Image(systemName: "person.crop.circle.badge.checkmark")
                        .font(.system(size: 13, weight: .semibold))
                    Text("Sign in with Feishu")
                }
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 40)
                .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(p.accent))
            }
            .buttonStyle(.plain)
            .help("Sign in on accounts.feishu.cn inside this app")

            Text("You'll sign in on accounts.feishu.cn. Swifty Lark never sees your password.")
                .font(.system(size: 10.5))
                .foregroundColor(p.textMuted)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 34)
        .padding(.vertical, 30)
        .frame(width: 400)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(p.list)
                .shadow(color: Color.black.opacity(p.dark ? 0.35 : 0.10), radius: 30, y: 12)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(p.borderSoft, lineWidth: 1)
        )
    }

    private var background: some View {
        ZStack {
            p.dark ? Color(hex: "#0d0e10") : Color(hex: "#f5f7fa")
            RadialGradient(
                colors: [p.accent.opacity(p.dark ? 0.20 : 0.14), .clear],
                center: .top,
                startRadius: 10,
                endRadius: 520
            )
        }
        .ignoresSafeArea()
    }
}

struct FeishuLoginSheet: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.palette) private var p
    @Environment(\.dismiss) private var dismiss
    @State private var loading = true

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Button("Cancel") { dismiss() }
                    .buttonStyle(.plain)
                    .font(.system(size: 12))
                    .foregroundColor(p.textSecondary)
                    .frame(width: 56, alignment: .leading)
                Spacer()
                VStack(spacing: 1) {
                    Text("Sign in to Feishu")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(p.textPrimary)
                    Text("accounts.feishu.cn")
                        .font(.system(size: 10))
                        .foregroundColor(p.textMuted)
                }
                Spacer()
                ProgressView()
                    .controlSize(.small)
                    .opacity(loading ? 1 : 0)
                    .frame(width: 56, alignment: .trailing)
            }
            .padding(.horizontal, 16)
            .frame(height: 54)
            Rectangle().fill(p.borderSoft).frame(height: 1)
            FeishuLoginWebView(isLoading: $loading) {
                model.completeSignIn()
                dismiss()
            }
        }
        .frame(width: 880, height: 680)
        .background(p.content)
    }
}

struct FeishuLoginWebView: NSViewRepresentable {
    @Binding var isLoading: Bool
    var onSignedIn: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(isLoading: $isLoading, onSignedIn: onSignedIn)
    }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        // The default store keeps Feishu's cookies, so the session survives quits.
        configuration.websiteDataStore = .default()
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.load(URLRequest(url: FeishuSignIn.loginURL))
        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {}

    final class Coordinator: NSObject, WKNavigationDelegate {
        private let isLoading: Binding<Bool>
        private let onSignedIn: () -> Void
        private var finished = false

        init(isLoading: Binding<Bool>, onSignedIn: @escaping () -> Void) {
            self.isLoading = isLoading
            self.onSignedIn = onSignedIn
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation?) {
            isLoading.wrappedValue = true
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation?) {
            isLoading.wrappedValue = false
            check(webView.url)
        }

        func webView(_ webView: WKWebView, didCommit navigation: WKNavigation?) {
            check(webView.url)
        }

        private func check(_ url: URL?) {
            guard !finished, FeishuSignIn.isSignedIn(url) else { return }
            finished = true
            onSignedIn()
        }
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
