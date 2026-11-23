// Swifty Lark core — a small native backend for the SwiftUI macOS client.
// It owns the local workspace: chats, messages, contacts, docs, calendar and tasks.
// Protocol: line-delimited JSON on stdin/stdout.
//   {"id": 1, "cmd": "state", "params": {}}
//   {"id": 1, "ok": true, "data": {...}}
//   {"id": 1, "ok": false, "error": "..."}

use serde::{Deserialize, Serialize};
use serde_json::{json, Value};
use std::fs;
use std::io::{self, BufRead, Write};
use std::path::PathBuf;
use std::time::{SystemTime, UNIX_EPOCH};

const SCHEMA_VERSION: u32 = 4;

fn now_secs() -> f64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_secs_f64())
        .unwrap_or(0.0)
}

fn mins_ago(mins: f64) -> f64 {
    now_secs() - mins * 60.0
}

#[derive(Serialize, Deserialize, Clone, Debug)]
#[serde(rename_all = "camelCase")]
pub struct Reaction {
    pub emoji: String,
    pub count: u32,
    #[serde(default)]
    pub mine: bool,
}

#[derive(Serialize, Deserialize, Clone, Debug)]
#[serde(rename_all = "camelCase")]
pub struct Attachment {
    pub kind: String,
    pub name: String,
    pub detail: String,
}

#[derive(Serialize, Deserialize, Clone, Debug)]
#[serde(rename_all = "camelCase")]
pub struct Message {
    pub id: String,
    pub sender: String,
    pub sender_id: String,
    pub text: String,
    pub ts: f64,
    pub mine: bool,
    #[serde(default)]
    pub system: bool,
    #[serde(default)]
    pub reactions: Vec<Reaction>,
    #[serde(default)]
    pub attachment: Option<Attachment>,
    #[serde(default)]
    pub edited: bool,
}

#[derive(Serialize, Deserialize, Clone, Debug)]
#[serde(rename_all = "camelCase")]
pub struct Chat {
    pub id: String,
    pub name: String,
    pub kind: String,
    pub avatar_text: String,
    pub hue: i32,
    pub members: Vec<String>,
    pub unread: i32,
    pub muted: bool,
    pub pinned: bool,
    pub typing: bool,
    pub topic: String,
    pub messages: Vec<Message>,
}

impl Chat {
    fn last_ts(&self) -> f64 {
        self.messages.last().map(|m| m.ts).unwrap_or(0.0)
    }
}

#[derive(Serialize, Deserialize, Clone, Debug)]
#[serde(rename_all = "camelCase")]
pub struct Contact {
    pub id: String,
    pub name: String,
    pub title: String,
    pub dept: String,
    pub status: String,
    pub email: String,
    pub phone: String,
    pub timezone: String,
    pub avatar_text: String,
    pub hue: i32,
    pub bio: String,
}

#[derive(Serialize, Deserialize, Clone, Debug)]
#[serde(rename_all = "camelCase")]
pub struct Doc {
    pub id: String,
    pub title: String,
    pub kind: String,
    pub owner: String,
    pub updated: f64,
    pub snippet: String,
    pub shared: bool,
}

#[derive(Serialize, Deserialize, Clone, Debug)]
#[serde(rename_all = "camelCase")]
pub struct Event {
    pub id: String,
    pub title: String,
    pub day_offset: i32,
    pub start_min: i32,
    pub end_min: i32,
    pub location: String,
    pub attendees: Vec<String>,
    pub color_key: String,
}

#[derive(Serialize, Deserialize, Clone, Debug)]
#[serde(rename_all = "camelCase")]
pub struct Task {
    pub id: String,
    pub title: String,
    pub done: bool,
    pub due: String,
    pub list: String,
    pub assignee: String,
}

#[derive(Serialize, Deserialize, Clone, Debug)]
#[serde(rename_all = "camelCase")]
pub struct Prefs {
    pub theme: String,
    pub notifications: bool,
    pub send_with_enter: bool,
    pub compact: bool,
}

#[derive(Serialize, Deserialize, Clone, Debug)]
#[serde(rename_all = "camelCase")]
pub struct User {
    pub id: String,
    pub name: String,
    pub title: String,
    pub email: String,
    pub avatar_text: String,
    pub hue: i32,
}

#[derive(Serialize, Deserialize, Clone, Debug)]
#[serde(rename_all = "camelCase")]
pub struct Workspace {
    pub name: String,
    pub plan: String,
    pub members: u32,
}

#[derive(Serialize, Deserialize, Clone, Debug)]
#[serde(rename_all = "camelCase")]
pub struct Store {
    pub schema: u32,
    /// True once the workspace has been replaced by real data imported from the
    /// signed-in Feishu web client. The SwiftUI app only shows the native
    /// workspace when this is set, so the seeded demo never masquerades as real.
    #[serde(default)]
    pub imported: bool,
    pub user: User,
    pub workspace: Workspace,
    pub chats: Vec<Chat>,
    pub contacts: Vec<Contact>,
    pub docs: Vec<Doc>,
    pub events: Vec<Event>,
    pub tasks: Vec<Task>,
    pub prefs: Prefs,
}

fn msg(id: &str, sender: &str, sender_id: &str, text: &str, ts: f64, mine: bool) -> Message {
    Message {
        id: id.to_string(),
        sender: sender.to_string(),
        sender_id: sender_id.to_string(),
        text: text.to_string(),
        ts,
        mine,
        system: false,
        reactions: Vec::new(),
        attachment: None,
        edited: false,
    }
}

fn sys(id: &str, text: &str, ts: f64) -> Message {
    Message {
        id: id.to_string(),
        sender: "".into(),
        sender_id: "".into(),
        text: text.to_string(),
        ts,
        mine: false,
        system: true,
        reactions: Vec::new(),
        attachment: None,
        edited: false,
    }
}

