import Cocoa
import FlutterMacOS
import AVFoundation
import CoreAudio
import UserNotifications
import Network

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
    // and the hidden title bar style is applied from Dart after launch: re-place the lights each time.
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
    MicLevelChannel.register(with: flutterViewController.engine.binaryMessenger)
    AudioEventsChannel.register(with: flutterViewController.engine.binaryMessenger)
    PushChannel.register(with: flutterViewController.engine.binaryMessenger)
    PermissionsChannel.register(with: flutterViewController.engine.binaryMessenger)
    BugReportMenuChannel.register(with: flutterViewController.engine.binaryMessenger)
    ProfileMenuChannel.register(with: flutterViewController.engine.binaryMessenger)

    super.awakeFromNib()
    DispatchQueue.main.async { [weak self] in self?.placeTrafficLights() }
    // the hidden title bar style is applied from Dart (AppWindow.configure) a moment later.
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

/// Tells the pre-show check when the Mac's default input changes (a headset or
/// a USB mic plugged in or out). Same contract as the iOS runner's
/// `app.synctogether/audio_events`: `start`, `stop`, `useBuiltIn`; events go
/// back as `event` calls. A Mac has no call interruption to report.
enum AudioEventsChannel {
  private static var channel: FlutterMethodChannel?
  private static var listening = false
  private static var address = AudioObjectPropertyAddress(
    mSelector: kAudioHardwarePropertyDefaultInputDevice,
    mScope: kAudioObjectPropertyScopeGlobal,
    mElement: kAudioObjectPropertyElementMain)
  private static let listener: AudioObjectPropertyListenerBlock = { _, _ in
    DispatchQueue.main.async { sendInput() }
  }

