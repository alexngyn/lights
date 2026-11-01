import ServiceManagement
import SwiftUI

struct SettingsView: View {
    @ObservedObject var store: PresetStore
    @ObservedObject var lightStore: LightStore
    /// Current slider values in the menu: (dimming, temp).
    let current: () -> (Int, Int)
    let apply: (Preset) -> Void

    var body: some View {
        TabView {
            GeneralTab()
                .tabItem { Label("General", systemImage: "gearshape") }
            PresetsTab(store: store, current: current, apply: apply)
                .tabItem { Label("Presets", systemImage: "slider.horizontal.3") }
            LightsTab(store: lightStore)
                .tabItem { Label("Lights", systemImage: "lightbulb") }
        }
        .padding(12)
        .frame(minWidth: 700, minHeight: 380)
    }
}

private struct GeneralTab: View {
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle("Launch at Login", isOn: $launchAtLogin)
                .onChange(of: launchAtLogin) { _, on in
                    let service = SMAppService.mainApp
                    guard on != (service.status == .enabled) else { return }
                    do {
                        if on { try service.register() } else { try service.unregister() }
                        error = nil
                    } catch {
                        self.error = error.localizedDescription
                        launchAtLogin = service.status == .enabled
                    }
                }
            Text("Start WizBar automatically when you log in.")
                .font(.caption)
                .foregroundStyle(.secondary)
            if let error {
                Text(error).font(.caption).foregroundStyle(.red)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .onAppear { launchAtLogin = SMAppService.mainApp.status == .enabled }
    }
}

private struct LightsTab: View {
    @ObservedObject var store: LightStore
    @State private var blinking: Set<String> = []
    @State private var failed: Set<String> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Light names").font(.headline)
            Text("Names replace IP addresses in the menu. Use Identify to blink a light and see which one it is.")
                .font(.caption)
                .foregroundStyle(.secondary)

            List {
                ForEach(store.lights, id: \.self) { ip in
                    HStack(spacing: 12) {
                        Image(systemName: "lightbulb").foregroundStyle(.secondary)
                        TextField("Name", text: nameBinding(ip), prompt: Text(ip))
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 220)
                        Text(ip)
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                        Spacer()
                        if failed.contains(ip) {
                            Text("No response").font(.caption).foregroundStyle(.red)
                        }
                        Button(blinking.contains(ip) ? "Blinking…" : "Identify") {
                            blinking.insert(ip)
                            failed.remove(ip)
                            store.identify(ip) { ok in
                                blinking.remove(ip)
                                if !ok { failed.insert(ip) }
                            }
                        }
                        .buttonStyle(.bordered)
                        .disabled(blinking.contains(ip))
                    }
                    .padding(.vertical, 4)
                }
            }
            .listStyle(.bordered(alternatesRowBackgrounds: true))
            .overlay {
                if store.lights.isEmpty {
                    Text("No lights found yet. Use Refresh Lights in the menu.")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(8)
    }

    private func nameBinding(_ ip: String) -> Binding<String> {
        Binding(get: { store.names[ip] ?? "" },
                set: { store.names[ip] = $0.isEmpty ? nil : $0 })
    }
}

private struct PresetsTab: View {
    @ObservedObject var store: PresetStore
    let current: () -> (Int, Int)
    let apply: (Preset) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Presets").font(.headline)
            Text("Shown in the Presets menu. The first nine get ⌘1–⌘9.")
                .font(.caption)
                .foregroundStyle(.secondary)

            List {
                ForEach($store.presets) { $preset in
                    PresetRow(preset: $preset,
                              isFirst: preset.id == store.presets.first?.id,
                              isLast: preset.id == store.presets.last?.id,
                              apply: { apply(preset) },
                              move: { store.move(preset.id, by: $0) },
                              remove: { store.remove(preset.id) })
                }
            }
            .listStyle(.bordered(alternatesRowBackgrounds: true))

            HStack {
                Button {
                    store.add(dimming: 70, temp: 3500)
                } label: {
                    Label("Add", systemImage: "plus")
                }
                Button {
                    let (d, t) = current()
                    store.add(dimming: d, temp: t)
                } label: {
                    Label("Add from Current Light", systemImage: "lightbulb")
                }
                Spacer()
                Button("Reset to Defaults") { store.resetToDefaults() }
            }
        }
        .padding(8)
    }
}

private struct PresetRow: View {
    @Binding var preset: Preset
    let isFirst: Bool
    let isLast: Bool
    let apply: () -> Void
    let move: (Int) -> Void
    let remove: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            TextField("Name", text: $preset.name)
                .textFieldStyle(.roundedBorder)
                .frame(width: 120)

            Image(systemName: "sun.max").foregroundStyle(.secondary)
            Slider(value: intBinding(\.dimming), in: 10...100, step: 1)
                .frame(width: 110)
            Text("\(preset.dimming)%")
                .monospacedDigit()
                .frame(width: 40, alignment: .trailing)

            Image(systemName: "thermometer.medium").foregroundStyle(.secondary)
            Slider(value: intBinding(\.temp), in: 2200...6500, step: 100)
                .frame(width: 110)
            Text("\(preset.temp)K")
                .monospacedDigit()
                .frame(width: 52, alignment: .trailing)

            Spacer(minLength: 0)

            Button(action: apply) { Image(systemName: "play.fill") }
                .help("Apply to lights")
            Button { move(-1) } label: { Image(systemName: "chevron.up") }
                .disabled(isFirst)
                .help("Move up")
            Button { move(1) } label: { Image(systemName: "chevron.down") }
                .disabled(isLast)
                .help("Move down")
            Button(action: remove) { Image(systemName: "trash") }
                .help("Delete")
        }
        .buttonStyle(.borderless)
        .padding(.vertical, 4)
    }

    private func intBinding(_ key: WritableKeyPath<Preset, Int>) -> Binding<Double> {
        Binding(get: { Double(preset[keyPath: key]) },
                set: { preset[keyPath: key] = Int($0.rounded()) })
    }
}