fn seed() -> Store {
    let will = ("William Yao", "u-william", "w");
    let richard = ("Richard Chen", "u-richard", "R");
    let leo = ("Leo Tan", "u-leo", "L");
    let barry = ("Barry Lim", "u-barry", "B");

    let mut chats = Vec::new();

    let mut apollo_msgs = vec![
        sys("m-a0", "Leo Tan created this group", mins_ago(60.0 * 26.0)),
        msg(
            "m-a1",
            richard.0,
            richard.1,
            "Morning. IrisEditor v1.6 is out — the AI companion panel is in the sidebar now.",
            mins_ago(214.0),
            false,
        ),
        msg(
            "m-a2",
            leo.0,
            leo.1,
            "Installed it. Launch feels instant compared to the old build. What did we do to the editor loop?",
            mins_ago(186.0),
            false,
        ),
        msg(
            "m-a3",
            "William Yao",
            "u-william",
            "Moved the document model into the Swift package and only redraw the changed line range. No more full rebuilds on every keystroke.",
            mins_ago(176.0),
            true,
        ),
        Message {
            reactions: vec![
                Reaction { emoji: "🔥".to_string(), count: 3, mine: true },
                Reaction { emoji: "👏".to_string(), count: 2, mine: false },
            ],
            ..msg(
                "m-a4",
                richard.0,
                richard.1,
                "That explains the memory graph. Nice work.",
                mins_ago(171.0),
                false,
            )
        },
        msg(
            "m-a5",
            barry.0,
            barry.1,
            "CourseManagment needs the same treatment. The Express API is fine, the React bundle is the heavy part.",
            mins_ago(96.0),
            false,
        ),
        Message {
            attachment: Some(Attachment {
                kind: "doc".into(),
                name: "CourseManagment — migration notes".into(),
                detail: "Lark Doc · 4 sections".into(),
            }),
            ..msg("m-a6", leo.0, leo.1, "Dropped the notes from Friday here:", mins_ago(84.0), false)
        },
        msg(
            "m-a7",
            "William Yao",
            "u-william",
            "Reading them now. If the router can stream the course list we can drop the client cache entirely.",
            mins_ago(72.0),
            true,
        ),
        Message {
            reactions: vec![Reaction { emoji: "👍".to_string(), count: 2, mine: false }],
            ..msg("m-a8", richard.0, richard.1, "Standup at 10:30, same room.", mins_ago(38.0), false)
        },
        msg(
            "m-a9",
            barry.0,
            barry.1,
            "I'll bring the benchmark numbers for the Electron build so we can compare.",
            mins_ago(9.0),
            false,
        ),
    ];
    apollo_msgs.sort_by(|a, b| a.ts.partial_cmp(&b.ts).unwrap());
    chats.push(Chat {
        id: "c-apollo".into(),
        name: "Apollo Studios".into(),
        kind: "group".into(),
        avatar_text: "AS".into(),
        hue: 214,
        members: vec![
            will.0.into(),
            richard.0.into(),
            leo.0.into(),
            barry.0.into(),
        ],
        unread: 3,
        muted: false,
        pinned: true,
        typing: false,
        topic: "Shipping IrisEditor, CourseManagment and the Paper Server".into(),
        messages: apollo_msgs,
    });

    let mut richard_msgs = vec![
        msg(
            "m-r1",
            richard.0,
            richard.1,
            "Pushed the release notes to the repo.",
            mins_ago(60.0 * 20.0),
            false,
        ),
        msg(
            "m-r2",
            "William Yao",
            "u-william",
            "Saw them. I'll add the screenshot section tonight.",
            mins_ago(60.0 * 19.6),
            true,
        ),
        msg(
            "m-r3",
            richard.0,
            richard.1,
            "Also — can you review the PR that moves the toolbar into its own view?",
            mins_ago(60.0 * 19.5),
            false,
        ),
        msg(
            "m-r4",
            "William Yao",
            "u-william",
            "Tomorrow morning, first thing.",
            mins_ago(60.0 * 19.4),
            true,
        ),
        msg(
            "m-r5",
            richard.0,
            richard.1,
            "No rush. The editor is finally quiet when you type.",
            mins_ago(300.0),
            false,
        ),
    ];
    richard_msgs.sort_by(|a, b| a.ts.partial_cmp(&b.ts).unwrap());
    chats.push(Chat {
        id: "c-richard".into(),
        name: "Richard Chen".into(),
        kind: "direct".into(),
        avatar_text: "R".into(),
        hue: 265,
        members: vec![will.0.into(), richard.0.into()],
        unread: 0,
        muted: false,
        pinned: true,
        typing: true,
        topic: "IrisEditor · release".into(),
        messages: richard_msgs,
    });

    let mut leo_msgs = vec![
        msg("m-l1", leo.0, leo.1, "Paper Server hit 40 players last night without a tick spike.", mins_ago(60.0 * 8.0), false),
        msg("m-l2", "William Yao", "u-william", "With the new chunk pre-loader?", mins_ago(60.0 * 7.8), true),
        msg("m-l3", leo.0, leo.1, "Yeah. View distance 10, and it still holds 20 TPS.", mins_ago(60.0 * 7.7), false),
        msg("m-l4", leo.0, leo.1, "One thing — the scoreboard branding still says the placeholder name. Can you send the final wording?", mins_ago(48.0), false),
    ];
    leo_msgs.sort_by(|a, b| a.ts.partial_cmp(&b.ts).unwrap());
    chats.push(Chat {
        id: "c-leo".into(),
        name: "Leo Tan".into(),
        kind: "direct".into(),
        avatar_text: "L".into(),
        hue: 152,
        members: vec![will.0.into(), leo.0.into()],
        unread: 1,
        muted: false,
        pinned: false,
        typing: false,
        topic: "Paper Server".into(),
        messages: leo_msgs,
    });

    let mut barry_msgs = vec![
        msg(
            "m-b1",
            "William Yao",
            "u-william",
            "Did the MySQL schema import cleanly?",
            mins_ago(60.0 * 30.0),
            true,
        ),
        msg(
            "m-b2",
            barry.0,
            barry.1,
            "Mostly. The enrolment table needs a composite key.",
            mins_ago(60.0 * 29.0),
            false,
        ),
        msg(
            "m-b3",
            barry.0,
            barry.1,
            "Sent you the fixed migration file.",
            mins_ago(60.0 * 28.0),
            false,
        ),
        msg(
            "m-b4",
            barry.0,
            barry.1,
            "Also the calendar view in the admin panel is still static. Want me to wire it up?",
            mins_ago(60.0 * 3.2),
            false,
        ),
    ];
    barry_msgs.sort_by(|a, b| a.ts.partial_cmp(&b.ts).unwrap());
    chats.push(Chat {
        id: "c-barry".into(),
        name: "Barry Lim".into(),
        kind: "direct".into(),
        avatar_text: "B".into(),
        hue: 32,
        members: vec![will.0.into(), barry.0.into()],
        unread: 2,
        muted: false,
        pinned: false,
        typing: false,
        topic: "CourseManagment".into(),
        messages: barry_msgs,
    });

    let mut design_msgs = vec![
        sys(
            "m-d0",
            "Richard Chen added 4 people to this group",
            mins_ago(60.0 * 50.0),
        ),
        msg(
            "m-d1",
            "Mia Wong",
            "u-mia",
            "Uploaded three directions for the dashboard: dense, calm, and the dark one.",
            mins_ago(60.0 * 26.0),
            false,
        ),
        msg(
            "m-d2",
            "William Yao",
            "u-william",
            "Dark one. Keep the cyan accents but lower the saturation on the cards.",
            mins_ago(60.0 * 25.0),
            true,
        ),
        Message {
            reactions: vec![Reaction {
                emoji: "💙".to_string(),
                count: 1,
                mine: false,
            }],
            ..msg(
                "m-d3",
                "Mia Wong",
                "u-mia",
                "Agreed. The dense version fights the sidebar.",
                mins_ago(60.0 * 24.5),
                false,
            )
        },
    ];
    design_msgs.sort_by(|a, b| a.ts.partial_cmp(&b.ts).unwrap());
    chats.push(Chat {
        id: "c-design".into(),
        name: "Design Sync".into(),
        kind: "group".into(),
        avatar_text: "DS".into(),
        hue: 285,
        members: vec![
            will.0.into(),
            "Mia Wong".into(),
            richard.0.into(),
            "Priya Nair".into(),
            "Sam Ito".into(),
        ],
        unread: 0,
        muted: true,
        pinned: false,
        typing: false,
        topic: "Visual language for the dashboard".into(),
        messages: design_msgs,
    });

    let mut course_msgs = vec![
        sys(
            "m-c0",
            "Barry Lim created this group",
            mins_ago(60.0 * 72.0),
        ),
        msg(
            "m-c1",
            barry.0,
            barry.1,
            "Migration branch is open. API routes unchanged.",
            mins_ago(60.0 * 70.0),
            false,
        ),
        msg(
            "m-c2",
            "William Yao",
            "u-william",
            "Good. Keep the enrolment endpoints stable, the mobile client still calls them.",
            mins_ago(60.0 * 69.0),
            true,
        ),
        msg(
            "m-c3",
            "Priya Nair",
            "u-priya",
            "Front-end is on the new table component. Two more screens to go.",
            mins_ago(60.0 * 12.0),
            false,
        ),
    ];
    course_msgs.sort_by(|a, b| a.ts.partial_cmp(&b.ts).unwrap());
    chats.push(Chat {
        id: "c-course".into(),
        name: "CourseManagment".into(),
        kind: "group".into(),
        avatar_text: "CM".into(),
        hue: 195,
        members: vec![
            will.0.into(),
            barry.0.into(),
            "Priya Nair".into(),
            leo.0.into(),
        ],
        unread: 0,
        muted: false,
        pinned: false,
        typing: false,
        topic: "React + Express course platform".into(),
        messages: course_msgs,
    });

    let mut swifty_msgs = vec![
        sys(
            "m-s0",
            "Swifty Lark is running on its native core. No Chromium, no renderer processes.",
            mins_ago(60.0 * 2.0),
        ),
        msg(
            "m-s1",
            "Swifty Lark",
            "u-bot",
            "Tip: press ⌘K anywhere to search chats, messages, people and docs.",
            mins_ago(60.0 * 1.9),
            false,
        ),
    ];
    swifty_msgs.sort_by(|a, b| a.ts.partial_cmp(&b.ts).unwrap());
    chats.push(Chat {
        id: "c-swifty".into(),
        name: "Swifty Lark".into(),
        kind: "bot".into(),
        avatar_text: "SL".into(),
        hue: 214,
        members: vec![will.0.into()],
        unread: 0,
        muted: false,
        pinned: false,
        typing: false,
        topic: "Native core notices".into(),
        messages: swifty_msgs,
    });

    let contacts = vec![
        Contact {
            id: richard.1.into(),
            name: richard.0.into(),
            title: "Co-founder".into(),
            dept: "Apollo Studios".into(),
            status: "online".into(),
            email: "richard@apollostudios.dev".into(),
            phone: "+65 8123 4410".into(),
            timezone: "Asia/Singapore".into(),
            avatar_text: "R".into(),
            hue: 265,
            bio: "Ships IrisEditor. Reviews every release.".into(),
        },
        Contact {
            id: leo.1.into(),
            name: leo.0.into(),
            title: "Infrastructure".into(),
            dept: "Apollo Studios".into(),
            status: "online".into(),
            email: "leo@apollostudios.dev".into(),
            phone: "+65 8123 9081".into(),
            timezone: "Asia/Singapore".into(),
            avatar_text: "L".into(),
            hue: 152,
            bio: "Runs the Paper Server and the deploy pipeline.".into(),
        },
        Contact {
            id: barry.1.into(),
            name: barry.0.into(),
            title: "Backend engineer".into(),
            dept: "Apollo Studios".into(),
            status: "away".into(),
            email: "barry@apollostudios.dev".into(),
            phone: "+65 8123 2277".into(),
            timezone: "Asia/Singapore".into(),
            avatar_text: "B".into(),
            hue: 32,
            bio: "CourseManagment API and database.".into(),
        },
        Contact {
            id: "u-mia".into(),
            name: "Mia Wong".into(),
            title: "Product designer".into(),
            dept: "Design".into(),
            status: "online".into(),
            email: "mia@apollostudios.dev".into(),
            phone: "+65 8123 6650".into(),
            timezone: "Asia/Singapore".into(),
            avatar_text: "M".into(),
            hue: 285,
            bio: "Interface and brand work for the studio.".into(),
        },
        Contact {
            id: "u-priya".into(),
            name: "Priya Nair".into(),
            title: "Frontend engineer".into(),
            dept: "Apollo Studios".into(),
            status: "offline".into(),
            email: "priya@apollostudios.dev".into(),
            phone: "+65 8123 1129".into(),
            timezone: "Asia/Kolkata".into(),
            avatar_text: "P".into(),
            hue: 340,
            bio: "React and the course platform UI.".into(),
        },
        Contact {
            id: "u-sam".into(),
            name: "Sam Ito".into(),
            title: "Motion designer".into(),
            dept: "Design".into(),
            status: "offline".into(),
            email: "sam@apollostudios.dev".into(),
            phone: "+65 8123 7734".into(),
            timezone: "Asia/Tokyo".into(),
            avatar_text: "S".into(),
            hue: 8,
            bio: "Motion studies and product video.".into(),
        },
    ];

    let docs = vec![
        Doc { id: "d-1".into(), title: "CourseManagment — migration notes".into(), kind: "doc".into(), owner: "Leo Tan".into(), updated: mins_ago(88.0), snippet: "Moving the enrolment table to a composite key, keeping the mobile endpoints stable across the cutover.".into(), shared: true },
        Doc { id: "d-2".into(), title: "IrisEditor 1.6 release notes".into(), kind: "doc".into(), owner: "Richard Chen".into(), updated: mins_ago(60.0 * 19.0), snippet: "AI companion panel, quieter typing, and a faster document model. Screenshots pending.".into(), shared: true },
        Doc { id: "d-3".into(), title: "Paper Server — launch checklist".into(), kind: "sheet".into(), owner: "Leo Tan".into(), updated: mins_ago(60.0 * 6.0), snippet: "Timings, view distance, scoreboard branding, backup windows and the rollback plan.".into(), shared: true },
        Doc { id: "d-4".into(), title: "Studio dashboard directions".into(), kind: "slide".into(), owner: "Mia Wong".into(), updated: mins_ago(60.0 * 25.0), snippet: "Three visual directions: dense, calm, and dark with cyan accents.".into(), shared: false },
        Doc { id: "d-5".into(), title: "Engineering handbook".into(), kind: "wiki".into(), owner: "William Yao".into(), updated: mins_ago(60.0 * 40.0), snippet: "How we review, release and keep the toolchain small.".into(), shared: true },
    ];

    let events = vec![
        Event {
            id: "e-1".into(),
            title: "Standup".into(),
            day_offset: 0,
            start_min: 630,
            end_min: 645,
            location: "Studio · Room 3".into(),
            attendees: vec!["Richard Chen".into(), "Leo Tan".into(), "Barry Lim".into()],
            color_key: "blue".into(),
        },
        Event {
            id: "e-2".into(),
            title: "CourseManagment review".into(),
            day_offset: 0,
            start_min: 840,
            end_min: 900,
            location: "Video meeting".into(),
            attendees: vec!["Barry Lim".into(), "Priya Nair".into()],
            color_key: "violet".into(),
        },
        Event {
            id: "e-3".into(),
            title: "Design sync".into(),
            day_offset: 0,
            start_min: 960,
            end_min: 1020,
            location: "Studio · Whiteboard".into(),
            attendees: vec!["Mia Wong".into(), "Sam Ito".into()],
            color_key: "green".into(),
        },
        Event {
            id: "e-4".into(),
            title: "IrisEditor release cut".into(),
            day_offset: 1,
            start_min: 600,
            end_min: 660,
            location: "Focus block".into(),
            attendees: vec!["Richard Chen".into()],
            color_key: "orange".into(),
        },
        Event {
            id: "e-5".into(),
            title: "Paper Server maintenance".into(),
            day_offset: 2,
            start_min: 1380,
            end_min: 1440,
            location: "Maintenance window".into(),
            attendees: vec!["Leo Tan".into()],
            color_key: "red".into(),
        },
        Event {
            id: "e-6".into(),
            title: "Weekly planning".into(),
            day_offset: 3,
            start_min: 570,
            end_min: 630,
            location: "Studio · Room 3".into(),
            attendees: vec!["Apollo Studios".into()],
            color_key: "blue".into(),
        },
        Event {
            id: "e-7".into(),
            title: "1:1 with Richard".into(),
            day_offset: 4,
            start_min: 900,
            end_min: 930,
            location: "Video meeting".into(),
            attendees: vec!["Richard Chen".into()],
            color_key: "violet".into(),
        },
    ];

    let tasks = vec![
        Task {
            id: "t-1".into(),
            title: "Review the toolbar PR in IrisEditor".into(),
            done: false,
            due: "Today".into(),
            list: "IrisEditor".into(),
            assignee: "William Yao".into(),
        },
        Task {
            id: "t-2".into(),
            title: "Send final scoreboard wording to Leo".into(),
            done: false,
            due: "Today".into(),
            list: "Paper Server".into(),
            assignee: "William Yao".into(),
        },
        Task {
            id: "t-3".into(),
            title: "Benchmark the Electron build for comparison".into(),
            done: false,
            due: "Tomorrow".into(),
            list: "CourseManagment".into(),
            assignee: "Barry Lim".into(),
        },
        Task {
            id: "t-4".into(),
            title: "Add screenshots to the 1.6 release notes".into(),
            done: true,
            due: "Yesterday".into(),
            list: "IrisEditor".into(),
            assignee: "William Yao".into(),
        },
        Task {
            id: "t-5".into(),
            title: "Move enrolment table to a composite key".into(),
            done: true,
            due: "Friday".into(),
            list: "CourseManagment".into(),
            assignee: "Barry Lim".into(),
        },
        Task {
            id: "t-6".into(),
            title: "Pick the dashboard direction".into(),
            done: true,
            due: "Friday".into(),
            list: "Design".into(),
            assignee: "Mia Wong".into(),
        },
    ];

    Store {
        schema: SCHEMA_VERSION,
        imported: false,
        user: User {
            id: will.1.into(),
            name: will.0.into(),
            title: "Founder & engineer".into(),
            email: "william@apollostudios.dev".into(),
            avatar_text: "W".into(),
            hue: 214,
        },
        workspace: Workspace {
            name: "Apollo Studios".into(),
            plan: "Team".into(),
            members: 12,
        },
        chats,
        contacts,
        docs,
        events,
        tasks,
        prefs: Prefs {
            theme: "dark".into(),
            notifications: true,
            send_with_enter: true,
            compact: false,
        },
    }
}

