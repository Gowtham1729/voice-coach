import SwiftUI

struct CreateSessionView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.studioSnapshot) private var snapshot
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var name = "Morning Practice"
    @State private var mode: PracticeMode = .general
    @State private var keepsRecordings = true
    @State private var excerptStart = 0.0
    @State private var excerptEnd = 0.0

    init(initialMode: PracticeMode = .general) {
        _mode = State(initialValue: initialMode)
    }

    var body: some View {
        StudioPage(maxWidth: 760, horizontalPadding: 24) {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Text("New Session")
                        .font(.title2.weight(.semibold))
                    Spacer()
                }

                settingsSection("Session", symbol: "folder") {
                    formRow("Name") {
                        if snapshot {
                            snapshotField(name)
                        } else {
                            TextField("Session name", text: $name)
                                .textFieldStyle(.roundedBorder)
                                .frame(maxWidth: 420)
                        }
                    }

                    Divider()

                    formRow("Practice Mode") {
                        if snapshot {
                            HStack(spacing: 8) {
                                ForEach(PracticeMode.allCases) { item in
                                    Text(item.title)
                                        .font(.caption)
                                        .padding(.horizontal, 10)
                                        .frame(height: 28)
                                        .background(mode == item ? Studio.accent.opacity(0.18) : Studio.background, in: RoundedRectangle(cornerRadius: 6))
                                }
                            }
                        } else {
                            Picker("Practice Mode", selection: $mode) {
                                ForEach(PracticeMode.allCases) { item in
                                    Text(item.title).tag(item)
                                }
                            }
                            .labelsHidden()
                            .pickerStyle(.menu)
                            .frame(maxWidth: 420)
                            .animation(StudioMotion.spring(reduceMotion: reduceMotion), value: mode)
                        }
                    }

                    Text(mode.detail)
                        .font(.caption)
                        .foregroundStyle(Studio.secondary)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }

                if mode == .mimic {
                    MimicReferencePicker(start: $excerptStart, end: $excerptEnd)
                }

                if mode != .mimic {
                    settingsSection("Local Storage", symbol: "internaldrive") {
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Save every take")
                                    .font(.body.weight(.medium))
                                Text(keepsRecordings ? "Keep every recording in this session for comparison." : "Keep only the newest recording in this session.")
                                    .font(.caption)
                                    .foregroundStyle(Studio.secondary)
                            }
                            Spacer()
                            if snapshot {
                                Capsule().fill(keepsRecordings ? Studio.accent : Studio.line).frame(width: 38, height: 22)
                            } else {
                                Toggle("Save every take", isOn: $keepsRecordings)
                                    .labelsHidden()
                                    .toggleStyle(.switch)
                            }
                        }
                    }
                }

                HStack {
                    Spacer()
                    Button("Cancel") { model.navigate(to: AppDestination.studio) }
                        .tint(.primary)
                        .keyboardShortcut(.cancelAction)
                        .studioGlassButton()
                    Button("Create Session") {
                        if mode == .mimic {
                            model.createMimicSession(name: name, start: excerptStart, end: excerptEnd)
                        } else {
                            model.createSession(name: name, mode: .general, prompt: "", keepsRecordings: keepsRecordings)
                        }
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                              || (mode == .mimic && (model.mimicDraft == nil || model.mimicIsPreparing || model.isCapturingMimicReference || excerptEnd - excerptStart < 1)))
                    .studioGlassButton(prominent: true)
                }

                Text("Recordings and analysis stay on this Mac. Voice Coach measurements are not a medical assessment.")
                    .font(.caption)
                    .foregroundStyle(Studio.secondary)
            }
            .onChange(of: model.mimicDraft?.id) { _, _ in
                loadMimicDraft()
            }
            .onAppear { if mode == .mimic, excerptEnd == 0 { loadMimicDraft() } }
            .onDisappear { model.cancelMimicPreparation() }
        }
    }

    private func loadMimicDraft() {
        guard let draft = model.mimicDraft else { return }
        excerptStart = 0
        excerptEnd = min(draft.duration, 20)
        if name == "Morning Practice" { name = draft.sourceName }
    }

    private func settingsSection<Content: View>(_ title: String, symbol: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: symbol)
                .font(.headline)
            content()
        }
        .padding(16)
        .desktopPanel()
    }

    private func formRow<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .center, spacing: 18) {
            Text(label)
                .font(.body)
                .frame(width: 110, alignment: .leading)
            Spacer(minLength: 8)
            content()
        }
    }

    private func snapshotField(_ value: String, height: CGFloat = 28) -> some View {
        Text(value)
            .font(.body)
            .foregroundStyle(value.hasPrefix("Add") ? Studio.secondary : Studio.ink)
            .padding(.horizontal, 8)
            .frame(maxWidth: 420, minHeight: height, alignment: .leading)
            .background(Studio.background, in: RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Studio.line, lineWidth: 0.5))
    }
}
