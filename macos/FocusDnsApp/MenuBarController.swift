//
//  MenuBarController.swift
//  FocusDnsApp
//
//  macOS Native Menu Bar Companion Controller (NSStatusItem).
//  Provides instant menu bar visibility into FocusDNS protection status,
//  live query counters, active security profile, and anti-tamper posture.
//

import Cocoa
import Foundation
import os.log

private let logger = Logger(subsystem: "com.focusguard.macos.app", category: "MenuBarController")

public protocol MenuBarActionDelegate: AnyObject {
    func didSelectOpenDashboard()
    func didSelectToggleProtection(enable: Bool)
    func didRequestExtensionUninstallation()
}

@available(macOS 11.0, *)
public class FocusMenuBarController: NSObject, NSMenuDelegate {

    // MARK: - Properties
    private var statusItem: NSStatusItem?
    private let statusMenu = NSMenu()
    public weak var delegate: MenuBarActionDelegate?

    // Local State
    private var isProtectionActive: Bool = false
    private var isFocusLocked: Bool = false
    private var remainingSeconds: Int = 0
    private var activeProfile: String = "profile_mac_workstation"
    private var queriesProcessed: UInt64 = 0
    private var bypassesBlocked: UInt64 = 0

    // Menu Items
    private let titleMenuItem = NSMenuItem(title: "FocusGuard DNS", action: nil, keyEquivalent: "")
    private let profileMenuItem = NSMenuItem(title: "Profile: Loading...", action: nil, keyEquivalent: "")
    private let statsMenuItem = NSMenuItem(title: "Queries: 0 | Blocked: 0", action: nil, keyEquivalent: "")
    private let lockStatusMenuItem = NSMenuItem(title: "Status: Idle", action: nil, keyEquivalent: "")
    private let toggleProtectionItem = NSMenuItem(title: "Activate Focus Mode", action: #selector(toggleProtectionClicked), keyEquivalent: "t")
    private let openDashboardItem = NSMenuItem(title: "Open Dashboard...", action: #selector(openDashboardClicked), keyEquivalent: "d")
    private let uninstallItem = NSMenuItem(title: "Uninstall System Extension", action: #selector(uninstallExtensionClicked), keyEquivalent: "u")

    // Timer for countdown refresh
    private var countdownTimer: Timer?

    // MARK: - Initialization

    public override init() {
        super.init()
        setupStatusItem()
        setupMenu()
        updateDisplay()
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "shield.fill", accessibilityDescription: "FocusGuard DNS Shield")
            button.imagePosition = .imageLeft
        }
        statusItem?.menu = statusMenu
        statusMenu.delegate = self
    }

    private func setupMenu() {
        titleMenuItem.isEnabled = false
        profileMenuItem.isEnabled = false
        statsMenuItem.isEnabled = false
        lockStatusMenuItem.isEnabled = false

        toggleProtectionItem.target = self
        openDashboardItem.target = self
        uninstallItem.target = self

        statusMenu.addItem(titleMenuItem)
        statusMenu.addItem(lockStatusMenuItem)
        statusMenu.addItem(profileMenuItem)
        statusMenu.addItem(statsMenuItem)
        statusMenu.addItem(NSMenuItem.separator())
        statusMenu.addItem(toggleProtectionItem)
        statusMenu.addItem(openDashboardItem)
        statusMenu.addItem(NSMenuItem.separator())
        statusMenu.addItem(uninstallItem)
        statusMenu.addItem(NSMenuItem.separator())
        statusMenu.addItem(NSMenuItem(title: "Quit FocusGuard", action: #selector(quitClicked), keyEquivalent: "q"))
    }

    // MARK: - Update State

    public func updateState(
        isProtectionActive: Bool,
        isFocusLocked: Bool,
        remainingSeconds: Int,
        activeProfile: String,
        queriesProcessed: UInt64,
        bypassesBlocked: UInt64
    ) {
        self.isProtectionActive = isProtectionActive
        self.isFocusLocked = isFocusLocked
        self.remainingSeconds = remainingSeconds
        self.activeProfile = activeProfile
        self.queriesProcessed = queriesProcessed
        self.bypassesBlocked = bypassesBlocked

        updateDisplay()

        if remainingSeconds > 0 && countdownTimer == nil {
            startCountdownTimer()
        } else if remainingSeconds <= 0 && countdownTimer != nil {
            stopCountdownTimer()
        }
    }

    private func updateDisplay() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }

            // 1. Icon & Button Text
            if let button = self.statusItem?.button {
                if self.isFocusLocked {
                    let mins = self.remainingSeconds / 60
                    let secs = self.remainingSeconds % 60
                    button.title = String(format: " 🔒 %02d:%02d", mins, secs)
                    button.image = NSImage(systemSymbolName: "lock.shield.fill", accessibilityDescription: "Locked Focus Session")
                } else if self.isProtectionActive {
                    button.title = " Shield"
                    button.image = NSImage(systemSymbolName: "checkmark.shield.fill", accessibilityDescription: "Active Shield")
                } else {
                    button.title = ""
                    button.image = NSImage(systemSymbolName: "shield", accessibilityDescription: "FocusGuard DNS Idle")
                }
            }

            // 2. Profile & Statistics
            self.profileMenuItem.title = "Active Profile: \(self.activeProfile)"
            self.statsMenuItem.title = "Filtered: \(self.queriesProcessed) | Bypasses Blocked: \(self.bypassesBlocked)"

            // 3. Conditional Uninstallation Posture
            let canUninstall = (!self.isFocusLocked && self.remainingSeconds == 0)
            if canUninstall {
                self.lockStatusMenuItem.title = "Posture: Normal Mode (Clean Removal Permitted)"
                self.uninstallItem.title = "Uninstall System Extension"
                self.uninstallItem.isEnabled = true
                self.toggleProtectionItem.title = self.isProtectionActive ? "Deactivate Focus Mode" : "Activate Focus Mode"
            } else {
                let mins = self.remainingSeconds / 60
                let secs = self.remainingSeconds % 60
                self.lockStatusMenuItem.title = String(format: "Posture: STRICT LOCK (%02d:%02d Remaining)", mins, secs)
                self.uninstallItem.title = "🔒 Uninstallation Locked (Active Session)"
                self.uninstallItem.isEnabled = false
                self.toggleProtectionItem.title = "🔒 Focus Session Locked"
                self.toggleProtectionItem.isEnabled = false
            }
        }
    }

