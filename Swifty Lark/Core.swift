import Foundation

// MARK: - Wire models (mirrors the Rust core's JSON)

struct LarkUser: Codable {
    var id: String
    var name: String
    var title: String
    var email: String
    var avatarText: String
    var hue: Int
}

struct LarkWorkspace: Codable {
    var name: String
    var plan: String
    var members: Int
}

struct Reaction: Codable, Hashable {
    var emoji: String
    var count: Int
    var mine: Bool
}

struct Attachment: Codable, Hashable {
    var kind: String
    var name: String
    var detail: String
}

struct LarkMessage: Codable, Identifiable, Hashable {
    var id: String
    var sender: String
    var senderId: String
    var text: String
    var ts: Double
    var mine: Bool
    var system: Bool
    var reactions: [Reaction]
    var attachment: Attachment?
    var edited: Bool
}

struct LarkChat: Codable, Identifiable, Hashable {
    var id: String
    var name: String
    var kind: String
    var avatarText: String
    var hue: Int
    var members: [String]
    var unread: Int
    var muted: Bool
    var pinned: Bool
    var typing: Bool
    var topic: String
    var messages: [LarkMessage]
    var lastTs: Double
    var preview: String

    var isGroup: Bool { kind == "group" }
}

struct LarkContact: Codable, Identifiable, Hashable {
    var id: String
    var name: String
    var title: String
    var dept: String
    var status: String
    var email: String
    var phone: String
    var timezone: String
    var avatarText: String
    var hue: Int
    var bio: String
}

struct LarkDoc: Codable, Identifiable, Hashable {
    var id: String
    var title: String
    var kind: String
    var owner: String
    var updated: Double
    var minutesAgo: Double?
    var snippet: String
    var shared: Bool
}

struct LarkEvent: Codable, Identifiable, Hashable {
    var id: String
    var title: String
    var dayOffset: Int
    var startMin: Int
    var endMin: Int
    var location: String
    var attendees: [String]
    var colorKey: String
}

struct LarkTask: Codable, Identifiable, Hashable {
    var id: String
    var title: String
    var done: Bool
    var due: String
    var list: String
    var assignee: String
}

struct LarkPrefs: Codable, Hashable {
    var theme: String
    var notifications: Bool
    var sendWithEnter: Bool
    var compact: Bool
}

struct CoreInfo: Codable, Hashable {
    var rssMb: Double
    var version: String
}

struct CoreStats: Codable, Hashable {
    var rssMb: Double
    var pid: Int
    var threads: Int
    var chats: Int
    var messages: Int
    var contacts: Int
    var docs: Int
    var storeBytes: Double
    var uptimeSecs: Double
    var engine: String
}

struct StatePayload: Codable {
    var user: LarkUser
    var workspace: LarkWorkspace
    var imported: Bool?
    var source: String?
    var chats: [LarkChat]
    var contacts: [LarkContact]
    var docs: [LarkDoc]
    var events: [LarkEvent]
    var tasks: [LarkTask]
    var prefs: LarkPrefs
    var now: Double
    var core: CoreInfo
}

struct SearchHit: Codable, Identifiable, Hashable {
    var kind: String
    var title: String
    var subtitle: String
    var chatId: String?
    var messageId: String?
    var contactId: String?
    var docId: String?
    var taskId: String?
    var hue: Int?
    var avatar: String?

    var id: String { (chatId ?? "") + (messageId ?? "") + (contactId ?? "") + (docId ?? "") + (taskId ?? "") + title + subtitle }
}

struct SearchPayload: Codable {
    var results: [SearchHit]
    var query: String
}

// MARK: - Core client (owns the Rust subprocess)

final class CoreClient {
    static let shared = CoreClient()

    private var process: Process?
    private let stdinPipe = Pipe()
    private let stdoutPipe = Pipe()
    private let lock = NSLock()
    private var nextId = 1
    private var buffer = Data()
    private(set) var isRunning = false
    private(set) var launchError: String?
    private(set) var binaryPath: String?

    private init() {
        start()
    }

