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
                ZStack {
                    // The signed-in window is native SwiftUI fed by the Rust
                    // core. Until the first import arrives, show what the sync
                    // is doing instead of the seeded demo workspace.
                    if model.hasImportedWorkspace {
                        workspace(p)
                    } else {
                        SyncProgressView()
                    }
                    // Invisible web client: it keeps the Feishu session alive
                    // and scrapes conversations/messages into the core. Kept at
                    // zero opacity so the user only ever sees native UI.
                    FeishuSyncView()
                        .frame(width: 1200, height: 800)
                        .opacity(0.01)
                        .allowsHitTesting(false)
                }
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
            // A saved frame from an old layout can land completely off-screen.
            if !NSScreen.screens.contains(where: { $0.visibleFrame.intersects(window.frame) }) {
                window.center()
            }
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

    /// The real Feishu web client, opened after sign-in so the app shows the
    /// actual workspace instead of the local sample data.
    static let messengerURL = URL(string: "https://www.feishu.cn/messenger")!

    /// Feishu rejects the bare WKWebView user agent; present Safari's identity.
    static let browserUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.6 Safari/605.1.15"

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
        .onAppear { presentLoginIfRequested() }
        // The session can expire after this view appears, so watch for a late
        // request as well as the one present at launch.
        .onChange(of: model.loginRequested) { _ in presentLoginIfRequested() }
    }

    private func presentLoginIfRequested() {
        if model.loginRequested {
            model.loginRequested = false
            showLogin = true
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
                    .frame(width: 56, alignment: .trailing)
            }
            .padding(.horizontal, 16)
            .frame(height: 54)
            Rectangle().fill(p.borderSoft).frame(height: 1)
            FeishuLoginWebView()
        }
        .frame(width: 880, height: 680)
        .background(p.content)
        // Feishu's own page landed in the tenant messenger: leave the web view
        // in place (the sync view re-attaches the same instance) and show the
        // native workspace.
        .onChange(of: model.signedIn) { signedIn in
            if signedIn { dismiss() }
        }
    }
}

struct FeishuLoginWebView: NSViewRepresentable {
    func makeNSView(context: Context) -> WKWebView {
        FeishuWebHost.start()
        let webView = FeishuWebHost.webView
        // The same instance is re-attached after a sign-out/sign-in cycle.
        if webView.superview != nil { webView.removeFromSuperview() }
        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {}
}

/// The one Feishu web client in the app: the sign-in sheet shows it, and after
/// login the same instance is re-attached offscreen to keep feeding the Rust
/// core. Reusing it matters because Feishu keeps part of its session in
/// per-web-view state; a fresh WKWebView loading the tenant URL gets bounced to
/// the session-refresh page.
enum FeishuWebHost {
    static let webView: WKWebView = {
        let configuration = WKWebViewConfiguration()
        // The default store keeps Feishu's cookies, so the session survives quits.
        configuration.websiteDataStore = .default()
        let controller = WKUserContentController()
        controller.add(FeishuSync.shared, name: FeishuSync.handler)
        controller.add(FeishuProfile.shared, name: FeishuProfile.handler)
        controller.addUserScript(WKUserScript(
            source: FeishuProfile.script,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: false
        ))
        controller.addUserScript(WKUserScript(
            source: FeishuSync.script,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: false
        ))
        if CommandLine.arguments.contains("--capture") {
            controller.add(FeishuCapture.shared, name: "feishuCapture")
            controller.addUserScript(WKUserScript(
                source: FeishuCapture.script,
                injectionTime: .atDocumentStart,
                forMainFrameOnly: false
            ))
        }
        // Feishu's login flow switches routes without a full page load, so the
        // navigation delegate alone can miss the moment the tenant appears.
        controller.add(auth, name: "feishuLoginState")
        controller.addUserScript(WKUserScript(
            source: "setInterval(function(){try{window.webkit.messageHandlers.feishuLoginState.postMessage(location.href);}catch(e){}},1000);",
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true
        ))
        configuration.userContentController = controller
        let webView = WKWebView(
            frame: NSRect(x: 0, y: 0, width: 1200, height: 800),
            configuration: configuration
        )
        webView.customUserAgent = FeishuSignIn.browserUserAgent
        webView.navigationDelegate = auth
        return webView
    }()

    private static let auth = FeishuAuth {
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .feishuBrowserSignedIn, object: nil)
        }
    }

    private static var started = false

    static func start() {
        guard !started else { return }
        started = true
        let signedIn = UserDefaults.standard.bool(forKey: AppModel.signedInKey)
        let url = signedIn ? FeishuSession.messengerURL : FeishuSignIn.loginURL
        log("start \(url.absoluteString)")
        webView.load(URLRequest(url: url))
    }

    /// Show Feishu's own login page again in the same web view.
    static func beginLogin() {
        auth.reset()
        log("begin login")
        webView.load(URLRequest(url: FeishuSignIn.loginURL))
    }

    static func log(_ message: String) {
        guard CommandLine.arguments.contains("--capture") else { return }
        FeishuCapture.append(["url": "SYNC-LOG \(message)", "body": ""])
    }
}

