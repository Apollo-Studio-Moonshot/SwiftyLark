import SwiftUI
import AppKit

// MARK: - Search overlay

struct SearchOverlay: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.palette) private var p
    @FocusState private var focused: Bool

    private var grouped: [(String, [SearchHit])] {
        let order = ["message", "chat", "person", "doc", "task"]
        var out: [(String, [SearchHit])] = []
        for kind in order {
            let items = model.searchHits.filter { $0.kind == kind }
            if !items.isEmpty { out.append((kind, items)) }
        }
        return out
    }

    private func label(_ kind: String) -> String {
        switch kind {
        case "message": return "Messages"
        case "chat": return "Conversations"
        case "person": return "People"
        case "doc": return "Docs"
        case "task": return "Tasks"
        default: return kind
        }
    }

    var body: some View {
        ZStack(alignment: .top) {
            Color.black.opacity(p.dark ? 0.55 : 0.25)
                .ignoresSafeArea()
                .onTapGesture { model.searchOpen = false }

            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(p.accent)
                    TextField("", text: $model.searchQuery, prompt: Text("Search messages, people, docs and tasks").foregroundColor(p.textMuted))
                        .textFieldStyle(.plain)
                        .font(.system(size: 14))
                        .foregroundColor(p.textPrimary)
                        .focused($focused)
                        .onChange(of: model.searchQuery) { q in
                            model.runSearch(q)
                        }
                    if !model.searchQuery.isEmpty {
                        Button { model.searchQuery = ""; model.searchHits = [] } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(p.textMuted)
                        }
                        .buttonStyle(.plain)
                    }
                    Text("esc")
                        .font(.system(size: 10, design: .rounded))
                        .foregroundColor(p.textMuted)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(RoundedRectangle(cornerRadius: 4).fill(p.dark ? Color.white.opacity(0.06) : Color.black.opacity(0.05)))
                }
                .padding(.horizontal, 14)
                .frame(height: 48)

                DividerLine()

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        if model.searchHits.isEmpty {
                            VStack(spacing: 8) {
                                Image(systemName: "magnifyingglass")
                                    .font(.system(size: 22, weight: .light))
                                    .foregroundColor(p.textMuted)
                                Text(model.searchQuery.isEmpty ? "Type to search everything you own" : "No results for “\(model.searchQuery)”")
                                    .font(.system(size: 12))
                                    .foregroundColor(p.textMuted)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 40)
                        }
                        ForEach(grouped, id: \.0) { section in
                            Text(label(section.0).uppercased())
                                .font(.system(size: 9.5, weight: .semibold))
                                .foregroundColor(p.textMuted)
                                .padding(.horizontal, 14)
                                .padding(.top, 12)
                                .padding(.bottom, 4)
                            ForEach(section.1) { hit in
                                SearchRow(hit: hit) { model.open(hit: hit) }
                            }
                        }
                    }
                    .padding(.bottom, 8)
                }
                .frame(maxHeight: 420)
                .scrollIndicators(.hidden)
            }
            .frame(width: 620)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous).fill(p.list)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(p.border, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .shadow(color: .black.opacity(0.35), radius: 30, y: 14)
            .padding(.top, 74)
        }
        .onAppear {
            focused = true
        }
        .onExitCommand { model.searchOpen = false }
    }
}

struct SearchRow: View {
    var hit: SearchHit
    var action: () -> Void
    @Environment(\.palette) private var p
    @State private var hovering = false

