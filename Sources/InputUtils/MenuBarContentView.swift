// Renders the concise menu bar controls for scroll switching, audio input pinning, permissions, and settings.

import AppKit
import SwiftUI

struct MenuBarContentView: View {
  @ObservedObject var controller: ScrollDirectionController
  @ObservedObject var audioInputController: AudioInputController

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      StatusHeader(
        title: controller.status.title,
        detail: controller.status.detail,
        color: statusColor
      )

      VStack(spacing: 6) {
        InputRow(
          title: "Trackpad",
          detail: "Natural scrolling",
          systemImage: "rectangle.and.hand.point.up.left",
          isOn: Binding(
            get: { controller.isTrackpadNaturalScrollingEnabled },
            set: { controller.setTrackpadNaturalScrollingEnabled($0) }
          ),
          isActive: controller.activeDevice == .trackpad
        )

        InputRow(
          title: "Mouse",
          detail: "Wheel scrolling",
          systemImage: "computermouse",
          status: "Reversed",
          isActive: controller.activeDevice == .mouse
        )

        InputRow(
          title: "Audio Input",
          detail: "Built-in mic",
          systemImage: "mic",
          status: audioInputController.status,
          isOn: Binding(
            get: { audioInputController.isEnabled },
            set: { audioInputController.setEnabled($0) }
          )
        )
      }

      VStack(spacing: 6) {
        Button {
          controller.setEnabled(!controller.isEnabled)
        } label: {
          ActionLabel(
            title: controller.isEnabled ? "Pause switching" : "Resume switching",
            systemImage: controller.isEnabled ? "pause.fill" : "play.fill"
          )
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.regular)

        if controller.status == .permissionNeeded {
          Button {
            controller.requestPermissionAndRetry()
          } label: {
            ActionLabel(
              title: "Retry permission",
              systemImage: "arrow.clockwise"
            )
          }
          .buttonStyle(.bordered)
        }

        Button {
          SystemSettingsLinks.openAccessibilityPrivacy()
        } label: {
          ActionLabel(
            title: "Privacy settings",
            systemImage: "lock.shield"
          )
        }
        .buttonStyle(.bordered)

        Button {
          SystemSettingsLinks.openTrackpad()
        } label: {
          ActionLabel(
            title: "Trackpad settings",
            systemImage: "rectangle.connected.to.line.below"
          )
        }
        .buttonStyle(.bordered)
      }

      Button {
        NSApplication.shared.terminate(nil)
      } label: {
        Label("Quit", systemImage: "power")
          .frame(maxWidth: .infinity, alignment: .center)
      }
      .buttonStyle(.plain)
      .foregroundStyle(.secondary)
    }
    .padding(12)
    .frame(width: 280)
    .background(.regularMaterial)
  }

  private var statusColor: Color {
    switch controller.status {
    case .running:
      return .primary
    case .paused:
      return .secondary
    case .permissionNeeded, .preferenceUnavailable:
      return .red
    }
  }
}

private struct StatusHeader: View {
  let title: String
  let detail: String
  let color: Color

  var body: some View {
    HStack(alignment: .top, spacing: 9) {
      Image(nsImage: InputUtilsIcon.menuBarImage)
        .resizable()
        .scaledToFit()
        .foregroundStyle(color)
        .frame(width: 18, height: 18)
        .padding(.top, 3)
        .frame(width: 30, alignment: .center)

      VStack(alignment: .leading, spacing: 1) {
        Text(title)
          .font(.system(size: 15, weight: .semibold))
          .foregroundStyle(.primary)
          .lineLimit(2)

        Text(detail)
          .font(.system(size: 11, weight: .medium))
          .foregroundStyle(.secondary)
      }
    }
  }
}

/// One input row: icon, title and detail, then an optional status label and switch.
/// `isActive` tints the row while its device is the one currently scrolling.
private struct InputRow: View {
  let title: String
  let detail: String
  let systemImage: String
  var status: String?
  var isOn: Binding<Bool>?
  var isActive = false

  var body: some View {
    HStack(spacing: 8) {
      Image(systemName: systemImage)
        .font(.system(size: 14, weight: .semibold))
        .foregroundStyle(tint)
        .frame(width: 20, height: 20)

      VStack(alignment: .leading, spacing: 2) {
        Text(title)
          .font(.system(size: 12, weight: .semibold))
          .foregroundStyle(.primary)

        Text(detail)
          .font(.system(size: 10, weight: .medium))
          .foregroundStyle(.secondary)
          .lineLimit(1)
      }

      Spacer(minLength: 8)

      if let status {
        Text(status)
          .font(.system(size: 11, weight: .semibold, design: .rounded))
          .foregroundStyle(tint)
          .lineLimit(1)
      }

      if let isOn {
        Toggle("", isOn: isOn)
          .labelsHidden()
          .toggleStyle(.switch)
          .controlSize(.small)
      }
    }
    .padding(.horizontal, 9)
    .padding(.vertical, 7)
    .background(
      isActive ? Color.accentColor.opacity(0.16) : Color.secondary.opacity(0.08),
      in: RoundedRectangle(cornerRadius: 8)
    )
    .overlay {
      RoundedRectangle(cornerRadius: 8)
        .stroke(isActive ? Color.accentColor.opacity(0.55) : Color.clear, lineWidth: 1)
    }
    .animation(.easeOut(duration: 0.18), value: isActive)
  }

  private var tint: Color {
    isActive ? .accentColor : .secondary
  }
}

private struct ActionLabel: View {
  let title: String
  let systemImage: String

  var body: some View {
    Label(title, systemImage: systemImage)
      .frame(maxWidth: .infinity, alignment: .leading)
  }
}

private enum SystemSettingsLinks {
  /// Opens the Privacy & Security pane where Accessibility permission is granted.
  static func openAccessibilityPrivacy() {
    open(
      "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
    )
  }

  /// Opens the Trackpad pane where macOS exposes the Natural Scrolling switch.
  static func openTrackpad() {
    open("x-apple.systempreferences:com.apple.Trackpad-Settings.extension")
  }

  private static func open(_ rawURL: String) {
    guard let url = URL(string: rawURL) else {
      return
    }

    NSWorkspace.shared.open(url)
  }
}
