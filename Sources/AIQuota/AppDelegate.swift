import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let store = QuotaStore()
    private var statusItem: NSStatusItem?
    private var globalEventMonitor: Any?
    private var localEventMonitor: Any?

    private lazy var hostingController: NSHostingController<QuotaPanel> = {
        let controller = NSHostingController(rootView: QuotaPanel(store: store))
        controller.view.wantsLayer = true
        controller.view.layer?.backgroundColor = NSColor.clear.cgColor
        return controller
    }()

    private lazy var panel: NSPanel = {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 300, height: 416),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.contentViewController = hostingController
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .popUpMenu
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.becomesKeyOnlyIfNeeded = true
        return panel
    }()

    private lazy var contextMenu: NSMenu = {
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "重新整理", action: #selector(refresh), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "結束 AIQuota", action: #selector(quit), keyEquivalent: "q"))
        menu.items.forEach { $0.target = self }
        return menu
    }()

    func applicationDidFinishLaunching(_ notification: Notification) {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = NSImage(systemSymbolName: "chart.bar.fill", accessibilityDescription: "AI Quota")
        item.button?.imagePosition = .imageOnly
        item.button?.target = self
        item.button?.action = #selector(handleStatusItemClick(_:))
        item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        statusItem = item

        Task { await store.refresh() }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    @objc private func handleStatusItemClick(_ sender: NSStatusBarButton) {
        if NSApp.currentEvent?.type == .rightMouseUp {
            hidePanel()
            if let event = NSApp.currentEvent {
                NSMenu.popUpContextMenu(contextMenu, with: event, for: sender)
            }
            return
        }

        panel.isVisible ? hidePanel() : showPanel(relativeTo: sender)
    }

    private func showPanel(relativeTo button: NSStatusBarButton) {
        guard let statusWindow = button.window else { return }

        hostingController.view.layoutSubtreeIfNeeded()
        let fittingHeight = max(hostingController.view.fittingSize.height, 1)
        panel.setContentSize(NSSize(width: 300, height: fittingHeight))

        let buttonRect = statusWindow.convertToScreen(button.convert(button.bounds, to: nil))
        let screenFrame = statusWindow.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero
        var origin = NSPoint(
            x: buttonRect.midX - panel.frame.width / 2,
            y: buttonRect.minY - panel.frame.height - 6
        )
        origin.x = min(max(origin.x, screenFrame.minX + 8), screenFrame.maxX - panel.frame.width - 8)
        if origin.y < screenFrame.minY + 8 {
            origin.y = buttonRect.maxY + 6
        }

        panel.setFrameOrigin(origin)
        panel.orderFrontRegardless()
        installEventMonitors()
    }

    private func hidePanel() {
        panel.orderOut(nil)
        removeEventMonitors()
    }

    private func installEventMonitors() {
        removeEventMonitors()

        globalEventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor in self?.hidePanel() }
        }
        localEventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            guard let self else { return event }
            let statusWindow = self.statusItem?.button?.window
            if event.window !== self.panel, event.window !== statusWindow {
                self.hidePanel()
            }
            return event
        }
    }

    private func removeEventMonitors() {
        if let globalEventMonitor {
            NSEvent.removeMonitor(globalEventMonitor)
            self.globalEventMonitor = nil
        }
        if let localEventMonitor {
            NSEvent.removeMonitor(localEventMonitor)
            self.localEventMonitor = nil
        }
    }

    @objc private func refresh() {
        Task { await store.refresh() }
    }

    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }
}
