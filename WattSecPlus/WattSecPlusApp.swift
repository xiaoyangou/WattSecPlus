//
//  WattSecPlusApp.swift
//  WattSecPlus
//
//  Created by Ben Beutton on 3/4/25.
//

import Cocoa
import Combine
import Foundation
import ServiceManagement
import SwiftUI

// MARK: - Main App

@main
struct WattSecPlusApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings { EmptyView() }
    }
}

// MARK: - Enums

enum DetailLevel: Int, CaseIterable {
    case low = 0
    case medium = 1
    case high = 2
}

enum PaceLevel: Int, CaseIterable {
    case fast = 1
    case medium = 3
    case slow = 5
}

enum WidthMode: String, CaseIterable {
    case dynamic
    case fixed
}

// MARK: Default Settings

private struct Defaults {
    static let detailLevel: DetailLevel = .medium
    static let paceLevel: PaceLevel = .fast
    static let widthMode: WidthMode = .dynamic
}

// MARK: Constants

private struct Constants {
    static let highWattageTimeoutSeconds: TimeInterval = 60.0
    static let highWattageThreshold: Double = 100.0
}

// MARK: - App Delegate

class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {

    // MARK: Properties

    private var statusItem: NSStatusItem?
    private var batterySubscription: AnyCancellable?
    private let batteryPowerItem = NSMenuItem(title: "电池功率：—", action: nil, keyEquivalent: "")
    private let inputPowerItem = NSMenuItem(title: "电源输入功率：—", action: nil, keyEquivalent: "")

    private var detailLevel: DetailLevel = Defaults.detailLevel
    private var paceLevel: PaceLevel = Defaults.paceLevel
    private var widthMode: WidthMode = Defaults.widthMode
    private var launchAtLogin: Bool = false

    // New properties for fixed width mode
    private var widestWidths: [DetailLevel: [Int: CGFloat]] = [:]
    private var highWattageTimestamp: Date?
    private var highWattageTimer: Timer?

