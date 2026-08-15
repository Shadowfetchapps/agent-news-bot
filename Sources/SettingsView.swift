import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var engine: NewsEngine
    @ObservedObject private var settings = SettingsStore.shared
    @State private var hermesToken = ""
    @State private var openClawToken = ""

    var body: some View {
        Form {
            Section("Freshness") {
                Stepper(value: $settings.lookbackHours, in: 2...48, step: 1) {
                    Text("Lookback \(Int(settings.lookbackHours)) hours")
                }
                Stepper(value: $settings.maxPerDesk, in: 5...50, step: 5) {
                    Text("Max \(settings.maxPerDesk) stories per desk")
                }
                Text("A story appears only if it is unseen and published inside the lookback window. Markets appear only on a real move. Weather appears when the forecast changes.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("Weather & markets") {
                TextField("Weather city", text: $settings.weatherCity)
                TextField("Yahoo symbols", text: $settings.marketSymbols, axis: .vertical)
                    .lineLimit(2...4)
            }
            Section("Hermes") {
                Toggle("Prefer `hermes chat` CLI", isOn: $settings.hermesUseCLI)
                TextField("API base URL", text: $settings.hermesAPIURL)
                SecureField("API bearer token (optional)", text: $hermesToken)
                Text("Native send uses `hermes chat -Q` when the CLI is on PATH. Otherwise POST /v1/chat/completions. Local Hermes was detected at ~/.local/bin/hermes.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("OpenClaw") {
                TextField("Gateway URL", text: $settings.openClawURL)
                SecureField("Gateway token (optional)", text: $openClawToken)
                Text("The app probes the gateway on loopback and can send via the `openclaw` CLI. Agents can also pull GET /v1/fresh from the local bridge.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("Agent bridge") {
                Stepper(value: $settings.bridgePort, in: 1025...64999, step: 1) {
                    Text("Listen 127.0.0.1:\(settings.bridgePort)")
                }
                LabeledContent("Bearer token") {
                    Text(engine.bridgeToken)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                }
                Text("Loopback only. Hermes skill is installed to ~/.hermes/skills/agent-news-bot.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("Desks") {
                ForEach(Desk.allCases) { desk in
                    Toggle(desk.title, isOn: Binding(
                        get: { settings.enabledDesks.contains(desk) },
                        set: { on in
                            if on { settings.enabledDesks.insert(desk) } else { settings.enabledDesks.remove(desk) }
                        }
                    ))
                }
            }
        }
        .formStyle(.grouped)
        .onAppear {
            hermesToken = settings.hermesToken
            openClawToken = settings.openClawToken
        }
        .onDisappear {
            settings.hermesToken = hermesToken
            settings.openClawToken = openClawToken
            settings.save()
            engine.bridge.start(port: settings.bridgePort, token: engine.bridgeToken)
        }
    }
}
