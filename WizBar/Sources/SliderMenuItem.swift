import AppKit

/// Menu item hosting an icon + continuous slider, like the brightness row in
/// macOS display menu bar utilities.
final class SliderMenuItem: NSMenuItem {
    let slider: NSSlider
    private let valueLabel = NSTextField(labelWithString: "")
    private let unit: String
    /// Called with (value, isFinal). isFinal is true on mouse-up.
    var onChange: ((Int, Bool) -> Void)?

    init(symbol: String, label: String, unit: String, min: Double, max: Double) {
        slider = NSSlider(value: min, minValue: min, maxValue: max, target: nil, action: nil)
        self.unit = unit
        super.init(title: label, action: nil, keyEquivalent: "")

        // The menu sizes itself from its widest item; let this row stretch to
        // match, with the slider growing and the value pinned to the right.
        // Size the value label to the widest possible text so the slider can
        // run right up to it.
        let font = NSFont.monospacedDigitSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular)
        let labelWidth = ceil(["\(Int(min))\(unit)", "\(Int(max))\(unit)"]
            .map { ($0 as NSString).size(withAttributes: [.font: font]).width }
            .max() ?? 40) + 4  // + text field cell padding
        let width: CGFloat = 290, rightInset: CGFloat = 16, gap: CGFloat = 8
        let labelX = width - rightInset - labelWidth

        let view = NSView(frame: NSRect(x: 0, y: 0, width: width, height: 30))
        view.autoresizingMask = [.width]
        let icon = NSImageView(frame: NSRect(x: 16, y: 6, width: 18, height: 18))
        icon.image = NSImage(systemSymbolName: symbol, accessibilityDescription: label)
        icon.contentTintColor = .secondaryLabelColor
        slider.frame = NSRect(x: 42, y: 4, width: labelX - gap - 42, height: 22)
        slider.autoresizingMask = [.width]
        slider.isContinuous = true
        slider.target = self
        slider.action = #selector(changed)
        slider.toolTip = label
        valueLabel.frame = NSRect(x: labelX, y: 7, width: labelWidth, height: 16)
        valueLabel.autoresizingMask = [.minXMargin]
        valueLabel.alignment = .right
        valueLabel.font = font
        valueLabel.textColor = .secondaryLabelColor
        view.addSubview(icon)
        view.addSubview(slider)
        view.addSubview(valueLabel)
        self.view = view
        updateLabel()
    }

    required init(coder: NSCoder) { fatalError("init(coder:) not used") }

    var value: Int {
        get { Int(slider.doubleValue.rounded()) }
        set { slider.doubleValue = Double(newValue); updateLabel() }
    }

    private func updateLabel() {
        valueLabel.stringValue = "\(value)\(unit)"
    }

    @objc private func changed() {
        updateLabel()
        onChange?(value, NSApp.currentEvent?.type == .leftMouseUp)
    }
}