    private func candidatePaths() -> [String] {
        var candidates: [String] = []
        if let env = ProcessInfo.processInfo.environment["SWIFTYLARK_CORE"], !env.isEmpty {
            candidates.append(env)
        }
        if let res = Bundle.main.resourceURL {
            candidates.append(res.appendingPathComponent("swiftylark-core").path)
            candidates.append(res.appendingPathComponent("SwiftyLarkCore").path)
        }
        let exeDir = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent()
        var dir = exeDir
        for _ in 0..<6 {
            candidates.append(dir.appendingPathComponent("swiftylark-core").path)
            candidates.append(dir.appendingPathComponent("rust/target/release/swiftylark-core").path)
            candidates.append(dir.appendingPathComponent("app/rust/target/release/swiftylark-core").path)
            dir = dir.deletingLastPathComponent()
        }
        candidates.append(FileManager.default.currentDirectoryPath + "/rust/target/release/swiftylark-core")
        return candidates
    }

    private func start() {
        let fm = FileManager.default
        guard let path = candidatePaths().first(where: { fm.isExecutableFile(atPath: $0) }) else {
            launchError = "Swifty Lark's core is missing from the app bundle."
            return
        }
        binaryPath = path
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.standardInput = stdinPipe
        p.standardOutput = stdoutPipe
        p.standardError = FileHandle.nullDevice
        do {
            try p.run()
            process = p
            isRunning = true
        } catch {
            launchError = error.localizedDescription
        }
    }

    /// One request at a time; called from background threads only.
    func call(_ cmd: String, _ params: [String: Any] = [:]) -> [String: Any]? {
        lock.lock()
        defer { lock.unlock() }
        guard let process, process.isRunning else { return nil }
        let id = nextId
        nextId += 1
        let request: [String: Any] = ["id": id, "cmd": cmd, "params": params]
        guard let data = try? JSONSerialization.data(withJSONObject: request),
              var line = String(data: data, encoding: .utf8) else { return nil }
        line += "\n"
        stdinPipe.fileHandleForWriting.write(Data(line.utf8))

        buffer.removeAll()
        while true {
            var chunk = Data()
            let deadline = Date().addingTimeInterval(5)
            repeat {
                let avail = stdoutPipe.fileHandleForReading.availableData
                if avail.isEmpty {
                    if Date() > deadline { return nil }
                    usleep(2000)
                    continue
                }
                chunk.append(avail)
            } while !chunk.contains(0x0A)
            buffer.append(chunk)
            guard let newline = buffer.firstIndex(of: 0x0A) else { continue }
            let lineData = buffer[..<newline]
            buffer = buffer[(newline + 1)...]
            guard let obj = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any] else { continue }
            if (obj["id"] as? Int) == id { return obj }
        }
    }

    func state() -> StatePayload? {
        guard let resp = call("state"), (resp["ok"] as? Bool) == true,
              let data = resp["data"] else { return nil }
        return decode(StatePayload.self, from: data)
    }

    func send(chatId: String, text: String) -> LarkChat? {
        guard let resp = call("send", ["chatId": chatId, "text": text]),
              let data = resp["data"] as? [String: Any] else { return nil }
        return decode(LarkChat.self, from: data["chat"] ?? [:])
    }

    func markRead(chatId: String) {
        _ = call("read", ["chatId": chatId])
    }

    func react(chatId: String, messageId: String, emoji: String) -> LarkChat? {
        guard let resp = call("react", ["chatId": chatId, "messageId": messageId, "emoji": emoji]),
              let data = resp["data"] as? [String: Any] else { return nil }
        return decode(LarkChat.self, from: data["chat"] ?? [:])
    }

    func toggleTask(id: String) -> LarkTask? {
        guard let resp = call("toggle_task", ["id": id]),
              let data = resp["data"] as? [String: Any] else { return nil }
        return decode(LarkTask.self, from: data["task"] ?? [:])
    }

    func addTask(title: String) -> LarkTask? {
        guard let resp = call("add_task", ["title": title]),
              let data = resp["data"] as? [String: Any] else { return nil }
        return decode(LarkTask.self, from: data["task"] ?? [:])
    }

    func setPrefs(_ params: [String: Any]) -> LarkPrefs? {
        guard let resp = call("set_prefs", params),
              let data = resp["data"] as? [String: Any] else { return nil }
        return decode(LarkPrefs.self, from: data["prefs"] ?? [:])
    }

    func search(_ query: String) -> [SearchHit] {
        guard let resp = call("search", ["query": query]),
              let data = resp["data"] else { return [] }
        return decode(SearchPayload.self, from: data)?.results ?? []
    }

    func stats() -> CoreStats? {
        guard let resp = call("stats"), (resp["ok"] as? Bool) == true else { return nil }
        return decode(CoreStats.self, from: resp["data"] ?? [:])
    }

    /// Replaces the core's workspace with real data scraped from Feishu's web
    /// client. Returns the import summary (chat/message counts) on success.
    func importWorkspace(_ payload: [String: Any]) -> [String: Any]? {
        guard let resp = call("import", payload), (resp["ok"] as? Bool) == true else { return nil }
        return resp["data"] as? [String: Any]
    }

    private func decode<T: Decodable>(_ type: T.Type, from any: Any) -> T? {
        guard JSONSerialization.isValidJSONObject(any),
              let data = try? JSONSerialization.data(withJSONObject: any) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }
}