fn store_path() -> PathBuf {
    if let Ok(dir) = std::env::var("SWIFTYLARK_HOME") {
        return PathBuf::from(dir).join("store.json");
    }
    let home = std::env::var("HOME").unwrap_or_else(|_| ".".into());
    PathBuf::from(home)
        .join("Library")
        .join("Application Support")
        .join("Swifty Lark")
        .join("store.json")
}

fn load() -> Store {
    let path = store_path();
    if let Ok(text) = fs::read_to_string(&path) {
        if let Ok(mut s) = serde_json::from_str::<Store>(&text) {
            if s.schema == SCHEMA_VERSION {
                // keep demo times believable after a reload
                s.schema = SCHEMA_VERSION;
                return s;
            }
        }
    }
    let s = seed();
    save(&s);
    s
}

fn save(s: &Store) {
    let path = store_path();
    if let Some(parent) = path.parent() {
        let _ = fs::create_dir_all(parent);
    }
    if let Ok(text) = serde_json::to_string_pretty(s) {
        let tmp = path.with_extension("json.tmp");
        if fs::write(&tmp, text).is_ok() {
            let _ = fs::rename(&tmp, &path);
        }
    }
}

fn own_rss_mb() -> f64 {
    let pid = std::process::id().to_string();
    if let Ok(out) = std::process::Command::new("ps")
        .args(["-o", "rss=", "-p", &pid])
        .output()
    {
        let t = String::from_utf8_lossy(&out.stdout);
        if let Ok(kb) = t.trim().parse::<f64>() {
            return (kb / 1024.0 * 10.0).round() / 10.0;
        }
    }
    0.0
}

