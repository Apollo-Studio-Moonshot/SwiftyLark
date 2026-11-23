# Swifty Lark — mechanics sheet

What this app reproduces from Feishu / Lark, and where each number came from.

The machine-readable copy is `mechanics.json` (version 1) next to this file. The
build ships it into `Swifty Lark.app/Contents/Resources/mechanics.json`, and the
app loads it at launch (`Mechanics.swift`). The palette, conversation-list
width, message text size, composer line count, default window size, default
send key and notification default are all read from that sheet, so editing the
sheet changes the app rather than drifting away from a constant in the code.
`Swifty Lark --selftest` prints the sheet it loaded and fails if a value has
neither a source nor `"estimated": true`.

## How the original was inspected

`/Applications/Lark.app` is a 1.7 GB Electron bundle (Chromium 147.0.7727.149,
`CFBundleIdentifier com.electron.lark`, `CFBundleExecutable Feishu`). Nothing was
executed — no Lark process, no sign-in, no network call.

This round the native layer was decompiled, not just the web bundle read:

1. **`Contents/MacOS/Feishu`** — Mach-O arm64 launcher, 976,880 bytes, sha256
   `25738a3e6216bc1abe2e83b92ba553d51baf91728ce0eb8335708fab3fec1a6c`. Opened
   with `core_target_open`; strings searched with `native_strings_find`; the
   functions holding them were followed through their references and read with
   `native_function_pseudocode`.
2. **`Contents/Frameworks/Lark Framework.framework/Versions/Current/Lark Framework`**
   — 305,580,144 bytes, sha256
   `1371f21ee5de4aeaf4a7ec8af5c25e285768fa0f4b29d668ca0c5eaf3af07ae1`. This is
   where the app's own code lives; `_LarkMain` is an exported symbol.
3. **`Libraries/liblark.dylib`** (94,511,904 bytes) was searched too, but it is a
   merged static blob: its 62 exports do not include `LarkMain` and its string
   pool is one concatenated table, so per-function attribution there was
   unreliable. Nothing below is taken from it.
4. **The settings layer** — `webcontent/setting.asar` (extracted read-only with
   `core_archive_extract`) holds the JavaScript that defines Lark's default
   preferences and its shortcut editor; `webcontent/messenger.asar` holds the
   composer's key handling. Minified, but not obfuscated: the defaults are
   quoted exactly below.

Decompiler note: Ghidra is installed but its macOS decompiler binary is missing,
so the built-in Clean-room lifter produced the pseudo-code (every such evidence
record carries `deep_engine_unavailable`). Addresses, call lists and string
arguments are exact; the C is register-level with types unrecovered, so only
literals, string arguments and call order were treated as facts.

## Native layer — functions read, and what they establish

