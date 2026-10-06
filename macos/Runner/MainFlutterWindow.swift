import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  /// The Flutter header (`CinemaMarqueeBar`, 52 logical px) the traffic lights
  /// live in. They are placed against it explicitly: AppKit centres them in
  /// its own title bar, which is a different height, so left alone they sit
  /// off the header's centre line.
  private static let barHeight: CGFloat = 52
  /// Matches `CinemaMarqueeBar.macOsTrafficLightInset` on the Dart side, which
  /// reserves the room these occupy.
  private static let lightsLeading: CGFloat = 20

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    self.contentViewController = flutterViewController

    self.minSize = NSSize(width: 900, height: 600)

    self.titleVisibility = .hidden
    self.titlebarAppearsTransparent = true
    self.styleMask.insert(.fullSizeContentView)
    self.backgroundColor = NSColor(red: 0x12 / 255.0, green: 0x10 / 255.0, blue: 0x10 / 255.0, alpha: 1.0)
    self.isMovableByWindowBackground = false

    // AppKit re-lays the title bar out on resize, focus and fullscreen exit,
    // and window_manager restyles it after launch: re-place the lights each time.
    for name in [
      NSWindow.didResizeNotification, NSWindow.didEndLiveResizeNotification,
      NSWindow.didBecomeKeyNotification, NSWindow.didBecomeMainNotification,
      NSWindow.didExitFullScreenNotification, NSWindow.didDeminiaturizeNotification,
    ] {
      NotificationCenter.default.addObserver(
        self, selector: #selector(placeTrafficLights), name: name, object: self)
    }

    let autosaveName = "SyncTogetherMainWindow"
    if !self.setFrameUsingName(autosaveName) {
      let defaultSize = NSSize(width: 1280, height: 800)
      if let screen = NSScreen.main {
        let visible = screen.visibleFrame
        let x = visible.origin.x + (visible.width - defaultSize.width) / 2.0
        let y = visible.origin.y + (visible.height - defaultSize.height) / 2.0
        self.setFrame(NSRect(x: x, y: y, width: defaultSize.width, height: defaultSize.height), display: true)
      }
      self.saveFrame(usingName: autosaveName)
    } else {
      if let screen = self.screen ?? NSScreen.main {
        let visible = screen.visibleFrame
        var frame = self.frame
        if frame.maxX < visible.minX + 100 || frame.minX > visible.maxX - 100 ||
           frame.maxY < visible.minY + 100 || frame.minY > visible.maxY - 100 {
          let x = visible.origin.x + (visible.width - frame.width) / 2.0
          let y = visible.origin.y + (visible.height - frame.height) / 2.0
          frame.origin = CGPoint(x: max(visible.minX, x), y: max(visible.minY, y))
          self.setFrame(frame, display: true)
          self.saveFrame(usingName: autosaveName)
        }
      }
    }
    self.setFrameAutosaveName(autosaveName)

    RegisterGeneratedPlugins(registry: flutterViewController)
    SystemFontsChannel.register(with: flutterViewController.engine.binaryMessenger)

    super.awakeFromNib()
    DispatchQueue.main.async { [weak self] in self?.placeTrafficLights() }
    // window_manager applies its hidden title bar style from Dart a moment later.
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in self?.placeTrafficLights() }
  }

  @objc private func placeTrafficLights() {
    // In fullscreen the system draws its own bar and there is nothing to place.
    guard !styleMask.contains(.fullScreen),
      let close = standardWindowButton(.closeButton),
      let mini = standardWindowButton(.miniaturizeButton),
      let zoom = standardWindowButton(.zoomButton),
      let titlebar = close.superview,
      let container = titlebar.superview
    else { return }

    let height = MainFlutterWindow.barHeight
    var frame = container.frame
    frame.size.height = height
    frame.origin.y = (container.superview?.frame.height ?? self.frame.height) - height
    container.frame = frame

    let step = mini.frame.minX - close.frame.minX
    for (index, button) in [close, mini, zoom].enumerated() {
      button.setFrameOrigin(
        NSPoint(
          x: MainFlutterWindow.lightsLeading + CGFloat(index) * step,
          y: (height - button.frame.height) / 2))
    }
  }
}

/// Installed font families for the subtitle font picker. Face names are
/// PostScript names, which libass's CoreText provider matches directly.
enum SystemFontsChannel {
  static func register(with messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: "app.synctogether/system_fonts", binaryMessenger: messenger)
    channel.setMethodCallHandler { call, result in
      guard call.method == "list" else { return result(FlutterMethodNotImplemented) }
      DispatchQueue.global(qos: .userInitiated).async {
        let families = list()
        DispatchQueue.main.async { result(families) }
      }
    }
  }

  private static func cssWeight(_ w: Int) -> Int {
    switch w {
    case ...2: return 100
    case 3: return 200
    case 4: return 300
    case 5: return 400
    case 6: return 500
    case 7, 8: return 600
    case 9: return 700
    case 10: return 800
    default: return 900
    }
  }

  private static func list() -> [[String: Any]] {
    let manager = NSFontManager.shared
    return manager.availableFontFamilies.compactMap { family in
      // Each member is [postScriptName, styleName, weight (0-15), traits].
      let faces: [[String: Any]] = (manager.availableMembers(ofFontFamily: family) ?? []).compactMap { m in
        guard m.count >= 4, let name = m[0] as? String else { return nil }
        let traits = (m[3] as? NSNumber)?.uintValue ?? 0
        return [
          "name": name,
          "style": m[1] as? String ?? "",
          "weight": cssWeight((m[2] as? NSNumber)?.intValue ?? 5),
          "italic": traits & NSFontTraitMask.italicFontMask.rawValue != 0,
        ]
      }
      return faces.isEmpty ? nil : ["family": family, "faces": faces]
    }
  }
}
