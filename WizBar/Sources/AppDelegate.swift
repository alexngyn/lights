import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let menu = NSMenu()
    private let brightness = SliderMenuItem(symbol: "sun.max", label: "Brightness", unit: "%", min: 10, max: 100)
    private let temperature = SliderMenuItem(symbol: "thermometer.medium", label: "Color temperature", unit: "K", min: 2200, max: 6500)
    private let powerItem = SwitchMenuItem(title: "Lights")
    private let lightsHeader = NSMenuItem.sectionHeader(title: "Lights")
    private var lightItems: [NSMenuItem] = []
    private let presetsHeader = NSMenuItem.sectionHeader(title: "Presets")
    private var presetItems: [NSMenuItem] = []
    private let presetStore = PresetStore()
    private let lightStore = LightStore()
    private var settingsWindow: NSWindow?

    private let defaults = UserDefaults.standard
    /// Every light discovered so far.
    private var lights: [String] { lightStore.lights }
    /// Lights to control. Empty means all.
    private var selected: Set<String> {
        get { Set(defaults.stringArray(forKey: "selected") ?? []) }
        set { defaults.set(Array(newValue).sorted(), forKey: "selected") }
    }
    private var targets: [String] {
        let sel = selected
        return sel.isEmpty ? lights : lights.filter(sel.contains)
    }

    private var isOn = true { didSet { updateIcon() } }
    private var lastSend = Date.distantPast
    private var pending: DispatchWorkItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        buildMenu()
        updateIcon()
        statusItem.menu = menu
        discover()
    }

    // MARK: Menu

    private func buildMenu() {
        menu.delegate = self
        menu.autoenablesItems = false

        brightness.onChange = { [weak self] v, final in
            self?.send(["state": true, "dimming": WizClient.clampDimming(v)], final: final)
        }
        temperature.onChange = { [weak self] v, final in
            self?.send(["state": true, "temp": WizClient.clampTemp(v)], final: final)
        }
        powerItem.onChange = { [weak self] on in self?.setPower(on) }
        menu.addItem(powerItem)
        menu.addItem(brightness)
        menu.addItem(temperature)

        menu.addItem(.separator())
        menu.addItem(presetsHeader)
        rebuildPresetItems()

        menu.addItem(.separator())
        menu.addItem(lightsHeader)
        rebuildLightItems()

        menu.addItem(.separator())
        let settings = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)
        let quit = NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate), keyEquivalent: "q")
        menu.addItem(quit)
    }

    private func rebuildPresetItems() {
        presetItems.forEach(menu.removeItem)
        presetItems = presetStore.presets.enumerated().map { i, p in
            let item = NSMenuItem(title: "\(p.name)  —  \(p.dimming)%, \(p.temp)K",
                                  action: #selector(applyPreset), keyEquivalent: i < 9 ? "\(i + 1)" : "")
            item.tag = i
            item.target = self
            return item
        }
        if presetItems.isEmpty {
            let none = NSMenuItem(title: "No presets", action: nil, keyEquivalent: "")
            none.isEnabled = false
            presetItems.append(none)
        }
        var index = menu.index(of: presetsHeader) + 1
        for item in presetItems {
            menu.insertItem(item, at: index)
            index += 1
        }
    }

    private func rebuildLightItems() {
        lightItems.forEach(menu.removeItem)
        lightItems = []
        let sel = selected

        let all = NSMenuItem(title: "All Lights", action: #selector(selectAll), keyEquivalent: "")
        all.state = sel.isEmpty ? .on : .off
        lightItems.append(all)

        for ip in lights {
            let item = NSMenuItem(title: lightStore.displayName(ip), action: #selector(toggleLight), keyEquivalent: "")
            item.representedObject = ip
            item.toolTip = ip
            item.state = sel.contains(ip) ? .on : .off
            item.indentationLevel = 1
            lightItems.append(item)
        }
        if lights.isEmpty {
            let none = NSMenuItem(title: "No lights found", action: nil, keyEquivalent: "")
            none.isEnabled = false
            lightItems.append(none)
        }

        let refresh = NSMenuItem(title: "Refresh Lights", action: #selector(refreshLights), keyEquivalent: "r")
        lightItems.append(refresh)

        var index = menu.index(of: lightsHeader) + 1
        for item in lightItems {
            if item.action != nil { item.target = self }
            menu.insertItem(item, at: index)
            index += 1
        }
    }

    func menuWillOpen(_ menu: NSMenu) {
        rebuildPresetItems()
        rebuildLightItems()
        syncState()
    }

    private func updateIcon() {
        let name = isOn ? "lightbulb.fill" : "lightbulb"
        let image = NSImage(systemSymbolName: name, accessibilityDescription: "Lights")
        image?.isTemplate = true
        statusItem.button?.image = image
        powerItem.isOn = isOn
    }

    // MARK: Light control

    /// Throttles slider drags to ~10 sends/sec, always delivering the last value.
    private func send(_ params: [String: Any], final: Bool) {
        pending?.cancel()
        isOn = true
        let elapsed = Date().timeIntervalSince(lastSend)
        if final || elapsed >= 0.1 {
            lastSend = Date()
            WizClient.setPilot(targets, params)
        } else {
            let work = DispatchWorkItem { [weak self] in self?.send(params, final: true) }
            pending = work
            DispatchQueue.main.asyncAfter(deadline: .now() + (0.1 - elapsed), execute: work)
        }
    }

    /// Reads the first target's state to position the sliders.
    private func syncState() {
        guard let ip = targets.first else { return }
        DispatchQueue.global().async {
            guard let pilot = WizClient.getPilot(ip) else { return }
            DispatchQueue.main.async {
                self.isOn = pilot.state
                if let d = pilot.dimming { self.brightness.value = d }
                if let t = pilot.temp { self.temperature.value = t }
            }
        }
    }

    private func discover() {
        let known = lights
        DispatchQueue.global().async {
            let found = WizClient.discover(known: known)
            DispatchQueue.main.async {
                // Keep previously known lights even if one didn't answer this time.
                self.lightStore.merge(found.keys)
                self.rebuildLightItems()
                self.syncState()
            }
        }
    }

    // MARK: Actions

    private func setPower(_ on: Bool) {
        isOn = on
        WizClient.setPilot(targets, ["state": on])
    }

    @objc private func applyPreset(_ sender: NSMenuItem) {
        guard presetStore.presets.indices.contains(sender.tag) else { return }
        apply(presetStore.presets[sender.tag])
    }

    private func apply(_ p: Preset) {
        brightness.value = p.dimming
        temperature.value = p.temp
        isOn = true
        WizClient.setPilot(targets, ["state": true, "dimming": p.dimming, "temp": p.temp])
    }

    @objc private func selectAll() {
        selected = []
        rebuildLightItems()
        syncState()
    }

    @objc private func toggleLight(_ sender: NSMenuItem) {
        guard let ip = sender.representedObject as? String else { return }
        var sel = selected
        if sel.contains(ip) { sel.remove(ip) } else { sel.insert(ip) }
        selected = sel
        rebuildLightItems()
        syncState()
    }

    @objc private func refreshLights() {
        lightStore.lights = []
        discover()
    }

    @objc private func openSettings() {
        if settingsWindow == nil {
            let view = SettingsView(
                store: presetStore,
                lightStore: lightStore,
                current: { [weak self] in (self?.brightness.value ?? 70, self?.temperature.value ?? 3500) },
                apply: { [weak self] in self?.apply($0) })
            let window = NSWindow(contentViewController: NSHostingController(rootView: view))
            window.title = "WizBar Settings"
            window.styleMask = [.titled, .closable, .resizable]
            window.isReleasedWhenClosed = false
            window.center()
            settingsWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }
}
