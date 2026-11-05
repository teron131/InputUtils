// Renders the menu bar window: one switch per input behavior named by what it does, the idle fade's schedule drawn from the current brightness, and menu-style links to the settings those behaviors depend on.

import AppKit
import Charts
import SwiftUI

struct MenuBarContentView: View {
  @ObservedObject var scrollController: ScrollDirectionController
  @ObservedObject var naturalScrollPreference: NaturalScrollPreference
  @ObservedObject var audioInputController: AudioInputController
  @ObservedObject var idleDimmingController: IdleDimmingController
  @State private var brightness: Float?

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      HStack(spacing: Layout.glyphSpacing) {
        Image(nsImage: InputUtilsIcon.menuBarImage)
          .resizable()
          .scaledToFit()
          .frame(width: Layout.glyphSize, height: Layout.glyphSize)
          .frame(width: Layout.glyphWidth)

        Text("InputUtils")
          .font(.system(size: 13, weight: .semibold))
      }
      .padding(.vertical, 4)

      Divider()
        .padding(.vertical, 6)

      BehaviorRow(
        title: "Natural trackpad scrolling",
        systemImage: "rectangle.and.hand.point.up.left",
        problem: naturalScrollPreference.writeFailed ? "Set failed" : nil,
        isActive: scrollController.activeDevice == .trackpad,
        isOn: Binding(
          get: { naturalScrollPreference.isEnabled },
          set: { naturalScrollPreference.setEnabled($0) }
        )
      )

      RowDivider()

      // Flipping the wheel gives the mouse whichever direction the trackpad is not using.
      BehaviorRow(
        title: naturalScrollPreference.isEnabled
          ? "Traditional mouse scrolling" : "Natural mouse scrolling",
        systemImage: "computermouse",
        problem: scrollController.needsPermission ? "Needs Accessibility access" : nil,
        isActive: scrollController.activeDevice == .mouse,
        isOn: Binding(
          get: { scrollController.isEnabled },
          set: { scrollController.setEnabled($0) }
        )
      )

      RowDivider()

      BehaviorRow(
        title: "Keep built-in mic as input",
        systemImage: "mic",
        problem: audioInputController.problem,
        isOn: Binding(
          get: { audioInputController.isEnabled },
          set: { audioInputController.setEnabled($0) }
        )
      )

      RowDivider()

      BehaviorRow(
        title: "Dim screen gradually",
        systemImage: "sun.max",
        problem: idleDimmingController.isAvailable ? nil : "Unavailable",
        isOn: Binding(
          get: { idleDimmingController.isEnabled },
          set: { idleDimmingController.setEnabled($0) }
        )
      )
      .disabled(!idleDimmingController.isAvailable)

      // A brightness already at the floor has nothing to fade, so the schedule stays hidden.
      if idleDimmingController.isEnabled, let brightness,
        IdleDimming.fadeEnd(from: brightness) > IdleDimming.delay
      {
        FadeSchedule(start: brightness)
          .padding(.leading, Layout.textInset)
          .padding(.bottom, 6)
      }

      Divider()
        .padding(.vertical, 6)

      if scrollController.needsPermission {
        MenuItem(title: "Retry Accessibility access") {
          scrollController.requestPermissionAndRetry()
        }
      }

      MenuItem(title: "Accessibility settings…") {
        SystemSettingsLinks.openAccessibilityPrivacy()
      }

      MenuItem(title: "Trackpad settings…") {
        SystemSettingsLinks.openTrackpad()
      }

      Divider()
        .padding(.vertical, 6)

      MenuItem(title: "Quit") {
        NSApplication.shared.terminate(nil)
      }
    }
    .padding(10)
    .frame(width: 280)
    .animation(.easeOut(duration: 0.18), value: idleDimmingController.isEnabled)
    // The window becomes key each time the menu opens, which is when the fade would start from the brightness just set.
    // On the first open it becomes key before this view subscribes, so appearing reads the level too.
    .onAppear { brightness = idleDimmingController.brightnessLevel() }
    .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) {
      _ in
      brightness = idleDimmingController.brightnessLevel()
    }
  }
}

private enum Layout {
  static let glyphSize: CGFloat = 16
  static let glyphWidth: CGFloat = 20
  static let glyphSpacing: CGFloat = 10
  static let textInset = glyphWidth + glyphSpacing
}