fn chat_json(c: &Chat) -> Value {
    let mut v = serde_json::to_value(c).unwrap_or(Value::Null);
    if let Some(obj) = v.as_object_mut() {
        obj.insert("lastTs".into(), json!(c.last_ts()));
        obj.insert(
            "preview".into(),
            json!(c
                .messages
                .last()
                .map(|m| if !m.system && !m.sender.is_empty() && c.kind != "direct" {
                    format!("{}: {}", m.sender, m.text)
                } else {
                    m.text.clone()
                })
                .unwrap_or_default()),
        );
    }
    v
}

fn sorted_chats(s: &Store) -> Vec<&Chat> {
    let mut v: Vec<&Chat> = s.chats.iter().collect();
    v.sort_by(|a, b| {
        b.pinned.cmp(&a.pinned).then(
            b.last_ts()
                .partial_cmp(&a.last_ts())
                .unwrap_or(std::cmp::Ordering::Equal),
        )
    });
    v
}

fn state_payload(s: &Store) -> Value {
    json!({
        "user": s.user,
        "workspace": s.workspace,
        "imported": s.imported,
        "source": if s.imported { "feishu-web" } else { "demo" },
        "chats": sorted_chats(s).iter().map(|c| chat_json(c)).collect::<Vec<_>>(),
        "contacts": s.contacts,
        "docs": s.docs.iter().map(|d| {
            let mut v = serde_json::to_value(d).unwrap();
            v.as_object_mut().unwrap().insert("minutesAgo".into(), json!(((now_secs() - d.updated) / 60.0).round()));
            v
        }).collect::<Vec<_>>(),
        "events": s.events,
        "tasks": s.tasks,
        "prefs": s.prefs,
        "now": now_secs(),
        "core": { "rssMb": own_rss_mb(), "version": env!("CARGO_PKG_VERSION") }
    })
}

