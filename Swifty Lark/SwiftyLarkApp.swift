import SwiftUI
import AppKit

@main
struct SwiftyLarkApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(model)
                .frame(minWidth: 1000, minHeight: 620)
                .background(WindowAccessor { window in
                    delegate.register(window: window)
                })
                .overlay {
                    // Invisible shortcut holders so ⌘K and ⌘, work anywhere.
                    ZStack {
                        Button("Search") { model.searchOpen = true }
                            .keyboardShortcut("k", modifiers: .command)
                        // Lark's openSecondQuickSearch default is Command+F; both open search.
                        Button("Search again") { model.searchOpen = true }
                            .keyboardShortcut("f", modifiers: .command)
                        Button("Settings") { model.showSettings = true }
                            .keyboardShortcut(",", modifiers: .command)
                        Button("Close search") { model.searchOpen = false }
                            .keyboardShortcut(.escape, modifiers: [])
                        Button("Messages") { model.tab = .messages }
                            .keyboardShortcut("1", modifiers: .command)
                        Button("Calendar") { model.tab = .calendar }
                            .keyboardShortcut("2", modifiers: .command)
                        Button("Docs") { model.tab = .docs }
                            .keyboardShortcut("3", modifiers: .command)
                        Button("Contacts") { model.tab = .contacts }
                            .keyboardShortcut("4", modifiers: .command)
                        Button("Tasks") { model.tab = .tasks }
                            .keyboardShortcut("5", modifiers: .command)
                    }
                    .frame(width: 0, height: 0)
                    .opacity(0)
                    .allowsHitTesting(false)
                }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(
            width: CGFloat(MechanicsSheet.shared.number("default window width", 1200)),
            height: CGFloat(MechanicsSheet.shared.number("default window height", 800))
        )
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandGroup(replacing: .appInfo) {}
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var screenshotPath: String?
    private var mainWindow: NSWindow?
    private var didCapture = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        let args = CommandLine.arguments
        if args.contains("--selftest") { runSelfTest() }
        if let i = args.firstIndex(of: "--screenshot"), i + 1 < args.count {
            screenshotPath = args[i + 1]
        } else if let arg = args.first(where: { $0.hasPrefix("--screenshot=") }) {
            screenshotPath = String(arg.dropFirst("--screenshot=".count))
        }

        if screenshotPath != nil {
            NSApp.setActivationPolicy(.accessory)
            NSApp.windows.forEach { $0.orderOut(nil) }
        } else {
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    /// Runs the send-key rules against the real implementation and exits.
    private func runSelfTest() {
        typealias C = ComposerTextView
        let cases: [(String, Bool, Bool, Bool, C.ReturnAction)] = [
            ("hello", true, false, false, .send),
            ("hello", true, false, true, .newline),
            ("hello", false, false, false, .newline),
            ("hello", false, true, false, .send),
            ("hello", true, true, false, .send),
            ("   ", true, false, false, .ignore)
        ]
        var failures = 0
        for (text, sendWithEnter, command, shiftOrOption, expected) in cases {
            let got = C.returnAction(text: text, sendWithEnter: sendWithEnter,
                                     command: command, shiftOrOption: shiftOrOption)
            let ok = got == expected
            if !ok { failures += 1 }
            print("\(ok ? "ok  " : "FAIL") text=\(text.debugDescription) enter=\(sendWithEnter) cmd=\(command) shift=\(shiftOrOption) -> \(got.rawValue) (want \(expected.rawValue))")
        }
        let h = C.height(forLines: C.editorLines)
        print("composer height for \(Int(C.editorLines)) lines: \(h) pt")

        // The sheet is read at launch and drives the drawing code; fail loudly
        // if it did not load or a value has neither a source nor an estimate.
        let sheet = MechanicsSheet.shared
        print("mechanics sheet v\(sheet.version): \(sheet.count) values from \(sheet.loadedFrom ?? "not loaded")")
        print("  list width \(Int(sheet.number("conversation list width", 320))) pt, "
            + "message text \(Int(sheet.number("message text size", 14))) pt, "
            + "window \(Int(sheet.number("default window width", 1200)))×\(Int(sheet.number("default window height", 800)))")
        if sheet.version != 1 || sheet.count == 0 { failures += 1 }
        if sheet.unsourced.isEmpty {
            print("every value has a source or is marked estimated")
        } else {
            failures += 1
            print("UNSOURCED: \(sheet.unsourced.joined(separator: ", "))")
        }
        print(failures == 0 ? "SELFTEST PASS" : "SELFTEST FAIL (\(failures))")
        exit(failures == 0 ? 0 : 1)
    }

    func register(window: NSWindow) {
        guard window.contentView != nil else { return }
        mainWindow = window
        window.title = "Swifty Lark"
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = false
        window.setContentSize(NSSize(
            width: CGFloat(MechanicsSheet.shared.number("default window width", 1200)),
            height: CGFloat(MechanicsSheet.shared.number("default window height", 800))
        ))
        window.center()

        if screenshotPath != nil {
            // Show without taking focus; nothing is activated.
            window.orderFrontRegardless()
            window.makeFirstResponder(nil)
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.4) { [weak self] in
                self?.capture()
            }
        }
    }

    private func capture() {
        let sheet = NSApp.windows.first { $0.isSheet && $0.isVisible }
        guard !didCapture, let path = screenshotPath, let window = sheet ?? mainWindow, let view = window.contentView else {
            exit(2)
        }
        didCapture = true
        view.layoutSubtreeIfNeeded()
        view.displayIfNeeded()

        let data = renderPNG(view: view, window: window)
        guard let data else {
            FileHandle.standardError.write(Data("Swifty Lark: could not render the window\n".utf8))
            exit(3)
        }
        let url = URL(fileURLWithPath: path)
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        do {
            try data.write(to: url)
            print("saved screenshot: \(url.path) (\(data.count) bytes)")
            exit(0)
        } catch {
            FileHandle.standardError.write(Data("Swifty Lark: \(error.localizedDescription)\n".utf8))
            exit(4)
        }
    }

    private func renderPNG(view: NSView, window: NSWindow) -> Data? {
        let bounds = view.bounds
        guard bounds.width > 1, bounds.height > 1 else { return nil }

        // Draw the live view hierarchy into a bitmap (works without screen access).
        if let rep = view.bitmapImageRepForCachingDisplay(in: bounds) {
            view.cacheDisplay(in: bounds, to: rep)
            if let data = rep.representation(using: .png, properties: [:]) {
                if isNotBlank(rep), let scaled = scaledDown(data) { return scaled }
                if isNotBlank(rep) { return data }
            }
        }

        // Fallback: composite the window's layers.
        let layer = view.layer
        if let layer {
            let scale = window.backingScaleFactor
            let w = Int(bounds.width * scale)
            let h = Int(bounds.height * scale)
            if let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                   space: CGColorSpaceCreateDeviceRGB(),
                                   bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue) {
                ctx.scaleBy(x: scale, y: scale)
                layer.render(in: ctx)
                if let img = ctx.makeImage() {
                    let rep = NSBitmapImageRep(cgImage: img)
                    return rep.representation(using: .png, properties: [:])
                }
            }
        }
        return nil
    }

    private func scaledDown(_ data: Data) -> Data? {
        guard let img = NSImage(data: data), img.size.width > 1600 else { return data }
        let scale = 1180 / img.size.width
        let newSize = NSSize(width: img.size.width * scale, height: img.size.height * scale)
        let out = NSImage(size: newSize)
        out.lockFocus()
        img.draw(in: NSRect(origin: .zero, size: newSize))
        out.unlockFocus()
        guard let tiff = out.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) else { return data }
        return rep.representation(using: .png, properties: [:])
    }

    private func isNotBlank(_ rep: NSBitmapImageRep) -> Bool {
        guard let bitmap = rep.bitmapData else { return false }
        let step = max(1, rep.pixelsWide / 40)
        var first: UInt32 = 0
        var distinct = false
        var count = 0
        for y in stride(from: 0, to: rep.pixelsHigh, by: max(1, rep.pixelsHigh / 30)) {
            for x in stride(from: 0, to: rep.pixelsWide, by: step) {
                let offset = y * rep.bytesPerRow + x * rep.samplesPerPixel
                let value = UInt32(bitmap[offset]) << 16 | UInt32(bitmap[offset + 1]) << 8 | UInt32(bitmap[offset + 2])
                if count == 0 { first = value } else if value != first { distinct = true }
                count += 1
            }
        }
        return distinct
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
