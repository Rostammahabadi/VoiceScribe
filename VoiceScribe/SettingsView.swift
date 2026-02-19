import SwiftUI
import CoreAudio

struct SettingsView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem {
                    Label("General", systemImage: "gear")
                }

            ShortcutSettingsView()
                .tabItem {
                    Label("Shortcuts", systemImage: "keyboard")
                }

            AudioSettingsView()
                .tabItem {
                    Label("Audio", systemImage: "mic")
                }

            AboutView()
                .tabItem {
                    Label("About", systemImage: "info.circle")
                }
        }
        .frame(minWidth: 400, minHeight: 300)
    }
}

struct GeneralSettingsView: View {
    @EnvironmentObject var appState: AppState
    @State private var launchAtLogin = false

    var body: some View {
        Form {
            Section {
                Toggle("Auto-copy transcription to clipboard", isOn: $appState.autoCopyEnabled)

                Toggle("Auto-type transcription", isOn: $appState.autoTypeEnabled)
                    .help("Automatically type the transcribed text at the cursor position")

                Toggle("Clean up speech (via Ollama)", isOn: $appState.textCleanupEnabled)
                    .help("Use nemotron-mini running on local Ollama to remove filler words like 'um' and 'uh' and fix minor grammar issues")

                Toggle("Launch at login", isOn: $launchAtLogin)
                    .disabled(true)
                    .help("Coming soon")
            }

            Section {
                HStack {
                    Text("Server Status:")
                    Spacer()
                    Circle()
                        .fill(appState.serverStatus.isReady ? Color.green : Color.orange)
                        .frame(width: 8, height: 8)
                    Text(appState.serverStatus.description)
                        .foregroundColor(.secondary)
                }

                HStack {
                    Text("Model:")
                    Spacer()
                    Text(appState.modelLoaded ? "Parakeet TDT 0.6B v2" : "Not loaded")
                        .foregroundColor(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

struct ShortcutSettingsView: View {
    @EnvironmentObject var appState: AppState
    @State private var hasAccessibilityPermission = AXIsProcessTrusted()

    var body: some View {
        Form {
            Section {
                Picker("Push-to-talk key:", selection: $appState.shortcutKey) {
                    ForEach(ShortcutKey.allCases, id: \.self) { key in
                        Text(key.displayName).tag(key)
                    }
                }
                .pickerStyle(.radioGroup)

                Text("Hold the selected key to start recording. Release to stop and transcribe.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            // Only show if accessibility permission is missing
            if !hasAccessibilityPermission {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.orange)
                            Text("Accessibility Permission Required")
                                .font(.headline)
                        }

                        Text("VoiceScribe needs accessibility permissions to detect keyboard shortcuts globally.")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        Button("Open Accessibility Settings") {
                            openAccessibilitySettings()
                        }
                    }
                }
            } else {
                Section {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text("Accessibility permission granted")
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .padding()
        .onAppear {
            hasAccessibilityPermission = AXIsProcessTrusted()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            hasAccessibilityPermission = AXIsProcessTrusted()
        }
    }

    private func openAccessibilitySettings() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = ["x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"]
        try? process.run()
    }
}

struct AudioSettingsView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        Form {
            Section("Input Device") {
                Picker("Microphone:", selection: $appState.selectedInputDevice) {
                    ForEach(appState.availableInputDevices) { device in
                        HStack {
                            Text(device.name)
                            if device.isDefault {
                                Text("(Default)")
                                    .foregroundColor(.secondary)
                            }
                        }
                        .tag(device.id as AudioDeviceID?)
                    }
                }

                Button("Refresh Devices") {
                    appState.refreshInputDevices()
                }
            }

            Section {
                Text("Note: Changing the input device will set it as the system default input.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

struct AboutView: View {
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "waveform.circle.fill")
                .font(.system(size: 64))
                .foregroundColor(.accentColor)

            Text("VoiceScribe")
                .font(.title)
                .fontWeight(.bold)

            Text("Version 1.0.0")
                .foregroundColor(.secondary)

            Text("Speech-to-text transcription powered by MLX Audio and the Parakeet model, optimized for Apple Silicon.")
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
                .padding(.horizontal)

            Spacer()

            VStack(spacing: 4) {
                Text("Powered by:")
                    .font(.caption)
                    .foregroundColor(.secondary)

                if let mlxURL = URL(string: "https://github.com/Blaizzy/mlx-audio") {
                    Link("MLX Audio", destination: mlxURL)
                        .font(.caption)
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    SettingsView()
        .environmentObject(AppState.shared)
}