  static func register(with messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: "app.synctogether/audio_events", binaryMessenger: messenger)
    self.channel = channel
    channel.setMethodCallHandler { call, result in
      switch call.method {
      case "start":
        if !listening {
          AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject), &address, DispatchQueue.main, listener)
          listening = true
        }
        result(nil)
      case "stop":
        if listening {
          AudioObjectRemovePropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject), &address, DispatchQueue.main, listener)
          listening = false
        }
        result(nil)
      case "useBuiltIn":
        if let id = builtInInput(), let name = name(of: id) {
          result(["ok": true, "name": name])
        } else {
          result(["ok": false])
        }
      case "audioState":
        result(audioState())
      case "useBuiltInOutput":
        if let id = builtInOutput(), setDefaultOutput(id), let name = name(of: id) {
          result(["ok": true, "name": name])
        } else {
          result(["ok": false])
        }
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  // MARK: - Sound output

  private static func defaultOutput() -> AudioObjectID? {
    var id = AudioObjectID(0)
    var size = UInt32(MemoryLayout<AudioObjectID>.size)
    var addr = AudioObjectPropertyAddress(
      mSelector: kAudioHardwarePropertyDefaultOutputDevice, mScope: kAudioObjectPropertyScopeGlobal,
      mElement: kAudioObjectPropertyElementMain)
    guard
      AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &id)
        == noErr, id != 0
    else { return nil }
    return id
  }

  private static func hasOutput(_ id: AudioObjectID) -> Bool {
    var addr = AudioObjectPropertyAddress(
      mSelector: kAudioDevicePropertyStreams, mScope: kAudioObjectPropertyScopeOutput,
      mElement: kAudioObjectPropertyElementMain)
    var size = UInt32(0)
    return AudioObjectGetPropertyDataSize(id, &addr, 0, nil, &size) == noErr && size > 0
  }

  private static func builtInOutput() -> AudioObjectID? {
    var addr = AudioObjectPropertyAddress(
      mSelector: kAudioHardwarePropertyDevices, mScope: kAudioObjectPropertyScopeGlobal,
      mElement: kAudioObjectPropertyElementMain)
    var size = UInt32(0)
    guard
      AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size)
        == noErr
    else { return nil }
    var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
    guard
      AudioObjectGetPropertyData(
        AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &ids) == noErr
    else { return nil }
    return ids.first { hasOutput($0) && transportType(of: $0) == kAudioDeviceTransportTypeBuiltIn }
  }

  private static func setDefaultOutput(_ id: AudioObjectID) -> Bool {
    var target = id
    var addr = AudioObjectPropertyAddress(
      mSelector: kAudioHardwarePropertyDefaultOutputDevice, mScope: kAudioObjectPropertyScopeGlobal,
      mElement: kAudioObjectPropertyElementMain)
    return AudioObjectSetPropertyData(
      AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil,
      UInt32(MemoryLayout<AudioObjectID>.size), &target) == noErr
  }

  /// Output volume 0..1 (muted counts as 0), or nil where the device has no volume.
  private static func volume(of id: AudioObjectID) -> Double? {
    var muteAddr = AudioObjectPropertyAddress(
      mSelector: kAudioDevicePropertyMute, mScope: kAudioObjectPropertyScopeOutput,
      mElement: kAudioObjectPropertyElementMain)
    var muted = UInt32(0)
    var msize = UInt32(MemoryLayout<UInt32>.size)
    if AudioObjectGetPropertyData(id, &muteAddr, 0, nil, &msize, &muted) == noErr, muted != 0 {
      return 0
    }
    for element in [kAudioObjectPropertyElementMain, 1, 2] {
      var addr = AudioObjectPropertyAddress(
        mSelector: kAudioDevicePropertyVolumeScalar, mScope: kAudioObjectPropertyScopeOutput,
        mElement: AudioObjectPropertyElement(element))
      var v = Float32(0)
      var size = UInt32(MemoryLayout<Float32>.size)
      if AudioObjectGetPropertyData(id, &addr, 0, nil, &size, &v) == noErr { return Double(v) }
    }
    return nil
  }

  private static func audioState() -> [String: Any] {
    guard let id = defaultOutput() else { return [:] }
    let transport = transportType(of: id)
    let kind: String
    switch transport {
    case kAudioDeviceTransportTypeBuiltIn: kind = "builtIn"
    case kAudioDeviceTransportTypeBluetooth, kAudioDeviceTransportTypeBluetoothLE: kind = "bluetooth"
    case kAudioDeviceTransportTypeAirPlay: kind = "airplay"
    default: kind = "other"
    }
    var state: [String: Any] = ["kind": kind, "canBuiltIn": builtInOutput() != nil]
    if let n = name(of: id) { state["name"] = n }
    if let v = volume(of: id) { state["volume"] = v }
    return state
  }

  private static func sendInput() {
    var id = AudioObjectID(0)
    var size = UInt32(MemoryLayout<AudioObjectID>.size)
    var addr = address
    guard
      AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &id)
        == noErr, id != 0, let label = name(of: id)
    else { return }
    let transport = transportType(of: id)
    let bluetooth =
      transport == kAudioDeviceTransportTypeBluetooth
      || transport == kAudioDeviceTransportTypeBluetoothLE
    channel?.invokeMethod(
      "event",
      arguments: [
        "type": "input", "name": label,
        "builtIn": transport == kAudioDeviceTransportTypeBuiltIn, "bluetooth": bluetooth,
        "canBuiltIn": builtInInput() != nil,
      ])
  }

  private static func name(of id: AudioObjectID) -> String? {
    var addr = AudioObjectPropertyAddress(
      mSelector: kAudioObjectPropertyName, mScope: kAudioObjectPropertyScopeGlobal,
      mElement: kAudioObjectPropertyElementMain)
    var name: CFString = "" as CFString
    var size = UInt32(MemoryLayout<CFString>.size)
    let status = withUnsafeMutablePointer(to: &name) {
      AudioObjectGetPropertyData(id, &addr, 0, nil, &size, $0)
    }
    return status == noErr ? name as String : nil
  }

  private static func transportType(of id: AudioObjectID) -> UInt32 {
    var addr = AudioObjectPropertyAddress(
      mSelector: kAudioDevicePropertyTransportType, mScope: kAudioObjectPropertyScopeGlobal,
      mElement: kAudioObjectPropertyElementMain)
    var type = UInt32(0)
    var size = UInt32(MemoryLayout<UInt32>.size)
    AudioObjectGetPropertyData(id, &addr, 0, nil, &size, &type)
    return type
  }

  private static func hasInput(_ id: AudioObjectID) -> Bool {
    var addr = AudioObjectPropertyAddress(
      mSelector: kAudioDevicePropertyStreams, mScope: kAudioObjectPropertyScopeInput,
      mElement: kAudioObjectPropertyElementMain)
    var size = UInt32(0)
    return AudioObjectGetPropertyDataSize(id, &addr, 0, nil, &size) == noErr && size > 0
  }

  private static func builtInInput() -> AudioObjectID? {
    var addr = AudioObjectPropertyAddress(
      mSelector: kAudioHardwarePropertyDevices, mScope: kAudioObjectPropertyScopeGlobal,
      mElement: kAudioObjectPropertyElementMain)
    var size = UInt32(0)
    guard
      AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size)
        == noErr
    else { return nil }
    var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
    guard
      AudioObjectGetPropertyData(
        AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &ids) == noErr
    else { return nil }
    return ids.first { hasInput($0) && transportType(of: $0) == kAudioDeviceTransportTypeBuiltIn }
  }
}