    private var icon: String {
        switch hit.kind {
        case "person": return "person.fill"
        case "doc": return "doc.text.fill"
        case "task": return "checkmark.circle"
        case "chat": return "bubble.left.and.bubble.right.fill"
        default: return "text.bubble"
        }
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                if let avatar = hit.avatar, let hue = hit.hue {
                    AvatarView(text: avatar, hue: hue, size: 28, rounded: true)
                } else {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(p.dark ? Color.white.opacity(0.06) : Color.black.opacity(0.05))
                        .frame(width: 28, height: 28)
                        .overlay(Image(systemName: icon).font(.system(size: 12)).foregroundColor(p.textSecondary))
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(hit.title)
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundColor(p.textPrimary)
                        .lineLimit(1)
                    Text(hit.subtitle)
                        .font(.system(size: 11))
                        .foregroundColor(p.textMuted)
                        .lineLimit(1)
                }
                Spacer()
                Image(systemName: "arrow.turn.down.right")
                    .font(.system(size: 9))
                    .foregroundColor(p.textMuted.opacity(hovering ? 1 : 0))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .background(hovering ? p.hover : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

// MARK: - Contacts

struct ContactsScreen: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.palette) private var p
    @State private var query = ""

    private var filtered: [LarkContact] {
        if query.isEmpty { return model.contacts }
        return model.contacts.filter { $0.name.lowercased().contains(query.lowercased()) || $0.dept.lowercased().contains(query.lowercased()) }
    }

    private var online: Int { model.contacts.filter { $0.status == "online" }.count }

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("Contacts")
                            .font(.system(size: 17, weight: .bold))
                            .foregroundColor(p.textPrimary)
                        Spacer()
                        IconButton(symbol: "person.badge.plus", help: "Invite people") {}
                    }
                    SearchField(text: $query, placeholder: "Search people")
                    Text("\(model.contacts.count) people · \(online) online")
                        .font(.system(size: 10.5))
                        .foregroundColor(p.textMuted)
                }
                .padding(14)
                DividerLine()
                ScrollView {
                    LazyVStack(spacing: 1) {
                        ForEach(filtered) { c in
                            ContactRow(contact: c, selected: model.selectedContactID == c.id) {
                                model.selectedContactID = c.id
                            }
                        }
                    }
                    .padding(.vertical, 6)
                    .padding(.horizontal, 6)
                }
                .scrollIndicators(.hidden)
            }
            .frame(width: 300)
            .background(p.list)

            Rectangle().fill(p.borderSoft).frame(width: 1)

            if let c = model.contact(id: model.selectedContactID) {
                ContactDetail(contact: c)
            } else {
                EmptyDetail()
            }
        }
        .background(p.content)
    }
}

