import Foundation

/// Discovered lights and the names given to them in Settings, saved in UserDefaults.
final class LightStore: ObservableObject {
    private let defaults = UserDefaults.standard

    /// Every light discovered so far (IP addresses, sorted).
    @Published var lights: [String] {
        didSet { defaults.set(lights, forKey: "lights") }
    }
    /// IP -> user-given name.
    @Published var names: [String: String] {
        didSet { defaults.set(names, forKey: "lightNames") }
    }

    init() {
        lights = defaults.stringArray(forKey: "lights") ?? []
        names = defaults.dictionary(forKey: "lightNames") as? [String: String] ?? [:]
    }

    /// The name if one is set, otherwise the IP.
    func displayName(_ ip: String) -> String {
        let name = names[ip]?.trimmingCharacters(in: .whitespaces) ?? ""
        return name.isEmpty ? ip : name
    }

    func merge(_ found: some Sequence<String>) {
        lights = Set(lights).union(found).sorted { $0.compare($1, options: .numeric) == .orderedAscending }
    }

    /// Blinks one light three times so you can tell which one it is, then
    /// restores it. Calls `done(false)` if the light doesn't answer.
    func identify(_ ip: String, done: @escaping (Bool) -> Void) {
        DispatchQueue.global().async {
            let wasOn = WizClient.getPilot(ip)?.state ?? true
            var ok = false
            for _ in 0..<3 {
                ok = WizClient.setPilotSync(ip, ["state": !wasOn]) || ok
                usleep(600_000)
                ok = WizClient.setPilotSync(ip, ["state": wasOn]) || ok
                usleep(600_000)
            }
            DispatchQueue.main.async { done(ok) }
        }
    }
}
