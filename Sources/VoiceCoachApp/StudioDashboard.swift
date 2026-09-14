import SwiftUI
import VoiceCoachCore

struct StudioDashboard: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        StudioPage {
            VStack(alignment: .leading, spacing: 22) {
                hero
                if let latest = model.sessions.first { continueCard(latest) }
                recentSessions
                PrivacyFooter()
            }
        }
    }

    private var hero: some View {
        GeometryReader { geometry in
            let compact = geometry.size.width < 1080
            HStack(alignment: .center, spacing: 34) {
                VStack(alignment: .leading, spacing: 18) {
                    HStack(spacing: 9) {
                        Circle().fill(Studio.accent).frame(width: 6, height: 6)
                        SectionEyebrow(text: "Your personal voice studio")
                    }
                    Text("Practice your voice,\none take at a time.")
                        .font(.system(size: compact ? 42 : 53, weight: .regular))
                        .tracking(-2.2)
                        .lineSpacing(-4)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Build clarity, confidence, and presence. Take 10–30 seconds to speak,\nlisten back, and discover a stronger you.")
                        .font(.system(size: 15))
                        .foregroundStyle(Studio.secondary)
                        .lineSpacing(6)
                    HStack(spacing: 14) {
                        Button { model.navigate(to: .create) } label: {
                            HStack(spacing: 16) {
                                Image(systemName: "mic.fill")
                                Text("Start new session")
                                Image(systemName: "arrow.right")
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(StudioButtonStyle(prominent: true))
                        .frame(maxWidth: 305)

                        Button(action: model.startQuickPractice) {
                            HStack(spacing: 12) {
                                Image(systemName: "mic")
                                    .font(.system(size: 20))
                                    .foregroundStyle(Studio.accent)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Quick record").font(.system(size: 13, weight: .semibold))
                                    Text("Record a single take").font(.system(size: 10)).foregroundStyle(Studio.secondary)
                                }
                            }
                            .padding(.horizontal, 20)
                            .frame(height: 48)
                        }
                        .buttonStyle(.plain)
                        .studioCard(cornerRadius: 24)
                    }
                    Label("A session is a focused practice space where multiple takes stay together for review.", systemImage: "doc.text")
                        .font(.system(size: 11))
                        .foregroundStyle(Studio.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VoiceSculpture(recording: false, level: -80)
                    .frame(width: compact ? 250 : 330, height: 300)
                    .overlay(alignment: .bottom) {
                        Text("SPEAK. LISTEN. GROW.")
                            .font(.system(size: 8, design: .monospaced))
                            .tracking(2.4)
                            .foregroundStyle(Studio.secondary)
                            .padding(.bottom, 10)
                    }

                if !compact { howItWorks.frame(width: 340) }
            }
        }
        .frame(height: 430)
    }

    private var howItWorks: some View {
        VStack(alignment: .leading, spacing: 18) {
            SectionEyebrow(text: "How it works")
            step(1, "mic", "Start a session", "Choose a topic or go freeform. Find a quiet spot and get comfortable.")
            step(2, "waveform", "Record takes", "Speak naturally. Take as many tries as you like—small steps add up.")
            step(3, "chart.bar", "Review changes", "Listen back, see objective insights, and notice progress over time.")
            Rectangle().fill(Studio.line).frame(height: 1)
            Label("All processing happens on your device.\nYour voice stays private.", systemImage: "checkmark.shield")
                .font(.system(size: 11)).foregroundStyle(Studio.secondary).lineSpacing(3)
        }
        .padding(24)
        .studioCard(emphasized: true)
    }

    private func step(_ number: Int, _ icon: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Text("\(number)")
                .font(.system(size: 13, weight: .medium))
                .frame(width: 34, height: 34)
                .background(Studio.accent.opacity(0.06), in: Circle())
                .overlay(Circle().stroke(Studio.accent.opacity(0.25)))
            Image(systemName: icon).foregroundStyle(Studio.accent).frame(width: 28, height: 34)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.system(size: 12, weight: .semibold))
                Text(detail).font(.system(size: 10)).foregroundStyle(Studio.secondary).lineSpacing(3)
            }
        }
    }

    private func continueCard(_ session: CoachingSession) -> some View {
        HStack(spacing: 24) {
            VStack(alignment: .leading, spacing: 10) {
                SectionEyebrow(text: "Your latest session")
                HStack(spacing: 14) {
                    Image(systemName: "doc.text.fill")
                        .foregroundStyle(Studio.accent)
                        .frame(width: 48, height: 48)
                        .background(Studio.accent.opacity(0.09), in: RoundedRectangle(cornerRadius: 12))
                    VStack(alignment: .leading, spacing: 4) {
                        Text(session.name).font(.system(size: 17, weight: .semibold))
                        Text("\(session.takeCount) takes saved  ·  Updated \(session.updatedAt.formatted(.relative(presentation: .named)))")
                            .font(.system(size: 10)).foregroundStyle(Studio.secondary)
                    }
                }
            }
            Spacer()
            if let take = session.latestTake {
                VStack(alignment: .leading, spacing: 5) {
                    Label("Last take", systemImage: "chart.line.uptrend.xyaxis")
                        .font(.system(size: 11, weight: .medium)).foregroundStyle(Studio.accent)
                    Text(summary(for: take)).font(.system(size: 10)).foregroundStyle(Studio.secondary)
                }
                .frame(maxWidth: 330, alignment: .leading)
            }
            Button { model.resumeSession(session.id) } label: {
                Label("View session", systemImage: "arrow.right").frame(width: 190)
            }
            .buttonStyle(StudioButtonStyle(prominent: true))
        }
        .padding(22)
        .studioCard()
    }

    private var recentSessions: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                SectionEyebrow(text: "Recent sessions")
                Spacer()
                Button { model.navigate(to: AppDestination.sessions) } label: {
                    Label("View all", systemImage: "arrow.right").labelStyle(.titleAndIcon)
                }
                .buttonStyle(.plain)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Studio.secondary)
            }
            if model.sessions.isEmpty {
                EmptyState(
                    icon: "waveform.badge.plus",
                    title: "Your first session starts here",
                    detail: "Create a focused practice space, then record as many takes as you need.",
                    actionTitle: "Create a session"
                ) { model.navigate(to: .create) }
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 250), spacing: 14)], spacing: 14) {
                    ForEach(model.sessions.prefix(4)) { session in SessionSummaryCard(session: session) }
                }
            }
        }
    }

    private func summary(for take: PracticeSession) -> String {
        let metrics = take.result.metrics
        if metrics.phraseDecayDB > -3 { return "Stronger phrase endings and a steady pace." }
        if (metrics.pitchRangeSemitones ?? 0) > 8 { return "Expressive pitch range with clear variation." }
        return "Ready to listen back and explore."
    }
}

