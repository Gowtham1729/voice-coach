import SwiftUI
import VoiceCoachCore

struct InsightsView: View {
    @EnvironmentObject private var model: AppModel

    private var takes: [PracticeSession] { model.sessions.flatMap(\.takes) }

    var body: some View {
        StudioPage {
            VStack(alignment: .leading, spacing: 18) {
                if takes.isEmpty {
                    EmptyState(icon: "chart.line.uptrend.xyaxis", title: "Record a few takes to see trends", detail: "Insights become more useful as your local practice library grows.", actionTitle: "Start a session") {
                        model.navigate(to: .create)
                    }
                } else {
                    summaryMetrics
                    HStack(alignment: .top, spacing: 18) {
                        trendCard(title: "Pitch range", unit: "st", values: takes.compactMap { $0.result.metrics.pitchRangeSemitones }, detail: "Expressive range across saved takes")
                        trendCard(title: "Phrase ending", unit: "dB", values: takes.map { $0.result.metrics.phraseDecayDB }, detail: "End loudness relative to phrase start")
                        trendCard(title: "Non-speech", unit: "%", values: takes.map { $0.result.metrics.nonSpeechRatio * 100 }, detail: "Share of each recording without speech")
                    }
                    recentActivity
                }
            }
        }
    }

    private var summaryMetrics: some View {
        HStack(spacing: 0) {
            insightMetric("Sessions", "\(model.sessions.count)", "focused practice spaces", "folder")
            insightMetric("Takes", "\(model.totalTakeCount)", "recorded and analyzed", "waveform")
            insightMetric("Practice time", vcNumber(model.totalRecordedDuration / 60, 1), "minutes of recorded voice", "clock")
            insightMetric("Latest practice", model.sessions.first?.updatedAt.formatted(date: .abbreviated, time: .omitted) ?? "—", "stored locally", "calendar")
        }
        .padding(22)
        .studioCard(emphasized: true)
    }

    private func insightMetric(_ title: String, _ value: String, _ detail: String, _ icon: String) -> some View {
        HStack(spacing: 13) {
            Image(systemName: icon).font(.system(size: 16)).foregroundStyle(Studio.accent)
                .frame(width: 42, height: 42).background(Studio.accent.opacity(0.08), in: Circle())
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.system(size: 10)).foregroundStyle(Studio.secondary)
                Text(value).font(.system(size: 23, weight: .regular)).monospacedDigit()
                Text(detail).font(.system(size: 9)).foregroundStyle(Studio.secondary)
            }
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .trailing) { Rectangle().fill(Studio.line).frame(width: 1) }
    }

    private func trendCard(title: String, unit: String, values: [Double], detail: String) -> some View {
        let points = values.enumerated().map { TimePoint(time: Double($0.offset), value: $0.element) }
        let average = values.isEmpty ? 0 : values.reduce(0, +) / Double(values.count)
        return VStack(alignment: .leading, spacing: 13) {
            SectionEyebrow(text: title)
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text(vcNumber(average, 1)).font(.system(size: 32, weight: .regular)).foregroundStyle(Studio.accent).monospacedDigit()
                Text(unit).font(.system(size: 10)).foregroundStyle(Studio.secondary)
                Spacer()
                Text("average").font(.system(size: 9)).foregroundStyle(Studio.secondary)
            }
            MiniSparkline(points: points).frame(height: 70)
            Text(detail).font(.system(size: 10)).foregroundStyle(Studio.secondary)
        }
        .padding(20)
        .frame(maxWidth: .infinity, minHeight: 180, alignment: .leading)
        .studioCard()
    }

    private var recentActivity: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionEyebrow(text: "Recent activity")
            ForEach(model.sessions.prefix(5)) { session in
                Button { model.resumeSession(session.id) } label: {
                    HStack(spacing: 14) {
                        Image(systemName: session.mode.icon).foregroundStyle(Studio.accent).frame(width: 28)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(session.name).font(.system(size: 12, weight: .semibold))
                            Text("\(session.takeCount) takes · \(vcNumber(session.totalDuration, 0)) seconds recorded")
                                .font(.system(size: 9)).foregroundStyle(Studio.secondary)
                        }
                        Spacer()
                        Text(session.updatedAt.formatted(.relative(presentation: .named))).font(.system(size: 9)).foregroundStyle(Studio.secondary)
                        Image(systemName: "arrow.right").foregroundStyle(Studio.secondary)
                    }
                    .padding(15).studioCard(cornerRadius: 11)
                }.buttonStyle(.plain)
            }
        }
    }
}

struct SettingsView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.studioSnapshot) private var snapshot
    @AppStorage("voiceCoach.confirmBeforeDelete") private var confirmDelete = true

    var body: some View {
        StudioPage(maxWidth: 980) {
            VStack(alignment: .leading, spacing: 16) {
                settingsSection("Practice", icon: "mic") {
                    settingToggle("Confirm before removing a session", detail: "Adds a confirmation step in the Sessions library.", value: $confirmDelete)
                }
                settingsSection("Local data", icon: "internaldrive") {
                    HStack {
                        VStack(alignment: .leading, spacing: 5) {
                            Text("Session library").font(.system(size: 12, weight: .semibold))
                            Text(model.storageLocation.path).font(.system(size: 9, design: .monospaced)).foregroundStyle(Studio.secondary).textSelection(.enabled)
                            Text("\(model.sessions.count) sessions · \(model.totalTakeCount) takes · recordings and analysis stay together")
                                .font(.system(size: 9)).foregroundStyle(Studio.secondary)
                        }
                        Spacer()
                        Button("Show in Finder", action: model.revealStorage)
                            .tint(.primary)
                            .studioGlassButton()
                    }
                }
                settingsSection("About the measurements", icon: "info.circle") {
                    Text("Voice Coach reports objective acoustic measurements such as pitch, loudness, pauses, recording quality, and voice-quality proxies. These are coaching signals—not medical measurements or diagnoses.")
                        .font(.system(size: 11)).foregroundStyle(Studio.secondary).lineSpacing(4)
                    Text("Waveforms and spectrograms stay available in the interface but are intentionally excluded from copied and exported JSON.")
                        .font(.system(size: 11)).foregroundStyle(Studio.secondary).lineSpacing(4)
                }
            }
        }
    }

    private func settingsSection<Content: View>(_ title: String, icon: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Label(title, systemImage: icon).font(.system(size: 13, weight: .semibold)).foregroundStyle(Studio.accent)
            content()
        }
        .padding(22).studioCard()
    }

    private func settingToggle(_ title: String, detail: String, value: Binding<Bool>) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.system(size: 12, weight: .medium))
                Text(detail).font(.system(size: 9)).foregroundStyle(Studio.secondary)
            }
            Spacer()
            if snapshot {
                Capsule().fill(value.wrappedValue ? Studio.accent : Studio.line).frame(width: 38, height: 22)
                    .overlay(alignment: value.wrappedValue ? .trailing : .leading) {
                        Circle().fill(value.wrappedValue ? Studio.background : Studio.secondary).frame(width: 17, height: 17).padding(2.5)
                    }
            } else {
                Toggle("", isOn: value).labelsHidden().toggleStyle(.switch)
            }
        }
        .padding(.vertical, 3)
    }
}