fn find_chat_mut<'a>(s: &'a mut Store, id: &str) -> Option<&'a mut Chat> {
    s.chats.iter_mut().find(|c| c.id == id)
}

fn do_send(s: &mut Store, p: &Value) -> Result<Value, String> {
    let chat_id = p
        .get("chatId")
        .and_then(|v| v.as_str())
        .ok_or("chatId required")?;
    let text = p
        .get("text")
        .and_then(|v| v.as_str())
        .unwrap_or("")
        .trim()
        .to_string();
    if text.is_empty() {
        return Err("empty message".into());
    }
    let ts = now_secs();
    let id = format!("m-{}-{}", ts as i64, (ts * 1000.0) as i64 % 1000);
    let sender = s.user.name.clone();
    let sender_id = s.user.id.clone();
    let chat = find_chat_mut(s, chat_id).ok_or("chat not found")?;
    chat.messages
        .push(msg(&id, &sender, &sender_id, &text, ts, true));
    chat.unread = 0;
    chat.typing = false;
    let out = json!({ "messageId": id, "chat": chat_json(chat), "ts": ts });
    save(s);
    Ok(out)
}

fn do_read(s: &mut Store, p: &Value) -> Result<Value, String> {
    let chat_id = p
        .get("chatId")
        .and_then(|v| v.as_str())
        .ok_or("chatId required")?;
    if let Some(c) = find_chat_mut(s, chat_id) {
        c.unread = 0;
        save(s);
    }
    let total: i32 = s.chats.iter().map(|c| c.unread).sum();
    Ok(json!({ "unreadTotal": total }))
}

