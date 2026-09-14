import SwiftUI

struct CreateSessionView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.studioSnapshot) private var snapshot
    @State private var name = "Morning Practice"
    @State private var mode: PracticeMode = .general
    @State private var prompt = ""
    @State private var keepsRecordings = true

    var body: some View {
        StudioPage {
            HStack(alignment: .top, spacing: 46) {
                VStack(alignment: .leading, spacing: 22) {
                    BackButton(title: "Back to studio") { model.navigate(to: AppDestination.studio) }
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 9) {
                            Circle().fill(Studio.accent).frame(width: 6, height: 6)
                            SectionEyebrow(text: "Create a new session")
                        }
                        Text("Start a new session")
                            .font(.system(size: 43, weight: .regular)).tracking(-1.8)
                        Text("Choose a practice mode, add a topic if you’d like, and get ready to record.\nYou’ll take multiple takes, get feedback, and track your progress.")
                            .font(.system(size: 14)).foregroundStyle(Studio.secondary).lineSpacing(5)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    fieldTitle("1. Session name")
                    if snapshot {
                        snapshotField(name)
                    } else {
                        TextField("Session name", text: $name).textFieldStyle(StudioTextFieldStyle())
                    }
                    Text("Give your session a name to help you keep track later.")
                        .font(.system(size: 10)).foregroundStyle(Studio.secondary)

                    fieldTitle("2. Practice mode")
                    HStack(spacing: 12) {
                        ForEach(PracticeMode.allCases) { item in
                            Button { mode = item } label: {
                                HStack(alignment: .top, spacing: 13) {
                                    Image(systemName: item.icon)
                                        .font(.system(size: 17))
                                        .foregroundStyle(Studio.accent)
                                        .frame(width: 40, height: 40)
                                        .background(Studio.accent.opacity(0.08), in: Circle())
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(item.title).font(.system(size: 12, weight: .semibold))
                                        Text(item.detail).font(.system(size: 9)).foregroundStyle(Studio.secondary).lineSpacing(2)
                                    }
                                    Spacer(minLength: 4)
                                    Image(systemName: mode == item ? "largecircle.fill.circle" : "circle")
                                        .foregroundStyle(mode == item ? Studio.accent : Studio.secondary)
                                }
                                .padding(14)
                                .frame(maxWidth: .infinity, minHeight: 88, alignment: .topLeading)
                                .background(mode == item ? Studio.accent.opacity(0.055) : Studio.surface.opacity(0.48), in: RoundedRectangle(cornerRadius: 12))
                                .overlay(RoundedRectangle(cornerRadius: 12).stroke(mode == item ? Studio.accent : Studio.line, lineWidth: mode == item ? 1.5 : 1))
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    fieldTitle("3. Prompt or topic (optional)")
                    ZStack(alignment: .bottomTrailing) {
                        if snapshot {
                            snapshotField(prompt.isEmpty ? "e.g. A short introduction, a recent experience, or a topic to practice…" : prompt, height: 82)
                        } else {
                            TextEditor(text: $prompt)
                                .font(.system(size: 12))
                                .scrollContentBackground(.hidden)
                                .padding(10)
                                .frame(height: 82)
                                .background(Studio.surface.opacity(0.62), in: RoundedRectangle(cornerRadius: 10))
                                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Studio.line))
                        }
                        Text("\(prompt.count)/500")
                            .font(.system(size: 9, design: .monospaced)).foregroundStyle(Studio.secondary)
                            .padding(10)
                    }
                    .onChange(of: prompt) { _, value in if value.count > 500 { prompt = String(value.prefix(500)) } }
                    Text("Add a prompt to guide your session, or leave it blank for open practice.")
                        .font(.system(size: 10)).foregroundStyle(Studio.secondary)

                    fieldTitle("4. Save every take locally")
                    HStack(spacing: 12) {
                        if snapshot { snapshotSwitch(keepsRecordings) }
                        else { Toggle("", isOn: $keepsRecordings).labelsHidden().toggleStyle(.switch) }
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Save every take locally").font(.system(size: 12, weight: .medium))
                            Text(keepsRecordings ? "Keep all recordings on this device for review and comparison." : "Keep only the latest take; a new take replaces the previous recording.")
                                .font(.system(size: 9)).foregroundStyle(Studio.secondary)
                        }
                    }

                    HStack(spacing: 14) {
                        Button {
                            model.createSession(name: name, mode: mode, prompt: prompt, keepsRecordings: keepsRecordings)
                        } label: {
                            HStack(spacing: 16) {
                                Image(systemName: "mic.fill")
                                Text("Start session")
                                Image(systemName: "arrow.right")
                            }.frame(width: 240)
                        }
                        .buttonStyle(StudioButtonStyle(prominent: true))
                        .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        Button("Cancel") { model.navigate(to: AppDestination.studio) }
                            .buttonStyle(StudioButtonStyle())
                    }
                    PrivacyFooter()
                }
                .frame(maxWidth: 930, alignment: .leading)

                sessionExplanation
                    .frame(width: 350)
                    .padding(.top, 38)
            }
        }
    }

    private func fieldTitle(_ title: String) -> some View {
        Text(title).font(.system(size: 12, weight: .semibold))
    }

    private func snapshotField(_ value: String, height: CGFloat = 42) -> some View {
        Text(value)
            .font(.system(size: 12))
            .foregroundStyle(value.hasPrefix("e.g.") ? Studio.secondary : Studio.ink)
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity, minHeight: height, alignment: .leading)
            .background(Studio.surface.opacity(0.62), in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Studio.line))
    }

    private func snapshotSwitch(_ isOn: Bool) -> some View {
        Capsule().fill(isOn ? Studio.accent : Studio.line).frame(width: 38, height: 22)
            .overlay(alignment: isOn ? .trailing : .leading) {
                Circle().fill(isOn ? Studio.background : Studio.secondary).frame(width: 17, height: 17).padding(2.5)
            }
    }

    private var sessionExplanation: some View {
        VStack(alignment: .leading, spacing: 21) {
            SectionEyebrow(text: "What happens in a session")
            explanationStep(1, "mic", "Record multiple takes", "Take 2–12 takes, or as many as you like. Each take is analyzed on your device.")
            explanationStep(2, "chart.bar.fill", "Get instant feedback", "See objective signals for pitch, loudness, pauses, and more after each take.")
            explanationStep(3, "doc.on.doc", "Compare and improve", "Listen back, compare takes, and track your progress over time.")
            Rectangle().fill(Studio.line).frame(height: 1)
            Label("All recordings are processed and stored locally on your device. Your voice stays private.", systemImage: "checkmark.shield")
                .font(.system(size: 10)).foregroundStyle(Studio.secondary).lineSpacing(3)
            VoiceSculpture(recording: false, level: -80).frame(height: 220)
            Text("SPEAK. LISTEN. GROW.")
                .font(.system(size: 8, design: .monospaced)).tracking(2.4).foregroundStyle(Studio.secondary)
                .frame(maxWidth: .infinity)
        }
        .padding(25)
        .studioCard(emphasized: true)
    }

    private func explanationStep(_ number: Int, _ icon: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 13) {
            Text("\(number)").font(.system(size: 12, weight: .medium))
                .frame(width: 32, height: 32).overlay(Circle().stroke(Studio.accent.opacity(0.28)))
            Image(systemName: icon).foregroundStyle(Studio.accent).frame(width: 28, height: 32)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.system(size: 12, weight: .semibold))
                Text(detail).font(.system(size: 10)).foregroundStyle(Studio.secondary).lineSpacing(3)
            }
        }
    }
}

private struct StudioTextFieldStyle: TextFieldStyle {
    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
            .font(.system(size: 13))
            .padding(.horizontal, 14)
            .frame(height: 42)
            .background(Studio.surface.opacity(0.62), in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Studio.line))
    }
}