struct ContactRow: View {
    var contact: LarkContact
    var selected: Bool
    var action: () -> Void
    @Environment(\.palette) private var p
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                ZStack(alignment: .bottomTrailing) {
                    AvatarView(text: contact.avatarText, hue: contact.hue, size: 34, rounded: false)
                    StatusDot(status: contact.status).offset(x: 1, y: 1)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(contact.name)
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundColor(p.textPrimary)
                    Text(contact.title)
                        .font(.system(size: 10.5))
                        .foregroundColor(p.textMuted)
                        .lineLimit(1)
                }
                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 7)
            .background(RoundedRectangle(cornerRadius: 7).fill(selected ? p.selected : (hovering ? p.hover : Color.clear)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

struct ContactDetail: View {
    var contact: LarkContact
    @EnvironmentObject var model: AppModel
    @Environment(\.palette) private var p

    private var chatID: String? {
        model.chats.first { $0.kind == "direct" && $0.name.hasPrefix(contact.name) }?.id
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top, spacing: 16) {
                    AvatarView(text: contact.avatarText, hue: contact.hue, size: 64, rounded: false)
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 7) {
                            Text(contact.name)
                                .font(.system(size: 21, weight: .bold))
                                .foregroundColor(p.textPrimary)
                            StatusDot(status: contact.status)
                            Text(contact.status.capitalized)
                                .font(.system(size: 10.5))
                                .foregroundColor(p.textMuted)
                        }
                        Text("\(contact.title) · \(contact.dept)")
                            .font(.system(size: 12))
                            .foregroundColor(p.textSecondary)
                        Text(contact.bio)
                            .font(.system(size: 11.5))
                            .foregroundColor(p.textMuted)
                            .padding(.top, 2)
                    }
                    Spacer()
                }

                HStack(spacing: 8) {
                    Button {
                        if let id = chatID { model.select(chat: id) }
                    } label: {
                        Label("Message", systemImage: "bubble.left.fill")
                            .font(.system(size: 11.5, weight: .medium))
                            .foregroundColor(.white)
                            .padding(.horizontal, 12)
                            .frame(height: 28)
                            .background(RoundedRectangle(cornerRadius: 6).fill(p.accent))
                    }
                    .buttonStyle(.plain)
                    detailButton("Call", "phone")
                    detailButton("Video", "video")
                    Spacer()
                    IconButton(symbol: "ellipsis", help: "More") {}
                }

                VStack(alignment: .leading, spacing: 0) {
                    Text("Contact information".uppercased())
                        .font(.system(size: 9.5, weight: .semibold))
                        .foregroundColor(p.textMuted)
                        .padding(.bottom, 8)
                    infoRow("envelope", "Email", contact.email)
                    DividerLine().padding(.leading, 26)
                    infoRow("phone", "Phone", contact.phone)
                    DividerLine().padding(.leading, 26)
                    infoRow("clock", "Local time", contact.timezone.replacingOccurrences(of: "_", with: " "))
                    DividerLine().padding(.leading, 26)
                    infoRow("building.2", "Department", contact.dept)
                }
                .padding(14)
                .background(RoundedRectangle(cornerRadius: 10).fill(p.list))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(p.borderSoft, lineWidth: 1))

                VStack(alignment: .leading, spacing: 10) {
                    Text("Shared with you".uppercased())
                        .font(.system(size: 9.5, weight: .semibold))
                        .foregroundColor(p.textMuted)
                    ForEach(model.docs.filter { $0.owner == contact.name }) { d in
                        HStack(spacing: 9) {
                            Image(systemName: "doc.text.fill")
                                .font(.system(size: 12))
                                .foregroundColor(p.accent)
                            Text(d.title)
                                .font(.system(size: 12))
                                .foregroundColor(p.textPrimary)
                            Spacer()
                            Text(TimeFmt.ago(minutes: d.minutesAgo ?? 0))
                                .font(.system(size: 10))
                                .foregroundColor(p.textMuted)
                        }
                        .padding(.vertical, 5)
                    }
                    if model.docs.filter({ $0.owner == contact.name }).isEmpty {
                        Text("Nothing shared yet.")
                            .font(.system(size: 11))
                            .foregroundColor(p.textMuted)
                    }
                }
            }
            .padding(26)
            .frame(maxWidth: 760, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(p.content)
    }

    private func detailButton(_ title: String, _ symbol: String) -> some View {
        Label(title, systemImage: symbol)
            .font(.system(size: 11.5, weight: .medium))
            .foregroundColor(p.textSecondary)
            .padding(.horizontal, 12)
            .frame(height: 28)
            .background(RoundedRectangle(cornerRadius: 6).fill(p.list))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(p.borderSoft, lineWidth: 1))
    }

    private func infoRow(_ symbol: String, _ label: String, _ value: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 11))
                .foregroundColor(p.textMuted)
                .frame(width: 16)
            Text(label)
                .font(.system(size: 11.5))
                .foregroundColor(p.textMuted)
                .frame(width: 86, alignment: .leading)
            Text(value)
                .font(.system(size: 12))
                .foregroundColor(p.textPrimary)
                .textSelection(.enabled)
            Spacer()
        }
        .padding(.vertical, 7)
    }
}

// MARK: - Calendar