// MARK: - App state

enum SidebarTab: String, CaseIterable, Identifiable {
    case messages, calendar, docs, contacts, tasks
    var id: String { rawValue }

    var title: String {
        switch self {
        case .messages: return "Messages"
        case .calendar: return "Calendar"
        case .docs: return "Docs"
        case .contacts: return "Contacts"
        case .tasks: return "Tasks"
        }
    }

    var symbol: String {
        switch self {
        case .messages: return "bubble.left.and.bubble.right.fill"
        case .calendar: return "calendar"
        case .docs: return "doc.text.fill"
        case .contacts: return "person.2.fill"
        case .tasks: return "checkmark.circle"
        }
    }
}

@MainActor
final class AppModel: ObservableObject {
    @Published var user: LarkUser?
    @Published var workspace: LarkWorkspace?
    @Published var chats: [LarkChat] = []
    @Published var contacts: [LarkContact] = []
    @Published var docs: [LarkDoc] = []
    @Published var events: [LarkEvent] = []
    @Published var tasks: [LarkTask] = []
    // Defaults come from app/mechanics.json: notifySetting.notifySound = true
    // and shortcut.send = "Enter" (the first phrase of the "send key" value).
    @Published var prefs = LarkPrefs(
        theme: "dark",
        notifications: MechanicsSheet.shared.flag("notification sound default", true),
        sendWithEnter: MechanicsSheet.shared.text("send key", "Return sends").hasPrefix("Return sends"),
        compact: false
    )
    @Published var coreInfo: CoreInfo?
    @Published var stats: CoreStats?

    @Published var tab: SidebarTab = .messages
    @Published var selectedChatID: String?
    @Published var selectedContactID: String?
    @Published var selectedDocID: String?
    @Published var selectedDayOffset: Int = 0
    @Published var filter: ChatFilter = .all
    @Published var query: String = ""
    @Published var composer: String = ""
    @Published var searchOpen = false
    @Published var searchQuery = ""
    @Published var searchHits: [SearchHit] = []
    @Published var showSettings = false
    @Published var loading = true
    @Published var toast: String?
    /// True once the core holds a workspace imported from the real Feishu web
    /// client. Until then the app shows the import screen instead of demo data.
    @Published var imported = false
    @Published var syncStatus = ""
    @Published var syncChats = 0
    @Published var syncMessages = 0
    /// Ask the sign-in screen to open Feishu's login page (launch and expired
    /// sessions), so the user lands in their real account without hunting for a
    /// button.
    @Published var loginRequested = false
    /// Set once Feishu's own login page has completed inside the app (MeloX-style
    /// cookie login). The flag is kept so the persisted Feishu session is reused
    /// on the next launch instead of asking to log in again.
    @Published var signedIn = UserDefaults.standard.bool(forKey: AppModel.signedInKey)

    static let signedInKey = "feishu.signedIn"

    enum ChatFilter: String, CaseIterable, Identifiable {
        case all = "All"
        case unread = "Unread"
        case groups = "Groups"
        var id: String { rawValue }
    }

    private var refreshTimer: DispatchSourceTimer?