struct SessionSummaryCard: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.studioSnapshot) private var snapshot
    @AppStorage("voiceCoach.confirmBeforeDelete") private var confirmBeforeDelete = true
    let session: CoachingSession
    @State private var confirmDelete = false
    @State private var showingActions = false

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack {
                Image(systemName: session.mode.icon).foregroundStyle(Studio.accent)
                    .frame(width: 38, height: 38)
                    .background(Studio.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                VStack(alignment: .leading, spacing: 3) {
                    Text(session.name).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                    Text("\(session.updatedAt.formatted(date: .abbreviated, time: .omitted))  ·  \(session.takeCount) takes")
                        .font(.system(size: 9, design: .monospaced)).foregroundStyle(Studio.secondary)
                }
                Spacer()
                if snapshot {
                    Image(systemName: "ellipsis").foregroundStyle(Studio.secondary).frame(width: 24)
                } else {
                    Button { showingActions.toggle() } label: {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Studio.secondary)
                            .frame(width: 28, height: 28)
                            .background(Studio.line.opacity(0.35), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .popover(isPresented: $showingActions, arrowEdge: .top) {
                        actionPopover
                    }
                }
            }
            if let take = session.latestTake {
                MiniSparkline(points: take.result.pitchContour).frame(height: 26)
                Text(cardSummary(take.result.metrics)).font(.system(size: 10)).foregroundStyle(Studio.secondary).lineLimit(1)
            } else {
                Text("Ready for your first take").font(.system(size: 10)).foregroundStyle(Studio.secondary)
                Spacer(minLength: 26)
            }
            HStack {
                Spacer()
                Button { model.resumeSession(session.id) } label: {
                    Image(systemName: "arrow.right").frame(width: 30, height: 30)
                        .background(Studio.line, in: Circle())
                }.buttonStyle(.plain)
            }
        }
        .padding(18)
        .frame(minHeight: 154)
        .studioCard()
        .confirmationDialog("Delete \(session.name)?", isPresented: $confirmDelete) {
            Button("Delete session", role: .destructive) { model.deleteSession(session.id) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The session will be removed from your Voice Coach library.")
        }
    }

    private func cardSummary(_ metrics: VoiceMetrics) -> String {
        if metrics.phraseDecayDB > -3 { return "More confident phrase endings" }
        if metrics.internalPauseCount <= 3 { return "Steady rhythm with fewer pauses" }
        if (metrics.pitchRangeSemitones ?? 0) > 8 { return "Expressive pitch range" }
        return "Ready to compare and improve"
    }

    private var actionPopover: some View {
        VStack(alignment: .leading, spacing: 5) {
            actionButton("View session", icon: "arrow.right") {
                showingActions = false
                model.resumeSession(session.id)
            }
            if session.latestTake != nil {
                actionButton("Review latest", icon: "waveform") {
                    showingActions = false
                    model.review(sessionID: session.id)
                }
            }
            Divider().padding(.vertical, 4)
            actionButton("Delete session", icon: "trash", destructive: true) {
                showingActions = false
                if confirmBeforeDelete { confirmDelete = true }
                else { model.deleteSession(session.id) }
            }
        }
        .padding(8)
        .frame(width: 178)
    }

    private func actionButton(_ title: String, icon: String, destructive: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(destructive ? Color.red.opacity(0.9) : Studio.ink)
                .frame(maxWidth: .infinity, minHeight: 34, alignment: .leading)
                .padding(.horizontal, 8)
                .contentShape(RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 1)
    }
}
