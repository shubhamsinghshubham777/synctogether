import Flutter
import UIKit
import AVFoundation

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
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "MicLevelChannel") {
      MicLevelChannel.register(with: registrar.messenger())
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

/// Live input level for the "Test your mic" meter. WebRTC only captures once
/// a track rides a peer connection, so the dialog taps the input itself.
/// Same contract as the desktop runners: `start`, `peak`, `stop`. A phone has
/// one input in play, so the device name is ignored.
enum MicLevelChannel {
  private static var engine: AVAudioEngine?
  // Written from the audio thread, read from the main thread; a stale float
  // is harmless for a meter.
  private static var latestPeak: Float = 0

  static func register(with messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: "app.synctogether/mic_level", binaryMessenger: messenger)
    channel.setMethodCallHandler { call, result in
      switch call.method {
      case "start":
        start(result: result)
      case "peak":
        result(Double(latestPeak))
      case "stop":
        stop()
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  private static func stop() {
    engine?.inputNode.removeTap(onBus: 0)
    engine?.stop()
    engine = nil
    latestPeak = 0
  }

  private static func start(result: @escaping FlutterResult) {
    stop()
    AVAudioSession.sharedInstance().requestRecordPermission { granted in
      DispatchQueue.main.async {
        result(granted && open())
      }
    }
  }

  private static func open() -> Bool {
    let session = AVAudioSession.sharedInstance()
    // A room already holds the session as playAndRecord with LiveKit's own
    // mode and options (echo cancellation, Bluetooth routing); leave that
    // alone. Only claim it ourselves when nothing has, and mix so a room
    // already playing audio is not cut off by the test.
    if session.category != .playAndRecord {
      try? session.setCategory(
        .playAndRecord, mode: .default, options: [.mixWithOthers, .defaultToSpeaker, .allowBluetooth])
      try? session.setActive(true)
    }
    let engine = AVAudioEngine()
    let format = engine.inputNode.outputFormat(forBus: 0)
    guard format.sampleRate > 0 else { return false }
    engine.inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
      guard let data = buffer.floatChannelData else { return }
      var peak: Float = 0
      for c in 0..<Int(buffer.format.channelCount) {
        for i in 0..<Int(buffer.frameLength) { peak = max(peak, abs(data[c][i])) }
      }
      latestPeak = peak
    }
    do {
      try engine.start()
    } catch {
      engine.inputNode.removeTap(onBus: 0)
      return false
    }
    self.engine = engine
    return true
  }
}
