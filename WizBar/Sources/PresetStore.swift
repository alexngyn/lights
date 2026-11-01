import Foundation

struct Preset: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var dimming: Int
    var temp: Int
}

/// Presets saved in UserDefaults, edited from the Settings window.
final class PresetStore: ObservableObject {
    static let defaults = [
        Preset(name: "Bright", dimming: 100, temp: 5000),
        Preset(name: "Reading", dimming: 80, temp: 4000),
        Preset(name: "Relax", dimming: 50, temp: 2700),
        Preset(name: "Night", dimming: 10, temp: 2200),
    ]
    private static let key = "presets"

    @Published var presets: [Preset] {
        didSet { save() }
    }

    init() {
        if let data = UserDefaults.standard.data(forKey: Self.key),
           let saved = try? JSONDecoder().decode([Preset].self, from: data) {
            presets = saved
        } else {
            presets = Self.defaults
        }
    }

    func add(dimming: Int, temp: Int) {
        presets.append(Preset(name: "Preset \(presets.count + 1)", dimming: dimming, temp: temp))
    }

    func remove(_ id: UUID) {
        presets.removeAll { $0.id == id }
    }

    func move(_ id: UUID, by offset: Int) {
        guard let i = presets.firstIndex(where: { $0.id == id }) else { return }
        let j = i + offset
        guard presets.indices.contains(j) else { return }
        presets.swapAt(i, j)
    }

    func resetToDefaults() {
        presets = Self.defaults
    }

    private func save() {
        if let data = try? JSONEncoder().encode(presets) {
            UserDefaults.standard.set(data, forKey: Self.key)
        }
    }
}