| Address | Function | What the pseudo-code shows |
| --- | --- | --- |
| `0x100008c68` | `_main` (Feishu) | Bootstraps Chromium (`sub_1000246c8(1)`, `sub_10007007c`, `sub_100020ae0`, `sub_100020b80`, `sub_100020ea4`, `sub_1000782c0`), then calls `_dlsym(handle, "LarkMain")` and jumps to the result; if it is null it logs `dlsym LarkMain: %s.` and exits. The visible program is a loader — the UI logic is in the framework. |
| `0x1000201c0` | Feishu init | Builds `com.electron.lark.font_workaround` (33 = `0x21` bytes) and calls the preference API `sub_100075558(14, …)`. A real persisted font-workaround preference; its folder exists on this machine at `~/Library/Application Support/com.electron.lark.font_workaround`. |
| `0x1000205ec` | framework locator | Walks a 13-entry pointer table at `data_1000cb638`, compares each name with an ASCII case fold (`-0x41 / +0x20`, `csel`), and returns the entry equal to `Lark Framework` — how the launcher finds the framework it dlopens. |
| `0x42a5a60` | `_LarkMain` (Lark Framework export) | The real app entry: 266 lines, 18 gotos, calls `sub_18654e8`, `sub_18ded50`, `sub_23385e8`, `sub_23d8138`, `sub_ab344e0`, `sub_bb1c1f0` and friends. No window geometry literal survives at this level. |
| `0x4523ea0` | shortcut registry | 767 basic blocks, 6,164-line pseudo-code: builds the app's shortcut table. The strings it references are the registered ids — `lark.shortcut.return`, `lark.shortcut.close_widget_by_escape`, `lark.shortcut.im_next_unread_chat`, `lark.shortcut.im_previous_unr…`, `lark.shortcut.im_next_feed_filter`, `lark.shortcut.im_open_chat_in`, `lark.shortcut.im_expand_coll…`, `lark.shortcut.im_save_image_videos`, `lark.shortcut.im_voice_input`, `lark.shortcut.tab_content_*`, `lark.shortcut.accessibility_*`. This is why message-list filtering and unread navigation are keyboard-driven in Lark. |
| `0x3eae5a4` | theme preference reader | 1,062 lines; references `lark.setting.theme`, `lark.setting.content_theme` and `lark.setting.skin` — three separate stored values, so shell theme, content theme and skin are independent. |
| `0x4575fdc` | URL-open preference | 74 lines; calls a getter for `lark.setting.url_default_open_method` (argument length `0x24` = 36, exactly the string's length) and copies the returned string out. Links have a user-selectable open method. |

What the native layer does **not** hold: the default main-window size, the
send-key default, or filter labels. None of those are compiled literals — they
are in the settings layer.

## Values read from Lark's own settings layer (not estimated)

Source: `webcontent/setting.asar`, module `common/701c8997c4.js` (identical copy
in `common/1b3c9266fa.js`), the object returned when nothing has been saved yet:

```
autoLaunch: false
uiSetting:  { editorHeight: "3", doneNext: true }
shortcut:   { send: "Enter",
              openQuickSearch: "Command+K",
              openChatWindow: "Command+Shift+W",
              screenCapture: "Command+Shift+A",
              systemOpenQuickSearch: false,
              openSecondQuickSearch: "Command+F",
              muteOrUnmuteMic: "Command+Shift+D",
              startOrStopCam: "Command+Shift+V",
              systemOpenMic: false, systemOpenCam: false,
              recentListNext: "Control+Tab",
              recentListPrev: "Control+Shift+Tab" }
notifySetting: { notifySound: true, showDetail: true, showUnreadNumber: true,
                 newMessagePush: true, badgeStyle: 1 /* WEAK_REMIND */ }
```

Further evidence:

- `ShortcutSettingModal/510bc4a0e4.js` defines the two send-key choices —
  `Kt = "Enter"` (default) and ``Dt = `${Rt}+Enter` `` (the alternate) — and its
  shortcut label map contains `Command+,` for Settings.
- `webcontent/messenger.asar`, `common/c7d390d4c5.js`, `sendMessageKeyDown`: on
  `keyCode === RETURN` it sends only when `(0, eJ.l7)(event, shortcut)` matches
  the stored shortcut, then calls `preventDefault`. Return is a shortcut, not a
  hard-wired behaviour.
- `messenger.asar`, `app-chat~1/b86792886a.js` uses `feedFilterType: "TEAM"` when
  opening the team view, so the message list really has filter categories
  (team, unread, tag) rather than one flat list.
- `Libraries/lark_settings` (2,269,350 bytes of JSON) is the server-driven config,
  not local defaults; it was checked and does not define the composer or window
  defaults.

## Design tokens (evidenced)

| Token | Light | Dark | Source |
| --- | --- | --- | --- |
| Primary accent | `#3370ff` | `#4a86ff` (the app brightens accent on dark) | `main-window.asar` CSS, 6 uses of `#3370ff` |
| Content background | `#f8f9fa` | `#121212` | `--bg-content-base` in `css/ce657887.css` |
| Sidebar / panel | `#f5f6f7` (`--N50`) | `#1a1a1a` (`--N50`) | N-scale tokens |
| Primary text | `#1f2329` (`--N900`) | `#ebebeb` (`--N900`) | N-scale tokens |
| Secondary text | `#646a73` (`--N600`) | `#a6a6a6` (`--N600`) | N-scale tokens |
| Muted text | `#8f959e` (`--N500`) | `#757575` (`--N500`) | N-scale tokens |
| Divider | `#dee0e3` (`--N300`) | `#434343` (`--N300`) | N-scale tokens |
| Selected row | `#f0f4ff` | tinted accent | CSS `background-color:#f0f4ff` |
| Unread badge | `#fa1f41` | `#f54a45` | CSS, 4 uses of `#fa1f41` |
| Corner radius | 8 px | 8 px | `messenger.asar` CSS, 623 uses of `border-radius:8px` |
| Message text | 14 px | 14 px | `messenger.asar` CSS, 1112 uses of `font-size:14px` |
| Conversation list | 320 px | 320 px | `messenger.asar` CSS, 46 uses of `width:320px` |
| Window width | 1200 px | 1200 px | `main-window.asar` JS `width: 1200` |

Dark-mode values are the paired `--N*` tokens from the same CSS files (the
stylesheet carries both light and dark blocks).

## Layout rebuilt from the evidence

- Full-width custom title bar (46 px): workspace chip on the left with 78 px
  leading space for the traffic lights, centred global search pill with `⌘K`,
  notification / create / settings icons and the user's avatar on the right.
- 60 px icon rail: Messages, Calendar, Docs, Contacts, Tasks, then Apps, Help,
  and Settings + avatar pinned to the bottom. The Messages icon shows the total
  unread count.
- Messages: 320 px conversation column (title, search, All/Unread/Groups chips,
  rows with 38 px avatar, 13 px name, 11 px preview, trailing time and red
  unread pill) and the conversation pane (56 px header with member count, video,
  call, add-people and more; day separators; grouped bubbles; reactions;
  attachment cards; composer with formatting toolbar and Send button).
- Calendar, Docs, Contacts and Tasks are secondary screens on the same rail:
  week strip + day agenda + next-up/week/online panel; document cards by type;
  people list with a profile pane; grouped task lists with checkboxes.
- Global search (`⌘K`, `⌘F`) queries the Rust core across messages,
  conversations, people, docs and tasks and groups the hits.

## Rules the build now follows, and where each comes from

- **Send key.** Default `send: "Enter"`: Return sends, `Shift+Return` (or
  `Option+Return`) inserts a line, `Command+Return` always sends. The alternate
  setting (`Command+Enter`) makes Return insert a line and only `Command+Return`
  send. Source: the defaults object, `Kt`/`Dt`, and `sendMessageKeyDown`.
  *This was a real bug: Settings stored the preference but the composer always
  sent on Return.*
- **Composer height.** `uiSetting.editorHeight: "3"` — the editor is laid out for
  three lines (`ComposerTextView.editorLines` reads `composer editor height` from
  the sheet; height is derived from the font's line height instead of a fixed
  62 pt).
- **Search.** `Command+K` (openQuickSearch) and `Command+F`
  (openSecondQuickSearch) both open global search.
- **Settings.** `Command+,` from the shortcut label map.
- **Unread badge.** `showUnreadNumber: true` with `badgeStyle: 1` — the dock tile
  carries the unread count (`NSApp.dockTile.badgeLabel`), updated as the total
  changes.
- **Chat filters.** All / Unread / Groups maps to Lark's `feedFilterType`
  categories (all, `UNREAD`, `TEAM`); Lark cycles feed filters from the keyboard
  via `lark.shortcut.im_next_feed_filter`.
- **Theme.** Shell theme is a stored `lark.setting.theme` value with light / dark
  / system choices (native `0x3eae5a4`).

## Numbers that are still not evidenced

- **Default window height (800 px).** The main window is created in native code;
  no height literal appears in that path, and Lark restores saved bounds instead
  of shipping a constant. 1200 × 800 is kept as the build's default and is *not*
  presented as read from the original. Settling it needs a first launch of the
  original on a clean profile (its saved window rect) — not done, nothing is run.
- **The third filter's label.** The category (`TEAM`) is evidenced; the English
  word on the chip ("Groups") was not read out of an i18n bundle.
- **Notification sounds.** The bundle ships `notify-normal-new.wav`,
  `notify-urgent-new.wav`, `notify-special_focus-new.wav` and
  `notify-at-new.wav`, and `notifySound` defaults to true. This build stores the
  setting but does not play them.
- **"≈ 600 MB typical Chromium client"** in Settings is an estimate for
  comparison only, not a measurement of the original on this machine.

## Core behaviour (implemented in Rust, `app/rust/src/main.rs`)

- Line-delimited JSON request/response on stdin/stdout; the SwiftUI client owns
  the subprocess, so there is no HTTP port, no browser engine and no renderer
  process.
- State (chats, messages, contacts, docs, events, tasks, preferences) persists to
  `~/Library/Application Support/Swifty Lark/store.json` via an atomic
  write-then-rename, so an interrupted save cannot corrupt the store.
- Commands: `state`, `send`, `read`, `react`, `toggle_task`, `add_task`,
  `set_prefs`, `search`, `stats`, `save`, `ping`.
- Opening a conversation clears its unread count and persists the change.
- Reactions toggle on/off and keep a per-emoji count with a "mine" flag.
- `stats` reports the core's own RSS (measured 2.4 MB, 2 threads) — the number
  the Settings → Performance panel displays.

## Open questions

1. Exact default window height and minimum size on macOS (CSS shows modal
   `min-width:1208px`; the JS shows `width: 1200`). Would be settled by running
   the original and reading its window frame.
2. Whether Lark plays all four notification WAVs on every message or only for
   mentions — the file names imply levels (normal / urgent / special focus / at)
   but the trigger rules were not read.
3. Whether Lark keeps a local message cache separate from the server; this
   rebuild always persists locally, a deliberate choice for an offline-capable
   native client rather than a copy of Lark's storage.

## Deliberately not reproduced (first version)

- Real Feishu/Lark account sign-in and network sync: the public API needs an
  app id/secret and OAuth, and this build ships a local demo workspace instead.
- Video meetings, mail, wiki spaces, moments and the AI assistant panels.
- Notification sounds and per-shortcut remapping (Lark's shortcut editor writes
  the same keys the native registry reads).
