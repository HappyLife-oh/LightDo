import Cocoa
import FlutterMacOS
import bitsdojo_window_macos
import desktop_multi_window

class MainFlutterWindow: BitsdojoWindow {
  override func bitsdojo_window_configure() -> UInt {
    BDW_CUSTOM_FRAME | BDW_HIDE_ON_STARTUP
  }

  override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
    return frameRect
  }

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)
    FlutterMultiWindowPlugin.setOnWindowCreatedCallback { controller in
      RegisterGeneratedPlugins(registry: controller)
    }

    super.awakeFromNib()

    self.styleMask.insert(.fullSizeContentView)
    self.titlebarAppearsTransparent = true
    self.titleVisibility = .hidden
    self.isOpaque = false
    self.hasShadow = false
    self.backgroundColor = NSColor.clear

    if let contentView = self.contentView {
      contentView.wantsLayer = true
      contentView.layer?.cornerRadius = 38
      contentView.layer?.masksToBounds = true
    }
  }
}