struct CalendarScreen: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.palette) private var p
    private let cal = Calendar.current

    private var days: [Date] {
        (0..<7).compactMap { cal.date(byAdding: .day, value: $0, to: cal.startOfDay(for: Date())) }
    }

    private var dayEvents: [LarkEvent] {
        model.events.filter { $0.dayOffset == model.selectedDayOffset }.sorted { $0.startMin < $1.startMin }
    }

    private var nowMinutes: Int {
        let c = cal.dateComponents([.hour, .minute], from: Date())
        return (c.hour ?? 0) * 60 + (c.minute ?? 0)
    }

    private var nextEvent: LarkEvent? {
        let today = model.events.filter { $0.dayOffset == 0 }.sorted { $0.startMin < $1.startMin }
        if let upcoming = today.first(where: { $0.endMin > nowMinutes }) { return upcoming }
        return model.events.filter { $0.dayOffset > 0 }.sorted {
            $0.dayOffset == $1.dayOffset ? $0.startMin < $1.startMin : $0.dayOffset < $1.dayOffset
        }.first
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Calendar")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundColor(p.textPrimary)
                    Text(TimeFmt.dayHeader(cal.date(byAdding: .day, value: model.selectedDayOffset, to: Date()) ?? Date()))
                        .font(.system(size: 11))
                        .foregroundColor(p.textMuted)
                }
                Spacer()
                Button {
                    model.selectedDayOffset = 0
                } label: {
                    Text("Today")
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundColor(p.textPrimary)
                        .padding(.horizontal, 10)
                        .frame(height: 26)
                        .background(RoundedRectangle(cornerRadius: 6).fill(p.list))
                        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(p.borderSoft, lineWidth: 1))
                }
                .buttonStyle(.plain)
                IconButton(symbol: "plus", help: "New event") {}
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 14)

            HStack(spacing: 6) {
                ForEach(Array(days.enumerated()), id: \.offset) { idx, day in
                    DayCell(
                        date: day,
                        isToday: cal.isDateInToday(day),
                        selected: model.selectedDayOffset == idx,
                        count: model.events.filter { $0.dayOffset == idx }.count
                    ) {
                        model.selectedDayOffset = idx
                    }
                }
                Spacer()
            }
            .padding(.horizontal, 22)
            .padding(.bottom, 14)

            DividerLine()

            HStack(alignment: .top, spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 6) {
                            Text("SCHEDULE")
                                .font(.system(size: 9.5, weight: .semibold))
                                .foregroundColor(p.textMuted)
                            Text("\(dayEvents.count)")
                                .font(.system(size: 9.5))
                                .foregroundColor(p.textMuted)
                            Spacer()
                        }
                        .padding(.bottom, 2)

                        if dayEvents.isEmpty {
                            VStack(spacing: 8) {
                                Image(systemName: "calendar.badge.checkmark")
                                    .font(.system(size: 26, weight: .light))
                                    .foregroundColor(p.textMuted.opacity(0.7))
                                Text("No events — a clear day.")
                                    .font(.system(size: 12))
                                    .foregroundColor(p.textMuted)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 50)
                        }
                        ForEach(dayEvents) { e in
                            EventCard(event: e)
                        }
                        if !dayEvents.isEmpty {
                            Text("\(dayEvents.count) events · \(dayEvents.reduce(0) { $0 + ($1.endMin - $1.startMin) } / 60)h booked")
                                .font(.system(size: 10.5))
                                .foregroundColor(p.textMuted)
                                .padding(.top, 4)
                        }
                    }
                    .padding(22)
                }
                .scrollIndicators(.hidden)

                Rectangle().fill(p.borderSoft).frame(width: 1)

                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        if let next = nextEvent {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("NEXT UP")
                                    .font(.system(size: 9.5, weight: .semibold))
                                    .foregroundColor(p.textMuted)
                                HStack(spacing: 3) {
                                    Circle().fill(p.eventColor(next.colorKey)).frame(width: 6, height: 6)
                                    Text(next.dayOffset == 0 ? "Today" : "In \(next.dayOffset) day\(next.dayOffset == 1 ? "" : "s")")
                                        .font(.system(size: 10))
                                        .foregroundColor(p.textMuted)
                                }
                                Text(next.title)
                                    .font(.system(size: 13.5, weight: .semibold))
                                    .foregroundColor(p.textPrimary)
                                Text(String(format: "%02d:%02d – %02d:%02d", next.startMin / 60, next.startMin % 60, next.endMin / 60, next.endMin % 60))
                                    .font(.system(size: 11.5, weight: .medium, design: .rounded))
                                    .foregroundColor(p.textSecondary)
                                Label(next.location, systemImage: next.location.lowercased().contains("video") ? "video" : "mappin.and.ellipse")
                                    .font(.system(size: 10.5))
                                    .foregroundColor(p.textMuted)
                                HStack(spacing: -6) {
                                    ForEach(Array(next.attendees.prefix(4).enumerated()), id: \.offset) { idx, name in
                                        AvatarView(text: String(name.prefix(1)), hue: (idx * 57 + 180) % 360, size: 22, rounded: false)
                                            .overlay(Circle().stroke(p.list, lineWidth: 1.5))
                                    }
                                    if next.attendees.count > 4 {
                                        Text("+\(next.attendees.count - 4)")
                                            .font(.system(size: 9.5))
                                            .foregroundColor(p.textMuted)
                                            .padding(.leading, 10)
                                    }
                                    Spacer()
                                }
                                .padding(.top, 2)
                            }
                            .padding(13)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(RoundedRectangle(cornerRadius: 10).fill(p.list))
                            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(p.borderSoft, lineWidth: 1))
                        }

                        VStack(alignment: .leading, spacing: 9) {
                            Text("THIS WEEK")
                                .font(.system(size: 9.5, weight: .semibold))
                                .foregroundColor(p.textMuted)
                            ForEach(0..<7, id: \.self) { idx in
                                let count = model.events.filter { $0.dayOffset == idx }.count
                                HStack(spacing: 8) {
                                    Text(shortDay(days[idx]))
                                        .font(.system(size: 10))
                                        .foregroundColor(p.textMuted)
                                        .frame(width: 26, alignment: .leading)
                                    Capsule()
                                        .fill(count > 0 ? p.accent.opacity(0.85) : (p.dark ? Color.white.opacity(0.06) : Color.black.opacity(0.05)))
                                        .frame(width: count > 0 ? CGFloat(24 + count * 22) : 6, height: 6)
                                    Spacer()
                                    Text(count > 0 ? "\(count)" : "—")
                                        .font(.system(size: 9.5))
                                        .foregroundColor(count > 0 ? p.textSecondary : p.textMuted)
                                }
                            }
                        }

                        VStack(alignment: .leading, spacing: 9) {
                            Text("ONLINE NOW")
                                .font(.system(size: 9.5, weight: .semibold))
                                .foregroundColor(p.textMuted)
                            ForEach(model.contacts.filter { $0.status == "online" }) { c in
                                HStack(spacing: 7) {
                                    AvatarView(text: c.avatarText, hue: c.hue, size: 20, rounded: false)
                                    Text(c.name)
                                        .font(.system(size: 11))
                                        .foregroundColor(p.textSecondary)
                                    Spacer()
                                    Circle().fill(p.online).frame(width: 6, height: 6)
                                }
                            }
                        }
                    }
                    .padding(20)
                }
                .scrollIndicators(.hidden)
                .frame(width: 262)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(p.content)
    }

    private func shortDay(_ d: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "EEE"
        return f.string(from: d)
    }
}