fn do_react(s: &mut Store, p: &Value) -> Result<Value, String> {
    let chat_id = p
        .get("chatId")
        .and_then(|v| v.as_str())
        .ok_or("chatId required")?;
    let msg_id = p
        .get("messageId")
        .and_then(|v| v.as_str())
        .ok_or("messageId required")?;
    let emoji = p.get("emoji").and_then(|v| v.as_str()).unwrap_or("👍");
    let chat = find_chat_mut(s, chat_id).ok_or("chat not found")?;
    if let Some(m) = chat.messages.iter_mut().find(|m| m.id == msg_id) {
        if let Some(r) = m.reactions.iter_mut().find(|r| r.emoji == emoji) {
            if r.mine {
                r.count = r.count.saturating_sub(1);
                r.mine = false;
                if r.count == 0 {
                    m.reactions.retain(|x| x.emoji != emoji);
                }
            } else {
                r.count += 1;
                r.mine = true;
            }
        } else {
            m.reactions.push(Reaction {
                emoji: emoji.into(),
                count: 1,
                mine: true,
            });
        }
        let out = chat_json(chat);
        save(s);
        return Ok(json!({ "chat": out }));
    }
    Err("message not found".into())
}

fn do_toggle_task(s: &mut Store, p: &Value) -> Result<Value, String> {
    let id = p.get("id").and_then(|v| v.as_str()).ok_or("id required")?;
    if let Some(t) = s.tasks.iter_mut().find(|t| t.id == id) {
        t.done = !t.done;
        let out = serde_json::to_value(&*t).unwrap();
        save(s);
        return Ok(json!({ "task": out }));
    }
    Err("task not found".into())
}

fn do_add_task(s: &mut Store, p: &Value) -> Result<Value, String> {
    let title = p
        .get("title")
        .and_then(|v| v.as_str())
        .unwrap_or("")
        .trim()
        .to_string();
    if title.is_empty() {
        return Err("title required".into());
    }
    let task = Task {
        id: format!("t-{}", now_secs() as i64),
        title,
        done: false,
        due: "Today".into(),
        list: p
            .get("list")
            .and_then(|v| v.as_str())
            .unwrap_or("Inbox")
            .to_string(),
        assignee: s.user.name.clone(),
    };
    s.tasks.insert(0, task.clone());
    save(s);
    Ok(json!({ "task": task }))
}

fn stable_hash(text: &str) -> u64 {
    let mut h: u64 = 0xcbf2_9ce4_8422_2325;
    for b in text.as_bytes() {
        h ^= *b as u64;
        h = h.wrapping_mul(0x0000_0100_0000_01b3);
    }
    h
}

fn initials(name: &str) -> String {
    let take: String = name.trim().chars().take(2).collect();
    if take.chars().all(|c| c.is_ascii_alphabetic()) {
        take.to_uppercase()
    } else {
        take
    }
}

/// Sidebar previews arrive as "Sender: text" (sometimes with a full-width
/// colon). Split the sender back out so the imported message has one.
fn split_preview(text: &str) -> (String, String) {
    for sep in [": ", "："] {
        if let Some(pos) = text.find(sep) {
            if pos > 0 && pos < 60 {
                let sender = text[..pos].trim();
                if !sender.is_empty() {
                    return (sender.to_string(), text[pos + sep.len()..].trim().to_string());
                }
            }
        }
    }
    (String::new(), text.trim().to_string())
}

