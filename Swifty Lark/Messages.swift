import SwiftUI
import AppKit

struct MessagesScreen: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.palette) private var p

    var body: some View {
        HStack(spacing: 0) {
            ChatListColumn()
                .frame(width: p.conversationListWidth)
            Rectangle().fill(p.borderSoft).frame(width: 1)
            if let chat = model.selectedChat {
                ChatDetail(chat: chat)
                    .id(chat.id)
            } else {
                EmptyDetail()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(p.content)
    }
}

// MARK: - Chat list

struct ChatListColumn: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.palette) private var p

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Messages")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundColor(p.textPrimary)
                if model.unreadTotal > 0 {
                    Text("\(model.unreadTotal)")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(p.textSecondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1.5)
                        .background(Capsule().fill(p.dark ? Color.white.opacity(0.07) : Color.black.opacity(0.06)))
                }
                Spacer()
                IconButton(symbol: "square.and.pencil", help: "New message") {}
            }
            .padding(.horizontal, 14)
            .padding(.top, 14)
            .padding(.bottom, 10)

            SearchField(text: $model.query, placeholder: "Search")
                .padding(.horizontal, 12)
                .padding(.bottom, 10)

            HStack(spacing: 6) {
                ForEach(AppModel.ChatFilter.allCases) { f in
                    FilterChip(title: f.rawValue, selected: model.filter == f) {
                        model.filter = f
                    }
                }
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 8)

            DividerLine()

            ScrollView {
                LazyVStack(spacing: 1) {
                    ForEach(model.visibleChats) { chat in
                        ChatRow(chat: chat, selected: model.selectedChatID == chat.id) {
                            model.select(chat: chat.id)
                        }
                    }
                }
                .padding(.vertical, 6)
            }
            .scrollIndicators(.hidden)

            HStack(spacing: 6) {
                Image(systemName: "bolt.horizontal.circle")
                    .font(.system(size: 11))
                    .foregroundColor(p.accent)
                Text("\(model.stats?.messages ?? 0) messages held by the Rust core")
                    .font(.system(size: 10))
                    .foregroundColor(p.textMuted)
                    .lineLimit(1)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .top) { DividerLine() }
        }
        .background(p.list)
    }
}

struct FilterChip: View {
    var title: String
    var selected: Bool
    var action: () -> Void
    @Environment(\.palette) private var p
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11, weight: selected ? .semibold : .regular))
                .foregroundColor(selected ? p.accent : p.textSecondary)
                .padding(.horizontal, 9)
                .padding(.vertical, 3.5)
                .background(
                    Capsule().fill(selected ? p.accentSoft : (hovering ? p.hover : Color.clear))
                )
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

struct SearchField: View {
    @Binding var text: String
    var placeholder: String
    @Environment(\.palette) private var p
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11))
                .foregroundColor(p.textMuted)
            TextField("", text: $text, prompt: Text(placeholder).foregroundColor(p.textMuted))
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .foregroundColor(p.textPrimary)
                .focused($focused)
            if !text.isEmpty {
                Button { text = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 10))
                        .foregroundColor(p.textMuted)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 8)
        .frame(height: 28)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(p.dark ? Color.white.opacity(0.05) : Color.black.opacity(0.035))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .strokeBorder(focused ? p.accent.opacity(0.6) : p.borderSoft, lineWidth: 1)
        )
    }
}

struct ChatRow: View {
    var chat: LarkChat
    var selected: Bool
    var action: () -> Void
    @Environment(\.palette) private var p
    @EnvironmentObject var model: AppModel
    @State private var hovering = false

