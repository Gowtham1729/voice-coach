import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        ZStack {
            Studio.background.ignoresSafeArea()
            RadialGradient(
                colors: [Studio.accent.opacity(0.055), .clear],
                center: .topTrailing,
                startRadius: 0,
                endRadius: 760
            )
            .ignoresSafeArea()
            .allowsHitTesting(false)

            VStack(spacing: 0) {
                AppHeader()
                Rectangle().fill(Studio.line).frame(height: 1)
                destination
            }
        }
        .foregroundStyle(Studio.ink)
        .preferredColorScheme(.dark)
        .tint(Studio.accent)
        .alert("Voice Coach", isPresented: errorBinding) {
            Button("OK", role: .cancel) { model.errorMessage = nil }
        } message: {
            Text(model.errorMessage ?? "")
        }
        .overlay(alignment: .bottom) { toast }
    }

    @ViewBuilder
    private var destination: some View {
        switch model.destination {
        case .studio:
            StudioDashboard()
        case .create:
            CreateSessionView()
        case .practice:
            PracticeView()
        case .review:
            ReviewView()
        case .sessions:
            SessionsView()
        case .insights:
            InsightsView()
        case .settings:
            SettingsView()
        }
    }

    private var toast: some View {
        Group {
            if let message = model.toastMessage {
                Label(message, systemImage: "checkmark.circle.fill")
                    .font(.callout.weight(.medium))
                    .padding(.horizontal, 20)
                    .frame(height: 44)
                    .background(Studio.surface, in: Capsule())
                    .overlay(Capsule().stroke(Studio.line))
                    .shadow(color: .black.opacity(0.35), radius: 20, y: 8)
                    .padding(.bottom, 22)
                    .task(id: message) {
                        try? await Task.sleep(for: .seconds(2.7))
                        if !Task.isCancelled, model.toastMessage == message { model.toastMessage = nil }
                    }
            }
        }
    }

    private var errorBinding: Binding<Bool> {
        Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })
    }
}

private struct AppHeader: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        HStack(spacing: 34) {
            Button { model.navigate(to: AppDestination.studio) } label: {
                HStack(spacing: 11) {
                    Image(systemName: "waveform")
                        .font(.system(size: 23, weight: .medium))
                        .foregroundStyle(Studio.accent)
                    Text("VoiceCoach")
                        .font(.system(size: 18, weight: .semibold))
                        .tracking(-0.5)
                }
            }
            .buttonStyle(.plain)

            HStack(spacing: 30) {
                ForEach(NavigationSection.allCases) { section in
                    Button { model.navigate(to: section) } label: {
                        Text(section.rawValue)
                            .font(.system(size: 13, weight: model.destination.navigationSection == section ? .semibold : .regular))
                            .foregroundStyle(model.destination.navigationSection == section ? Studio.ink : Studio.secondary)
                            .padding(.vertical, 23)
                            .overlay(alignment: .bottom) {
                                if model.destination.navigationSection == section {
                                    Capsule().fill(Studio.accent).frame(height: 2)
                                }
                            }
                    }
                    .buttonStyle(.plain)
                    .disabled(model.isRecording)
                }
            }

            Spacer()
            Label("On-device · Private", systemImage: "lock")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Studio.secondary)
                .help("Recordings, transcripts and analysis stay on this Mac.")
        }
        .padding(.horizontal, 42)
        .frame(height: 70)
    }
}
