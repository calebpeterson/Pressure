import Cocoa
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {

    private var statusItem: NSStatusItem!
    private let statusMenu = NSMenu()
    private var startAtLoginMenuItem: NSMenuItem!
    private var refreshTimer: Timer?
    private var thermalObserver: NSObjectProtocol?
    private let cpuReader = CPUReader()
    private let sensorReader = makePlatformSensorReader()
    private var lastCPUPercent: Double?
    private let highPercentThreshold: Double = 80

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        configureMenu()

        updateStatusItem()
        updateStartAtLoginMenuItemState()

        thermalObserver = NotificationCenter.default.addObserver(
            forName: ProcessInfo.thermalStateDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.updateStatusItem(sampleCPU: false)
        }

        refreshTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            self?.updateStatusItem()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        refreshTimer?.invalidate()
        if let thermalObserver {
            NotificationCenter.default.removeObserver(thermalObserver)
        }
    }

    func menuWillOpen(_ menu: NSMenu) {
        updateStartAtLoginMenuItemState()
    }

    private func updateStatusItem(sampleCPU: Bool = true) {
        if sampleCPU {
            lastCPUPercent = cpuReader.readCPUUsagePercent()
        }
        let cpuPercent = lastCPUPercent
        let memoryPercent = MemoryMetrics.readMemoryUsagePercent()
        let diskPercent = DiskMetrics.readDiskUsagePercent()
        let temperature = sensorReader.cpuTemperatureFahrenheit()
        let cpuLimit = sensorReader.cpuPerformanceLimitPercent()
        let thermalState = ProcessInfo.processInfo.thermalState
        let temperatureTitle = temperature.map { String(format: "%.0f°F", $0) } ?? "--°F"
        let cpuLimitTitle = cpuLimit.map { "\($0)%" } ?? "--%"

        let title = NSMutableAttributedString()
        title.append(iconSegment(symbolName: "cpu", color: color(for: cpuPercent)))
        title.append(percentSegment(for: cpuPercent))
        title.append(titleSegment("   "))
        title.append(iconSegment(symbolName: "square.stack.3d.up", color: color(for: memoryPercent)))
        title.append(percentSegment(for: memoryPercent))
        title.append(titleSegment("   "))
        title.append(iconSegment(symbolName: "internaldrive", color: color(for: diskPercent)))
        title.append(percentSegment(for: diskPercent))
        title.append(titleSegment("   "))
        title.append(iconSegment(symbolName: thermalSymbol(for: thermalState), color: .labelColor))
        title.append(titleSegment("\(temperatureTitle) · \(cpuLimitTitle)"))

        statusItem.button?.attributedTitle = title
        statusItem.button?.setAccessibilityLabel(
            "CPU usage \(percentTitle(for: cpuPercent)), memory usage \(percentTitle(for: memoryPercent)), disk usage \(percentTitle(for: diskPercent)), CPU temperature \(temperatureTitle), CPU performance limit \(cpuLimitTitle), thermal state \(thermalStateDescription(for: thermalState))"
        )
    }

    private func thermalSymbol(for state: ProcessInfo.ThermalState) -> String {
        switch state {
        case .nominal: return "thermometer.low"
        case .fair: return "thermometer.medium"
        case .serious: return "thermometer.high"
        case .critical: return "exclamationmark.triangle.fill"
        @unknown default: return "questionmark"
        }
    }

    private func thermalStateDescription(for state: ProcessInfo.ThermalState) -> String {
        switch state {
        case .nominal: return "nominal"
        case .fair: return "fair"
        case .serious: return "serious"
        case .critical: return "critical"
        @unknown default: return "unknown"
        }
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

        let openActivityMonitorMenuItem = NSMenuItem(
            title: "Open Activity Monitor",
            action: #selector(openActivityMonitor(_:)),
            keyEquivalent: ""
        )
        openActivityMonitorMenuItem.target = self
        statusMenu.addItem(openActivityMonitorMenuItem)

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
    private func openActivityMonitor(_ sender: Any?) {
        let url = URL(fileURLWithPath: "/System/Applications/Utilities/Activity Monitor.app")
        NSWorkspace.shared.open(url)
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