/// Watches the shared web view's URL. It confirms a sign-in only once the
/// tenant messenger is genuinely on screen, so a stale cookie that briefly
/// paints the tenant shell is not mistaken for a valid session.
final class FeishuAuth: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
    private let onSignedIn: () -> Void
    private var finished = false
    private var pendingConfirm: DispatchWorkItem?
    private var latestURL: URL?
    private var confirmTries = 0
    /// True once Feishu's own login form has been shown. Completing sign-in
    /// only after this prevents a cached, half-expired tenant page from
    /// counting as a successful login.
    private var sawLoginPage = false

    init(onSignedIn: @escaping () -> Void) {
        self.onSignedIn = onSignedIn
    }

    func reset() {
        finished = false
        sawLoginPage = false
        confirmTries = 0
        pendingConfirm?.cancel()
        pendingConfirm = nil
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation?) {
        FeishuWebHost.log("start \(webView.url?.absoluteString ?? "nil")")
        // Any full navigation interrupts a pending "did we really land in
        // the tenant?" confirmation.
        pendingConfirm?.cancel()
        pendingConfirm = nil
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation?) {
        FeishuWebHost.log("finish \(webView.url?.absoluteString ?? "nil")")
        if let url = webView.url { observe(url) }
    }

    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation?) {
        if let url = webView.url { observe(url) }
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation?, withError error: Error) {
        FeishuWebHost.log("fail \(error.localizedDescription) \(webView.url?.absoluteString ?? "nil")")
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let raw = message.body as? String, let url = URL(string: raw) else { return }
        observe(url)
    }

    private func observe(_ url: URL) {
        latestURL = url
        if let host = url.host?.lowercased(), host.hasPrefix("accounts."),
           url.path.lowercased().contains("/login") {
            sawLoginPage = true
        }
        guard !finished, sawLoginPage, FeishuSignIn.isSignedIn(url) else {
            // Still on the login/refresh page: don't confirm a sign-in.
            pendingConfirm?.cancel()
            pendingConfirm = nil
            confirmTries = 0
            return
        }
        guard pendingConfirm == nil else { return }
        // Wait briefly to make sure this is not the tenant page Feishu
        // briefly shows before bouncing to its session refresh page.
        var work: DispatchWorkItem!
        work = DispatchWorkItem { [weak self] in
            guard let self, !self.finished,
                  let current = self.latestURL, FeishuSignIn.isSignedIn(current) else { return }
            // A stale cookie paints the tenant shell before the account API
            // rejects it, so require the messenger itself to be on screen.
            let probe = "(function(){var t=(document.body&&document.body.innerText)||'';"
                + "return t.length+':'+(/Chats|聊天|Messages|消息|Search|搜索|Calendar|日历/.test(t)?1:0);})()"
            FeishuWebHost.webView.evaluateJavaScript(probe) { [weak self] result, _ in
                guard let self, !self.finished,
                      let current = self.latestURL, FeishuSignIn.isSignedIn(current) else { return }
                var ready = false
                if let text = result as? String {
                    let parts = text.split(separator: ":")
                    if parts.count == 2, let length = Int(parts[0]), let hit = Int(parts[1]) {
                        ready = length > 200 && hit == 1
                    }
                }
                if ready {
                    self.finished = true
                    FeishuSession.store(current)
                    FeishuWebHost.log("signed in \(current.absoluteString)")
                    self.onSignedIn()
                    return
                }
                self.confirmTries += 1
                if self.confirmTries < 15 {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2, execute: work)
                } else {
                    self.pendingConfirm = nil
                }
            }
        }
        pendingConfirm = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 6, execute: work)
    }
}

/// Bridge from Feishu's own web client: forwards JSON API responses to Swift so
/// they can be mapped into the Rust store. Only active with `--capture`.
final class FeishuCapture: NSObject, WKScriptMessageHandler {
    static let shared = FeishuCapture()
    private let queue = DispatchQueue(label: "swiftylark.feishu.capture")
    private var bytes = 0