    // MARK: - Timer Handling

    private func startCountdownTimer() {
        countdownTimer?.invalidate()
        countdownTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            if self.remainingSeconds > 0 {
                self.remainingSeconds -= 1
                self.updateDisplay()
            } else {
                self.isFocusLocked = false
                self.stopCountdownTimer()
                self.updateDisplay()
            }
        }
    }

    private func stopCountdownTimer() {
        countdownTimer?.invalidate()
        countdownTimer = nil
    }

    // MARK: - Menu Actions

    @objc private func toggleProtectionClicked() {
        guard !isFocusLocked else {
            logger.warning("Attempted to toggle protection while session is locked.")
            return
        }
        let newState = !isProtectionActive
        delegate?.didSelectToggleProtection(enable: newState)
    }

    @objc private func openDashboardClicked() {
        delegate?.didSelectOpenDashboard()
    }

    @objc private func uninstallExtensionClicked() {
        guard !isFocusLocked && remainingSeconds == 0 else {
            logger.error("ACCESS DENIED: Uninstallation is strictly locked during active focus mode.")
            return
        }
        delegate?.didRequestExtensionUninstallation()
    }

    @objc private func quitClicked() {
        if isFocusLocked || remainingSeconds > 0 {
            let alert = NSAlert()
            alert.messageText = "FocusGuard Lock Active"
            alert.informativeText = "Cannot quit FocusGuard while an active focus session or countdown timer is running."
            alert.alertStyle = .critical
            alert.addButton(withTitle: "OK")
            alert.runModal()
            return
        }
        NSApplication.shared.terminate(nil)
    }
}