/// Live input level for the "Test your mic" meter. WebRTC only captures once
/// a track rides a peer connection, so the bare local track the settings
/// dialog opens never delivers audio; this reads the input device directly.
/// Same contract as the Windows runner's `mic_level` channel: `start(name)`,
/// `peak`, `stop`.
///
/// AVCaptureSession rather than AVAudioEngine: the engine drives input and the
/// default output through one I/O unit, which started cleanly against a USB
/// codec and then never delivered a buffer. A capture session is input only
/// and picks its device by name.
enum MicLevelChannel {
  private static var session: AVCaptureSession?
  private static let queue = DispatchQueue(label: "app.synctogether.mic_level")
  private static let sink = LevelSink()
  // Written from the capture queue, read from the main thread; a stale float
  // is harmless for a meter.
  fileprivate static var latestPeak: Float = 0

  static func register(with messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: "app.synctogether/mic_level", binaryMessenger: messenger)
    channel.setMethodCallHandler { call, result in
      switch call.method {
      case "start":
        let name = (call.arguments as? [String: Any])?["name"] as? String
        // Ask first (no prompt once the user has answered): a denied mic would
        // otherwise start and deliver silence.
        AVCaptureDevice.requestAccess(for: .audio) { granted in
          DispatchQueue.main.async { result(granted && start(deviceName: name)) }
        }
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
    session?.stopRunning()
    session = nil
    latestPeak = 0
  }

  private static func start(deviceName: String?) -> Bool {
    stop()
    guard let device = inputDevice(named: deviceName) else { return false }
    let session = AVCaptureSession()
    let output = AVCaptureAudioDataOutput()
    // Fixed format so the sink only ever reads interleaved 16-bit samples.
    output.audioSettings = [
      AVFormatIDKey: kAudioFormatLinearPCM,
      AVLinearPCMBitDepthKey: 16,
      AVLinearPCMIsFloatKey: false,
      AVLinearPCMIsBigEndianKey: false,
      AVLinearPCMIsNonInterleaved: false,
    ]
    output.setSampleBufferDelegate(sink, queue: queue)
    guard let input = try? AVCaptureDeviceInput(device: device),
      session.canAddInput(input), session.canAddOutput(output)
    else { return false }
    session.addInput(input)
    session.addOutput(output)
    session.startRunning()
    self.session = session
    return true
  }

  /// WebRTC's device label is the CoreAudio device name, give or take a
  /// "Default - " style prefix, so match by containment either way. Falls back
  /// to the system default input.
  private static func inputDevice(named wanted: String?) -> AVCaptureDevice? {
    let want = wanted?.trimmingCharacters(in: .whitespaces).lowercased() ?? ""
    if !want.isEmpty {
      for device in AVCaptureDevice.devices(for: .audio) {
        let have = device.localizedName.lowercased()
        if have == want || want.contains(have) || have.contains(want) { return device }
      }
    }
    return AVCaptureDevice.default(for: .audio)
  }

  fileprivate final class LevelSink: NSObject, AVCaptureAudioDataOutputSampleBufferDelegate {
    func captureOutput(
      _ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer,
      from connection: AVCaptureConnection
    ) {
      guard let block = CMSampleBufferGetDataBuffer(sampleBuffer) else { return }
      var length = 0
      var pointer: UnsafeMutablePointer<Int8>?
      guard
        CMBlockBufferGetDataPointer(
          block, atOffset: 0, lengthAtOffsetOut: nil, totalLengthOut: &length,
          dataPointerOut: &pointer) == kCMBlockBufferNoErr, let pointer
      else { return }
      var peak: Int32 = 0
      pointer.withMemoryRebound(to: Int16.self, capacity: length / 2) { samples in
        for i in 0..<(length / 2) { peak = max(peak, abs(Int32(samples[i]))) }
      }
      MicLevelChannel.latestPeak = Float(peak) / 32768
    }
  }
}

/// Push notifications over APNs - directly, with no third-party SDK. Same
/// contract as the iOS runner (`app.synctogether/push`), so the Dart side is one
/// implementation. Nothing here prompts by itself: `permission` only reads, and
/// `request` is the one call that shows the system alert.
///
/// Registration needs the `aps-environment` entitlement, which only a
/// provisioned (store) build carries. A local debug build has none, so
/// `registerForRemoteNotifications` fails quietly and the app runs without push.
/// Camera and microphone permission, read and asked for on purpose (the pre-show
/// check). Dart side: lib/av/system_permissions.dart. Same contract as iOS; the
/// settings links go to the matching Privacy & Security pane.
enum PermissionsChannel {
  static func register(with messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: "app.synctogether/permissions", binaryMessenger: messenger)
    channel.setMethodCallHandler { call, result in
      let kind = (call.arguments as? [String: Any])?["kind"] as? String
      switch call.method {
      case "status":
        result(status(kind))
      case "request":
        guard let type = mediaType(kind) else { return result("unknown") }
        AVCaptureDevice.requestAccess(for: type) { _ in
          DispatchQueue.main.async { result(status(kind)) }
        }
      case "openAppSettings":
        let pane = kind == "camera" ? "Privacy_Camera" : "Privacy_Microphone"
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") {
          NSWorkspace.shared.open(url)
        }
        result(nil)
      case "networkInfo":
        networkInfo { result($0) }
      case "openNetworkSettings":
        if let url = URL(string: "x-apple.systempreferences:com.apple.Network-Settings.extension") {
          NSWorkspace.shared.open(url)
        }
        result(true)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  /// One reading of the connection: whether there is one at all, whether it is
  /// Wi-Fi or something metered (cellular, a hotspot), and Low Data Mode.
  private static func networkInfo(_ done: @escaping ([String: Any]) -> Void) {
    let monitor = NWPathMonitor()
    var finished = false
    monitor.pathUpdateHandler = { path in
      guard !finished else { return }
      finished = true
      monitor.cancel()
      let transport: String
      if path.status != .satisfied {
        transport = "none"
      } else if path.usesInterfaceType(.wifi) || path.usesInterfaceType(.wiredEthernet) {
        transport = path.isExpensive ? "cellular" : "wifi"
      } else if path.usesInterfaceType(.cellular) {
        transport = "cellular"
      } else {
        transport = "other"
      }
      DispatchQueue.main.async { done(["transport": transport, "saver": path.isConstrained]) }
    }
    monitor.start(queue: DispatchQueue(label: "app.synctogether.netinfo"))
  }

  private static func mediaType(_ kind: String?) -> AVMediaType? {
    switch kind {
    case "camera": return .video
    case "mic": return .audio
    default: return nil
    }
  }

  private static func status(_ kind: String?) -> String {
    guard let type = mediaType(kind) else { return "unknown" }
    switch AVCaptureDevice.authorizationStatus(for: type) {
    case .authorized: return "granted"
    case .denied: return "blocked"
    case .restricted: return "restricted"
    default: return "notDetermined"
    }
  }
}

enum PushChannel {
  private static var channel: FlutterMethodChannel?
  private static var lastToken: String?
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
          if granted == "granted" { NSApplication.shared.registerForRemoteNotifications() }
          result(granted)
        }
      case "request":
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { ok, _ in
          DispatchQueue.main.async {
            if ok { NSApplication.shared.registerForRemoteNotifications() }
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
        if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") {
          NSWorkspace.shared.open(url)
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
      case .authorized, .provisional: value = "granted"
      case .denied: value = "denied"
      default: value = "unknown"
      }
      DispatchQueue.main.async { done(value) }
    }
  }