    static let script = """
    (function () {
      if (window.__swiftyCapture) return;
      window.__swiftyCapture = true;
      function send(url, body, type) {
        try {
          window.webkit.messageHandlers.feishuCapture.postMessage({
            url: String(url), type: String(type || ''), body: String(body || '').slice(0, 300000)
          });
        } catch (e) {}
      }
      var origFetch = window.fetch;
      window.fetch = function () {
        var args = arguments;
        var url = (args[0] && args[0].url) ? args[0].url : String(args[0]);
        return origFetch.apply(this, args).then(function (res) {
          try {
            var ct = res.headers.get('content-type') || '';
            if (url.indexOf('/im/gateway') >= 0 && res.body) {
              try {
                var reader = res.clone().body.getReader();
                var chunks = 0;
                var pump = function () {
                  reader.read().then(function (r) {
                    if (r.done || chunks > 200) return;
                    chunks++;
                    try {
                      send('GW ' + url, new TextDecoder('utf-8').decode(r.value), 'gw');
                    } catch (e) {}
                    pump();
                  }).catch(function () {});
                };
                pump();
              } catch (e) {}
            } else if (ct.indexOf('json') >= 0) {
              res.clone().text().then(function (t) { send(url, t, ct); }).catch(function () {});
            } else {
              send(url, '', ct);
            }
          } catch (e) {}
          return res;
        });
      };
      var origOpen = XMLHttpRequest.prototype.open;
      var origSend = XMLHttpRequest.prototype.send;
      XMLHttpRequest.prototype.open = function (method, url) {
        this.__swiftyURL = url;
        return origOpen.apply(this, arguments);
      };
      XMLHttpRequest.prototype.send = function () {
        var xhr = this;
        xhr.addEventListener('load', function () {
          try {
            var ct = xhr.getResponseHeader('content-type') || '';
            send(xhr.__swiftyURL, ct.indexOf('json') >= 0 ? xhr.responseText : '', ct);
          } catch (e) {}
        });
        return origSend.apply(this, arguments);
      };
      try {
        var OrigWS = window.WebSocket;
        window.WebSocket = function (url, protocols) {
          var ws = protocols ? new OrigWS(url, protocols) : new OrigWS(url);
          ws.addEventListener('message', function (e) {
            try {
              if (typeof e.data === 'string') send('WS ' + url, e.data, 'ws');
              else send('WSBIN ' + url, String((e.data && e.data.byteLength) || 0), 'ws');
            } catch (err) {}
          });
          return ws;
        };
        window.WebSocket.prototype = OrigWS.prototype;
      } catch (e) {}
      function reportPage() {
        try {
          window.webkit.messageHandlers.feishuCapture.postMessage({
            url: 'PAGE ' + location.href + ' | ' + document.title, type: 'page', body: ''
          });
        } catch (e) {}
      }
      window.addEventListener('load', reportPage, true);
      setTimeout(reportPage, 4000);
      setTimeout(reportPage, 10000);
      setTimeout(reportPage, 18000);
      setTimeout(function () {
        try { send('TEXT', document.body.innerText.slice(0, 30000), 'text'); } catch (e) {}
      }, 15000);
      setTimeout(function () {
        try { send('TEXT', document.body.innerText.slice(0, 30000), 'text'); } catch (e) {}
      }, 22000);
      setTimeout(function () {
        try {
          var out = [];
          var nodes = document.querySelectorAll('[data-testid],[data-message-id],[data-chat-id],[role="listitem"],[role="row"],[class*="message"],[class*="chat"]');
          for (var i = 0; i < nodes.length && i < 140; i++) {
            var n = nodes[i], r = n.getBoundingClientRect();
            out.push([
              n.tagName || '',
              n.getAttribute ? (n.getAttribute('role') || '') : '',
              (n.className || '').toString().slice(0, 90),
              n.getAttribute ? (n.getAttribute('data-testid') || '') : '',
              n.getAttribute ? (n.getAttribute('data-chat-id') || '') : '',
              n.getAttribute ? (n.getAttribute('data-message-id') || '') : '',
              Math.round(r.x) + ',' + Math.round(r.y) + ' ' + Math.round(r.width) + 'x' + Math.round(r.height),
              (n.innerText || '').slice(0, 70).replace(/\n/g, ' | ')
            ].join(' ~ '));
          }
          send('DOM', out.join('\n'), 'dom');
        } catch (e) { send('DOMERR', String(e), 'dom'); }
      }, 17000);
    })();
    """

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let payload = message.body as? [String: Any],
              let url = payload["url"] as? String,
              let body = payload["body"] as? String else { return }
        guard bytes < 30_000_000 else { return }
        bytes += body.utf8.count
        FeishuCapture.append(["url": url, "body": body])
    }

    static func append(_ object: [String: String]) {
        var stamped = object
        stamped["t"] = ISO8601DateFormatter().string(from: Date())
        guard let data = try? JSONSerialization.data(withJSONObject: stamped) else { return }
        shared.queue.async {
            let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("Swifty Lark", isDirectory: true)
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let file = dir.appendingPathComponent("web-capture.jsonl")
            if !FileManager.default.fileExists(atPath: file.path) {
                FileManager.default.createFile(atPath: file.path, contents: nil)
            }
            if let handle = try? FileHandle(forWritingTo: file) {
                handle.seekToEndOfFile()
                handle.write(data)
                handle.write(Data("\n".utf8))
                try? handle.close()
            }
        }
    }
}

