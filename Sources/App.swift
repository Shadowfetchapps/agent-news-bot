import SwiftUI
import AppKit

@main
struct AgentNewsBotApp: App {
    @ObservedObject private var engine = NewsEngine.shared

    init() {
        NSApplication.shared.appearance = NSAppearance(named: .darkAqua)
    }

    var body: some Scene {
        WindowGroup("Agent News Bot") {
            ContentView()
                .environmentObject(engine)
                .preferredColorScheme(.dark)
                .frame(minWidth: 1100, minHeight: 700)
                .onAppear { engine.start() }
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandMenu("Desk") {
                Button("Fetch Fresh") {
                    Task { await engine.fetchFresh() }
                }
                .keyboardShortcut("r", modifiers: [.command])
                Divider()
                Button("Send Selection to Hermes") {
                    Task { await engine.sendToHermes() }
                }
                .keyboardShortcut("h", modifiers: [.command, .shift])
                Button("Send Selection to OpenClaw") {
                    Task { await engine.sendToOpenClaw() }
                }
                Button("Reveal Exports") {
                    engine.revealExports()
                }
            }
        }

        Settings {
            SettingsView()
                .environmentObject(engine)
                .frame(width: 520, height: 560)
        }

        MenuBarExtra("Agent News Bot", systemImage: "dot.radiowaves.left.and.right") {
            Button(engine.isFetching ? "Fetching…" : "Fetch Fresh") {
                Task { await engine.fetchFresh() }
            }
            .disabled(engine.isFetching)
            Text("\(engine.articles.count) fresh")
            Divider()
            Button("Open Desk") {
                NSApp.activate(ignoringOtherApps: true)
            }
            Button("Quit") { NSApp.terminate(nil) }
        }
    }
}
