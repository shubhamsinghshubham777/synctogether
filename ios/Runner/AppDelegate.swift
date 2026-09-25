import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "SystemFontsChannel") {
      SystemFontsChannel.register(with: registrar.messenger())
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

  /// UIFont.Weight (-1...1) to CSS 100-900.
  private static func cssWeight(_ w: CGFloat) -> Int {
    let steps: [(CGFloat, Int)] = [
      (UIFont.Weight.ultraLight.rawValue, 100), (UIFont.Weight.thin.rawValue, 200),
      (UIFont.Weight.light.rawValue, 300), (UIFont.Weight.regular.rawValue, 400),
      (UIFont.Weight.medium.rawValue, 500), (UIFont.Weight.semibold.rawValue, 600),
      (UIFont.Weight.bold.rawValue, 700), (UIFont.Weight.heavy.rawValue, 800),
      (UIFont.Weight.black.rawValue, 900),
    ]
    return steps.min(by: { abs($0.0 - w) < abs($1.0 - w) })!.1
  }

  private static func list() -> [[String: Any]] {
    return UIFont.familyNames.compactMap { family in
      let faces: [[String: Any]] = UIFont.fontNames(forFamilyName: family).compactMap { name in
        guard let font = UIFont(name: name, size: 12) else { return nil }
        let d = font.fontDescriptor
        let traits = d.object(forKey: .traits) as? [UIFontDescriptor.TraitKey: Any]
        let weight = (traits?[.weight] as? NSNumber).map { CGFloat($0.doubleValue) } ?? 0
        return [
          "name": name,
          "style": d.object(forKey: .face) as? String ?? "",
          "weight": cssWeight(weight),
          "italic": d.symbolicTraits.contains(.traitItalic),
        ]
      }
      return faces.isEmpty ? nil : ["family": family, "faces": faces]
    }
  }
}
