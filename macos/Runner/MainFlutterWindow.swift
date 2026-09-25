import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)
    SystemFontsChannel.register(with: flutterViewController.engine.binaryMessenger)

    super.awakeFromNib()
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
