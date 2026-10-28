import AppKit
import SwiftUI

@main
struct UnzipperApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = AppModel.shared

    var body: some Scene {
        Window("Unzipper", id: "main") {
            ContentView()
                .environmentObject(model)
        }
        .defaultSize(width: 1120, height: 720)
        .windowToolbarStyle(.unified(showsTitle: true))
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Open Archive…") {
                    AppModel.shared.chooseArchive()
                }
                .keyboardShortcut("o")

                Button("New Archive…") {
                    AppModel.shared.presentNewArchive()
                }
                .keyboardShortcut("n")
            }

            CommandGroup(after: .saveItem) {
                Divider()
                Button("Extract All…") {
                    AppModel.shared.extractAll()
                }
                .keyboardShortcut("e")

                Button("Extract Selected…") {
                    AppModel.shared.extractSelected()
                }
                .keyboardShortcut("e", modifiers: [.command, .shift])

                Divider()

                Button("Close Archive") {
                    AppModel.shared.closeArchive()
                }
                .keyboardShortcut("w", modifiers: [.command, .shift])

                Button("Reveal Archive in Finder") {
                    AppModel.shared.revealArchive()
                }

                Divider()

                Button("Select All Items") {
                    AppModel.shared.selectAllRows()
                }
                .keyboardShortcut("a", modifiers: [.command, .shift])
            }

            CommandGroup(after: .toolbar) {
                Divider()

                Button("Quick Look") {
                    AppModel.shared.quickLookSelection()
                }
                .keyboardShortcut("y")

                Button("Enclosing Folder") {
                    AppModel.shared.goUp()
                }
                .keyboardShortcut(.upArrow, modifiers: .command)

                Button("Find…") {
                    AppModel.shared.focusSearch()
                }
                .keyboardShortcut("f")
            }
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.activate(ignoringOtherApps: true)
        openLaunchArgumentIfPresent()
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        guard let url = urls.first(where: { FileManager.default.fileExists(atPath: $0.path) }) else { return }
        AppModel.shared.open(url)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            sender.windows.first?.makeKeyAndOrderFront(nil)
        }
        return true
    }

    private func openLaunchArgumentIfPresent() {
        for argument in CommandLine.arguments.dropFirst() where !argument.hasPrefix("-") {
            let url = URL(fileURLWithPath: argument)
            if FileManager.default.fileExists(atPath: url.path) {
                AppModel.shared.open(url)
                break
            }
        }
    }
}