struct DayCell: View {
    var date: Date
    var isToday: Bool
    var selected: Bool
    var count: Int
    var action: () -> Void
    @Environment(\.palette) private var p
    @State private var hovering = false
    private let cal = Calendar.current

    var body: some View {
        Button(action: action) {
            VStack(spacing: 5) {
                Text(weekday(date).uppercased())
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(selected ? .white : p.textMuted)
                Text("\(cal.component(.day, from: date))")
                    .font(.system(size: 17, weight: selected ? .bold : .medium, design: .rounded))
                    .foregroundColor(selected ? .white : (isToday ? p.accent : p.textPrimary))
                Circle()
                    .fill(count > 0 ? (selected ? Color.white.opacity(0.9) : p.accent) : Color.clear)
                    .frame(width: 4, height: 4)
            }
            .frame(width: 56, height: 62)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(selected ? p.accent : (hovering ? p.hover : p.list))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(selected ? Color.clear : p.borderSoft, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }

    private func weekday(_ d: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "EEE"
        return f.string(from: d)
    }
}

struct EventCard: View {
    var event: LarkEvent
    @Environment(\.palette) private var p

    private var time: String {
        func fmt(_ m: Int) -> String { String(format: "%02d:%02d", m / 60, m % 60) }
        return "\(fmt(event.startMin)) – \(fmt(event.endMin))"
    }

    var body: some View {
        HStack(spacing: 0) {
            RoundedRectangle(cornerRadius: 2)
                .fill(p.eventColor(event.colorKey))
                .frame(width: 3)
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text(event.title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(p.textPrimary)
                    Spacer()
                    Text(time)
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundColor(p.textSecondary)
                }
                HStack(spacing: 10) {
                    Label(event.location, systemImage: event.location.lowercased().contains("video") ? "video" : "mappin.and.ellipse")
                        .font(.system(size: 10.5))
                        .foregroundColor(p.textMuted)
                    Label(event.attendees.joined(separator: ", "), systemImage: "person.2")
                        .font(.system(size: 10.5))
                        .foregroundColor(p.textMuted)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
        }
        .background(RoundedRectangle(cornerRadius: 9).fill(p.list))
        .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(p.borderSoft, lineWidth: 1))
    }
}

// MARK: - Docs

struct DocsScreen: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.palette) private var p
    @State private var kind: String = "All"