    private var preview: String {
        guard let last = chat.messages.last else { return "No messages yet" }
        if last.system { return last.text }
        if last.mine { return "You: \(last.text)" }
        if chat.isGroup { return "\(last.sender.split(separator: " ").first ?? "")：\(last.text)" }
        return last.text
    }

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 9) {
                ZStack(alignment: .bottomTrailing) {
                    AvatarView(text: chat.avatarText, hue: chat.hue, size: 38, rounded: chat.isGroup || chat.kind == "bot")
                    if !chat.isGroup, let contact = model.contacts.first(where: { contact in
                        chat.name.hasPrefix(contact.name)
                    }) {
                        StatusDot(status: contact.status)
                            .offset(x: 1, y: 1)
                    }
                }
                .padding(.top, 1)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 4) {
                        Text(chat.name)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(p.textPrimary)
                            .lineLimit(1)
                        if chat.muted {
                            Image(systemName: "bell.slash.fill")
                                .font(.system(size: 8))
                                .foregroundColor(p.textMuted)
                        }
                        Spacer(minLength: 4)
                        Text(TimeFmt.short(chat.lastTs))
                            .font(.system(size: 10))
                            .foregroundColor(p.textMuted)
                    }
                    HStack(spacing: 4) {
                        if chat.typing {
                            Text("typing…")
                                .font(.system(size: 11))
                                .foregroundColor(p.accent)
                        } else {
                            Text(preview)
                                .font(.system(size: 11))
                                .foregroundColor(p.textMuted)
                                .lineLimit(1)
                        }
                        Spacer(minLength: 4)
                        if chat.unread > 0 {
                            Text(chat.unread > 99 ? "99+" : "\(chat.unread)")
                                .font(.system(size: 9.5, weight: .semibold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 5)
                                .frame(minWidth: 16, minHeight: 16)
                                .background(Capsule().fill(p.danger))
                        }
                    }
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(selected ? p.selected : (hovering ? p.hover : Color.clear))
            )
            .padding(.horizontal, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

// MARK: - Conversation

struct ChatDetail: View {
    var chat: LarkChat
    @EnvironmentObject var model: AppModel
    @Environment(\.palette) private var p

    private var onlineCount: Int {
        model.contacts.filter { $0.status == "online" && chat.members.contains($0.name) }.count
    }

    private var subtitle: String {
        if chat.typing { return "typing…" }
        if chat.isGroup {
            return "\(chat.members.count) members · \(onlineCount) online"
        }
        if let c = model.contacts.first(where: { chat.name.hasPrefix($0.name) }) {
            return c.status == "online" ? "Active now · \(c.title)" : c.title
        }
        return chat.topic
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 9) {
                AvatarView(text: chat.avatarText, hue: chat.hue, size: 28, rounded: chat.isGroup || chat.kind == "bot")
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 5) {
                        Text(chat.name)
                            .font(.system(size: 13.5, weight: .semibold))
                            .foregroundColor(p.textPrimary)
                        if chat.pinned {
                            Image(systemName: "pin.fill")
                                .font(.system(size: 8))
                                .foregroundColor(p.textMuted)
                        }
                    }
                    Text(subtitle)
                        .font(.system(size: 10.5))
                        .foregroundColor(chat.typing ? p.accent : p.textMuted)
                }
                Spacer()
                IconButton(symbol: "magnifyingglass", help: "Search in conversation") {}
                IconButton(symbol: "video", help: "Start video call") {}
                IconButton(symbol: "phone", help: "Start call") {}
                IconButton(symbol: "person.badge.plus", help: "Add people") {}
                IconButton(symbol: "ellipsis", help: "More") {}
            }
            .padding(.horizontal, 16)
            .frame(height: 56)
            .background(p.list)

            DividerLine()

            MessageList(chat: chat)

            ComposerView(chat: chat)
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 14)
        }
        .background(p.content)
    }
}

struct MessageList: View {
    var chat: LarkChat
    @EnvironmentObject var model: AppModel
    @Environment(\.palette) private var p