    init() {
        let args = CommandLine.arguments
        if let tabArg = args.first(where: { $0.hasPrefix("--tab=") }) {
            let name = String(tabArg.dropFirst("--tab=".count))
            if let t = SidebarTab(rawValue: name) { tab = t }
        }
        if args.contains("--settings") { showSettings = true }
        if let i = args.firstIndex(of: "--search"), i + 1 < args.count {
            searchOpen = true
            searchQuery = args[i + 1]
            runSearch(args[i + 1])
        }
        // No default workspace: nothing is read from the core until the user
        // has signed in, so the app opens on the sign-in screen instead.
        if signedIn { load() }
        // On launch (and after a Feishu session expires) open the login page
        // right away, so signing in is the first thing the app does.
        if !signedIn && !args.contains(where: { $0.hasPrefix("--screenshot") }) && !args.contains("--selftest") {
            loginRequested = true
        }
        NotificationCenter.default.addObserver(forName: .feishuDidImport, object: nil, queue: .main) { [weak self] note in
            Task { @MainActor in
                guard let self else { return }
                if let c = note.userInfo?["chats"] as? Int { self.syncChats = c }
                if let m = note.userInfo?["messages"] as? Int { self.syncMessages = m }
                self.load()
            }
        }
        NotificationCenter.default.addObserver(forName: .feishuSyncStatus, object: nil, queue: .main) { [weak self] note in
            Task { @MainActor in self?.syncStatus = note.userInfo?["text"] as? String ?? "" }
        }
        NotificationCenter.default.addObserver(forName: .feishuSessionExpired, object: nil, queue: .main) { [weak self] _ in
            print("SWIFTYLARK: session expired notification received")
            Task { @MainActor in self?.handleSessionExpired() }
        }
        // The shared web view reached the tenant messenger with a real session.
        NotificationCenter.default.addObserver(forName: .feishuBrowserSignedIn, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                guard let self, !self.signedIn else { return }
                self.completeSignIn()
            }
        }
        // keep the list times fresh and pick up core-side changes
        let t = DispatchSource.makeTimerSource(queue: .main)
        t.schedule(deadline: .now() + 30, repeating: 30)
        t.setEventHandler { [weak self] in
            guard let self, self.signedIn else { return }
            self.refreshQuietly()
        }
        t.resume()
        refreshTimer = t
    }

    var selectedChat: LarkChat? {
        chats.first { $0.id == selectedChatID }
    }

    var unreadTotal: Int {
        chats.reduce(0) { $0 + $1.unread }
    }

    var visibleChats: [LarkChat] {
        var list = chats
        switch filter {
        case .all: break
        case .unread: list = list.filter { $0.unread > 0 }
        case .groups: list = list.filter { $0.isGroup }
        }
        if !query.trimmingCharacters(in: .whitespaces).isEmpty {
            let q = query.lowercased()
            list = list.filter { $0.name.lowercased().contains(q) || $0.preview.lowercased().contains(q) }
        }
        return list
    }

    func load() {
        DispatchQueue.global(qos: .userInitiated).async {
            let payload = CoreClient.shared.state()
            let st = CoreClient.shared.stats()
            DispatchQueue.main.async {
                if let payload {
                    self.apply(payload)
                }
                self.stats = st
                self.loading = false
            }
        }
    }

    func refreshQuietly() {
        DispatchQueue.global(qos: .utility).async {
            let payload = CoreClient.shared.state()
            let st = CoreClient.shared.stats()
            DispatchQueue.main.async {
                guard let payload else { return }
                self.apply(payload, keepSelection: true)
                self.stats = st
            }
        }
    }

    /// Feishu's login page reached the tenant messenger inside the login sheet.
    func completeSignIn() {
        if CommandLine.arguments.contains("--capture") {
            FeishuCapture.append(["url": "SYNC-LOG completeSignIn", "body": ""])
        }
        UserDefaults.standard.set(true, forKey: AppModel.signedInKey)
        signedIn = true
        load()
    }

    /// The persisted Feishu session was rejected (the web client redirected to
    /// accounts.feishu.cn). Keep the shared web view's cookies — its refresh
    /// page may still be able to renew them — and show Feishu's login page in
    /// the same web view so the user can re-authenticate.
    func handleSessionExpired() {
        if CommandLine.arguments.contains("--capture") {
            FeishuCapture.append(["url": "SYNC-LOG handleSessionExpired", "body": ""])
        }
        guard signedIn else { return }
        UserDefaults.standard.set(false, forKey: AppModel.signedInKey)
        signedIn = false
        imported = false
        chats = []
        syncStatus = ""
        FeishuSession.clear()
        FeishuWebHost.beginLogin()
        loginRequested = true
    }

    var hasImportedWorkspace: Bool { imported && !chats.isEmpty }

    private func apply(_ p: StatePayload, keepSelection: Bool = false) {
        user = p.user
        workspace = p.workspace
        imported = p.imported ?? false
        chats = p.chats
        contacts = p.contacts
        docs = p.docs
        events = p.events
        tasks = p.tasks
        prefs = p.prefs
        coreInfo = p.core
        if !keepSelection || selectedChatID == nil {
            if selectedChatID == nil {
                selectedChatID = p.chats.first(where: { $0.pinned })?.id ?? p.chats.first?.id
            }
        }
        if selectedContactID == nil { selectedContactID = p.contacts.first?.id }
        if selectedDocID == nil { selectedDocID = p.docs.first?.id }
    }

    func select(chat id: String) {
        selectedChatID = id
        tab = .messages
        composer = ""
        if let chat = chats.first(where: { $0.id == id }), chat.unread > 0 {
            if let idx = chats.firstIndex(where: { $0.id == id }) {
                chats[idx].unread = 0
            }
            DispatchQueue.global(qos: .userInitiated).async {
                CoreClient.shared.markRead(chatId: id)
            }
        }
    }

    func sendCurrent() {
        let text = composer.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, let chatID = selectedChatID else { return }
        composer = ""
        DispatchQueue.global(qos: .userInitiated).async {
            let updated = CoreClient.shared.send(chatId: chatID, text: text)
            DispatchQueue.main.async {
                guard let updated else { return }
                if let idx = self.chats.firstIndex(where: { $0.id == updated.id }) {
                    self.chats[idx] = updated
                }
                self.resort()
            }
        }
    }

    func toggleReaction(chatID: String, messageID: String, emoji: String) {
        DispatchQueue.global(qos: .userInitiated).async {
            let updated = CoreClient.shared.react(chatId: chatID, messageId: messageID, emoji: emoji)
            DispatchQueue.main.async {
                guard let updated, let idx = self.chats.firstIndex(where: { $0.id == updated.id }) else { return }
                self.chats[idx] = updated
            }
        }
    }

    func toggleTask(_ id: String) {
        guard let idx = tasks.firstIndex(where: { $0.id == id }) else { return }
        tasks[idx].done.toggle()
        DispatchQueue.global(qos: .userInitiated).async {
            let updated = CoreClient.shared.toggleTask(id: id)
            DispatchQueue.main.async {
                guard let updated, let i = self.tasks.firstIndex(where: { $0.id == updated.id }) else { return }
                self.tasks[i] = updated
            }
        }
    }

    func addTask(_ title: String) {
        guard !title.isEmpty else { return }
        DispatchQueue.global(qos: .userInitiated).async {
            let t = CoreClient.shared.addTask(title: title)
            DispatchQueue.main.async { if let t { self.tasks.insert(t, at: 0) } }
        }
    }

    func runSearch(_ q: String) {
        let trimmed = q.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty {
            searchHits = []
            return
        }
        DispatchQueue.global(qos: .userInitiated).async {
            let hits = CoreClient.shared.search(trimmed)
            DispatchQueue.main.async {
                if self.searchQuery == q { self.searchHits = hits }
            }
        }
    }

    func open(hit: SearchHit) {
        searchOpen = false
        switch hit.kind {
        case "message", "chat":
            if let id = hit.chatId { select(chat: id) }
        case "person":
            tab = .contacts
            selectedContactID = hit.contactId
        case "doc":
            tab = .docs
            selectedDocID = hit.docId
        case "task":
            tab = .tasks
        default:
            break
        }
    }

    func setTheme(_ theme: String) {
        prefs.theme = theme
        DispatchQueue.global(qos: .utility).async { _ = CoreClient.shared.setPrefs(["theme": theme]) }
    }

    func togglePref(_ key: String, _ value: Bool) {
        DispatchQueue.global(qos: .utility).async { _ = CoreClient.shared.setPrefs([key: value]) }
    }

    private func resort() {
        chats.sort { a, b in
            if a.pinned != b.pinned { return a.pinned }
            return a.lastTs > b.lastTs
        }
    }

    func contact(id: String?) -> LarkContact? {
        guard let id else { return nil }
        return contacts.first { $0.id == id }
    }
}

extension Notification.Name {
    static let feishuDidImport = Notification.Name("swiftylark.feishu.imported")
    static let feishuSyncStatus = Notification.Name("swiftylark.feishu.syncStatus")
    static let feishuSessionExpired = Notification.Name("swiftylark.feishu.sessionExpired")
    static let feishuProfileUpdated = Notification.Name("swiftylark.feishu.profile")
    static let feishuBrowserSignedIn = Notification.Name("swiftylark.feishu.browserSignedIn")
}
