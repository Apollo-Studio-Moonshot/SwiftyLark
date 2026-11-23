import Foundation

/// One value from app/mechanics.json. The sheet is the single source of truth
/// for the numbers and colours this app draws with, so changing the sheet
/// changes the app instead of leaving a stale constant behind in the code.
enum MechValue {
    case number(Double)
    case text(String)
    case flag(Bool)
}

struct MechanicsSheet {
    struct Entry {
        let name: String
        let group: String
        let value: MechValue
        let unit: String?
        let source: String?
        let estimated: Bool
    }

    static let shared = MechanicsSheet()

    private var byName: [String: Entry] = [:]
    private(set) var loadedFrom: String?
    private(set) var version: Int = 0

    private init() {
        guard let (data, path) = MechanicsSheet.locate(),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let values = root["values"] as? [[String: Any]] else { return }
        version = root["version"] as? Int ?? 0
        loadedFrom = path
        for raw in values {
            guard let name = raw["name"] as? String,
                  let group = raw["group"] as? String else { continue }
            let value: MechValue?
            if let n = raw["value"] as? NSNumber {
                // JSON booleans also arrive as NSNumber; tell them apart.
                if CFGetTypeID(n) == CFBooleanGetTypeID() {
                    value = .flag(n.boolValue)
                } else {
                    value = .number(n.doubleValue)
                }
            } else if let s = raw["value"] as? String {
                value = .text(s)
            } else {
                value = nil
            }
            guard let parsed = value else { continue }
            byName[name] = Entry(
                name: name,
                group: group,
                value: parsed,
                unit: raw["unit"] as? String,
                source: raw["source"] as? String,
                estimated: raw["estimated"] as? Bool ?? false
            )
        }
    }

    /// mechanics.json is shipped inside the bundle; the other paths let the
    /// binary run straight from the source tree during development.
    private static func locate() -> (Data, String)? {
        var candidates: [URL] = []
        if let bundled = Bundle.main.url(forResource: "mechanics", withExtension: "json") {
            candidates.append(bundled)
        }
        let exe = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath()
        candidates.append(exe.deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Resources/mechanics.json"))
        let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        candidates.append(cwd.appendingPathComponent("app/mechanics.json"))
        candidates.append(cwd.appendingPathComponent("mechanics.json"))
        candidates.append(cwd.deletingLastPathComponent().appendingPathComponent("app/mechanics.json"))
        for url in candidates {
            if let data = try? Data(contentsOf: url) {
                return (data, url.path)
            }
        }
        return nil
    }

    var count: Int { byName.count }

    func entry(_ name: String) -> Entry? { byName[name] }

    func number(_ name: String, _ fallback: Double) -> Double {
        if case .number(let v)? = byName[name]?.value { return v }
        return fallback
    }

    func text(_ name: String, _ fallback: String) -> String {
        if case .text(let v)? = byName[name]?.value { return v }
        return fallback
    }

    func flag(_ name: String, _ fallback: Bool) -> Bool {
        if case .flag(let v)? = byName[name]?.value { return v }
        return fallback
    }

    /// Every value must carry a source or be explicitly marked estimated.
    /// Used by --selftest so an invalid sheet fails the build check loudly.
    var unsourced: [String] {
        byName.values
            .filter { ($0.source ?? "").isEmpty && !$0.estimated }
            .map(\.name)
            .sorted()
    }
}