    private var groups: [(day: Date, items: [LarkMessage])] {
        let cal = Calendar.current
        var out: [(Date, [LarkMessage])] = []
        for m in chat.messages {
            let day = cal.startOfDay(for: Date(timeIntervalSince1970: m.ts))
            if let last = out.last, cal.isDate(last.0, inSameDayAs: day) {
                out[out.count - 1].1.append(m)
            } else {
                out.append((day, [m]))
            }
        }
        return out.map { (day: $0.0, items: $0.1) }
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(groups, id: \.day) { group in
                        HStack {
                            Spacer()
                            Text(TimeFmt.dayHeader(group.day))
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(p.textMuted)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Capsule().fill(p.dark ? Color.white.opacity(0.04) : Color.black.opacity(0.04)))
                            Spacer()
                        }
                        .padding(.vertical, 10)

                        ForEach(Array(group.items.enumerated()), id: \.element.id) { index, message in
                            if message.system {
                                Text(message.text)
                                    .font(.system(size: 10))
                                    .foregroundColor(p.textMuted)
                                    .padding(.vertical, 5)
                                    .frame(maxWidth: .infinity)
                            } else {
                                MessageRow(
                                    chat: chat,
                                    message: message,
                                    showName: chat.isGroup && !message.mine,
                                    showAvatar: index == group.items.count - 1 || group.items[index].sender != group.items[index + 1].sender
                                )
                                .id(message.id)
                            }
                        }
                    }
                    Color.clear.frame(height: 8).id("bottom")
                }
                .padding(.horizontal, 22)
                .padding(.top, 4)
            }
            .scrollIndicators(.hidden)
            .background(p.content)
            .onAppear { proxy.scrollTo("bottom", anchor: .bottom) }
            .onChange(of: chat.id) { _ in proxy.scrollTo("bottom", anchor: .bottom) }
            .onChange(of: chat.messages.count) { _ in
                withAnimation(.easeOut(duration: 0.15)) { proxy.scrollTo("bottom", anchor: .bottom) }
            }
        }
    }
}

struct MessageRow: View {
    var chat: LarkChat
    var message: LarkMessage
    var showName: Bool
    var showAvatar: Bool
    @EnvironmentObject var model: AppModel
    @Environment(\.palette) private var p

    private var contact: LarkContact? {
        model.contacts.first { $0.name == message.sender }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            if message.mine {
                Spacer(minLength: 60)
            } else if showAvatar {
                AvatarView(text: String(message.sender.prefix(1)), hue: contact?.hue ?? 200, size: 30, rounded: false)
            } else {
                Color.clear.frame(width: 30, height: 1)
            }

            VStack(alignment: message.mine ? .trailing : .leading, spacing: 3) {
                if showName {
                    HStack(spacing: 5) {
                        Text(message.sender)
                            .font(.system(size: 10.5, weight: .medium))
                            .foregroundColor(p.textSecondary)
                        Text(TimeFmt.clock(message.ts))
                            .font(.system(size: 9.5))
                            .foregroundColor(p.textMuted)
                    }
                } else if message.mine {
                    Text(TimeFmt.clock(message.ts))
                        .font(.system(size: 9.5))
                        .foregroundColor(p.textMuted)
                }

                if !message.text.isEmpty {
                    Text(message.text)
                        .font(.system(size: p.messageTextSize))
                        .foregroundColor(message.mine ? p.bubbleMineText : p.bubbleOtherText)
                        .textSelection(.enabled)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(
                            RoundedRectangle(cornerRadius: p.cornerRadius, style: .continuous)
                                .fill(message.mine ? p.bubbleMine : p.bubbleOther)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: p.cornerRadius, style: .continuous)
                                .strokeBorder(message.mine ? Color.clear : p.borderSoft, lineWidth: 1)
                        )
                        .frame(maxWidth: 520, alignment: message.mine ? .trailing : .leading)
                }

                if let att = message.attachment {
                    HStack(spacing: 9) {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(p.accentSoft)
                            .frame(width: 30, height: 34)
                            .overlay(Image(systemName: att.kind == "image" ? "photo" : "doc.text.fill")
                                .font(.system(size: 13))
                                .foregroundColor(p.accent))
                        VStack(alignment: .leading, spacing: 1) {
                            Text(att.name)
                                .font(.system(size: 11.5, weight: .medium))
                                .foregroundColor(p.textPrimary)
                                .lineLimit(1)
                            Text(att.detail)
                                .font(.system(size: 10))
                                .foregroundColor(p.textMuted)
                        }
                        Spacer(minLength: 10)
                        Image(systemName: "arrow.down.circle")
                            .font(.system(size: 13))
                            .foregroundColor(p.textMuted)
                    }
                    .padding(8)
                    .frame(width: 260)
                    .background(RoundedRectangle(cornerRadius: 9).fill(p.elevated))
                    .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(p.borderSoft, lineWidth: 1))
                }

