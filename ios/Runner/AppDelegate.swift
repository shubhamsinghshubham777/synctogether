import Flutter
import UIKit
import AVFoundation
import PhotosUI
import UniformTypeIdentifiers

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
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "MediaAccessChannel") {
      MediaAccessChannel.register(with: registrar.messenger())
    }
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "PhotoPickerChannel") {
      PhotoPickerChannel.register(with: registrar.messenger())
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

/// Keeps picked videos readable. The document picker opens files IN PLACE, so a
/// URL outside the app container needs `startAccessingSecurityScopedResource`
/// for as long as the player holds it, and only a bookmark survives a relaunch.
/// Also asks iCloud to download an evicted file. Dart side:
/// lib/player/media_access.dart (channel `app.synctogether/media_access`).
enum MediaAccessChannel {
  static func register(with messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: "app.synctogether/media_access", binaryMessenger: messenger)
    channel.setMethodCallHandler { call, result in
      let args = call.arguments as? [String: Any]
      switch call.method {
      case "startAccess":
        guard let url = fileURL(args?["url"]) else { return result(false) }
        result(url.startAccessingSecurityScopedResource())
      case "stopAccess":
        fileURL(args?["url"])?.stopAccessingSecurityScopedResource()
        result(nil)
      case "createBookmark":
        guard let url = fileURL(args?["url"]) else { return result(nil) }
        // Bookmarking a picked URL needs its scope open; a URL that never had
        // one (inside our container) simply bookmarks.
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let data = try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
        result(data?.base64EncodedString())
      case "resolveBookmark":
        result(resolve(args?["bookmark"] as? String))
      case "ensureLocal":
        result(ensureLocal(path: args?["path"] as? String))
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  /// A `file://` string, or a bare path, as a file URL.
  private static func fileURL(_ raw: Any?) -> URL? {
    guard let s = raw as? String, !s.isEmpty else { return nil }
    if s.hasPrefix("file:"), let u = URL(string: s) { return u }
    return URL(fileURLWithPath: s)
  }

  /// Resolves AND starts access on the result; the caller stops it later.
  private static func resolve(_ b64: String?) -> [String: Any]? {
    guard let b64 = b64, let data = Data(base64Encoded: b64) else { return nil }
    var stale = false
    guard let url = try? URL(resolvingBookmarkData: data, options: [], relativeTo: nil, bookmarkDataIsStale: &stale)
    else { return nil }
    let scoped = url.startAccessingSecurityScopedResource()
    var out: [String: Any] = ["url": url.absoluteString, "path": url.path]
    if stale,
      let fresh = try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
    {
      out["refreshedBookmark"] = fresh.base64EncodedString()
    }
    // Resolving a bookmark whose file is gone still returns a URL; Dart checks.
    _ = scoped
    return out
  }

  /// "local", "downloading" (an iCloud fetch was started or is running) or "missing".
  private static func ensureLocal(path: String?) -> String {
    guard let path = path else { return "missing" }
    let url = URL(fileURLWithPath: path)
    let fm = FileManager.default
    if fm.fileExists(atPath: path) {
      let keys: Set<URLResourceKey> = [.isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey]
      if let v = try? url.resourceValues(forKeys: keys), v.isUbiquitousItem == true,
        v.ubiquitousItemDownloadingStatus == .notDownloaded
      {
        try? fm.startDownloadingUbiquitousItem(at: url)
        return "downloading"
      }
      return "local"
    }
    // The legacy evicted form: `.Name.mkv.icloud` next to where the file was.
    let placeholder = url.deletingLastPathComponent().appendingPathComponent("." + url.lastPathComponent + ".icloud")
    if fm.fileExists(atPath: placeholder.path) {
      try? fm.startDownloadingUbiquitousItem(at: url)
      return "downloading"
    }
    return "missing"
  }
}

/// "From Photos": `PHPickerViewController` filtered to videos. It runs out of
/// process, so the app is never granted library access and there is no prompt
/// and no usage string. The provider's file is deleted when the completion
/// returns, so the movie is exported once into a temp folder of ours. Dart side:
/// lib/player/photo_picker.dart (channel `app.synctogether/photo_picker`).
final class PhotoPickerChannel: NSObject, PHPickerViewControllerDelegate {
  private static let shared = PhotoPickerChannel()
  private var pending: FlutterResult?

  static func register(with messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: "app.synctogether/photo_picker", binaryMessenger: messenger)
    channel.setMethodCallHandler { call, result in
      guard call.method == "pickVideo" else { return result(FlutterMethodNotImplemented) }
      shared.present(result: result)
    }
  }

  private static var folder: URL {
    URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("PhotosPicks", isDirectory: true)
  }

  /// Exports from earlier sessions are not worth keeping; a day is plenty for
  /// anything still playing.
  private static func sweep() {
    let fm = FileManager.default
    let cutoff = Date().addingTimeInterval(-86_400)
    for url in (try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.contentModificationDateKey])) ?? [] {
      let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
      if let modified = modified, modified < cutoff { try? fm.removeItem(at: url) }
    }
  }

  private func present(result: @escaping FlutterResult) {
    pending?(nil)
    pending = result
    var config = PHPickerConfiguration(photoLibrary: .shared())
    config.filter = .videos
    config.selectionLimit = 1
    // `.current` hands over the original bytes instead of transcoding.
    config.preferredAssetRepresentationMode = .current
    let picker = PHPickerViewController(configuration: config)
    picker.delegate = self
    guard let top = PhotoPickerChannel.topController() else {
      pending = nil
      return result(nil)
    }
    top.present(picker, animated: true)
  }

  private static func topController() -> UIViewController? {
    let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
      .first { $0.activationState == .foregroundActive } ?? UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
    var top = scene?.windows.first(where: { $0.isKeyWindow })?.rootViewController ?? scene?.windows.first?.rootViewController
    while let presented = top?.presentedViewController { top = presented }
    return top
  }

  func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
    picker.dismiss(animated: true)
    guard let reply = pending else { return }
    pending = nil
    guard let provider = results.first?.itemProvider else { return reply(nil) }
    let type = UTType.movie.identifier
    guard provider.hasItemConformingToTypeIdentifier(type) else { return reply(nil) }
    PhotoPickerChannel.sweep()
    provider.loadFileRepresentation(forTypeIdentifier: type) { url, error in
      guard let url = url, error == nil else {
        DispatchQueue.main.async { reply(nil) }
        return
      }
      let fm = FileManager.default
      let dir = PhotoPickerChannel.folder.appendingPathComponent(UUID().uuidString, isDirectory: true)
      let target = dir.appendingPathComponent(url.lastPathComponent)
      do {
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        try fm.copyItem(at: url, to: target)
        DispatchQueue.main.async { reply(["path": target.path, "name": target.lastPathComponent]) }
      } catch {
        DispatchQueue.main.async { reply(nil) }
      }
    }
  }
}
