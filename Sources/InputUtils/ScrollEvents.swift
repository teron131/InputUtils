// Owns the scroll-event rules shared by the event tap and the verification probe: which events count as wheel-mouse input and how their deltas are inverted.

import CoreGraphics

enum ScrollEventClassifier {
  /// Treats only scroll events without continuous or gesture phase markers as physical wheel mouse input.
  static func isWheelMouse(_ event: CGEvent) -> Bool {
    let isContinuous = event.getIntegerValueField(.scrollWheelEventIsContinuous) != 0
    let hasGesturePhase = event.getIntegerValueField(.scrollWheelEventScrollPhase) != 0
    let hasMomentumPhase = event.getIntegerValueField(.scrollWheelEventMomentumPhase) != 0

    return !isContinuous && !hasGesturePhase && !hasMomentumPhase
  }
}

enum ScrollEventInverter {
  private static let axisDeltaFields: [CGEventField] = [
    .scrollWheelEventDeltaAxis1,
    .scrollWheelEventDeltaAxis2,
    .scrollWheelEventDeltaAxis3,
  ]

  /// Flips primary wheel-axis deltas and lets CoreGraphics keep derived point and fixed-point fields consistent.
  static func invert(_ event: CGEvent) {
    for field in axisDeltaFields {
      let value = event.getIntegerValueField(field)
      if value != 0 {
        event.setIntegerValueField(field, value: -value)
      }
    }
  }
}
