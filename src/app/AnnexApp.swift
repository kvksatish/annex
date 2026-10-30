import SwiftUI

@main
struct AnnexApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var model = AppModel.shared

    var body: some Scene {
        Window("Annex", id: "dashboard") {
            DashboardView().environmentObject(model)
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)

        MenuBarExtra {
            MenuContent().environmentObject(model)
        } label: {
            Image(systemName: model.menuIcon)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        AppModel.shared.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        AppModel.shared.log.add("Annex quit")
    }

    // Closing the dashboard keeps Annex running in the menu bar.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}

struct MenuContent: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        if let name = model.receivingFrom {
            Text("Showing \(name)")
            Button("Give My Screen Back") { model.handBackScreen() }
        } else if model.link == .streaming, let peer = model.targetPeer {
            Text("Extended to \(peer.name) · \(Int(model.stats.fps)) fps")
        } else {
            Text(model.peers.isEmpty ? "Looking for your other Mac…" : "Ready")
        }
        Divider()
        ForEach(model.peers) { peer in
            Button(model.targetID == peer.id ? "Stop Using \(peer.name)" : "Use \(peer.name) as Display") {
                model.toggle(peer)
            }
        }
        Divider()
        Button("Open Annex…") {
            openWindow(id: "dashboard")
            NSApp.activate(ignoringOtherApps: true)
        }
        Button("Quit Annex") { NSApp.terminate(nil) }.keyboardShortcut("q")
    }
}
