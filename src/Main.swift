import Cocoa
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {

    private var statusItem: NSStatusItem!
    private let statusMenu = NSMenu()
    private var startAtLoginMenuItem: NSMenuItem!
    private var refreshTimer: Timer?
    private let cpuReader = CPUReader()
    private let highPercentThreshold: Double = 80

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        configureMenu()

        updateStatusItem()
        updateStartAtLoginMenuItemState()

        refreshTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            self?.updateStatusItem()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        refreshTimer?.invalidate()
    }

    func menuWillOpen(_ menu: NSMenu) {
        updateStartAtLoginMenuItemState()
    }

    private func updateStatusItem() {
        let cpuPercent = cpuReader.readCPUUsagePercent()
        let memoryPercent = MemoryMetrics.readMemoryUsagePercent()

        let title = NSMutableAttributedString()
        title.append(iconSegment(symbolName: "cpu", color: color(for: cpuPercent)))
        title.append(percentSegment(for: cpuPercent))
        title.append(titleSegment("   "))
        title.append(iconSegment(symbolName: "memorychip", color: color(for: memoryPercent)))
        title.append(percentSegment(for: memoryPercent))

        statusItem.button?.attributedTitle = title
    }

    private func percentTitle(for percent: Double?) -> String {
        guard let percent else {
            return "--%"
        }

        return "\(Int(percent.rounded()))%"
    }

    private func percentSegment(for percent: Double?) -> NSAttributedString {
        titleSegment(percentTitle(for: percent), color: color(for: percent))
    }

    private func color(for percent: Double?) -> NSColor {
        let isHighPercent = percent.map { $0 > highPercentThreshold } ?? false
        return isHighPercent ? .systemRed : .labelColor
    }

    private func titleSegment(_ text: String, color: NSColor = .labelColor) -> NSAttributedString {
        NSAttributedString(
            string: text,
            attributes: [
                .foregroundColor: color,
                .font: NSFont.menuBarFont(ofSize: 0)
            ]
        )
    }

    private func iconSegment(symbolName: String, color: NSColor) -> NSAttributedString {
        let font = NSFont.menuBarFont(ofSize: 0)
        let attachment = NSTextAttachment()

        if let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil) {
            image.isTemplate = true

            let iconHeight = font.pointSize
            let iconWidth = iconHeight * (image.size.width / image.size.height)
            attachment.image = image
            attachment.bounds = NSRect(
                x: 0,
                y: (font.capHeight - iconHeight) / 2,
                width: iconWidth,
                height: iconHeight
            )
        }

        let attachmentString = NSMutableAttributedString(attachment: attachment)
        attachmentString.addAttribute(.foregroundColor, value: color, range: NSRange(location: 0, length: attachmentString.length))
        attachmentString.append(
            NSAttributedString(
                string: " ",
                attributes: [
                    .foregroundColor: color,
                    .font: font
                ]
            )
        )
        return attachmentString
    }

    private func configureMenu() {
        statusMenu.delegate = self

        startAtLoginMenuItem = NSMenuItem(
            title: "Open at Login",
            action: #selector(toggleStartAtLogin(_:)),
            keyEquivalent: ""
        )
        startAtLoginMenuItem.target = self
        statusMenu.addItem(startAtLoginMenuItem)

        statusMenu.addItem(.separator())

        let quitMenuItem = NSMenuItem(title: "Quit", action: #selector(quit(_:)), keyEquivalent: "")
        quitMenuItem.target = self
        statusMenu.addItem(quitMenuItem)

        statusItem.menu = statusMenu
    }

    private func updateStartAtLoginMenuItemState() {
        switch SMAppService.mainApp.status {
        case .enabled:
            startAtLoginMenuItem.state = .on
        case .requiresApproval:
            startAtLoginMenuItem.state = .mixed
        case .notRegistered, .notFound:
            startAtLoginMenuItem.state = .off
        @unknown default:
            startAtLoginMenuItem.state = .off
        }
    }

    @objc
    private func toggleStartAtLogin(_ sender: Any?) {
        do {
            switch SMAppService.mainApp.status {
            case .enabled:
                try SMAppService.mainApp.unregister()
            case .notRegistered, .requiresApproval, .notFound:
                try SMAppService.mainApp.register()
            @unknown default:
                try SMAppService.mainApp.register()
            }
        } catch {
            NSSound.beep()
        }

        updateStartAtLoginMenuItemState()
    }

    @objc
    private func quit(_ sender: Any?) {
        NSApplication.shared.terminate(sender)
    }
}

@main
struct PressureApp {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }
}