                if !message.reactions.isEmpty {
                    HStack(spacing: 4) {
                        ForEach(message.reactions, id: \.emoji) { r in
                            Button {
                                model.toggleReaction(chatID: chat.id, messageID: message.id, emoji: r.emoji)
                            } label: {
                                HStack(spacing: 3) {
                                    Text(r.emoji).font(.system(size: 10))
                                    Text("\(r.count)")
                                        .font(.system(size: 9.5, weight: .medium))
                                        .foregroundColor(r.mine ? p.accent : p.textSecondary)
                                }
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2.5)
                                .background(
                                    Capsule().fill(r.mine ? p.accentSoft : (p.dark ? Color.white.opacity(0.05) : Color.black.opacity(0.04)))
                                )
                                .overlay(Capsule().strokeBorder(r.mine ? p.accent.opacity(0.5) : Color.clear, lineWidth: 1))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.top, 1)
                }
            }

            if message.mine && showAvatar {
                AvatarView(text: model.user?.avatarText ?? "W", hue: model.user?.hue ?? 214, size: 30, rounded: false)
            } else if message.mine {
                Color.clear.frame(width: 30, height: 1)
            }
            if !message.mine {
                Spacer(minLength: 60)
            }
        }
        .padding(.vertical, 5)
        .contextMenu {
            Button("Copy text") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(message.text, forType: .string)
            }
            Button("React 👍") {
                model.toggleReaction(chatID: chat.id, messageID: message.id, emoji: "👍")
            }
        }
    }
}

// MARK: - Composer

struct ComposerView: View {
    var chat: LarkChat
    @EnvironmentObject var model: AppModel
    @Environment(\.palette) private var p
    @FocusState private var focused: Bool

    private var canSend: Bool {
        !model.composer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 2) {
                ForEach(["bold", "italic", "underline", "strikethrough", "chevron.left.forwardslash.chevron.right", "link", "paperclip", "photo", "face.smiling", "at"], id: \.self) { symbol in
                    IconButton(symbol: symbol, help: symbol, size: 24) {
                        if symbol == "face.smiling" {
                            model.composer += model.composer.isEmpty ? "🙂 " : " 🙂"
                        }
                    }
                }
                Spacer()
                IconButton(symbol: "clock.arrow.circlepath", help: "Message history", size: 24) {}
            }
            .padding(.horizontal, 8)
            .padding(.top, 6)

            ZStack(alignment: .topLeading) {
                if model.composer.isEmpty {
                    Text("Message \(chat.name)")
                        .font(.system(size: 12.5))
                        .foregroundColor(p.textMuted)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .allowsHitTesting(false)
                }
                ComposerTextView(text: $model.composer,
                                 sendWithEnter: model.prefs.sendWithEnter,
                                 onSubmit: { model.sendCurrent() })
                    .frame(height: ComposerTextView.height(forLines: ComposerTextView.editorLines))
                    .padding(.horizontal, 4)
            }
            .padding(.top, 2)