    // MARK: Application Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        loadUserPreferences()
        setupMenuBar()
        calculateWidestWidths()
        bindToPowerMonitor()
        PowerMonitor.shared.fetchWattage()
        checkLaunchAtLoginStatus()
    }

    deinit {
        // Cancel subscription to prevent memory leaks
        batterySubscription?.cancel()
        highWattageTimer?.invalidate()
    }

    // MARK: User Preferences

    private func loadUserPreferences() {
        let defaults = UserDefaults.standard
        let currentVersion = 1
        let savedVersion = defaults.integer(forKey: "settingsVersion")

        if savedVersion < currentVersion {
            // Reset to defaults if version is outdated, then update version
            defaults.set(currentVersion, forKey: "settingsVersion")
            defaults.set(Defaults.detailLevel.rawValue, forKey: "detailLevel")
            defaults.set(Defaults.paceLevel.rawValue, forKey: "paceLevel")
            defaults.set(Defaults.widthMode.rawValue, forKey: "widthMode")
            // We don't need to set launchAtLogin in UserDefaults anymore
        }

        detailLevel = DetailLevel(rawValue: defaults.integer(forKey: "detailLevel")) ?? Defaults.detailLevel
        paceLevel = PaceLevel(rawValue: defaults.integer(forKey: "paceLevel")) ?? Defaults.paceLevel
        widthMode = WidthMode(rawValue: defaults.string(forKey: "widthMode") ?? Defaults.widthMode.rawValue) ?? Defaults.widthMode

        // We'll set launchAtLogin in checkLaunchAtLoginStatus() instead

        PowerMonitor.shared.updatePace(paceLevel)
    }

    // MARK: Widest Width Calculation

    private func calculateWidestWidths() {
        // Widest strings for each detail level and character count
        let widestStrings: [DetailLevel: [Int: String]] = [
            .low: [
                3: "88W",    // 3 chars
                4: "888W"    // 4 chars
            ],
            .medium: [
                5: "88.8W",  // 5 chars
                6: "888.8W"  // 6 chars
            ],
            .high: [
                6: "88.88W", // 6 chars
                7: "888.88W" // 7 chars
            ]
        ]

        // Calculate widths for widest strings
        for (level, strings) in widestStrings {
            widestWidths[level] = [:]
            for (charCount, widestString) in strings {
                if let button = statusItem?.button {
                    let width = ceil(estimateTextWidth(widestString, font: button.font ?? .systemFont(ofSize: NSFont.systemFontSize))) + 8
                    widestWidths[level]?[charCount] = width
                }
            }
        }
    }

    // MARK: Menu Setup

    private func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        guard let statusItem = statusItem else {
            print("Failed to create status item. Terminating app.")
            NSApplication.shared.terminate(self)
            return
        }

        if let button = statusItem.button {
            let size = button.font?.pointSize ?? NSFont.systemFontSize
            button.font = .monospacedDigitSystemFont(ofSize: size, weight: .regular)
        }

        let menu = NSMenu()
        menu.delegate = self
        for item in [batteryPowerItem, inputPowerItem] {
            menu.addItem(item)
        }
        menu.addItem(NSMenuItem.separator())
        menu.addItem(createDetailMenuItem())
        menu.addItem(createPaceMenuItem())
        menu.addItem(createWidthModeItem())
        menu.addItem(NSMenuItem.separator())
        menu.addItem(createLaunchAtLoginMenuItem())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(quitApp), keyEquivalent: "q"))
        statusItem.menu = menu
    }

    private func createDetailMenuItem() -> NSMenuItem {
        let menuItem = NSMenuItem(title: "Detail", action: nil, keyEquivalent: "")
        let submenu = NSMenu()

        for level in DetailLevel.allCases {
            let label = String(describing: level).capitalized
            let item = createStyledMenuItem(
                title: label,
                suffix: "\(level.rawValue)",
                action: #selector(changeDetailLevel),
                value: level.rawValue,
                isSelected: level == detailLevel
            )
            submenu.addItem(item)
        }

        menuItem.submenu = submenu
        return menuItem
    }

    private func createPaceMenuItem() -> NSMenuItem {
        let menuItem = NSMenuItem(title: "Pace", action: nil, keyEquivalent: "")
        let submenu = NSMenu()

        for level in PaceLevel.allCases {
            let label = String(describing: level).capitalized
            let item = createStyledMenuItem(
                title: label,
                suffix: "\(level.rawValue)s",
                action: #selector(changePace),
                value: level.rawValue,
                isSelected: level == paceLevel
            )
            submenu.addItem(item)
        }

        menuItem.submenu = submenu
        return menuItem
    }

    private func createWidthModeItem() -> NSMenuItem {
        let menuItem = NSMenuItem(title: "Width", action: nil, keyEquivalent: "")
        let submenu = NSMenu()

        for mode in WidthMode.allCases {
            let label = mode == .dynamic ? "Dynamic" : "Fixed"
            let item = NSMenuItem(title: label, action: #selector(changeWidthMode), keyEquivalent: "")
            item.representedObject = mode.rawValue
            item.target = self
            item.state = mode == widthMode ? .on : .off
            submenu.addItem(item)
        }

        menuItem.submenu = submenu
        return menuItem
    }

    private func createLaunchAtLoginMenuItem() -> NSMenuItem {
        let menuItem = NSMenuItem(title: "Launch", action: nil, keyEquivalent: "")
        let submenu = NSMenu()

        let item = NSMenuItem(title: "at Login", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        item.target = self
        item.state = launchAtLogin ? .on : .off
        submenu.addItem(item)

        menuItem.submenu = submenu
        return menuItem
    }

    // MARK: Menu Actions

    @objc private func changeDetailLevel(sender: NSMenuItem) {
        guard let rawValue = sender.representedObject as? Int,
              let newLevel = DetailLevel(rawValue: rawValue) else { return }

        detailLevel = newLevel
        UserDefaults.standard.set(rawValue, forKey: "detailLevel")
        updateWattageDisplay()
        updateBatteryDisplay()
        updateMenuStates(sender.menu, selectedValue: rawValue)
    }

    @objc private func changePace(sender: NSMenuItem) {
        guard let rawValue = sender.representedObject as? Int,
              let newPace = PaceLevel(rawValue: rawValue) else { return }

        paceLevel = newPace
        UserDefaults.standard.set(rawValue, forKey: "paceLevel")
        PowerMonitor.shared.updatePace(newPace)
        updateMenuStates(sender.menu, selectedValue: rawValue)
    }

    @objc private func changeWidthMode(sender: NSMenuItem) {
        guard let rawValue = sender.representedObject as? String,
              let newMode = WidthMode(rawValue: rawValue) else { return }

        widthMode = newMode
        UserDefaults.standard.set(rawValue, forKey: "widthMode")

        switch newMode {
        case .dynamic:
            statusItem?.length = NSStatusItem.variableLength
            highWattageTimer?.invalidate()
            highWattageTimer = nil
            highWattageTimestamp = nil
        case .fixed:
            // Initialize widest widths if needed
            if widestWidths.isEmpty {
                calculateWidestWidths()
            }
        }

        updateWattageDisplay()
        updateMenuStates(sender.menu, selectedValue: rawValue)
    }

    // MARK: Display Updates

    private func updateWattageDisplay(_ reading: BatteryStatus? = nil) {
        guard let button = statusItem?.button else { return }
        guard let wattage = (reading ?? PowerMonitor.shared.battery).systemWatts else {
            if button.title != "—" { button.title = "—" }
            highWattageTimestamp = nil
            highWattageTimer?.invalidate()
            highWattageTimer = nil
            if widthMode == .fixed {
                statusItem?.length = ceil(estimateTextWidth("—", font: button.font ?? .systemFont(ofSize: NSFont.systemFontSize))) + 8
            }
            return
        }
        let text = String(format: detailLevelFormatString(), wattage)
        if button.title != text { button.title = text }
        if widthMode == .fixed { updateFixedWidth(for: text, wattage: wattage) }
    }

    private func updateFixedWidth(for text: String, wattage: Double) {
        guard let widths = widestWidths[detailLevel],
              let largestCount = widths.keys.max(),
              let button = statusItem?.button else { return }
        let actualWidth = ceil(estimateTextWidth(text, font: button.font ?? .systemFont(ofSize: NSFont.systemFontSize))) + 8
        let matchingCount = widths.keys.sorted().first(where: { $0 >= text.count }) ?? largestCount
        let normalWidth = max(widths[matchingCount] ?? actualWidth, actualWidth)
        let wideWidth = max(widths[largestCount] ?? actualWidth, actualWidth)

        if wattage >= Constants.highWattageThreshold {
            highWattageTimestamp = Date()
            highWattageTimer?.invalidate()
            highWattageTimer = nil
            // Apply the current Detail width on every update, even while the width is held.
            statusItem?.length = wideWidth
        } else if let timestamp = highWattageTimestamp {
            let remaining = Constants.highWattageTimeoutSeconds - Date().timeIntervalSince(timestamp)
            if remaining > 0 {
                statusItem?.length = wideWidth
                if highWattageTimer == nil {
                    let timer = Timer(timeInterval: remaining, repeats: false) { [weak self] _ in
                        self?.highWattageTimer = nil
                        self?.updateWattageDisplay()
                    }
                    highWattageTimer = timer
                    RunLoop.main.add(timer, forMode: .common)
                }
            } else {
                highWattageTimestamp = nil
                highWattageTimer?.invalidate()
                highWattageTimer = nil
                statusItem?.length = normalWidth
            }
        } else {
            statusItem?.length = normalWidth
        }
    }

    // MARK: Helper Methods

    private func createStyledMenuItem(title: String, suffix: String, action: Selector, value: Any, isSelected: Bool) -> NSMenuItem {
        let fullText = "\(title)  \(suffix)"
        let attributedTitle = NSMutableAttributedString(string: fullText)

        let suffixRange = (fullText as NSString).range(of: suffix)
        let smallFont = NSFont.systemFont(ofSize: 11)
        attributedTitle.addAttributes([
            .font: smallFont,
            .foregroundColor: NSColor.secondaryLabelColor
        ], range: suffixRange)

        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.attributedTitle = attributedTitle
        item.representedObject = value
        item.target = self
        item.state = isSelected ? .on : .off
        return item
    }

    private func detailLevelFormatString() -> String {
        switch detailLevel {
        case .low: return "%.0fW"
        case .medium: return "%.1fW"
        case .high: return "%.2fW"
        }
    }

    private func estimateTextWidth(_ text: String, font: NSFont) -> CGFloat {
        let attributes: [NSAttributedString.Key: Any] = [.font: font]
        return (text as NSString).size(withAttributes: attributes).width
    }

    private func updateMenuStates(_ menu: NSMenu?, selectedValue: Any) {
        menu?.items.forEach { item in
            if let value = item.representedObject as? NSObject,
               value.isEqual(selectedValue) {
                item.state = .on
            } else {
                item.state = .off
            }
        }
    }

    private func bindToPowerMonitor() {
        batterySubscription = PowerMonitor.shared.$battery
            .sink { [weak self] reading in
                self?.updateWattageDisplay(reading)
                self?.updateBatteryDisplay(reading)
            }
    }

    private func updateBatteryDisplay(_ battery: BatteryStatus? = nil) {
        let battery = battery ?? PowerMonitor.shared.battery
        let power = battery.displayedBatteryWatts(decimalPlaces: detailLevel.rawValue).map { String(format: "%.*f W", detailLevel.rawValue, $0) } ?? "不可用"
        let batteryTitle = battery.powerLabel(decimalPlaces: detailLevel.rawValue) + "：" + power
        if batteryPowerItem.title != batteryTitle { batteryPowerItem.title = batteryTitle }
        let input = battery.inputWatts.map { String(format: "%.*f W", detailLevel.rawValue, $0) } ?? "不可用"
        let inputTitle = "电源输入功率：" + input
        if inputPowerItem.title != inputTitle { inputPowerItem.title = inputTitle }
    }

    func menuWillOpen(_ menu: NSMenu) {
        PowerMonitor.shared.fetchWattage()
        updateBatteryDisplay()
    }

    // MARK: Menu Actions

    @objc private func quitApp() {
        NSApplication.shared.terminate(nil)
    }

    // MARK: Launch at Login

    private func checkLaunchAtLoginStatus() {
        launchAtLogin = SMAppService.mainApp.status == .enabled

        // Update menu item state if menu exists
        if let menu = statusItem?.menu {
            for item in menu.items {
                if let submenu = item.submenu,
                   let loginItem = submenu.items.first(where: { $0.action == #selector(toggleLaunchAtLogin) }) {
                    loginItem.state = launchAtLogin ? .on : .off
                    break
                }
            }
        }
    }

    @objc private func toggleLaunchAtLogin() {
        do {
            if launchAtLogin {
                try SMAppService.mainApp.unregister()
                launchAtLogin = false
            } else {
                try SMAppService.mainApp.register()
                launchAtLogin = true
            }

            // Update menu item state
            if let menu = statusItem?.menu {
                for item in menu.items {
                    if let submenu = item.submenu,
                       let loginItem = submenu.items.first(where: { $0.action == #selector(toggleLaunchAtLogin) }) {
                        loginItem.state = launchAtLogin ? .on : .off
                        break
                    }
                }
            }
        } catch let error as NSError {
            print("Error toggling launch at login: \(error.localizedDescription)")
            print("Error domain: \(error.domain), code: \(error.code)")
            if let reason = error.userInfo[NSLocalizedFailureReasonErrorKey] as? String {
                print("Reason: \(reason)")
            }

            let alert = NSAlert()
            alert.messageText = "Launch at Login Error"
            alert.informativeText = "Could not change launch at login setting: \(error.localizedDescription)"
            alert.alertStyle = .warning
            alert.addButton(withTitle: "OK")
            alert.runModal()

            // Reset the state to match the actual system state
            checkLaunchAtLoginStatus()
        }
    }
}

// MARK: - Power Monitor

class PowerMonitor: ObservableObject {
    static let shared = PowerMonitor()
    @Published var battery = BatteryStatus()

    private let samplingQueue = DispatchQueue(label: "io.github.xiaoyangou.WattSecPlus.sampling", qos: .utility)
    private let sampler: () -> BatteryStatus
    private var timer: AnyCancellable?
    private var timerInterval: TimeInterval
    // These gates are only read/written on the main run loop.
    private var isSampling = false
    private var lastSampleStarted: TimeInterval = -.infinity

    init(sampler: @escaping () -> BatteryStatus = {
        BatteryStatus(systemWatts: SMC.shared.getValue("PSTR"), inputWatts: SMC.shared.getValue("PDTR"))
    }, startsTimer: Bool = true) {
        self.sampler = sampler
        timerInterval = Double(PaceLevel.medium.rawValue)
        if startsTimer { setupTimer() }
    }

    func updatePace(_ pace: PaceLevel) {
        let newInterval = Double(pace.rawValue)
        guard newInterval != timerInterval else { return }
        timerInterval = newInterval
        setupTimer()
    }

    func fetchWattage() {
        let now = ProcessInfo.processInfo.systemUptime
        guard !isSampling, now - lastSampleStarted >= 0.2 else { return }
        isSampling = true
        lastSampleStarted = now
        samplingQueue.async { [weak self] in
            guard let self else { return }
            let reading = self.sampler()
            // Common modes keep publication running while AppKit tracks an open menu.
            RunLoop.main.perform(inModes: [.common]) { [weak self] in
                self?.isSampling = false
                self?.battery = reading
            }
        }
    }

    private func setupTimer() {
        timer?.cancel()
        timer = Timer.publish(every: timerInterval, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in self?.fetchWattage() }
    }
}