  static func deliver(token data: Data) {
    let token = data.map { String(format: "%02x", $0) }.joined()
    lastToken = token
    channel?.invokeMethod("token", arguments: ["token": token, "environment": environment])
  }

  /// Hands a seat-taken push to Dart while the app is open. False when Dart is
  /// not listening (so the system banner shows instead).
  static func presentInApp(_ notification: UNNotification) -> Bool {
    let content = notification.request.content
    guard
      dartReady, let channel = channel,
      (content.userInfo["kind"] as? String) == "seat_taken"
    else { return false }
    channel.invokeMethod(
      "foreground",
      arguments: [
        "kind": "seat_taken",
        "title": content.title,
        "body": content.body,
        "route": content.userInfo["route"] as Any,
      ])
    return true
  }

  static func tapped(route: String?) {
    if dartReady, let channel = channel {
      channel.invokeMethod("tap", arguments: ["route": route as Any])
    } else {
      pendingRoute = route
    }
  }
}

/// The Help menu's "Report a Bug…" tells Dart to open the bug report sheet.
/// One-way: there is nothing for Dart to answer. AppKit owns the Shift+Cmd+B
/// key equivalent on macOS, so the Dart side does not bind it there (see
/// `BugReportShortcut`).
final class BugReportMenuChannel: NSObject {
  static let shared = BugReportMenuChannel()
  private static var channel: FlutterMethodChannel?