/// Replaces the workspace with data scraped from the signed-in Feishu web
/// client. Chats are keyed by a stable hash of their name, so repeated imports
/// update the same rows instead of duplicating them.
fn do_import(s: &mut Store, p: &Value) -> Result<Value, String> {
    if let Some(u) = p.get("user").and_then(|v| v.as_object()) {
        if let Some(v) = u.get("id").and_then(|v| v.as_str()) {
            if !v.is_empty() {
                s.user.id = v.into();
            }
        }
        if let Some(v) = u.get("name").and_then(|v| v.as_str()) {
            if !v.is_empty() {
                s.user.name = v.into();
            }
        }
        if let Some(v) = u.get("title").and_then(|v| v.as_str()) {
            s.user.title = v.into();
        }
        if let Some(v) = u.get("email").and_then(|v| v.as_str()) {
            s.user.email = v.into();
        }
        if let Some(v) = u.get("avatarText").and_then(|v| v.as_str()) {
            if !v.is_empty() {
                s.user.avatar_text = v.into();
            }
        }
    }
    if let Some(w) = p.get("workspace").and_then(|v| v.as_object()) {
        if let Some(v) = w.get("name").and_then(|v| v.as_str()) {
            if !v.is_empty() {
                s.workspace.name = v.into();
            }
        }
        if let Some(v) = w.get("plan").and_then(|v| v.as_str()) {
            if !v.is_empty() {
                s.workspace.plan = v.into();
            }
        }
        if let Some(v) = w.get("members").and_then(|v| v.as_u64()) {
            s.workspace.members = v as u32;
        }
    }
    if let Some(list) = p.get("chats").and_then(|v| v.as_array()) {
        let ts_now = now_secs();
        let mut chats: Vec<Chat> = Vec::new();
        for c in list {
            let name = c
                .get("name")
                .and_then(|v| v.as_str())
                .unwrap_or("")
                .trim()
                .to_string();
            if name.is_empty() {
                continue;
            }
            let hash = stable_hash(&name);
            let mut messages: Vec<Message> = Vec::new();
            if let Some(ms) = c.get("messages").and_then(|v| v.as_array()) {
                for (mi, m) in ms.iter().enumerate() {
                    let text = m
                        .get("text")
                        .and_then(|v| v.as_str())
                        .unwrap_or("")
                        .trim()
                        .to_string();
                    if text.is_empty() {
                        continue;
                    }
                    let ts = m.get("ts").and_then(|v| v.as_f64()).unwrap_or(ts_now);
                    messages.push(Message {
                        id: format!("{}-{}-{}", hash, mi, (ts * 1000.0) as i64),
                        sender: m
                            .get("sender")
                            .and_then(|v| v.as_str())
                            .unwrap_or("")
                            .to_string(),
                        sender_id: String::new(),
                        text,
                        ts,
                        mine: m.get("mine").and_then(|v| v.as_bool()).unwrap_or(false),
                        system: m.get("system").and_then(|v| v.as_bool()).unwrap_or(false),
                        reactions: Vec::new(),
                        attachment: None,
                        edited: false,
                    });
                }
            }
            if messages.is_empty() {
                let preview = c
                    .get("preview")
                    .and_then(|v| v.as_str())
                    .unwrap_or("")
                    .trim()
                    .to_string();
                if !preview.is_empty() {
                    let (sender, text) = split_preview(&preview);
                    let ts = c.get("time").and_then(|v| v.as_f64()).unwrap_or(ts_now);
                    messages.push(msg(
                        &format!("{}-p", hash),
                        &sender,
                        "",
                        &text,
                        ts,
                        c.get("mine").and_then(|v| v.as_bool()).unwrap_or(false),
                    ));
                }
            }
            messages.sort_by(|a, b| a.ts.partial_cmp(&b.ts).unwrap_or(std::cmp::Ordering::Equal));
            let mut members = vec![s.user.name.clone()];
            members.retain(|m| !m.is_empty());
            chats.push(Chat {
                id: format!("c-{:x}", hash),
                avatar_text: initials(&name),
                hue: (hash % 360) as i32,
                kind: c
                    .get("kind")
                    .and_then(|v| v.as_str())
                    .unwrap_or("group")
                    .to_string(),
                members,
                unread: c
                    .get("unread")
                    .and_then(|v| v.as_i64())
                    .unwrap_or(0)
                    .max(0) as i32,
                muted: c.get("muted").and_then(|v| v.as_bool()).unwrap_or(false),
                pinned: c.get("pinned").and_then(|v| v.as_bool()).unwrap_or(false),
                typing: false,
                topic: String::new(),
                name,
                messages,
            });
        }
        if !chats.is_empty() {
            s.chats = chats;
            s.imported = true;
        }
    }
    save(s);
    let messages: usize = s.chats.iter().map(|c| c.messages.len()).sum();
    Ok(json!({
        "imported": s.imported,
        "chats": s.chats.len(),
        "messages": messages,
        "workspace": s.workspace.name,
        "user": s.user.name,
    }))
}

fn do_prefs(s: &mut Store, p: &Value) -> Result<Value, String> {
    if let Some(theme) = p.get("theme").and_then(|v| v.as_str()) {
        if ["dark", "light", "system"].contains(&theme) {
            s.prefs.theme = theme.to_string();
        }
    }
    if let Some(b) = p.get("notifications").and_then(|v| v.as_bool()) {
        s.prefs.notifications = b;
    }
    if let Some(b) = p.get("sendWithEnter").and_then(|v| v.as_bool()) {
        s.prefs.send_with_enter = b;
    }
    if let Some(b) = p.get("compact").and_then(|v| v.as_bool()) {
        s.prefs.compact = b;
    }
    save(s);
    Ok(json!({ "prefs": s.prefs }))
}

fn snippet(text: &str, q: &str) -> String {
    let lower = text.to_lowercase();
    if let Some(pos) = lower.find(&q.to_lowercase()) {
        let start = text[..pos]
            .char_indices()
            .rev()
            .nth(28)
            .map(|(i, _)| i)
            .unwrap_or(0);
        let end = text[pos..]
            .char_indices()
            .nth(60)
            .map(|(i, _)| pos + i)
            .unwrap_or(text.len());
        let mut out = String::new();
        if start > 0 {
            out.push('…');
        }
        out.push_str(text[start..end].trim());
        if end < text.len() {
            out.push('…');
        }
        out
    } else {
        text.chars().take(60).collect()
    }
}

