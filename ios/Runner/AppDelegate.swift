import Flutter
import UIKit
import AVFoundation
import PhotosUI
import UniformTypeIdentifiers
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // The delegate has to be in place before launch finishes, or the tap that
    // launched the app from a notification is delivered to nobody.
    UNUserNotificationCenter.current().delegate = self
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  override func application(
    _ application: UIApplication,
    didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
  ) {
    PushChannel.deliver(token: deviceToken)
    super.application(application, didRegisterForRemoteNotificationsWithDeviceToken: deviceToken)
  }

  override func application(
    _ application: UIApplication,
    didFailToRegisterForRemoteNotificationsWithError error: Error
  ) {
    // No token is a normal outcome (no network, simulator without a profile).
    // The Dart side keeps working without push.
    NSLog("push registration failed: \(error.localizedDescription)")
    super.application(application, didFailToRegisterForRemoteNotificationsWithError: error)
  }

  // A notification arriving while the app is open is still shown: a call or a
  // reminder is the thing the person asked to hear about.
  override func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    willPresent notification: UNNotification,
    withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
  ) {
    completionHandler([.banner, .list, .sound])
  }

  override func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    didReceive response: UNNotificationResponse,
    withCompletionHandler completionHandler: @escaping () -> Void
  ) {
    PushChannel.tapped(route: response.notification.request.content.userInfo["route"] as? String)
    completionHandler()
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
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "DisplayRegionsChannel") {
      DisplayRegionsChannel.register(with: registrar.messenger())
    }
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "PushChannel") {
      PushChannel.register(with: registrar.messenger())
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
/// returns, so the movie is exported once into a folder of ours. Dart side:
/// lib/player/photo_picker.dart (channel `app.synctogether/photo_picker`).
///
/// The folder is `Application Support/PhotosPicks`, NOT tmp: iOS purges tmp
/// whenever the app is not running, which silently lost the pick between a
/// leave and a rejoin and made the room stream the host's copy instead.
/// Application Support is never purged by the OS, so retention is ours: Dart's
/// `PhotoExports` (lib/player/photo_exports.dart) sweeps by age and total size
/// and owns the policy. The folder is excluded from iCloud/device backups.
final class PhotoPickerChannel: NSObject, PHPickerViewControllerDelegate {
  private static let shared = PhotoPickerChannel()
  private var pending: FlutterResult?

  static func register(with messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: "app.synctogether/photo_picker", binaryMessenger: messenger)
    channel.setMethodCallHandler { call, result in
      switch call.method {
      case "pickVideo": shared.present(result: result)
      case "photoExportsDir": result(folder.path)
      default: result(FlutterMethodNotImplemented)
      }
    }
  }

  /// Created on demand and marked `isExcludedFromBackup` (set again on every
  /// call: the flag is cheap and a restore can drop it).
  private static var folder: URL {
    var url = (FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
      ?? URL(fileURLWithPath: NSTemporaryDirectory()))
      .appendingPathComponent("PhotosPicks", isDirectory: true)
    try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    var values = URLResourceValues()
    values.isExcludedFromBackup = true
    try? url.setResourceValues(values)
    return url
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
        // copyItem keeps the clip's original modification date; retention reads
        // it as "last used", so stamp it now or an old video looks stale.
        let now = Date()
        try? fm.setAttributes([.modificationDate: now], ofItemAtPath: target.path)
        try? fm.setAttributes([.modificationDate: now], ofItemAtPath: dir.path)
        DispatchQueue.main.async { reply(["path": target.path, "name": target.lastPathComponent]) }
      } catch {
        DispatchQueue.main.async { reply(nil) }
      }
    }
  }
}

/// iPhone Duo (iOS 27.1): the fold and any occluded area, as the OS reports
/// them. Flutter's iOS embedder fills `MediaQuery.displayFeatures` with nothing,
/// so this is the whole of the app's fold awareness on that device. Dart side:
/// lib/ui/display_regions.dart (channel `app.synctogether/display_regions`).
///
/// A *division* region is the fold (it splits the display into usable areas);
/// an *occlusion* region is an area the content cannot use (a hinge gap).
/// Frames are in the Flutter view's coordinates, in points - Flutter's logical
/// pixels. Below iOS 27.1, and on every device that does not fold, the list is
/// empty and nothing here does anything.
///
/// Dart asks once (`get`) and is then pushed every change (`regions`): a
/// zero-size probe view fills the Flutter view, and its `layoutSubviews` runs
/// whenever the window changes shape - opening, closing, folding, rotating,
/// Split View - which is when the regions can have changed.
enum DisplayRegionsChannel {
  private static var channel: FlutterMethodChannel?
  private static var probe: RegionProbeView?
  private static var last: [[String: Any]] = []

