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

    /// 玻璃島只會取樣「視窗後方」的螢幕內容，任何同視窗的墊底圖層都會破壞自動深淺適應。
    /// 因此把控制中心式的暗化底放在獨立視窗、墊在玻璃面板後面——
    /// 暗化會被玻璃一起取樣，輪廓、暗化與自適應同時成立
    private lazy var dimPanel: NSPanel = {
        let dim = NSPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        dim.isOpaque = false
        dim.backgroundColor = .clear
        dim.hasShadow = false
        dim.level = .popUpMenu
        dim.ignoresMouseEvents = true
        dim.isReleasedWhenClosed = false
        dim.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]

        let view = NSView()
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.14).cgColor
        view.layer?.cornerRadius = 26
        view.layer?.cornerCurve = .continuous
        dim.contentView = view
        return dim
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

        if ProcessInfo.processInfo.environment["AIQUOTA_SHOW_PANEL"] == "1", let button = item.button {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { self.showPanel(relativeTo: button) }
        }

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

        if #available(macOS 26.0, *) {
            // 玻璃的自動深淺適應只對內容稀疏的島生效（OS 內部啟發式，實測），
            // 資料密集的卡片永遠不會翻轉。改採音量 OSD 式的固定深色煙燻玻璃，
            // 任何背景上都協調可讀
            panel.appearance = NSAppearance(named: .darkAqua)
        } else {
            // 選單列在深色桌布上會轉為深色玻璃；面板跟隨選單列的實際外觀而非系統外觀
            panel.appearance = button.effectiveAppearance
        }

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

        // 玻璃在顯示當下取樣背景決定深淺，位置必須在 orderFront 前定案；
        // AIQUOTA_PANEL_XY 供視覺測試指定位置（Cocoa 座標，左下原點）
        if let xy = ProcessInfo.processInfo.environment["AIQUOTA_PANEL_XY"]?.split(separator: ","),
           xy.count == 2, let x = Double(xy[0]), let y = Double(xy[1]) {
            origin = NSPoint(x: x, y: y)
        }

        panel.setFrameOrigin(origin)
        panel.orderFrontRegardless()
        panel.invalidateShadow()
        if #available(macOS 26.0, *), ProcessInfo.processInfo.environment["AIQUOTA_NODIM"] != "1" {
            dimPanel.setFrame(panel.frame, display: true)
            panel.addChildWindow(dimPanel, ordered: .below)
        }
        installEventMonitors()
    }

    private func hidePanel() {
        if #available(macOS 26.0, *) {
            panel.removeChildWindow(dimPanel)
            dimPanel.orderOut(nil)
        }
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
