import Cocoa
import FlutterMacOS
import IOKit.pwr_mgt

@main
class AppDelegate: FlutterAppDelegate {
  private var powerAssertion: IOPMAssertionID = 0

  override func applicationDidFinishLaunching(_ notification: Notification) {
    super.applicationDidFinishLaunching(notification)
    // Prevent idle display sleep while the app runs.
    IOPMAssertionCreateWithName(
      kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString,
      IOPMAssertionLevel(kIOPMAssertionLevelOn),
      "Awesome Time keep screen on" as CFString,
      &powerAssertion
    )
  }

  override func applicationWillTerminate(_ notification: Notification) {
    if powerAssertion != 0 {
      IOPMAssertionRelease(powerAssertion)
      powerAssertion = 0
    }
    super.applicationWillTerminate(notification)
  }

  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }
}