fn do_search(s: &Store, p: &Value) -> Result<Value, String> {
    let q = p
        .get("query")
        .and_then(|v| v.as_str())
        .unwrap_or("")
        .trim()
        .to_string();
    if q.is_empty() {
        return Ok(json!({ "results": [] }));
    }
    let ql = q.to_lowercase();
    let mut out: Vec<Value> = Vec::new();

    for c in &s.chats {
        if c.name.to_lowercase().contains(&ql) {
            out.push(json!({ "kind": "chat", "title": c.name, "subtitle": if c.kind == "group" { format!("Group · {} members", c.members.len()) } else { "Direct message".to_string() }, "chatId": c.id, "hue": c.hue, "avatar": c.avatar_text }));
        }
        for m in c.messages.iter().rev() {
            if m.system {
                continue;
            }
            if m.text.to_lowercase().contains(&ql) {
                out.push(json!({ "kind": "message", "title": c.name, "subtitle": format!("{}: {}", m.sender, snippet(&m.text, &q)), "chatId": c.id, "messageId": m.id, "ts": m.ts, "hue": c.hue, "avatar": c.avatar_text }));
                if out.len() > 60 {
                    break;
                }
            }
        }
    }
    for p in &s.contacts {
        if p.name.to_lowercase().contains(&ql)
            || p.email.to_lowercase().contains(&ql)
            || p.title.to_lowercase().contains(&ql)
        {
            out.push(json!({ "kind": "person", "title": p.name, "subtitle": format!("{} · {}", p.title, p.dept), "contactId": p.id, "hue": p.hue, "avatar": p.avatar_text }));
        }
    }
    for d in &s.docs {
        if d.title.to_lowercase().contains(&ql) || d.snippet.to_lowercase().contains(&ql) {
            out.push(json!({ "kind": "doc", "title": d.title, "subtitle": format!("{} · {}", d.kind, d.owner), "docId": d.id }));
        }
    }
    for t in &s.tasks {
        if t.title.to_lowercase().contains(&ql) {
            out.push(json!({ "kind": "task", "title": t.title, "subtitle": format!("{} · {}", t.list, if t.done { "Done" } else { "Open" }), "taskId": t.id }));
        }
    }
    Ok(json!({ "results": out, "query": q }))
}

fn do_stats(s: &Store) -> Value {
    let msgs: usize = s.chats.iter().map(|c| c.messages.len()).sum();
    let bytes = fs::metadata(store_path()).map(|m| m.len()).unwrap_or(0);
    json!({
        "rssMb": own_rss_mb(),
        "pid": std::process::id(),
        "threads": 2,
        "chats": s.chats.len(),
        "messages": msgs,
        "contacts": s.contacts.len(),
        "docs": s.docs.len(),
        "storeBytes": bytes,
        "uptimeSecs": now_secs() - start_time(),
        "engine": "Rust native core"
    })
}

static PROCESS_START: std::sync::OnceLock<f64> = std::sync::OnceLock::new();

fn start_time() -> f64 {
    *PROCESS_START.get_or_init(now_secs)
}

fn handle(s: &mut Store, cmd: &str, p: &Value) -> Result<Value, String> {
    match cmd {
        "ping" => Ok(json!({ "pong": true })),
        "state" => Ok(state_payload(s)),
        "send" => do_send(s, p),
        "read" => do_read(s, p),
        "react" => do_react(s, p),
        "toggle_task" => do_toggle_task(s, p),
        "add_task" => do_add_task(s, p),
        "import" => do_import(s, p),
        "set_prefs" => do_prefs(s, p),
        "search" => do_search(s, p),
        "stats" => Ok(do_stats(s)),
        "save" => {
            save(s);
            Ok(json!({ "saved": true }))
        }
        other => Err(format!("unknown command: {}", other)),
    }
}

fn main() {
    let _ = start_time();
    let args: Vec<String> = std::env::args().collect();
    let mut store = load();

    if args.iter().any(|a| a == "--stats") {
        println!(
            "{}",
            serde_json::to_string_pretty(&do_stats(&store)).unwrap()
        );
        return;
    }
    if args.iter().any(|a| a == "--reset") {
        store = seed();
        save(&store);
        println!("{}", json!({"ok": true, "reset": true}));
        return;
    }
    if args.iter().any(|a| a == "--dump") {
        println!("{}", serde_json::to_string(&state_payload(&store)).unwrap());
        return;
    }

    let stdin = io::stdin();
    let stdout = io::stdout();
    for line in stdin.lock().lines() {
        let line = match line {
            Ok(l) => l,
            Err(_) => break,
        };
        let line = line.trim();
        if line.is_empty() {
            continue;
        }
        let v: Value = match serde_json::from_str(line) {
            Ok(v) => v,
            Err(e) => {
                let resp = json!({ "ok": false, "error": format!("bad json: {}", e) });
                let mut lock = stdout.lock();
                let _ = writeln!(lock, "{}", resp);
                let _ = lock.flush();
                continue;
            }
        };
        let id = v.get("id").cloned().unwrap_or(Value::Null);
        let cmd = v.get("cmd").and_then(|c| c.as_str()).unwrap_or("");
        let params = v.get("params").cloned().unwrap_or(json!({}));
        let resp = match handle(&mut store, cmd, &params) {
            Ok(data) => json!({ "id": id, "ok": true, "data": data }),
            Err(e) => json!({ "id": id, "ok": false, "error": e }),
        };
        let mut lock = stdout.lock();
        if writeln!(lock, "{}", resp).is_err() {
            break;
        }
        let _ = lock.flush();
    }
}
