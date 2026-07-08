// Renders the concise menu bar controls for scroll switching, permissions, and settings.

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
        TrackpadToggleRow(
          isOn: Binding(
            get: { controller.isTrackpadNaturalScrollingEnabled },
            set: { controller.setTrackpadNaturalScrollingEnabled($0) }
          ),
          isActive: controller.activeDevice == .trackpad
        )

        DeviceStatusRow(
          title: "Mouse",
          status: "Reversed",
          detail: "Wheel scrolling",
          systemImage: "computermouse",
          isActive: controller.activeDevice == .mouse
        )

        MicToggleRow(
          isOn: Binding(
            get: { audioInputController.isEnabled },
            set: { audioInputController.setEnabled($0) }
          ),
          status: audioInputController.status
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
    case .permissionNeeded, .preferenceUnavailable, .tapUnavailable:
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

private struct TrackpadToggleRow: View {
  @Binding var isOn: Bool
  let isActive: Bool
  private let accent = Color.accentColor

  var body: some View {
    HStack(spacing: 8) {
      Image(systemName: "rectangle.and.hand.point.up.left")
        .font(.system(size: 14, weight: .semibold))
        .foregroundStyle(isActive ? accent : .secondary)
        .frame(width: 20, height: 20)

      VStack(alignment: .leading, spacing: 2) {
        Text("Trackpad")
          .font(.system(size: 12, weight: .semibold))
          .foregroundStyle(.primary)

        Text("Natural scrolling")
          .font(.system(size: 10, weight: .medium))
          .foregroundStyle(.secondary)
      }

      Spacer(minLength: 8)

      Toggle("", isOn: $isOn)
        .labelsHidden()
        .toggleStyle(.switch)
        .controlSize(.small)
    }
    .deviceRowStyle(isActive: isActive, accent: accent)
  }
}

private struct DeviceStatusRow: View {
  let title: String
  let status: String
  let detail: String
  let systemImage: String
  let isActive: Bool
  private let accent = Color.accentColor

  var body: some View {
    HStack(spacing: 8) {
      Image(systemName: systemImage)
        .font(.system(size: 14, weight: .semibold))
        .foregroundStyle(isActive ? accent : .secondary)
        .frame(width: 20, height: 20)

      VStack(alignment: .leading, spacing: 2) {
        Text(title)
          .font(.system(size: 12, weight: .semibold))
          .foregroundStyle(.primary)

        Text(detail)
          .font(.system(size: 10, weight: .medium))
          .foregroundStyle(.secondary)
      }

      Spacer(minLength: 8)

      Text(status)
        .font(.system(size: 11, weight: .semibold, design: .rounded))
        .foregroundStyle(isActive ? accent : .secondary)
        .lineLimit(1)
    }
    .deviceRowStyle(isActive: isActive, accent: accent)
  }
}

private struct MicToggleRow: View {
  @Binding var isOn: Bool
  let status: String

  var body: some View {
    HStack(spacing: 8) {
      Image(systemName: "mic")
        .font(.system(size: 14, weight: .semibold))
        .foregroundStyle(.secondary)
        .frame(width: 20, height: 20)

      VStack(alignment: .leading, spacing: 2) {
        Text("Audio Input")
          .font(.system(size: 12, weight: .semibold))
          .foregroundStyle(.primary)

        Text("Built-in mic")
          .font(.system(size: 10, weight: .medium))
          .foregroundStyle(.secondary)
          .lineLimit(1)
      }

      Spacer(minLength: 8)

      Text(status)
        .font(.system(size: 11, weight: .semibold, design: .rounded))
        .foregroundStyle(.secondary)
        .lineLimit(1)

      Toggle("", isOn: $isOn)
        .labelsHidden()
        .toggleStyle(.switch)
        .controlSize(.small)
    }
    .plainRowStyle()
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

private extension View {
  func deviceRowStyle(
    isActive: Bool,
    accent: Color
  ) -> some View {
    padding(.horizontal, 9)
      .padding(.vertical, 7)
      .background(
        isActive ? accent.opacity(0.16) : Color.secondary.opacity(0.08),
        in: RoundedRectangle(cornerRadius: 8)
      )
      .overlay {
        RoundedRectangle(cornerRadius: 8)
          .stroke(isActive ? accent.opacity(0.55) : Color.clear, lineWidth: 1)
      }
      .animation(.easeOut(duration: 0.18), value: isActive)
  }

  func plainRowStyle() -> some View {
    padding(.horizontal, 9)
      .padding(.vertical, 7)
      .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
  }
}
