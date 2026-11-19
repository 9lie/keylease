import AppKit
import SwiftUI
import Carbon.HIToolbox

final class KeyleasePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var statusItem: NSStatusItem!
    private var panel: KeyleasePanel!
    private var server: LeaseServer!
    private let store = LeaseStore.shared

    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?
    private var lastHide = Date.distantPast

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        setupStatusItem()
        setupPanel()
        setupServer()
        setupHotKey()

        store.onChange = { [weak self] in
            self?.refreshStatusItem()
        }
        refreshStatusItem()
    }

    func applicationWillTerminate(_ notification: Notification) {
        server?.stop()

        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
        }
        if let eventHandlerRef {
            RemoveEventHandler(eventHandlerRef)
        }
    }

    func windowDidResignKey(_ notification: Notification) {
        lastHide = Date()
        panel?.orderOut(nil)
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        guard let button = statusItem.button else { return }

        button.image = NSImage(systemSymbolName: "key", accessibilityDescription: "Keylease")
        button.image?.isTemplate = true
        button.imagePosition = .imageLeft
        button.target = self
        button.action = #selector(togglePanel(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }

    private func setupPanel() {
        panel = KeyleasePanel(
            contentRect: NSRect(x: 0, y: 0, width: 340, height: 240),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        panel.contentViewController = NSHostingController(rootView: PopoverView(store: store))
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .floating
        panel.isFloatingPanel = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isMovable = false
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = false
        panel.acceptsMouseMovedEvents = true
        panel.becomesKeyOnlyIfNeeded = false
        panel.delegate = self
    }

    private func setupServer() {
        server = LeaseServer(store: store)
        server.onShow = { [weak self] in
            self?.showPanel(atMouse: false)
        }

        do {
            try server.start()
        } catch ServerError.alreadyRunning {
            NSApp.terminate(nil)
        } catch {
            let alert = NSAlert()
            alert.messageText = "Keylease 无法启动"
            alert.informativeText = error.localizedDescription
            alert.runModal()
            NSApp.terminate(nil)
        }
    }

    private func setupHotKey() {
        let hotKeyID = EventHotKeyID(signature: OSType(0x4B45594C), id: 1)
        let status = RegisterEventHotKey(
            UInt32(kVK_ANSI_K),
            UInt32(cmdKey | shiftKey),
            hotKeyID,
            GetEventDispatcherTarget(),
            0,
            &hotKeyRef
        )

        guard status == noErr else { return }

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let handler: EventHandlerUPP = { _, _, userData in
            guard let userData else { return noErr }
            let delegate = Unmanaged<AppDelegate>.fromOpaque(userData).takeUnretainedValue()
            DispatchQueue.main.async {
                delegate.activateFromClipboard()
            }
            return noErr
        }

        InstallEventHandler(
            GetEventDispatcherTarget(),
            handler,
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandlerRef
        )
    }

    @objc private func togglePanel(_ sender: Any?) {
        if panel.isVisible {
            lastHide = Date()
            panel.orderOut(nil)
            return
        }

        if Date().timeIntervalSince(lastHide) < 0.25 {
            return
        }

        showPanel(atMouse: true)
    }

    private func showPanel(atMouse: Bool) {
        let size = NSSize(width: 340, height: 240)
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first(where: { NSPointInRect(mouse, $0.frame) })
            ?? NSScreen.main
            ?? NSScreen.screens.first!

        let anchor: NSPoint
        if atMouse {
            anchor = mouse
        } else {
            anchor = NSPoint(x: screen.visibleFrame.maxX - 24, y: screen.visibleFrame.maxY)
        }

        var x = anchor.x - size.width / 2
        x = min(max(x, screen.visibleFrame.minX + 8), screen.visibleFrame.maxX - size.width - 8)
        let top = min(anchor.y - 6, screen.visibleFrame.maxY)

        panel.setContentSize(size)
        panel.setFrameTopLeftPoint(NSPoint(x: x, y: top))
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        panel.orderFrontRegardless()
        panel.makeKey()
    }

    private func activateFromClipboard() {
        guard let raw = NSPasteboard.general.string(forType: .string) else {
            NSSound.beep()
            showPanel(atMouse: false)
            return
        }

        let secret = raw.trimmingCharacters(in: .newlines)
        guard !secret.isEmpty else {
            NSSound.beep()
            showPanel(atMouse: false)
            return
        }

        store.activate(secret: secret)
        showPanel(atMouse: false)
    }

    private func refreshStatusItem() {
        guard let button = statusItem.button else { return }

        let symbol = store.isActive ? "key.fill" : "key"
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: "Keylease")
        button.image?.isTemplate = true
    }
}
