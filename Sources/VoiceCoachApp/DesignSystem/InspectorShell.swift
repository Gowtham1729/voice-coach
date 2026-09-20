import SwiftUI
import VoiceCoachSession

/// Shared Take / Practice / Compare inspector chrome: fixed header, scrolling body, optional pinned footer.
struct InspectorShell<Header: View, Content: View, Footer: View>: View {
  @Environment(\.studioSnapshot) private var snapshot

  private let header: Header
  private let content: Content
  private let footer: Footer
  private let showsFooter: Bool

  init(
    @ViewBuilder header: () -> Header,
    @ViewBuilder content: () -> Content,
    @ViewBuilder footer: () -> Footer
  ) {
    self.header = header()
    self.content = content()
    self.footer = footer()
    self.showsFooter = Footer.self != EmptyView.self
  }

  var body: some View {
    VStack(spacing: 0) {
      header
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity, alignment: .leading)

      Divider()

      Group {
        if snapshot {
          content
            .padding(16)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        } else {
          ScrollView {
            content
              .padding(16)
              .frame(maxWidth: .infinity, alignment: .topLeading)
          }
          .scrollContentBackground(.hidden)
        }
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

      if showsFooter {
        Divider()
        footer
          .padding(16)
          .frame(maxWidth: .infinity)
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
  }
}

extension InspectorShell where Footer == EmptyView {
  init(
    @ViewBuilder header: () -> Header,
    @ViewBuilder content: () -> Content
  ) {
    self.init(header: header, content: content, footer: { EmptyView() })
  }
}

struct InspectorHeader<Accessory: View>: View {
  let eyebrow: String
  let title: String
  var meta: [String] = []
  var accessory: Accessory

  init(
    eyebrow: String,
    title: String,
    meta: [String] = [],
    @ViewBuilder accessory: () -> Accessory
  ) {
    self.eyebrow = eyebrow
    self.title = title
    self.meta = meta
    self.accessory = accessory()
  }

  var body: some View {
    HStack(alignment: .top, spacing: 8) {
      VStack(alignment: .leading, spacing: 3) {
        SectionEyebrow(text: eyebrow)
        Text(title)
          .font(.headline)
          .lineLimit(2)
        ForEach(Array(meta.enumerated()), id: \.offset) { _, line in
          Text(line)
            .font(.caption)
            .foregroundStyle(Studio.secondary)
            .lineLimit(2)
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)

      accessory
    }
  }
}

extension InspectorHeader where Accessory == EmptyView {
  init(eyebrow: String, title: String, meta: [String] = []) {
    self.init(eyebrow: eyebrow, title: title, meta: meta, accessory: { EmptyView() })
  }
}

struct InspectorTakePager: View {
  @EnvironmentObject private var model: AppModel
  let session: CoachingSession

  var body: some View {
    if session.takeCount > 1 {
      HStack(spacing: 2) {
        Button {
          model.stepTake(by: -1)
        } label: {
          Image(systemName: "chevron.left")
        }
        .disabled(!model.canStepTake(by: -1))
        .help("Previous take")
        .accessibilityLabel("Previous take")

        Button {
          model.stepTake(by: 1)
        } label: {
          Image(systemName: "chevron.right")
        }
        .disabled(!model.canStepTake(by: 1))
        .help("Next take")
        .accessibilityLabel("Next take")
      }
      .buttonStyle(.borderless)
      .controlSize(.small)
      .disabled(model.isRecording || model.isAnalyzing)
    }
  }
}

struct InspectorFooterStack<Content: View>: View {
  @ViewBuilder var content: Content

  var body: some View {
    VStack(spacing: 8) {
      content
    }
  }
}

extension View {
  func inspectorActionLabel() -> some View {
    frame(maxWidth: .infinity)
  }
}