            HStack(spacing: 8) {
                IconButton(symbol: "plus.circle", help: "More", size: 24) {}
                IconButton(symbol: "scissors", help: "Screenshot", size: 24) {}
                Spacer()
                Text(model.prefs.sendWithEnter ? "Return sends · Shift+Return adds a line" : "Return adds a line · ⌘Return sends")
                    .font(.system(size: 9.5))
                    .foregroundColor(p.textMuted)
                Button {
                    model.sendCurrent()
                } label: {
                    HStack(spacing: 4) {
                        Text("Send")
                            .font(.system(size: 11.5, weight: .semibold))
                        Image(systemName: "paperplane.fill")
                            .font(.system(size: 9))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .frame(height: 26)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(canSend ? p.accent : p.accent.opacity(0.35))
                    )
                }
                .buttonStyle(.plain)
                .disabled(!canSend)
                .keyboardShortcut(.return, modifiers: .command)
            }
            .padding(.horizontal, 9)
            .padding(.bottom, 7)
        }
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(p.elevated)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(focused ? p.accent.opacity(0.55) : p.borderSoft, lineWidth: 1)
        )
    }
}

struct ComposerTextView: NSViewRepresentable {
    @Binding var text: String
    var sendWithEnter: Bool = true
    var onSubmit: () -> Void
    @Environment(\.palette) private var p

    // Lark's own default: uiSetting.editorHeight = "3" (three lines), read from
    // app/mechanics.json instead of being repeated here.
    static var editorLines: CGFloat {
        CGFloat(MechanicsSheet.shared.number("composer editor height", 3))
    }

    static func height(forLines lines: CGFloat) -> CGFloat {
        let font = NSFont.systemFont(ofSize: 12.5)
        let lineHeight = ceil(font.ascender - font.descender + font.leading)
        return lineHeight * lines + 10
    }

    enum ReturnAction: String {
        case send, newline, ignore
    }

    /// Lark's shortcut rules: send = "Enter" by default, alternate "Command+Enter".
    /// Command+Return always sends; Shift/Option+Return always adds a line.
    static func returnAction(text: String, sendWithEnter: Bool,
                             command: Bool, shiftOrOption: Bool) -> ReturnAction {
        let empty = text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if command { return empty ? .ignore : .send }
        if shiftOrOption { return .newline }
        if sendWithEnter { return empty ? .ignore : .send }
        return .newline
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = false
        scroll.borderType = .noBorder
        guard let tv = scroll.documentView as? NSTextView else { return scroll }
        tv.delegate = context.coordinator
        tv.isRichText = false
        tv.drawsBackground = false
        tv.font = NSFont.systemFont(ofSize: 12.5)
        tv.textColor = NSColor(p.textPrimary)
        tv.insertionPointColor = NSColor(p.accent)
        tv.textContainerInset = NSSize(width: 6, height: 5)
        tv.isAutomaticQuoteSubstitutionEnabled = false
        tv.isAutomaticDashSubstitutionEnabled = false
        tv.allowsUndo = true
        if let container = tv.textContainer {
            container.widthTracksTextView = true
            container.lineFragmentPadding = 2
        }
        DispatchQueue.main.async { tv.window?.makeFirstResponder(tv) }
        return scroll
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let tv = nsView.documentView as? NSTextView else { return }
        context.coordinator.parent = self
        if tv.string != text { tv.string = text }
        tv.textColor = NSColor(p.textPrimary)
        tv.insertionPointColor = NSColor(p.accent)
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: ComposerTextView
        init(_ parent: ComposerTextView) { self.parent = parent }

        func textDidChange(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView else { return }
            parent.text = tv.string
        }

        func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                let flags = NSEvent.modifierFlags
                let action = ComposerTextView.returnAction(
                    text: parent.text,
                    sendWithEnter: parent.sendWithEnter,
                    command: flags.contains(.command),
                    shiftOrOption: flags.contains(.shift) || flags.contains(.option)
                )
                switch action {
                case .send:
                    parent.onSubmit()
                case .newline:
                    textView.insertNewlineIgnoringFieldEditor(nil)
                case .ignore:
                    break
                }
                return true
            }
            return false
        }
    }
}

struct EmptyDetail: View {
    @Environment(\.palette) private var p
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 34, weight: .light))
                .foregroundColor(p.textMuted.opacity(0.6))
            Text("Pick a conversation")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(p.textSecondary)
            Text("Your messages live in the local Rust core.")
                .font(.system(size: 11.5))
                .foregroundColor(p.textMuted)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(p.content)
    }
}
