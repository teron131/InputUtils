// Owns the menu-bar-only SwiftUI app entry point, the app-wide scroll and audio controller lifetimes, and login-item registration.

import AppKit
import OSLog
import ServiceManagement
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
  private let logger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "com.codex.InputUtils",
    category: "LoginItem"
  )

  /// Keeps the utility out of the Dock because its only surface is the menu bar extra.
  func applicationDidFinishLaunching(_ notification: Notification) {
    NSApp.setActivationPolicy(.accessory)
    registerLoginItem()
  }

  /// Registers the app itself as a login item unless macOS has already enabled it or is awaiting approval.
  private func registerLoginItem() {
    let status = SMAppService.mainApp.status
    guard status != .enabled && status != .requiresApproval else {
      return
    }

    do {
      try SMAppService.mainApp.register()
      logger.info("Registered InputUtils to start at login")
    } catch {
      logger.error(
        "Could not register InputUtils to start at login: \(error.localizedDescription, privacy: .public)"
      )
    }
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
