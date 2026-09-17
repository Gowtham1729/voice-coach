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