    private var kinds: [String] { ["All", "Doc", "Sheet", "Slide", "Wiki"] }

    private var filtered: [LarkDoc] {
        if kind == "All" { return model.docs }
        return model.docs.filter { $0.kind.lowercased() == kind.lowercased() }
    }

    private func icon(_ k: String) -> (String, Color) {
        switch k {
        case "sheet": return ("tablecells.fill", Color(hex: "#2ea871"))
        case "slide": return ("rectangle.on.rectangle.fill", Color(hex: "#f07b24"))
        case "wiki": return ("book.closed.fill", Color(hex: "#7d5bff"))
        default: return ("doc.text.fill", p.accent)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Docs")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundColor(p.textPrimary)
                    Text("\(model.docs.count) documents · shared with Apollo Studios")
                        .font(.system(size: 11))
                        .foregroundColor(p.textMuted)
                }
                Spacer()
                HStack(spacing: 5) {
                    ForEach(kinds, id: \.self) { k in
                        FilterChip(title: k, selected: kind == k) { kind = k }
                    }
                }
                IconButton(symbol: "plus", help: "New document") {}
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 14)

            DividerLine()

            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 280, maximum: 420), spacing: 12)], spacing: 12) {
                    ForEach(filtered) { d in
                        Button {
                            model.selectedDocID = d.id
                        } label: {
                            DocCard(doc: d, icon: icon(d.kind))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(22)
            }
            .scrollIndicators(.hidden)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(p.content)
    }
}

struct DocCard: View {
    var doc: LarkDoc
    var icon: (String, Color)
    @Environment(\.palette) private var p
    @State private var hovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 7) {
                Image(systemName: icon.0)
                    .font(.system(size: 13))
                    .foregroundColor(icon.1)
                Text(doc.kind.uppercased())
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(p.textMuted)
                Spacer()
                if doc.shared {
                    Image(systemName: "person.2.fill")
                        .font(.system(size: 8.5))
                        .foregroundColor(p.textMuted)
                }
            }
            Text(doc.title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(p.textPrimary)
                .multilineTextAlignment(.leading)
                .lineLimit(2)
            Text(doc.snippet)
                .font(.system(size: 11))
                .foregroundColor(p.textMuted)
                .multilineTextAlignment(.leading)
                .lineLimit(3)
                .frame(maxWidth: .infinity, alignment: .leading)
            Spacer(minLength: 2)
            HStack {
                Text(doc.owner)
                    .font(.system(size: 10))
                    .foregroundColor(p.textSecondary)
                Spacer()
                Text(TimeFmt.ago(minutes: doc.minutesAgo ?? 0))
                    .font(.system(size: 10))
                    .foregroundColor(p.textMuted)
            }
        }
        .padding(13)
        .frame(height: 152)
        .background(RoundedRectangle(cornerRadius: 10).fill(hovering ? p.hover : p.list))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(p.borderSoft, lineWidth: 1))
        .onHover { hovering = $0 }
    }
}

// MARK: - Tasks

