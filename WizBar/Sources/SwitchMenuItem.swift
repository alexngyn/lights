import AppKit

/// Menu row with a title on the left and an NSSwitch on the right, styled to
/// line up with SliderMenuItem.
final class SwitchMenuItem: NSMenuItem {
    private let toggle = NSSwitch()
    var onChange: ((Bool) -> Void)?

    init(title: String) {
        super.init(title: title, action: nil, keyEquivalent: "")

        let width: CGFloat = 290, height: CGFloat = 32
        let view = NSView(frame: NSRect(x: 0, y: 0, width: width, height: height))
        view.autoresizingMask = [.width]

        let label = NSTextField(labelWithString: title)
        label.font = .menuFont(ofSize: 0).bold
        label.sizeToFit()
        label.frame.origin = NSPoint(x: 16, y: (height - label.frame.height) / 2)

        toggle.controlSize = .small
        toggle.sizeToFit()
        toggle.frame.origin = NSPoint(x: width - 16 - toggle.frame.width,
                                      y: (height - toggle.frame.height) / 2)
        toggle.autoresizingMask = [.minXMargin]
        toggle.target = self
        toggle.action = #selector(changed)

        view.addSubview(label)
        view.addSubview(toggle)
        self.view = view
    }

    required init(coder: NSCoder) { fatalError("init(coder:) not used") }

    var isOn: Bool {
        get { toggle.state == .on }
        set { toggle.state = newValue ? .on : .off }
    }

    @objc private func changed() {
        onChange?(isOn)
    }
}

private extension NSFont {
    var bold: NSFont {
        NSFontManager.shared.convert(self, toHaveTrait: .boldFontMask)
    }
}
