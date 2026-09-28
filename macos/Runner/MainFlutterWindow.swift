import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    self.contentViewController = flutterViewController

    // The design is phone-first, and the shell only switches to the sidebar
    // layout at 768 logical px. Opening at a phone-shaped size therefore shows
    // the intended layout instead of a stretched desktop window; widening the
    // window past the breakpoint brings in the sidebar.
    let defaultSize = NSSize(width: 430, height: 932)
    let screen = self.screen ?? NSScreen.main
    let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)

    // Centre it, but never taller than the screen allows.
    let height = min(defaultSize.height, visible.height - 40)
    let origin = NSPoint(
      x: visible.midX - defaultSize.width / 2,
      y: visible.midY - height / 2
    )
    self.setFrame(
      NSRect(x: origin.x, y: origin.y, width: defaultSize.width, height: height),
      display: true
    )
    // Below this the tab bar and the width-constrained cards start to clip.
    self.minSize = NSSize(width: 360, height: 480)

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()
  }
}