struct TasksScreen: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.palette) private var p
    @State private var filter = "All"
    @State private var draft = ""

    private var lists: [(String, [LarkTask])] {
        var order: [String] = []
        var map: [String: [LarkTask]] = [:]
        for t in model.tasks {
            if filter == "Open" && t.done { continue }
            if filter == "Done" && !t.done { continue }
            if map[t.list] == nil { order.append(t.list) }
            map[t.list, default: []].append(t)
        }
        return order.map { ($0, map[$0] ?? []) }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Tasks")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundColor(p.textPrimary)
                    Text("\(model.tasks.filter { !$0.done }.count) open · \(model.tasks.filter { $0.done }.count) done")
                        .font(.system(size: 11))
                        .foregroundColor(p.textMuted)
                }
                Spacer()
                HStack(spacing: 5) {
                    ForEach(["All", "Open", "Done"], id: \.self) { f in
                        FilterChip(title: f, selected: filter == f) { filter = f }
                    }
                }
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 14)

            HStack(spacing: 8) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 14))
                    .foregroundColor(p.accent)
                TextField("", text: $draft, prompt: Text("Add a task and press Return").foregroundColor(p.textMuted))
                    .textFieldStyle(.plain)
                    .font(.system(size: 12.5))
                    .foregroundColor(p.textPrimary)
                    .onSubmit {
                        model.addTask(draft.trimmingCharacters(in: .whitespaces))
                        draft = ""
                    }
            }
            .padding(.horizontal, 12)
            .frame(height: 38)
            .background(RoundedRectangle(cornerRadius: 8).fill(p.list))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(p.borderSoft, lineWidth: 1))
            .padding(.horizontal, 22)
            .padding(.bottom, 12)

            DividerLine()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    ForEach(lists, id: \.0) { list in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 6) {
                                Text(list.0)
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundColor(p.textSecondary)
                                Text("\(list.1.count)")
                                    .font(.system(size: 9.5))
                                    .foregroundColor(p.textMuted)
                                    .padding(.horizontal, 5)
                                    .background(Capsule().fill(p.dark ? Color.white.opacity(0.06) : Color.black.opacity(0.05)))
                                Spacer()
                            }
                            .padding(.bottom, 2)
                            ForEach(list.1) { t in
                                TaskRow(task: t) { model.toggleTask(t.id) }
                            }
                        }
                    }
                    if lists.isEmpty {
                        Text("Nothing here.")
                            .font(.system(size: 12))
                            .foregroundColor(p.textMuted)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 40)
                    }
                }
                .padding(22)
                .frame(maxWidth: 760, alignment: .leading)
            }
            .scrollIndicators(.hidden)
            .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(p.content)
    }
}

struct TaskRow: View {
    var task: LarkTask
    var action: () -> Void
    @Environment(\.palette) private var p
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 10) {
            Button(action: action) {
                Image(systemName: task.done ? "checkmark.square.fill" : "square")
                    .font(.system(size: 14))
                    .foregroundColor(task.done ? p.accent : p.textMuted)
            }
            .buttonStyle(.plain)
            VStack(alignment: .leading, spacing: 2) {
                Text(task.title)
                    .font(.system(size: 12.5))
                    .foregroundColor(task.done ? p.textMuted : p.textPrimary)
                    .strikethrough(task.done, color: p.textMuted)
                Text(task.assignee)
                    .font(.system(size: 10))
                    .foregroundColor(p.textMuted)
            }
            Spacer()
            Text(task.due)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(task.due == "Today" && !task.done ? p.accent : p.textMuted)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Capsule().fill(task.due == "Today" && !task.done ? p.accentSoft : Color.clear))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 7).fill(hovering ? p.hover : p.list))
        .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(p.borderSoft, lineWidth: 1))
        .onHover { hovering = $0 }
    }
}

// MARK: - Settings