// MARK: - Feishu session

/// The tenant messenger URL Feishu redirected to after login, persisted so the
/// next launch opens the same workspace directly.
enum FeishuSession {
    static let tenantURLKey = "feishu.tenantURL"

    static var messengerURL: URL {
        if let raw = UserDefaults.standard.string(forKey: tenantURLKey),
           let url = URL(string: raw),
           let host = url.host?.lowercased(),
           host.hasSuffix(".feishu.cn") || host.hasSuffix(".larksuite.com"),
           url.path.contains("/next/messenger") {
            return url
        }
        return FeishuSignIn.messengerURL
    }

    static func store(_ url: URL) {
        UserDefaults.standard.set(url.absoluteString, forKey: tenantURLKey)
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: tenantURLKey)
    }

    /// Wipes the web view's cookies/cache so the next login shows Feishu's real
    /// login form instead of auto-loading a half-expired tenant session.
    static func resetWebData(_ completion: @escaping () -> Void) {
        let store = WKWebsiteDataStore.default()
        store.removeData(
            ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(),
            modifiedSince: .distantPast
        ) {
            completion()
        }
    }
}

// MARK: - Signed-in profile

/// Reads the account and tenant from Feishu's own user endpoint while the login
/// flow runs, so the native window shows the real name and workspace.
final class FeishuProfile: NSObject, WKScriptMessageHandler {
    static let shared = FeishuProfile()
    static let handler = "feishuProfile"

    static let userKey = "feishu.userName"
    static let userIdKey = "feishu.userId"
    static let tenantKey = "feishu.tenantName"
    static let tenantIdKey = "feishu.tenantId"

