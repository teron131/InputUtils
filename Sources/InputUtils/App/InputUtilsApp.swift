// Owns the menu-bar-only SwiftUI app entry point and app-wide scroll controller lifetime.

import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
  /// Keeps the utility out of the Dock because its only surface is the menu bar extra.
  func applicationDidFinishLaunching(_ notification: Notification) {
    NSApp.setActivationPolicy(.accessory)
  }
}

@main
struct InputUtilsApp: App {
  @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
  @StateObject private var scrollController = ScrollDirectionController()
  @StateObject private var audioInputController = AudioInputController()

  var body: some Scene {
    MenuBarExtra {
      MenuBarContentView(
        controller: scrollController,
        audioInputController: audioInputController
      )
    } label: {
      Image(nsImage: InputUtilsIcon.menuBarImage)
        .accessibilityLabel("Input Utils")
    }
    .menuBarExtraStyle(.window)
  }
}