  static func register(with messenger: FlutterBinaryMessenger) {
    channel = FlutterMethodChannel(name: "app.synctogether/bug_report_menu", binaryMessenger: messenger)
    shared.installMenuItem(attemptsLeft: 20)
  }

  /// The main menu is not attached to `NSApp` yet while the window's nib is
  /// still waking up, so look again a moment later (the insert is idempotent).
  private func installMenuItem(attemptsLeft: Int) {
    // `helpMenu` is not always assigned from the nib, and the title is
    // localised, so fall back to the last top-level menu, which is Help.
    guard let help = NSApp.helpMenu ?? NSApp.mainMenu?.items.last?.submenu else {
      guard attemptsLeft > 0 else { return }
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
        self.installMenuItem(attemptsLeft: attemptsLeft - 1)
      }
      return
    }
    if help.items.contains(where: { $0.action == #selector(reportBug(_:)) }) { return }
    let item = NSMenuItem(
      title: "Report a Bug…", action: #selector(reportBug(_:)), keyEquivalent: "b")
    item.keyEquivalentModifierMask = [.command, .shift]
    item.target = self
    help.insertItem(item, at: 0)
    help.insertItem(.separator(), at: 1)
  }

  @objc private func reportBug(_ sender: Any?) {
    Self.channel?.invokeMethod("report", arguments: nil)
  }
}

/// The app menu's "Preferences…" (Cmd+,) tells Dart to open the profile. The nib
/// declares the item with its key equivalent but no action, so AppKit swallowed
/// the key; this gives it one. One-way, like `BugReportMenuChannel`; the Dart
/// side does not bind Cmd+, on macOS (see `ProfileShortcut`).
final class ProfileMenuChannel: NSObject {
  static let shared = ProfileMenuChannel()
  private static var channel: FlutterMethodChannel?

  static func register(with messenger: FlutterBinaryMessenger) {
    channel = FlutterMethodChannel(name: "app.synctogether/profile_menu", binaryMessenger: messenger)
    shared.attach(attemptsLeft: 20)
  }

  /// The main menu is not attached to `NSApp` yet while the nib is waking up.
  private func attach(attemptsLeft: Int) {
    guard let appMenu = NSApp.mainMenu?.items.first?.submenu else {
      guard attemptsLeft > 0 else { return }
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
        self.attach(attemptsLeft: attemptsLeft - 1)
      }
      return
    }
    guard let item = appMenu.items.first(where: { $0.keyEquivalent == "," }) else { return }
    item.title = "Profile…"
    item.target = self
    item.action = #selector(openProfile(_:))
  }

  @objc private func openProfile(_ sender: Any?) {
    Self.channel?.invokeMethod("open", arguments: nil)
  }
}