  static func register(with messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: "app.synctogether/display_regions", binaryMessenger: messenger)
    self.channel = channel
    channel.setMethodCallHandler { call, result in
      guard call.method == "get" else { return result(FlutterMethodNotImplemented) }
      attachProbe()
      let regions = current()
      last = regions
      result(regions)
    }
  }

  fileprivate static func flutterView() -> UIView? {
    let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
    let scene = scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
    let window = scene?.windows.first(where: { $0.isKeyWindow }) ?? scene?.windows.first
    return (window?.rootViewController as? FlutterViewController)?.view
  }

  private static func attachProbe() {
    guard probe == nil, let host = flutterView() else { return }
    let view = RegionProbeView(frame: host.bounds)
    view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    view.isUserInteractionEnabled = false
    view.backgroundColor = .clear
    host.addSubview(view)
    probe = view
  }

  fileprivate static func current() -> [[String: Any]] {
    guard #available(iOS 27.1, *), let view = flutterView() else { return [] }
    var out: [[String: Any]] = []
    let kinds: [(String, UIView.ReservedRegion.Kind)] = [("occlusion", .occlusion), ("division", .division)]
    for (name, kind) in kinds {
      for region in view.reservedRegions(kind: kind, options: [.includeInactive]) {
        let f = region.frame
        out.append([
          "kind": name,
          "active": region.isActive,
          "left": f.minX, "top": f.minY, "width": f.width, "height": f.height,
        ])
      }
    }
    return out
  }

  /// Pushes the regions when they differ from what Dart last had.
  fileprivate static func push() {
    let regions = current()
    guard !NSDictionary(dictionary: ["r": regions]).isEqual(to: ["r": last]) else { return }
    last = regions
    channel?.invokeMethod("regions", arguments: regions)
  }
}

/// Zero-cost: no drawing, no touches. It exists only to be laid out.
final class RegionProbeView: UIView {
  override func layoutSubviews() {
    super.layoutSubviews()
    DisplayRegionsChannel.push()
  }

  override func didMoveToWindow() {
    super.didMoveToWindow()
    DisplayRegionsChannel.push()
  }
}

/// Push notifications over APNs - directly, with no third-party SDK. The server
/// (`push-dispatch`) holds the key; this only registers the device and hands the
/// token to Dart. Dart side: lib/pairing/push_service.dart (channel
/// `app.synctogether/push`).
///
/// Nothing here prompts by itself. `permission` only reads; `request` is the one
/// call that shows the system alert, and Dart only makes it because a person just
/// turned a notification on.
///
/// A debug build's token only works on Apple's sandbox gateway and a release
/// build's only on production, so the build configuration decides which one the
/// server is told to use.
enum PushChannel {
  private static var channel: FlutterMethodChannel?
  private static var lastToken: String?
  // A tap that arrived before Dart was listening: the one that launched the app.
  private static var pendingRoute: String?
  private static var dartReady = false

  #if DEBUG
    private static let environment = "sandbox"
  #else
    private static let environment = "production"
  #endif

  static func register(with messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: "app.synctogether/push", binaryMessenger: messenger)
    self.channel = channel
    channel.setMethodCallHandler { call, result in
      switch call.method {
      case "configure":
        dartReady = true
        result(nil)
      case "permission":
        status { granted in
          // Already allowed: make sure the token callback fires this launch.
          if granted == "granted" { registerForRemote() }
          result(granted)
        }
      case "request":
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { ok, _ in
          DispatchQueue.main.async {
            if ok { registerForRemote() }
            result(ok ? "granted" : "denied")
          }
        }
      case "token":
        guard let token = lastToken else { return result(nil) }
        result(["token": token, "environment": environment])
      case "launchRoute":
        let route = pendingRoute
        pendingRoute = nil
        result(route)
      case "openSettings":
        // The notifications page itself is iOS 16+; older systems get the app's
        // own settings page, which has the same switch one tap further in.
        let target: String
        if #available(iOS 16.0, *) {
          target = UIApplication.openNotificationSettingsURLString
        } else {
          target = UIApplication.openSettingsURLString
        }
        if let url = URL(string: target) {
          UIApplication.shared.open(url)
        }
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  private static func status(_ done: @escaping (String) -> Void) {
    UNUserNotificationCenter.current().getNotificationSettings { settings in
      let value: String
      switch settings.authorizationStatus {
      case .authorized, .provisional, .ephemeral: value = "granted"
      case .denied: value = "denied"
      default: value = "unknown"
      }
      DispatchQueue.main.async { done(value) }
    }
  }

  private static func registerForRemote() {
    UIApplication.shared.registerForRemoteNotifications()
  }

  static func deliver(token data: Data) {
    let token = data.map { String(format: "%02x", $0) }.joined()
    lastToken = token
    channel?.invokeMethod("token", arguments: ["token": token, "environment": environment])
  }

  static func tapped(route: String?) {
    if dartReady, let channel = channel {
      channel.invokeMethod("tap", arguments: ["route": route as Any])
    } else {
      pendingRoute = route
    }
  }
}