/// One input behavior: its device glyph, what it does, any problem stopping it, and its switch.
/// The glyph takes the accent color while its device is the one scrolling.
private struct BehaviorRow: View {
  let title: String
  let systemImage: String
  let problem: String?
  var isActive = false
  @Binding var isOn: Bool

  var body: some View {
    HStack(spacing: Layout.glyphSpacing) {
      // A shared box keeps wide symbols such as the trackpad from outweighing the narrow ones.
      Image(systemName: systemImage)
        .resizable()
        .scaledToFit()
        .frame(width: Layout.glyphSize, height: Layout.glyphSize)
        .foregroundStyle(isActive ? Color.accentColor : Color.secondary)
        .frame(width: Layout.glyphWidth)

      VStack(alignment: .leading, spacing: 1) {
        Text(title)
          .font(.system(size: 13))

        if let problem {
          Text(problem)
            .font(.system(size: 11))
            .foregroundStyle(.red)
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)

      Toggle(title, isOn: $isOn)
        .labelsHidden()
        .toggleStyle(.switch)
        .controlSize(.small)
    }
    .padding(.vertical, 6)
    .animation(.easeOut(duration: 0.18), value: isActive)
  }
}

private struct RowDivider: View {
  var body: some View {
    Divider()
      .padding(.leading, Layout.textInset)
  }
}

/// Plots brightness against idle minutes: flat until the fade starts, then a straight fall to the floor, which reads as an even fade because the slider scale is perceptual.
private struct FadeSchedule: View {
  let start: Float

  private struct Point: Identifiable {
    let minutes: Double
    let level: Double
    var id: Double { minutes }
  }

  var body: some View {
    let startMinutes = IdleDimming.delay / 60
    let endMinutes = IdleDimming.fadeEnd(from: start) / 60
    // The tail past the floor shows that brightness stays there, and leaves room for the end label.
    let lastMinutes = endMinutes * 1.25
    let points = [
      Point(minutes: 0, level: Double(start)),
      Point(minutes: startMinutes, level: Double(start)),
      Point(minutes: endMinutes, level: Double(IdleDimming.floor)),
      Point(minutes: lastMinutes, level: Double(IdleDimming.floor)),
    ]

    Chart(points) { point in
      AreaMark(x: .value("Idle", point.minutes), y: .value("Brightness", point.level))
        .foregroundStyle(
          LinearGradient(
            colors: [Color.accentColor.opacity(0.3), Color.accentColor.opacity(0.02)],
            startPoint: .top,
            endPoint: .bottom
          )
        )

      LineMark(x: .value("Idle", point.minutes), y: .value("Brightness", point.level))
        .foregroundStyle(Color.accentColor)
        .lineStyle(StrokeStyle(lineWidth: 1.5, lineJoin: .round))
    }
    .chartXScale(domain: 0...lastMinutes)
    .chartYScale(domain: 0...1)
    .chartXAxis {
      AxisMarks(values: [startMinutes, endMinutes]) { value in
        // Centered under its point, since the default leading placement reads as a later minute.
        AxisValueLabel(anchor: .top, collisionResolution: .disabled) {
          if let minutes = value.as(Double.self) {
            Text("\(Int(minutes.rounded())) min")
          }
        }
      }
    }
    .chartYAxis {
      AxisMarks(position: .leading, values: [Double(start), Double(IdleDimming.floor)]) {
        value in
        AxisValueLabel {
          if let level = value.as(Double.self) {
            Text("\(Int((level * 100).rounded()))%")
          }
        }
      }
    }
    .font(.system(size: 10).monospacedDigit())
    .frame(height: 56)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(
      "Holds at \(Int((start * 100).rounded()))% for \(Int(startMinutes)) minutes, then dims to \(Int((IdleDimming.floor * 100).rounded()))% by \(Int(endMinutes.rounded())) minutes"
    )
  }
}

/// A menu-style action that highlights under the pointer like a native menu item.
private struct MenuItem: View {
  let title: String
  let action: () -> Void
  @State private var isHovered = false

  var body: some View {
    Button(action: action) {
      Text(title)
        .font(.system(size: 13))
        .foregroundStyle(isHovered ? Color.white : Color.primary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.leading, Layout.textInset)
        .padding(.vertical, 5)
        .background(
          isHovered ? Color.accentColor : Color.clear,
          in: RoundedRectangle(cornerRadius: 8)
        )
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .onHover { isHovered = $0 }
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