struct SettingsSheet: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.palette) private var p
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Settings")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(p.textPrimary)
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(p.textSecondary)
                        .frame(width: 24, height: 24)
                        .background(Circle().fill(p.hover))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            .frame(height: 50)
            DividerLine()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    section("Appearance") {
                        HStack {
                            Text("Theme")
                                .font(.system(size: 12.5))
                                .foregroundColor(p.textPrimary)
                            Spacer()
                            HStack(spacing: 4) {
                                ForEach(["light", "dark", "system"], id: \.self) { t in
                                    Button { model.setTheme(t) } label: {
                                        Text(t.capitalized)
                                            .font(.system(size: 11, weight: model.prefs.theme == t ? .semibold : .regular))
                                            .foregroundColor(model.prefs.theme == t ? p.accent : p.textSecondary)
                                            .padding(.horizontal, 10)
                                            .frame(height: 24)
                                            .background(RoundedRectangle(cornerRadius: 6).fill(model.prefs.theme == t ? p.accentSoft : Color.clear))
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                        DividerLine()
                        toggle("Compact message list", model.prefs.compact) { model.prefs.compact = $0; model.togglePref("compact", $0) }
                    }

                    section("Messages") {
                        toggle("Send with Return", model.prefs.sendWithEnter) { model.prefs.sendWithEnter = $0; model.togglePref("sendWithEnter", $0) }
                        Text(model.prefs.sendWithEnter
                             ? "Lark's default. ⌘Return also sends; Shift+Return adds a line."
                             : "Lark's alternate shortcut: Return adds a line, ⌘Return sends.")
                            .font(.system(size: 10.5))
                            .foregroundColor(p.textMuted)
                            .padding(.leading, 2)
                            .padding(.bottom, 4)
                        DividerLine()
                        toggle("Desktop notifications", model.prefs.notifications) { model.prefs.notifications = $0; model.togglePref("notifications", $0) }
                    }

                    section("Performance") {
                        HStack(alignment: .top, spacing: 14) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(String(format: "%.1f MB", model.stats?.rssMb ?? model.coreInfo?.rssMb ?? 0))
                                    .font(.system(size: 22, weight: .bold, design: .rounded))
                                    .foregroundColor(p.textPrimary)
                                Text("Core process memory")
                                    .font(.system(size: 10.5))
                                    .foregroundColor(p.textMuted)
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 3) {
                                Text("≈ 600 MB")
                                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                                    .foregroundColor(p.textMuted)
                                Text("typical Chromium client (estimated)")
                                    .font(.system(size: 9.5))
                                    .foregroundColor(p.textMuted)
                            }
                        }
                        .padding(.vertical, 6)

                        HStack(spacing: 14) {
                            metric("Chats", "\(model.stats?.chats ?? model.chats.count)")
                            metric("Messages", "\(model.stats?.messages ?? 0)")
                            metric("Contacts", "\(model.stats?.contacts ?? model.contacts.count)")
                            metric("Store", String(format: "%.0f KB", (model.stats?.storeBytes ?? 0) / 1024))
                        }

                        HStack(spacing: 6) {
                            Image(systemName: "memorychip")
                                .font(.system(size: 10))
                                .foregroundColor(p.accent)
                            Text("Rust native core \(model.coreInfo?.version ?? "") · \(model.stats?.threads ?? 2) threads · no Chromium, no renderer processes")
                                .font(.system(size: 10))
                                .foregroundColor(p.textMuted)
                        }
                        .padding(.top, 2)
                    }

                    section("About") {
                        HStack {
                            AvatarView(text: "SL", hue: 214, size: 30, rounded: true)
                            VStack(alignment: .leading, spacing: 1) {
                                Text("Swifty Lark")
                                    .font(.system(size: 12.5, weight: .semibold))
                                    .foregroundColor(p.textPrimary)
                                Text("Native macOS client · SwiftUI + Rust")
                                    .font(.system(size: 10.5))
                                    .foregroundColor(p.textMuted)
                            }
                            Spacer()
                            Text("1.0")
                                .font(.system(size: 11))
                                .foregroundColor(p.textMuted)
                        }
                    }
                }
                .padding(20)
            }
            .scrollIndicators(.hidden)
        }
        .frame(width: 540, height: 620)
        .background(p.list)
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(.system(size: 9.5, weight: .semibold))
                .foregroundColor(p.textMuted)
            VStack(alignment: .leading, spacing: 8) { content() }
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 9).fill(p.content))
                .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(p.borderSoft, lineWidth: 1))
        }
    }

    private func toggle(_ title: String, _ value: Bool, _ onChange: @escaping (Bool) -> Void) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 12.5))
                .foregroundColor(p.textPrimary)
            Spacer()
            Toggle("", isOn: Binding(get: { value }, set: { onChange($0) }))
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
        }
    }

    private func metric(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundColor(p.textPrimary)
            Text(label)
                .font(.system(size: 9.5))
                .foregroundColor(p.textMuted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
