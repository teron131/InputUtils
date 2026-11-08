// Renders the menu bar window: one switch per input behavior named by what it does, the idle fade drawn from the current brightness with its estimated saving and its settings, and menu-style links to the system settings those behaviors depend on.

import AppKit
import Charts
import SwiftUI

struct MenuBarContentView: View {
  @ObservedObject var scrollController: ScrollDirectionController
  @ObservedObject var naturalScrollPreference: NaturalScrollPreference
  @ObservedObject var audioInputController: AudioInputController
  @ObservedObject var idleDimmingController: IdleDimmingController
  @State private var brightness: Float?
  @State private var isOpen = false

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

      if idleDimmingController.isEnabled, idleDimmingController.isAvailable {
        let schedule = idleDimmingController.schedule
        VStack(alignment: .leading, spacing: 8) {
          // Both stay even when nothing would dim, so dragging a slider past the current brightness never moves the sliders under the pointer.
          if let brightness {
            FadeSchedule(start: brightness, schedule: schedule)
            DimmedSaving(start: brightness, schedule: schedule)
          }

          ScheduleSettings(schedule: $idleDimmingController.schedule)
        }
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
    // The window is key exactly while the menu is open, but on the first open it becomes key before this view subscribes, so appearing counts as opening too.
    .onAppear { isOpen = true }
    .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) {
      _ in
      isOpen = true
    }
    .onReceive(NotificationCenter.default.publisher(for: NSWindow.didResignKeyNotification)) {
      _ in
      isOpen = false
    }
    // macOS posts nothing when brightness changes, so it is read repeatedly while the menu is open, letting the chart and saving follow the brightness keys.
    .task(id: isOpen) {
      while isOpen, !Task.isCancelled {
        // Auto-brightness drifts the level in fractions of a point, which would flip the rounded labels back and forth, so only a whole point's move shows.
        switch (idleDimmingController.brightnessLevel(), brightness) {
        case (let level?, let shown?) where abs(level - shown) < 0.01:
          break
        case (let level, _):
          brightness = level
        }
        try? await Task.sleep(for: .milliseconds(250))
      }
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
/// A level already at or below the floor has nothing to fade, so it stays a flat line.
private struct FadeSchedule: View {
  let start: Float
  let schedule: IdleDimming.Schedule

  private struct Point: Identifiable {
    let minutes: Double
    let level: Double
    var id: Double { minutes }
  }

  var body: some View {
    let startMinutes = schedule.delay / 60
    let endMinutes = (schedule.delay + schedule.duration) / 60
    // The tail past the floor shows that brightness stays there, and leaves room for the end label.
    let lastMinutes = endMinutes * 1.25
    // Labels this close would print over each other, so each pair splits to its far sides: the start time left of its point and the end time right of it, the starting level above its line and the floor below its own.
    let timesCrowd = (endMinutes - startMinutes) / lastMinutes < 0.2
    let levelsCrowd = start - schedule.floor < 0.3
    let fades = schedule.fades(from: start)
    let end = fades ? schedule.floor : start
    let points = [
      Point(minutes: 0, level: Double(start)),
      Point(minutes: startMinutes, level: Double(start)),
      Point(minutes: endMinutes, level: Double(end)),
      Point(minutes: lastMinutes, level: Double(end)),
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
      AxisMarks(values: fades ? [startMinutes, endMinutes] : []) { value in
        // Centered under its point, since the default leading placement reads as a later minute.
        AxisValueLabel(
          anchor: timesCrowd ? (value.index == 0 ? .topTrailing : .topLeading) : .top,
          collisionResolution: .disabled
        ) {
          if let minutes = value.as(Double.self) {
            Text("\(Int(minutes.rounded())) min")
          }
        }
      }
    }
    .chartYAxis {
      AxisMarks(
        position: .leading,
        values: fades ? [Double(start), Double(schedule.floor)] : [Double(start)]
      ) {
        value in
        AxisValueLabel(
          anchor: levelsCrowd ? (value.index == 0 ? .bottomTrailing : .topTrailing) : nil,
          collisionResolution: .disabled
        ) {
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
      fades
        ? "Holds at \(Int((start * 100).rounded()))% for \(Int(startMinutes)) minutes, then dims to \(Int((schedule.floor * 100).rounded()))% by \(Int(endMinutes.rounded())) minutes"
        : "Stays at \(Int((start * 100).rounded()))%"
    )
  }
}

private struct DimmedSaving: View {
  let start: Float
  let schedule: IdleDimming.Schedule

  var body: some View {
    let current = "\(Int((start * 100).rounded()))%"
    let target = "\(Int((schedule.floor * 100).rounded()))%"
    let saved = ScreenPower.savedShare(from: start, to: schedule.floor)
    // Every message fits one line, so switching between them never changes the menu's height.
    Group {
      if !schedule.fades(from: start) {
        Text("\(current) is at or below the \(target) target")
      } else if saved < 0.005 {
        // The backlight is already off across the bottom of the slider, so a fade there saves nothing worth a number.
        Text("\(current) → \(target) saves almost no power")
      } else {
        Text(
          "\(current) → \(target) uses about \(saved, format: .percent.precision(.fractionLength(0))) less power"
        )
      }
    }
    .font(.system(size: 11))
    .foregroundStyle(.secondary)
    // The menu window sizes to one line of text unless told otherwise, which would cut off a line that runs long.
    .fixedSize(horizontal: false, vertical: true)
  }
}

private struct ScheduleSettings: View {
  @Binding var schedule: IdleDimming.Schedule

  var body: some View {
    VStack(spacing: 4) {
      SettingSlider(
        title: "Start after",
        value: Binding(get: { schedule.delay / 60 }, set: { schedule.delay = $0 * 60 }),
        range: 1...15,
        unit: " min"
      )
      SettingSlider(
        title: "Dim over",
        value: Binding(get: { schedule.duration / 60 }, set: { schedule.duration = $0 * 60 }),
        range: 1...20,
        unit: " min"
      )
      SettingSlider(
        title: "Dim to",
        value: Binding(
          get: { Double(schedule.floor) * 100 }, set: { schedule.floor = Float($0 / 100) }),
        range: 10...50,
        unit: "%"
      )
    }
  }
}

/// Moves in whole units, so the readout beside it is always exact.
private struct SettingSlider: View {
  let title: String
  @Binding var value: Double
  let range: ClosedRange<Double>
  let unit: String

  var body: some View {
    let readout = "\(Int(value.rounded()))\(unit)"
    HStack(spacing: 8) {
      Text(title)
        .font(.system(size: 12))
        .foregroundStyle(.secondary)
        .frame(width: 64, alignment: .leading)

      Slider(value: $value, in: range, step: 1) {
        Text(title)
      }
      .labelsHidden()
      .controlSize(.mini)
      .accessibilityValue(readout)

      Text(readout)
        .font(.system(size: 12).monospacedDigit())
        .frame(width: 42, alignment: .trailing)
    }
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
