import SwiftUI
import CoreAudio

struct MenuBarView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HeaderView()

            Divider()

            // Status
            StatusView()

            Divider()

            // Recording indicator
            if appState.isRecording || appState.isTranscribing {
                RecordingStatusView()
                Divider()
            }

            // Last transcription
            if !appState.lastTranscription.isEmpty {
                TranscriptionView()
                Divider()
            }

            // Input device selector
            InputDeviceView()

            Divider()

            // Actions
            ActionsView()
        }
        .frame(width: 320)
        .background(Color(NSColor.windowBackgroundColor))
    }
}

struct HeaderView: View {
    var body: some View {
        HStack {
            Image(systemName: "waveform.circle.fill")
                .font(.title2)
                .foregroundColor(.accentColor)

            Text("VoiceScribe")
                .font(.headline)

            Spacer()

            Text("v1.0")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
    }
}

struct StatusView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        HStack {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)

            Text(appState.serverStatus.description)
                .font(.subheadline)

            Spacer()

            if !appState.serverStatus.isReady {
                ProgressView()
                    .scaleEffect(0.7)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    private var statusColor: Color {
        switch appState.serverStatus {
        case .ready:
            return .green
        case .starting, .loadingModel:
            return .orange
        case .error:
            return .red
        }
    }
}

struct RecordingStatusView: View {
    @EnvironmentObject var appState: AppState
    @State private var animationAmount = 1.0

    var body: some View {
        HStack {
            if appState.isRecording {
                Circle()
                    .fill(.red)
                    .frame(width: 12, height: 12)
                    .scaleEffect(animationAmount)
                    .animation(
                        .easeInOut(duration: 0.5).repeatForever(autoreverses: true),
                        value: animationAmount
                    )
                    .onAppear {
                        animationAmount = 1.2
                    }

                Text("Recording...")
                    .font(.subheadline)
                    .foregroundColor(.red)
            } else if appState.isTranscribing {
                ProgressView()
                    .scaleEffect(0.8)

                Text("Transcribing...")
                    .font(.subheadline)
            }

            Spacer()
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }
}

struct TranscriptionView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Last Transcription")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Spacer()

                Button(action: copyToClipboard) {
                    Image(systemName: "doc.on.doc")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .help("Copy to clipboard")
            }

            Text(appState.lastTranscription)
                .font(.body)
                .lineLimit(5)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    private func copyToClipboard() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(appState.lastTranscription, forType: .string)
    }
}

struct InputDeviceView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Input Device")
                .font(.caption)
                .foregroundColor(.secondary)

            Picker("Input", selection: $appState.selectedInputDevice) {
                ForEach(appState.availableInputDevices) { device in
                    HStack {
                        if device.isDefault {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                        }
                        Text(device.name)
                    }
                    .tag(device.id as AudioDeviceID?)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()

            Button(action: { appState.refreshInputDevices() }) {
                HStack {
                    Image(systemName: "arrow.clockwise")
                    Text("Refresh")
                }
                .font(.caption)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }
}

struct ActionsView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(spacing: 4) {
            // Shortcut hint
            HStack {
                Image(systemName: "keyboard")
                    .foregroundColor(.secondary)

                Text("Hold \(appState.shortcutKey.displayName) to record")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Spacer()
            }
            .padding(.horizontal)
            .padding(.top, 8)

            Divider()
                .padding(.vertical, 4)

            // Menu items
            Button(action: openSettings) {
                HStack {
                    Image(systemName: "gear")
                    Text("Settings...")
                    Spacer()
                    Text("⌘,")
                        .foregroundColor(.secondary)
                }
            }
            .buttonStyle(MenuButtonStyle())

            Button(action: quitApp) {
                HStack {
                    Image(systemName: "power")
                    Text("Quit VoiceScribe")
                    Spacer()
                    Text("⌘Q")
                        .foregroundColor(.secondary)
                }
            }
            .buttonStyle(MenuButtonStyle())
        }
        .padding(.bottom, 8)
    }

    private func openSettings() {
        AppDelegate.shared?.openSettingsWindow()
    }

    private func quitApp() {
        NSApplication.shared.terminate(nil)
    }
}

struct MenuButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(configuration.isPressed ? Color.accentColor.opacity(0.2) : Color.clear)
            .contentShape(Rectangle())
    }
}

#Preview {
    MenuBarView()
        .environmentObject(AppState.shared)
}