    static let script = #"""
    (function () {
      if (window.__swiftyProfile) return;
      window.__swiftyProfile = true;
      function send(url, body) {
        try {
          window.webkit.messageHandlers.feishuProfile.postMessage({
            url: String(url), body: String(body || '').slice(0, 200000)
          });
        } catch (e) {}
      }
      function check(url, text) {
        if (!text) return;
        var u = String(url);
        if (u.indexOf('/accounts/web/user') >= 0 || u.indexOf('GetUserInfo') >= 0) send(u, text);
      }
      var origFetch = window.fetch;
      window.fetch = function () {
        var args = arguments;
        var url = (args[0] && args[0].url) ? args[0].url : String(args[0]);
        return origFetch.apply(this, args).then(function (res) {
          try {
            var ct = res.headers.get('content-type') || '';
            if (ct.indexOf('json') >= 0) {
              res.clone().text().then(function (t) { check(url, t); }).catch(function () {});
            }
          } catch (e) {}
          return res;
        });
      };
      var origOpen = XMLHttpRequest.prototype.open;
      var origSend = XMLHttpRequest.prototype.send;
      XMLHttpRequest.prototype.open = function (method, url) {
        this.__swiftyURL = url;
        return origOpen.apply(this, arguments);
      };
      XMLHttpRequest.prototype.send = function () {
        var xhr = this;
        xhr.addEventListener('load', function () {
          try { check(xhr.__swiftyURL, xhr.responseText); } catch (e) {}
        });
        return origSend.apply(this, arguments);
      };
    })();
    """#

    static var userName: String? { UserDefaults.standard.string(forKey: userKey) }
    static var userId: String? { UserDefaults.standard.string(forKey: userIdKey) }
    static var tenantName: String? { UserDefaults.standard.string(forKey: tenantKey) }

    static func ingest(_ body: String) {
        guard let data = body.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
        let root = (obj["data"] as? [String: Any]) ?? obj
        var changed = false
        if let user = root["user"] as? [String: Any] {
            if let name = (user["name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty {
                UserDefaults.standard.set(name, forKey: userKey)
                changed = true
            }
            if let id = user["id"] as? String, !id.isEmpty {
                UserDefaults.standard.set(id, forKey: userIdKey)
            }
            if let tenant = user["tenant"] as? [String: Any] {
                if let name = tenant["name"] as? String, !name.isEmpty {
                    UserDefaults.standard.set(name, forKey: tenantKey)
                    changed = true
                }
                if let id = tenant["id"] as? String, !id.isEmpty {
                    UserDefaults.standard.set(id, forKey: tenantIdKey)
                }
            }
        }
        if let name = root["tenantName"] as? String, !name.isEmpty {
            UserDefaults.standard.set(name, forKey: tenantKey)
            changed = true
        }
        if changed {
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .feishuProfileUpdated, object: nil)
            }
        }
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let payload = message.body as? [String: Any],
              let body = payload["body"] as? String else { return }
        FeishuProfile.ingest(body)
    }
}

// MARK: - Web sync

/// Keeps the signed-in Feishu web client running offscreen and scrapes its
/// conversation list and messages into the Rust core. The user never sees this
/// web view; the interface drawn on top is the native SwiftUI workspace.
final class FeishuSync: NSObject, WKScriptMessageHandler {
    static let shared = FeishuSync()
    static let handler = "feishuSync"

    private let queue = DispatchQueue(label: "swiftylark.feishu.sync")
    private var order: [String] = []
    private var rows: [String: [String: Any]] = [:]
    private var messagesByChat: [String: [[String: Any]]] = [:]
    private var importing = false
    private var pending = false

    static let script = #"""
    (function () {
      if (window.__swiftySync) return;
      window.__swiftySync = true;
      var MH = window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.feishuSync;
      if (!MH) return;
      function post(o) { try { MH.postMessage(o); } catch (e) {} }
      function sleep(ms) { return new Promise(function (r) { setTimeout(r, ms); }); }
      function lines(el) {
        return ((el && el.innerText) || '').replace(/\r/g, '').split('\n')
          .map(function (s) { return s.trim(); }).filter(Boolean);
      }
      var TIME_RE = /^(\d{1,2}:\d{2}(\s*[AP]M)?|Yesterday|昨天|前天|Monday|Tuesday|Wednesday|Thursday|Friday|Saturday|Sunday|\d{1,2}\/\d{1,2}(\/\d{2,4})?|\d{4}-\d{1,2}-\d{1,2})$/i;

      function hookProfile() {
        function check(url, text) {
          if (!text) return;
          var u = String(url);
          if (u.indexOf('/accounts/web/user') >= 0 || u.indexOf('GetUserInfo') >= 0) {
            post({ kind: 'profile', body: String(text).slice(0, 200000) });
          }
        }
        try {
          var origFetch = window.fetch;
          window.fetch = function () {
            var args = arguments;
            var url = (args[0] && args[0].url) ? args[0].url : String(args[0]);
            return origFetch.apply(this, args).then(function (res) {
              try {
                var ct = res.headers.get('content-type') || '';
                if (ct.indexOf('json') >= 0) {
                  res.clone().text().then(function (t) { check(url, t); }).catch(function () {});
                }
              } catch (e) {}
              return res;
            });
          };
          var origOpen = XMLHttpRequest.prototype.open;
          var origSend = XMLHttpRequest.prototype.send;
          XMLHttpRequest.prototype.open = function (m, u) {
            this.__swiftyURL = u;
            return origOpen.apply(this, arguments);
          };
          XMLHttpRequest.prototype.send = function () {
            var xhr = this;
            xhr.addEventListener('load', function () {
              try { check(xhr.__swiftyURL, xhr.responseText); } catch (e) {}
            });
            return origSend.apply(this, arguments);
          };
        } catch (e) {}
      }

      function onAccountsHost() {
        var host = location.host || '';
        return host.indexOf('accounts.') === 0 || host.indexOf('login.') === 0;
      }

      function sidebar() {
        var all = document.querySelectorAll('div');
        var best = null;
        for (var i = 0; i < all.length; i++) {
          var el = all[i];
          var r = el.getBoundingClientRect();
          if (r.left > 420 || r.width < 140 || r.width > 480 || r.height < 300) continue;
          var t = el.innerText || '';
          if (t.indexOf('Chats') < 0 && t.indexOf('聊天') < 0) continue;
          if (!best) { best = el; continue; }
          var br = best.getBoundingClientRect();
          if (t.length < (best.innerText || '').length && r.height >= br.height * 0.8) best = el;
        }
        return best;
      }

      function rowCandidates(sb) {
        if (!sb) return [];
        var out = [];
        var all = sb.querySelectorAll('div');
        for (var i = 0; i < all.length; i++) {
          var el = all[i];
          var r = el.getBoundingClientRect();
          if (r.width < 150 || r.height < 40 || r.height > 120 || r.left > 420) continue;
          var ls = lines(el);
          if (ls.length < 2) continue;
          var hasTime = false;
          for (var j = 1; j < ls.length; j++) {
            if (TIME_RE.test(ls[j])) { hasTime = true; break; }
          }
          if (!hasTime) continue;
          out.push({ el: el, ls: ls, area: r.width * r.height });
        }
        var map = {};
        out.forEach(function (c) {
          var key = c.ls.join('|');
          if (!map[key] || c.area < map[key].area) map[key] = c;
        });
        return Object.keys(map).map(function (k) { return map[k]; });
      }

      function timeToTs(s) {
        if (!s) return Date.now() / 1000;
        var m = s.match(/^(\d{1,2}):(\d{2})\s*([AP]M)?$/i);
        if (m) {
          var d = new Date();
          var h = parseInt(m[1], 10);
          if (m[3]) {
            h = h % 12;
            if (/PM/i.test(m[3])) h += 12;
          }
          d.setHours(h, parseInt(m[2], 10), 0, 0);
          var ts = d.getTime() / 1000;
          if (ts > Date.now() / 1000 + 120) ts -= 86400;
          return ts;
        }
        if (/^Yesterday$/i.test(s) || s === '昨天') return Date.now() / 1000 - 86400;
        if (s === '前天') return Date.now() / 1000 - 2 * 86400;
        return Date.now() / 1000;
      }

      function parseRow(c) {
        var ls = c.ls.slice();
        if (/^\d{1,3}$/.test(ls[0]) && ls.length > 2) ls = ls.slice(1);
        var name = ls[0];
        if (!name || /^(Chats|聊天|Search|More|No results)$/i.test(name)) return null;
        var timeIdx = -1;
        for (var i = 1; i < ls.length; i++) {
          if (TIME_RE.test(ls[i])) { timeIdx = i; break; }
        }
        var between = timeIdx > 1 ? ls.slice(1, timeIdx) : [];
        var preview = timeIdx >= 0 ? ls.slice(timeIdx + 1).join(' ') : ls.slice(1).join(' ');
        var badge = between.indexOf('BOT') >= 0 ? 'BOT' : (between.join(' ').indexOf('External') >= 0 ? 'External' : '');
        var unread = 0;
        for (var b = 0; b < between.length; b++) {
          if (/^\d{1,3}$/.test(between[b])) unread = Math.max(unread, parseInt(between[b], 10) || 0);
        }
        if (preview.length > 500) preview = preview.slice(0, 500);
        return {
          name: name,
          kind: badge === 'BOT' ? 'bot' : 'group',
          preview: preview,
          unread: unread,
          time: timeToTs(timeIdx >= 0 ? ls[timeIdx] : '')
        };
      }

      function scanChats() {
        var sb = sidebar();
        var cands = rowCandidates(sb);
        var chats = [];
        var seen = {};
        cands.forEach(function (c) {
          var row = parseRow(c);
          if (!row || seen[row.name]) return;
          seen[row.name] = true;
          chats.push(row);
        });
        post({ kind: 'chatlist', chats: chats });
        if (chats.length < 3) {
          post({
            kind: 'debug', url: location.href, note: 'few chat rows',
            sidebar: (sb ? sb.innerText : '').slice(0, 3000),
            rows: cands.slice(0, 12).map(function (c) { return c.ls.slice(0, 5).join(' / '); })
          });
        }
        return chats.map(function (c) { return c.name; });
      }

      function rowFor(name) {
        var sb = sidebar();
        var cands = rowCandidates(sb);
        for (var i = 0; i < cands.length; i++) {
          var row = parseRow(cands[i]);
          if (row && row.name === name) return cands[i].el;
        }
        return null;
      }

      function fireClick(el) {
        try { el.scrollIntoView({ block: 'center' }); } catch (e) {}
        var r = el.getBoundingClientRect();
        var x = r.left + r.width / 2;
        var y = r.top + r.height / 2;
        ['pointerdown', 'mousedown', 'pointerup', 'mouseup', 'click'].forEach(function (t) {
          try {
            var Ev = (t.indexOf('pointer') === 0 && window.PointerEvent) ? PointerEvent : MouseEvent;
            el.dispatchEvent(new Ev(t, { bubbles: true, cancelable: true, view: window, clientX: x, clientY: y, button: 0 }));
          } catch (e) {}
        });
        try { el.click(); } catch (e) {}
      }

      function pane() {
        var all = document.querySelectorAll('div');
        var best = null;
        var bestScore = 0;
        for (var i = 0; i < all.length; i++) {
          var el = all[i];
          var r = el.getBoundingClientRect();
          if (r.left < 300 || r.width < 420 || r.height < 260) continue;
          var st = getComputedStyle(el);
          if (!/auto|scroll/.test(st.overflowY)) continue;
          var score = el.scrollHeight + el.clientHeight;
          if (score > bestScore) { bestScore = score; best = el; }
        }
        return best;
      }

      function scrapeMessages() {
        var p = pane();
        if (!p) return [];
        var pr = p.getBoundingClientRect();
        var out = [];
        var seen = {};
        var cands = [];
        var all = p.querySelectorAll('div');
        for (var i = 0; i < all.length; i++) {
          var el = all[i];
          var r = el.getBoundingClientRect();
          if (r.width < 80 || r.height < 24 || r.height > 500) continue;
          var ls = lines(el);
          if (ls.length < 1) continue;
          var hasTime = false;
          for (var j = 0; j < ls.length; j++) {
            if (/^\d{1,2}:\d{2}(\s*[AP]M)?$/i.test(ls[j])) { hasTime = true; break; }
          }
          if (!hasTime) continue;
          cands.push({ el: el, ls: ls, area: r.width * r.height, r: r });
        }
        var map = {};
        cands.forEach(function (c) {
          var key = c.ls.join('|');
          if (!map[key] || c.area < map[key].area) map[key] = c;
        });
        Object.keys(map).forEach(function (k) {
          var c = map[k];
          var body = c.ls.filter(function (x) { return !/^\d{1,2}:\d{2}(\s*[AP]M)?$/i.test(x); });
          if (!body.length) return;
          var text = body.join(' ');
          if (seen[text]) return;
          seen[text] = true;
          var sender = '';
          if (body.length > 1 && body[0].length < 48 && !/[。！？.!?]$/.test(body[0])) sender = body[0];
          var mine = (c.r.left + c.r.width / 2) > (pr.left + pr.width * 0.62);
          out.push({
            sender: sender,
            text: (sender ? body.slice(1).join(' ') : text).slice(0, 4000),
            mine: mine,
            ts: Date.now() / 1000
          });
        });
        if (!out.length) {
          lines(p).forEach(function (line) {
            if (line.length < 1 || TIME_RE.test(line)) return;
            out.push({ sender: '', text: line.slice(0, 2000), mine: false, ts: Date.now() / 1000 });
          });
        }
        return out.slice(-60);
      }

      async function run() {
        hookProfile();
        await sleep(1200);
        if (onAccountsHost()) {
          // Feishu bounces through accounts.feishu.cn/session-tools/refresh to
          // renew cookies before returning to the tenant. Wait for that
          // redirect instead of calling the session dead after a few seconds.
          for (var g = 0; g < 20 && onAccountsHost(); g++) await sleep(2000);
          if (onAccountsHost()) {
            post({ kind: 'session', expired: true, url: location.href });
            return;
          }
        }
        post({ kind: 'status', text: 'Reading your conversation list…' });
        var names = [];
        for (var attempt = 0; attempt < 8 && names.length < 3; attempt++) {
          names = scanChats();
          if (names.length < 3) await sleep(2200);
        }
        if (!names.length) {
          post({ kind: 'debug', url: location.href, note: 'no chat rows', body: (document.body.innerText || '').slice(0, 4000) });
          // The messenger may still be painting its sidebar; keep looking
          // rather than dropping the import on the floor.
          post({ kind: 'status', text: 'Waiting for Feishu to finish loading your chats…' });
          for (var retry = 0; retry < 20 && !names.length; retry++) {
            await sleep(3000);
            names = scanChats();
          }
          if (!names.length) {
            post({ kind: 'status', text: 'Feishu is signed in, but its conversation list did not appear.' });
            return;
          }
        }
        var times = {};
        var sb = sidebar();
        rowCandidates(sb).forEach(function (c) {
          var row = parseRow(c);
          if (row) times[row.name] = row.time;
        });
        var limit = Math.min(names.length, 25);
        for (var i = 0; i < limit; i++) {
          var name = names[i];
          var el = rowFor(name);
          if (!el) continue;
          fireClick(el);
          await sleep(1300);
          var ms = scrapeMessages();
          if (times[name]) {
            for (var k = 0; k < ms.length; k++) ms[k].ts = times[name] - (ms.length - k) * 30;
          }
          post({ kind: 'messages', chat: name, messages: ms });
          post({ kind: 'status', text: 'Imported ' + (i + 1) + ' of ' + limit + ' conversations' });
          await sleep(250);
        }
        post({ kind: 'done' });
      }

      function start() {
        run().catch(function (e) {
          post({ kind: 'debug', url: location.href, note: 'error', error: String(e) });
        });
      }
      if (document.readyState === 'complete') setTimeout(start, 1800);
      else window.addEventListener('load', function () { setTimeout(start, 1800); }, true);
    })();
    """#

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let payload = message.body as? [String: Any],
              let kind = payload["kind"] as? String else { return }
        if CommandLine.arguments.contains("--capture") {
            FeishuCapture.append([
                "url": "SYNC-EVENT \(kind)",
                "body": String(describing: payload).prefix(900).description
            ])
        }
        switch kind {
        case "chatlist":
            let list = payload["chats"] as? [[String: Any]] ?? []
            queue.async {
                self.mergeChats(list)
                self.importNow()
            }
        case "messages":
            guard let name = payload["chat"] as? String,
                  let list = payload["messages"] as? [[String: Any]] else { return }
            queue.async {
                if self.rows[name] == nil {
                    self.order.append(name)
                    self.rows[name] = ["name": name]
                }
                self.messagesByChat[name] = list
                self.importNow()
            }
        case "profile":
            if let body = payload["body"] as? String {
                FeishuProfile.ingest(body)
                queue.async { self.importNow() }
            }
        case "status":
            let text = payload["text"] as? String ?? ""
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .feishuSyncStatus, object: nil, userInfo: ["text": text])
            }
        case "session":
            print("SWIFTYLARK: posting session expired")
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .feishuSessionExpired, object: nil)
            }
        case "done":
            queue.async { self.importNow() }
        default:
            if CommandLine.arguments.contains("--capture") {
                FeishuCapture.append([
                    "url": "SYNC \(payload["url"] as? String ?? "") \(payload["note"] as? String ?? "")",
                    "body": String(describing: payload).prefix(20000).description
                ])
            }
        }
    }

    private func mergeChats(_ list: [[String: Any]]) {
        for row in list {
            guard let name = (row["name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !name.isEmpty else { continue }
            if rows[name] == nil { order.append(name) }
            var merged = rows[name] ?? ["name": name]
            for (key, value) in row { merged[key] = value }
            rows[name] = merged
        }
    }

    private func importNow() {
        guard !order.isEmpty else { return }
        if importing { pending = true; return }
        importing = true
        var chats: [[String: Any]] = []
        for name in order {
            guard var row = rows[name] else { continue }
            var msgs = messagesByChat[name] ?? []
            if let time = row["time"] as? Double, !msgs.isEmpty {
                let count = msgs.count
                for i in 0..<count {
                    var m = msgs[i]
                    m["ts"] = time - Double(count - i) * 30.0
                    msgs[i] = m
                }
            }
            row["messages"] = msgs
            chats.append(row)
        }
        var payload: [String: Any] = ["chats": chats, "source": "feishu-web"]
        if let name = FeishuProfile.userName {
            payload["user"] = [
                "id": FeishuProfile.userId ?? "",
                "name": name,
                "title": "",
                "email": "",
                "avatarText": String(name.prefix(2)).uppercased(),
                "hue": 214
            ]
        }
        if let tenant = FeishuProfile.tenantName {
            payload["workspace"] = ["name": tenant, "plan": "Feishu", "members": 0]
        }
        let result = CoreClient.shared.importWorkspace(payload)
        importing = false
        if let result {
            let chatCount = result["chats"] as? Int ?? chats.count
            let messageCount = result["messages"] as? Int ?? 0
            DispatchQueue.main.async {
                NotificationCenter.default.post(
                    name: .feishuDidImport,
                    object: nil,
                    userInfo: ["chats": chatCount, "messages": messageCount]
                )
            }
        }
        if pending {
            pending = false
            importNow()
        }
    }
}

/// Invisible WKWebView that holds the Feishu web session and runs the scraper.
struct FeishuSyncView: NSViewRepresentable {
    func makeNSView(context: Context) -> WKWebView {
        FeishuWebHost.start()
        let webView = FeishuWebHost.webView
        if webView.superview != nil { webView.removeFromSuperview() }
        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {}
}

// MARK: - Import progress

struct SyncProgressView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.palette) private var p

    var body: some View {
        ZStack {
            WindowDragArea()
            VStack(spacing: 14) {
                ProgressView()
                    .controlSize(.large)
                Text("Importing your Feishu workspace")
                    .font(.system(size: 19, weight: .bold))
                    .foregroundColor(p.textPrimary)
                Text(model.syncStatus.isEmpty
                     ? "Opening your signed-in Feishu session and reading your conversations…"
                     : model.syncStatus)
                    .font(.system(size: 12))
                    .foregroundColor(p.textSecondary)
                    .multilineTextAlignment(.center)
                if model.syncChats > 0 {
                    Text("\(model.syncChats) conversations · \(model.syncMessages) messages in the Rust core")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(p.accent)
                }
                Text("The window you see next is native SwiftUI. The web client runs offscreen only to read your data; the Rust core stores it locally.")
                    .font(.system(size: 10.5))
                    .foregroundColor(p.textMuted)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 380)
                Button("Sign in again") { model.handleSessionExpired() }
                    .buttonStyle(.plain)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(p.textSecondary)
                    .padding(.top, 4)
            }
            .padding(34)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(p.content)
    }
}

// MARK: - Title bar

struct TitleBar: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.palette) private var p
    @State private var hoverSearch = false

    /// Imported workspaces do not expose a member count, so only mention it when
    /// it is actually known.
    private var workspaceSubtitle: String {
        let plan = model.workspace?.plan ?? "Team"
        let members = model.workspace?.members ?? 0
        return members > 0 ? "\(plan) · \(members) members" : plan
    }

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
                        Text(workspaceSubtitle)
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
