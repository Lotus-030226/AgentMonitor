// Modified by Lotus for Agent Monitor. See docs/UPSTREAM.md.
import AppKit
import AgentHUDCore
import AgentHUDDesktop
import LocalMonitorCore
import LocalMonitorUI
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var desktop: DesktopApplication?
    private var localStore: LocalMonitorStore?
    private var localController: LocalMonitorController?
    private var displayObserver: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let arguments = CommandLine.arguments
        let localDemo = arguments.contains("--local-demo")
        let localSnapshot = arguments.firstIndex(of: "--local-snapshot").flatMap { index in
            arguments.indices.contains(index + 1) ? arguments[index + 1] : nil
        }
        if arguments.contains("--local-snapshot"), localSnapshot == nil {
            FileHandle.standardError.write(Data("--local-snapshot requires a directory\n".utf8))
            exit(2)
        }
        if let directory = localSnapshot {
            let store = LocalMonitorStore(demo: true)
            let controller = LocalMonitorController(store: store)
            self.localStore = store
            self.localController = controller
            controller.start()
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(500))
                do {
                    try controller.snapshot(into: URL(fileURLWithPath: directory, isDirectory: true))
                    NSApp.terminate(nil)
                } catch {
                    FileHandle.standardError.write(Data("Local snapshot failed: \(error)\n".utf8))
                    controller.stop()
                    store.stop()
                    exit(1)
                }
            }
            return
        }
        var options = DesktopLaunchOptions.parse(arguments)
        if localDemo { options.demo = true }
        if let directory = options.snapshotDirectory {
            Task { @MainActor in
                await SnapshotRunner.run(language: options.language, into: directory)
                NSApp.terminate(nil)
            }
            return
        }
        // Only one Agent HUD runs at a time, since the one that runs points the clients' hooks at itself: a launch while
        // another copy runs says where it is and quits before reading or writing anything. A probe reads and quits, and
        // a demo keeps its own preferences, has no ledger or report cache, installs no hooks and serves no approvals, so
        // either may run beside the real one, unless it is told to reset the preferences, which that one uses.
        if options.resetDefaults || (!options.probe && !options.demo), !SingleInstance.claim() {
            NSApp.terminate(nil)
            return
        }
        let demoSuite = "app.lotus.agentmonitor.demo"
        if options.resetDefaults {
            // The demo keeps its own suite, so resetting has to clear that too or a stale demo survives it.
            UserDefaults.standard.removePersistentDomain(forName: demoSuite)
            if let bundleID = Bundle.main.bundleIdentifier {
                UserDefaults.standard.removePersistentDomain(forName: bundleID)
            }
        }
        let defaults = options.demo ? UserDefaults(suiteName: demoSuite)! : .standard
        let settings = UsageAssembly.settings(defaults: defaults,
                                              defaultAgents: options.demo ? DemoData.everyAgent : [], language: options.language)
        // Hooks require a person's choice in this app's own settings.
        if !defaults.bool(forKey: "agentmonitor.explicit-setup.v1") {
            settings.update {
                $0.language = options.language ?? .zhHant
                $0.clientHooks = false
                $0.launchAtLogin = false
            }
            defaults.set(true, forKey: "agentmonitor.explicit-setup.v1")
        }
        if options.probe {
            Task { @MainActor in exit(await UsageProbe.run(settings: settings)) }
            return
        }
        // Migrate only this launch suite. Future appearance changes remain effective.
        DesktopAppearanceMigration.apply(settings: settings, defaults: defaults)
        let useDemoDefaults = options.demo
        displayObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { _ in
            MainActor.assumeIsolated {
                let selectedDefaults = useDemoDefaults ? UserDefaults(suiteName: demoSuite)! : .standard
                DesktopAppearanceMigration.apply(settings: settings, defaults: selectedDefaults)
            }
        }
        // A demo saved before the sample changed holds rows the sample no longer reads; it starts over from the sample's,
        // keeping every other preference.
        if options.demo, !settings.agents.contains(where: { row in DemoData.agents.contains { $0.id == row.id } }) {
            settings.updateAgents { _ in DemoData.everyAgent }
        }
        let store = UsageAssembly.store(settings: settings, ledger: options.demo ? nil : .open())
        if !options.demo, settings.settings.clientHooks, let executable = Bundle.main.executableURL {
            SessionObservers.configure(executable: executable, enabled: settings.settings.clientHooks)
        }
        let localStore = LocalMonitorStore(demo: options.demo)
        let controller = LocalMonitorController(store: localStore)
        self.localStore = localStore
        self.localController = controller
        let desktop = DesktopApplication(options: options, settings: settings, store: store,
            localContent: { page in
                switch page {
                case .overview: AnyView(MonitorDetails(store: localStore, section: .overview, embedded: true))
                case .processes: AnyView(MonitorDetails(store: localStore, section: .processes, embedded: true))
                case .docker: AnyView(MonitorDetails(store: localStore, section: .docker, embedded: true))
                case .localServices: AnyView(LocalServicesPage(store: localStore))
                default: AnyView(EmptyView())
                }
            },
            additionalHUDControls: { collapse in
                AnyView(LocalMonitorHUDSummary(store: localStore) {
                    collapse()
                    controller.showDetails()
                })
            }, maxVisibleAgentGroups: 2)
        self.desktop = desktop
        controller.onShowDetails = { [weak desktop] in desktop?.showMain(.overview) }
        installMainMenu()
        desktop.start()
        controller.start()
        if localDemo { controller.showDetails() }
    }

    private func installMainMenu() {
        let mainMenu = NSMenu()
        let appItem = NSMenuItem()
        let appMenu = NSMenu(title: "Agent Monitor")
        let settings = NSMenuItem(title: "設定…", action: #selector(showSettings), keyEquivalent: ",")
        settings.target = self
        appMenu.addItem(settings)
        appMenu.addItem(.separator())
        let quit = NSMenuItem(title: "結束 Agent Monitor", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quit.target = NSApp
        appMenu.addItem(quit)
        appItem.submenu = appMenu
        mainMenu.addItem(appItem)

        let windowItem = NSMenuItem()
        let windowMenu = NSMenu(title: "視窗")
        let details = NSMenuItem(title: "本機監測", action: #selector(showLocalDetails), keyEquivalent: "1")
        details.target = self
        windowMenu.addItem(details)
        windowItem.submenu = windowMenu
        mainMenu.addItem(windowItem)
        NSApp.mainMenu = mainMenu
        NSApp.windowsMenu = windowMenu
    }

    @objc private func showSettings() { desktop?.showSettings() }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        desktop?.reopen()
        return false
    }

    @objc private func showLocalDetails() { localController?.showDetails() }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationWillTerminate(_ notification: Notification) {
        if let displayObserver { NotificationCenter.default.removeObserver(displayObserver) }
        localController?.stop()
        localStore?.stop()
        desktop?.stop()
    }
}

// Hooks and adapter commands run as short-lived processes, without the interface or an account query.
if let status = HookEntry.handle(arguments: CommandLine.arguments) { exit(status) }

if CommandLine.arguments.contains("--probe-open-agents") {
    Task { print(await OpenAgentDiagnostics.localSummary()); exit(0) }
    dispatchMain()
}

if CommandLine.arguments.contains("--local-probe") {
    Task { @MainActor in
        let store = LocalMonitorStore()
        await store.refresh()
        try? await Task.sleep(for: .seconds(1))
        await store.refresh()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        do {
            let data = try encoder.encode(store.snapshot)
            print(String(decoding: data, as: UTF8.self))
            store.stop()
            exit(0)
        } catch {
            FileHandle.standardError.write(Data("Local probe failed: \(error)\n".utf8))
            store.stop()
            exit(1)
        }
    }
    dispatchMain()
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
