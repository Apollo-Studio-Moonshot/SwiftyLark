# Swifty Lark

A native macOS client for Feishu / Lark. Two small pieces, no browser engine:

- `rust/` — `swiftylark-core`, the backend. Owns the workspace (chats, messages,
  contacts, docs, calendar, tasks), persists it and answers line-delimited JSON
  requests on stdin/stdout.
- `Swifty Lark/` — the SwiftUI app, built by `Swifty Lark.xcodeproj`. Draws the
  interface and talks to the core through a pipe it owns. Nothing is exposed on
  a port.

## Open in Xcode

```sh
open "Swifty Lark.xcodeproj"
```

Pick the `Swifty Lark` scheme and press Run (⌘R). The `Build Rust Core` build
phase runs `cargo build --release` automatically, and the `Embed Core` copy
phase places `swiftylark-core` in `Contents/Resources` alongside
`mechanics.json`. Set `SWIFTYLARK_CORE` to override the binary the app launches.

The Electron bundle it replaces is ~1.7 GB and runs several Chromium helper
processes. This build is a ~2.6 MB Swift binary plus a ~0.5 MB Rust binary; the
core itself sits at about 2 MB of resident memory.

## Build

```sh
./build.sh          # xcodebuild (Release); the Xcode build phases run cargo and assemble the .app
```

The build exits without opening a window. Output: `build/Swifty Lark.app`. You
can also build from Xcode itself (Product › Archive, or ⌘B).

`npm run build` runs the same script (npm is not needed for anything else; there
are no JavaScript dependencies).

## Run

```sh
open "build/Swifty Lark.app"
```

or run the executable directly:

```sh
"./build/Swifty Lark.app/Contents/MacOS/Swifty Lark"
```

Screenshot mode (opens without taking focus, waits for the first paint, writes a
PNG and exits):

```sh
"./build/Swifty Lark.app/Contents/MacOS/Swifty Lark" --screenshot shots/now.png
```

Useful extras while checking a build:

```sh
"Swifty Lark" --tab=calendar|docs|contacts|tasks   # open on another screen
"Swifty Lark" --search "editor"                    # open the search overlay with a query
./rust/target/release/swiftylark-core --stats     # core memory, message count, store size
./rust/target/release/swiftylark-core --dump      # the whole workspace as JSON
```

## Where data lives

`~/Library/Application Support/Swifty Lark/store.json`. Delete it to return to the
seeded demo workspace. Set `SWIFTYLARK_HOME` to keep a separate store (used by the
tests in this workspace).

## What is in this first version

- Conversation list with search, unread and group filters, pins, muted chats and
  unread badges; conversation view with day separators, grouped bubbles,
  reactions, attachments and a formatting-toolbar composer.
- Global search (`⌘K`) over messages, conversations, people, docs and tasks.
- Contacts with a profile pane, a week calendar with agenda and next-up panel,
  document cards, and task lists with working checkboxes.
- Settings with light/dark/system theme, sending and notification preferences,
  and a live performance panel reading the core's own memory figure.
- Everything persists through the Rust core; sending, reacting, reading and
  task toggles all round-trip through it.

Not in this version: real Feishu sign-in/network sync (the demo workspace is
local), meetings, mail, wiki, moments and the AI assistant. See `MECHANICS.md`.
