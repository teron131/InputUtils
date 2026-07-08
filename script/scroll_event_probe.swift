// Exercises scroll event helpers without requiring physical input devices.

import ApplicationServices
import Foundation

enum ProbeFailure: Error {
  case eventCreationFailed
  case assertionFailed(String)
}

let deltaFields: [CGEventField] = [
  .scrollWheelEventDeltaAxis1,
  .scrollWheelEventDeltaAxis2,
  .scrollWheelEventDeltaAxis3,
  .scrollWheelEventFixedPtDeltaAxis1,
  .scrollWheelEventFixedPtDeltaAxis2,
  .scrollWheelEventFixedPtDeltaAxis3,
  .scrollWheelEventPointDeltaAxis1,
  .scrollWheelEventPointDeltaAxis2,
  .scrollWheelEventPointDeltaAxis3,
]

func makeScrollEvent(
  isContinuous: Bool,
  verticalDelta: Int32 = 1,
  horizontalDelta: Int32 = 0
) throws -> CGEvent {
  guard
    let event = CGEvent(
      scrollWheelEvent2Source: nil,
      units: .line,
      wheelCount: 2,
      wheel1: verticalDelta,
      wheel2: horizontalDelta,
      wheel3: 0
    )
  else {
    throw ProbeFailure.eventCreationFailed
  }

  event.setIntegerValueField(
    .scrollWheelEventIsContinuous,
    value: isContinuous ? 1 : 0
  )
  event.setIntegerValueField(
    .scrollWheelEventPointDeltaAxis1,
    value: Int64(verticalDelta)
  )
  event.setIntegerValueField(
    .scrollWheelEventPointDeltaAxis2,
    value: Int64(horizontalDelta)
  )

  return event
}

func expect(
  _ condition: @autoclosure () -> Bool,
  _ message: String
) throws {
  if !condition() {
    throw ProbeFailure.assertionFailed(message)
  }
}

func sign(of value: Int64) -> Int64 {
  if value < 0 {
    return -1
  }

  if value > 0 {
    return 1
  }

  return 0
}

@main
enum ScrollEventProbe {
  static func main() throws {
    let wheelEvent = try makeScrollEvent(isContinuous: false)
    try expect(
      ScrollEventClassifier.isWheelMouse(wheelEvent),
      "non-continuous scroll events should be classified as mouse wheel input"
    )

    let trackpadEvent = try makeScrollEvent(isContinuous: true)
    try expect(
      !ScrollEventClassifier.isWheelMouse(trackpadEvent),
      "continuous scroll events should pass through as trackpad-like input"
    )

    let phasedTrackpadEvent = try makeScrollEvent(isContinuous: false)
    phasedTrackpadEvent.setIntegerValueField(
      .scrollWheelEventScrollPhase,
      value: 1
    )
    try expect(
      !ScrollEventClassifier.isWheelMouse(phasedTrackpadEvent),
      "phased scroll events should pass through as trackpad-like input"
    )

    let invertEvent = try makeScrollEvent(
      isContinuous: false,
      verticalDelta: 7,
      horizontalDelta: -3
    )
    let valuesBeforeInvert = deltaFields.reduce(into: [CGEventField: Int64]()) {
      values,
      field in
      values[field] = invertEvent.getIntegerValueField(field)
    }

    ScrollEventInverter.invert(invertEvent)

    for field in deltaFields {
      let originalValue = valuesBeforeInvert[field] ?? 0
      let invertedValue = invertEvent.getIntegerValueField(field)

      if [
        .scrollWheelEventDeltaAxis1,
        .scrollWheelEventDeltaAxis2,
        .scrollWheelEventDeltaAxis3,
      ].contains(field) {
        try expect(
          invertedValue == -originalValue,
          "\(field) should invert exactly from \(originalValue) to \(-originalValue)"
        )
      } else {
        try expect(
          sign(of: invertedValue) == -sign(of: originalValue),
          "\(field) should flip sign from \(originalValue), got \(invertedValue)"
        )
      }
    }

    print("scroll event probe passed")
  }
}
