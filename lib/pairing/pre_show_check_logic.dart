import 'dart:async';

import 'package:flutter/foundation.dart';

import '../av/system_permissions.dart';
import '../diagnostics.dart';
import 'pair_logic.dart';
import 'pair_models.dart';

/// The pre-show check (board 94): five rows that say whether a night is ready.
///
/// Everything here is local and nothing blocks. A row that is not ready says why
/// in words and offers the fix that is in reach (a button, or the system page
/// where only the system can change it); the sheet's button then reads "Take our
/// seats anyway". Permissions are asked only when the person taps that row.
/// Camera and microphone are released the moment the sheet closes or the app
/// leaves the front.

enum CheckId { film, camera, mic, sound, connection }

enum RowTone { idle, busy, ok, warn, bad }

/// What sits at the trailing edge of a row, before its status mark.
enum RowTrail { none, thumb, meter, progress, playButton }

/// A button on a row's fix card. [id] is what the controller acts on.
class FixAction {
  const FixAction(this.id, this.label, {this.primary = false});
  final String id;
  final String label;
  final bool primary;
}

class CheckRowView {
  const CheckRowView({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.tone,
    this.trail = RowTrail.none,
    this.progress,
    this.fix,
    this.actions = const [],
  });

  final CheckId id;
  final String title;
  final String subtitle;
  final RowTone tone;
  final RowTrail trail;

  /// 0..1 for [RowTrail.progress].
  final double? progress;

  /// The card under the row: why, and what to do. Null when there is nothing to say.
  final String? fix;
  final List<FixAction> actions;

  /// Something the person might want to look at before the lights go down.
  bool get flagged => tone == RowTone.warn || tone == RowTone.bad;
}

// ---------------------------------------------------------------------------
// The film row, from what the night (or room) carries
// ---------------------------------------------------------------------------

enum FilmKind { none, link, fileReady, fileUploading, fileStopped, local, youtubeInRoom }

class FilmCheck {
  const FilmCheck(this.kind, {this.percent = 0, this.name, this.mine = false});

  final FilmKind kind;
  final int percent;
  final String? name;

  /// This person is the one uploading it.
  final bool mine;

  /// A date night's film, as both people read it now.
  factory FilmCheck.forNight(DateNight night, DateTime now, {required bool mine}) {
    final view = fileViewOf(night, now);
    return switch (view.stage) {
      FileStage.ready => FilmCheck(FilmKind.fileReady, name: night.fileName, percent: 100),
      FileStage.uploading || FileStage.unfinished => FilmCheck(
        FilmKind.fileUploading,
        percent: view.percent,
        mine: mine,
        name: night.fileName,
      ),
      FileStage.stopped => FilmCheck(FilmKind.fileStopped, percent: view.percent, mine: mine),
      FileStage.none =>
        night.hasLink ? const FilmCheck(FilmKind.link) : const FilmCheck(FilmKind.none),
    };
  }

  /// Whether watching it means streaming (so the connection matters more).
  bool get streams =>
      kind == FilmKind.fileReady ||
      kind == FilmKind.fileUploading ||
      kind == FilmKind.link ||
      kind == FilmKind.youtubeInRoom;
}

// ---------------------------------------------------------------------------
// Device probes, behind an interface so the sheet is testable with no hardware
// ---------------------------------------------------------------------------

enum CameraOpen { ok, none, busy, denied, failed }

enum ChimeResult { played, failed }

/// A round trip to the room server.
class LatencyReading {
  const LatencyReading.ms(this.ms) : failed = false;
  const LatencyReading.failed() : ms = null, failed = true;
  final int? ms;
  final bool failed;
}

abstract class PreShowProbes {
  Future<PermissionState> permission(PermissionKind kind);
  Future<PermissionState> request(PermissionKind kind);
  Future<void> openPermissionSettings(PermissionKind kind);
  Future<bool> openNetworkSettings();
  Future<NetworkInfo> networkInfo();

  /// Opens the camera for a local preview. Nothing is published anywhere.
  Future<CameraOpen> openCamera();
  Future<void> closeCamera();

  /// Fires if the camera stops by itself (unplugged, taken by another app).
  Stream<void> get cameraEnded;

  /// Bar levels 0..1; errors if the microphone cannot be opened.
  Stream<List<double>> micLevels();
  Future<ChimeResult> playChime();
  Future<LatencyReading> measureLatency();
}

// ---------------------------------------------------------------------------
// States
// ---------------------------------------------------------------------------

enum CamState { idle, starting, on, denied, blocked, restricted, none, busy, stopped, off, paused }

enum MicState {
  idle,
  starting,
  listening,
  heard,
  flat,
  denied,
  blocked,
  restricted,
  failed,
  paused,
}

enum SoundState { idle, playing, confirm, heard, notHeard, failed }

enum LineState { measuring, good, slow, verySlow, offline, unreachable }

/// How the pre-show check's thresholds read a latency, in one place so the words
/// and the colours cannot disagree.
LineState lineStateFor(int ms) => ms < 250
    ? LineState.good
    : ms < 800
    ? LineState.slow
    : LineState.verySlow;

class PreShowCheckController extends ChangeNotifier {
  PreShowCheckController({
    required this.probes,
    required this.film,
    this.includeAv = true,
    this.partner = 'your person',
  });

  final PreShowProbes probes;

  /// Read each time the rows are built, so a night that changes under the sheet
  /// (an upload advancing, a film attached) shows at once.
  final FilmCheck Function() film;

  /// A room's own check has no camera or microphone rows: the room's bar owns them.
  final bool includeAv;
  final String partner;

  CamState cam = CamState.idle;
  MicState mic = MicState.idle;
  SoundState sound = SoundState.idle;
  LineState line = LineState.measuring;
  int? latencyMs;
  NetworkInfo network = const NetworkInfo();
  bool _mobileOk = false;
  bool _saverOk = false;
  bool _soundGaveUp = false;

  /// The meter's bars, on their own notifier: they move ~30 times a second and
  /// must not rebuild the whole sheet.
  final micLevels = ValueNotifier<List<double>>(const []);
  StreamSubscription<List<double>>? _micSub;
  StreamSubscription<void>? _camEndedSub;
  Timer? _flatTimer;
  bool _disposed = false;

  /// How long a live microphone may stay silent before we say so.
  static const flatAfter = Duration(seconds: 5);

  // ------------------------------------------------------------- lifecycle

  /// Reads where everything stands. Asks nothing: a permission that is already
  /// granted starts its preview, one that is not waits for a tap.
  Future<void> start() async {
    unawaited(measure());
    if (!includeAv) return;
    final camStatus = await probes.permission(.camera);
    final micStatus = await probes.permission(.mic);
    if (_disposed) return;
    cam = _camFor(camStatus, fallback: CamState.idle);
    mic = _micFor(micStatus, fallback: MicState.idle);
    notifyListeners();
    if (camStatus == PermissionState.granted) unawaited(startCamera());
    if (micStatus == PermissionState.granted) unawaited(startMic());
  }

  CamState _camFor(PermissionState s, {required CamState fallback}) => switch (s) {
    PermissionState.denied => CamState.denied,
    PermissionState.blocked => CamState.blocked,
    PermissionState.restricted => CamState.restricted,
    _ => fallback,
  };

  MicState _micFor(PermissionState s, {required MicState fallback}) => switch (s) {
    PermissionState.denied => MicState.denied,
    PermissionState.blocked => MicState.blocked,
    PermissionState.restricted => MicState.restricted,
    _ => fallback,
  };

  /// The app left the front: nothing stays on in a pocket. Rows say "paused".
  Future<void> background() async {
    if (!includeAv) return;
    final camWasOn = cam == CamState.on || cam == CamState.starting;
    final micWasOn =
        mic == MicState.listening ||
        mic == MicState.heard ||
        mic == MicState.flat ||
        mic == MicState.starting;
    await _releaseCamera();
    _releaseMic();
    if (camWasOn) cam = CamState.paused;
    if (micWasOn) mic = MicState.paused;
    trace('pre-show devices paused', category: 'av', data: {'cam': camWasOn, 'mic': micWasOn});
    if (!_disposed) notifyListeners();
  }

  /// Back in front. A permission changed in Settings in the meantime is read
  /// again, and a paused device shows its restart button (it never restarts by
  /// itself: a camera that comes on unprompted is not what "paused" promised).
  Future<void> foreground() async {
    if (!includeAv || _disposed) return;
    final camStatus = await probes.permission(.camera);
    final micStatus = await probes.permission(.mic);
    if (_disposed) return;
    if (const {CamState.denied, CamState.blocked, CamState.restricted}.contains(cam)) {
      if (camStatus == PermissionState.granted) {
        cam = CamState.idle;
        unawaited(startCamera());
      } else {
        cam = _camFor(camStatus, fallback: cam);
      }
    }
    if (const {MicState.denied, MicState.blocked, MicState.restricted}.contains(mic)) {
      if (micStatus == PermissionState.granted) {
        mic = MicState.idle;
        unawaited(startMic());
      } else {
        mic = _micFor(micStatus, fallback: mic);
      }
    }
    notifyListeners();
    unawaited(measure());
  }

  /// Camera and microphone off now, ahead of leaving (taking seats hands both to
  /// the room, which opens them itself).
  Future<void> releaseDevices() async {
    await _releaseCamera();
    _releaseMic();
  }

  @override
  void dispose() {
    _disposed = true;
    _flatTimer?.cancel();
    unawaited(_releaseCamera());
    _micSub?.cancel();
    _micSub = null;
    micLevels.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------- camera

  Future<void> startCamera() async {
    if (_disposed || cam == CamState.starting) return;
    cam = CamState.starting;
    notifyListeners();
    var status = await probes.permission(.camera);
    if (status == PermissionState.notDetermined || status == PermissionState.denied) {
      status = await probes.request(.camera);
    }
    if (_disposed) return;
    if (status == PermissionState.blocked ||
        status == PermissionState.denied ||
        status == PermissionState.restricted) {
      cam = _camFor(status, fallback: CamState.denied);
      trace('camera not allowed', category: 'av', data: {'status': status.name});
      notifyListeners();
      return;
    }
    final opened = await probes.openCamera();
    if (_disposed) {
      await probes.closeCamera();
      return;
    }
    cam = switch (opened) {
      CameraOpen.ok => CamState.on,
      CameraOpen.none => CamState.none,
      CameraOpen.busy => CamState.busy,
      CameraOpen.denied => CamState.blocked,
      CameraOpen.failed => CamState.busy,
    };
    trace('camera preview', category: 'av', data: {'result': opened.name});
    if (cam == CamState.on) {
      await _camEndedSub?.cancel();
      _camEndedSub = probes.cameraEnded.listen((_) {
        // Unplugged, or taken by another app: say so once and offer a restart.
        if (cam != CamState.on) return;
        cam = CamState.stopped;
        trace('camera stopped under the preview', category: 'av');
        if (!_disposed) notifyListeners();
      });
    }
    notifyListeners();
  }

  void voiceOnly() {
    unawaited(_releaseCamera());
    cam = CamState.off;
    notifyListeners();
  }

  Future<void> _releaseCamera() async {
    await _camEndedSub?.cancel();
    _camEndedSub = null;
    try {
      await probes.closeCamera();
    } catch (e, s) {
      reportNonFatal(e, s, during: 'closing the pre-show camera');
    }
  }

  // ------------------------------------------------------------ microphone

  Future<void> startMic() async {
    if (_disposed || mic == MicState.starting) return;
    mic = MicState.starting;
    notifyListeners();
    var status = await probes.permission(.mic);
    if (status == PermissionState.notDetermined || status == PermissionState.denied) {
      status = await probes.request(.mic);
    }
    if (_disposed) return;
    if (status == PermissionState.blocked ||
        status == PermissionState.denied ||
        status == PermissionState.restricted) {
      mic = _micFor(status, fallback: MicState.denied);
      trace('microphone not allowed', category: 'av', data: {'status': status.name});
      notifyListeners();
      return;
    }
    _releaseMic();
    mic = MicState.listening;
    _flatTimer = Timer(flatAfter, () {
      if (mic == MicState.listening) {
        mic = MicState.flat;
        trace('microphone silent', category: 'av');
        if (!_disposed) notifyListeners();
      }
    });
    _micSub = probes.micLevels().listen(
      (bars) {
        if (_disposed) return;
        micLevels.value = bars;
        final peak = bars.isEmpty ? 0.0 : bars.reduce((a, b) => a > b ? a : b);
        if (peak > 0.12 && (mic == MicState.listening || mic == MicState.flat)) {
          mic = MicState.heard;
          _flatTimer?.cancel();
          notifyListeners();
        }
      },
      onError: (Object _) async {
        // The permission may be what changed under us; otherwise the device failed.
        final now = await probes.permission(.mic);
        if (_disposed) return;
        _releaseMic();
        mic = now == PermissionState.granted || now == PermissionState.unknown
            ? MicState.failed
            : _micFor(now, fallback: MicState.failed);
        trace('microphone could not open', category: 'av', data: {'permission': now.name});
        notifyListeners();
      },
    );
    notifyListeners();
  }

  void _releaseMic() {
    _flatTimer?.cancel();
    _micSub?.cancel();
    _micSub = null;
    if (!_disposed) micLevels.value = const [];
  }

  // ----------------------------------------------------------------- sound

  Future<void> playChime() async {
    if (sound == SoundState.playing) return;
    sound = SoundState.playing;
    notifyListeners();
    final result = await probes.playChime();
    if (_disposed) return;
    sound = result == ChimeResult.played ? SoundState.confirm : SoundState.failed;
    trace('test chime', category: 'av', data: {'result': result.name});
    notifyListeners();
  }

  void heardChime(bool heard) {
    sound = heard ? SoundState.heard : SoundState.notHeard;
    if (!heard) _soundGaveUp = false;
    notifyListeners();
  }

  /// The person said no twice: stop asking, leave the row warn, never block.
  void giveUpOnSound() {
    _soundGaveUp = true;
    sound = SoundState.notHeard;
    notifyListeners();
  }

  // ------------------------------------------------------------ connection

  Future<void> measure() async {
    if (_disposed) return;
    line = LineState.measuring;
    notifyListeners();
    final info = await probes.networkInfo();
    final reading = await probes.measureLatency();
    if (_disposed) return;
    network = info;
    if (reading.failed) {
      line = info.transport == NetworkTransport.none ? LineState.offline : LineState.unreachable;
      latencyMs = null;
    } else {
      latencyMs = reading.ms;
      line = lineStateFor(reading.ms!);
    }
    trace(
      'connection read',
      category: 'network',
      data: {'state': line.name, 'ms': latencyMs, 'transport': info.transport.name},
    );
    notifyListeners();
  }

  // ----------------------------------------------------------------- actions

  /// A fix button was tapped. Actions that leave the sheet (`nights`) are the
  /// widget's to carry out: the controller has no router.
  Future<void> act(CheckId row, String action) async {
    trace('pre-show action', category: 'ui', data: {'row': row.name, 'action': action});
    switch ((row, action)) {
      case (.camera, 'allow') || (.camera, 'retry') || (.camera, 'restart'):
        await startCamera();
      case (.camera, 'settings'):
        await probes.openPermissionSettings(.camera);
      case (.camera, 'voice'):
        voiceOnly();
      case (.mic, 'allow') || (.mic, 'retry') || (.mic, 'restart'):
        await startMic();
      case (.mic, 'settings'):
        await probes.openPermissionSettings(.mic);
      case (.mic, 'listen-only'):
        _releaseMic();
        mic = MicState.idle;
        notifyListeners();
      case (.sound, 'play') || (.sound, 'again'):
        await playChime();
      case (.sound, 'yes'):
        heardChime(true);
      case (.sound, 'no'):
        sound == SoundState.notHeard ? giveUpOnSound() : heardChime(false);
      case (.connection, 'retry'):
        await measure();
      case (.connection, 'network'):
        await probes.openNetworkSettings();
      case (.connection, 'mobile-ok'):
        _mobileOk = true;
        notifyListeners();
      case (.connection, 'saver-ok'):
        _saverOk = true;
        notifyListeners();
      default:
        break;
    }
  }

  // ------------------------------------------------------------------ rows

  /// Nothing to take seats for while there is no connection at all.
  bool get offline => line == LineState.offline;

  List<CheckRowView> get rows => [
    _filmRow(),
    if (includeAv) ...[_camRow(), _micRow()],
    _soundRow(),
    _lineRow(),
  ];

  /// Every row is fine, or at worst neutral.
  bool get clean => !rows.any((r) => r.flagged);

  CheckRowView _filmRow() {
    final f = film();
    return switch (f.kind) {
      FilmKind.none => const CheckRowView(
        id: CheckId.film,
        title: 'The film',
        subtitle: 'Nobody has picked one yet',
        tone: RowTone.warn,
        fix: "Whoever planned the night can add one from Date nights, or you can pick together once you're in.",
        actions: [FixAction('nights', 'Open Date nights', primary: true)],
      ),
      FilmKind.link => const CheckRowView(
        id: CheckId.film,
        title: 'The film',
        subtitle: 'YouTube link attached',
        tone: RowTone.ok,
      ),
      FilmKind.fileReady => CheckRowView(
        id: CheckId.film,
        title: 'The film',
        subtitle: 'Ready on both sides',
        tone: RowTone.ok,
      ),
      FilmKind.fileUploading => CheckRowView(
        id: CheckId.film,
        title: 'The film',
        subtitle: f.mine
            ? 'Uploading ${f.percent}%. Keep the app open'
            : 'Still arriving on $partner\'s side · ${f.percent}%',
        tone: RowTone.warn,
        trail: RowTrail.progress,
        progress: f.percent / 100,
      ),
      FilmKind.fileStopped => CheckRowView(
        id: CheckId.film,
        title: 'The film',
        subtitle: 'Upload stalled at ${f.percent}%',
        tone: RowTone.bad,
        trail: RowTrail.progress,
        progress: f.percent / 100,
        fix: f.mine
            ? "The connection dropped mid-upload. What's sent so far is kept, and we pick up where we left off."
            : "$partner's upload stopped. It carries on when their connection is back.",
        actions: f.mine ? const [FixAction('nights', 'Open Date nights', primary: true)] : const [],
      ),
      FilmKind.local => CheckRowView(
        id: CheckId.film,
        title: 'The film',
        subtitle: f.name == null ? 'Local file' : 'Local file · ${f.name}',
        tone: RowTone.ok,
      ),
      FilmKind.youtubeInRoom => const CheckRowView(
        id: CheckId.film,
        title: 'The film',
        subtitle: 'YouTube video',
        tone: RowTone.ok,
      ),
    };
  }

  CheckRowView _camRow() {
    const id = CheckId.camera;
    const title = 'Camera';
    return switch (cam) {
      CamState.idle => const CheckRowView(
        id: id,
        title: title,
        subtitle: 'Tap to preview. We only ask when you do.',
        tone: RowTone.idle,
        fix: 'Nothing is sent. The preview stays on this device and stops when you close this.',
        actions: [
          FixAction('allow', 'Turn on camera', primary: true),
          FixAction('voice', 'Voice only'),
        ],
      ),
      CamState.starting => const CheckRowView(
        id: id,
        title: title,
        subtitle: 'Opening the camera…',
        tone: RowTone.busy,
      ),
      CamState.on => const CheckRowView(
        id: id,
        title: title,
        subtitle: 'You look good',
        tone: RowTone.ok,
        trail: RowTrail.thumb,
      ),
      CamState.denied => const CheckRowView(
        id: id,
        title: title,
        subtitle: 'Needs your OK to show a preview',
        tone: RowTone.bad,
        fix: 'We can ask once more.',
        actions: [
          FixAction('allow', 'Allow camera', primary: true),
          FixAction('voice', 'Voice only'),
        ],
      ),
      CamState.blocked => const CheckRowView(
        id: id,
        title: title,
        subtitle: "SyncTogether can't use your camera",
        tone: RowTone.bad,
        fix:
            'You said no earlier, and the system will not ask again. Change it in settings, then '
            'come straight back: this row checks again on its own.',
        actions: [
          FixAction('settings', 'Open settings', primary: true),
          FixAction('voice', 'Voice only'),
        ],
      ),
      CamState.restricted => const CheckRowView(
        id: id,
        title: title,
        subtitle: "This device doesn't allow it",
        tone: RowTone.warn,
        fix:
            'Screen Time, a school or work profile, or parental controls is switching the camera '
            "off. It isn't something this app can change.",
        actions: [FixAction('voice', 'Voice only', primary: true)],
      ),
      CamState.none => const CheckRowView(
        id: id,
        title: title,
        subtitle: 'No camera found on this device',
        tone: RowTone.warn,
        fix:
            'A Mac mini, a desktop with no webcam or a simulator has none. Plug one in and '
            "we'll pick it up.",
        actions: [
          FixAction('retry', 'Check again', primary: true),
          FixAction('voice', 'Voice only'),
        ],
      ),
      CamState.busy => const CheckRowView(
        id: id,
        title: title,
        subtitle: 'Busy: another app has it',
        tone: RowTone.bad,
        fix:
            'FaceTime, Zoom, a recording app or the system camera can hold the camera. Close it, '
            'then try again.',
        actions: [FixAction('retry', 'Try again', primary: true), FixAction('voice', 'Voice only')],
      ),
      CamState.stopped => const CheckRowView(
        id: id,
        title: title,
        subtitle: 'The camera stopped',
        tone: RowTone.bad,
        fix:
            'Something interrupted it: another app, a phone call, or the camera was unplugged. '
            'Your preview went dark.',
        actions: [
          FixAction('restart', 'Restart preview', primary: true),
          FixAction('voice', 'Voice only'),
        ],
      ),
      CamState.off => const CheckRowView(
        id: id,
        title: title,
        subtitle: 'Off · voice only tonight',
        tone: RowTone.idle,
        fix: 'Your seat shows your initial. You can turn the camera on any time in the room.',
        actions: [FixAction('allow', 'Turn on camera')],
      ),
      CamState.paused => const CheckRowView(
        id: id,
        title: title,
        subtitle: 'Paused while you were away',
        tone: RowTone.idle,
        fix:
            "We stop the camera and microphone whenever the app isn't in front, so nothing stays "
            'on in your pocket.',
        actions: [FixAction('restart', 'Restart preview', primary: true)],
      ),
    };
  }

  CheckRowView _micRow() {
    const id = CheckId.mic;
    const title = 'Microphone';
    return switch (mic) {
      MicState.idle => const CheckRowView(
        id: id,
        title: title,
        subtitle: 'Say something to test it',
        tone: RowTone.idle,
        trail: RowTrail.meter,
        fix:
            "We'll ask for the microphone when you tap. Nothing is recorded or sent; the bars "
            'just show that we can hear you.',
        actions: [FixAction('allow', 'Turn on microphone', primary: true)],
      ),
      MicState.starting => const CheckRowView(
        id: id,
        title: title,
        subtitle: 'Opening the microphone…',
        tone: RowTone.busy,
        trail: RowTrail.meter,
      ),
      MicState.listening => const CheckRowView(
        id: id,
        title: title,
        subtitle: 'Say something to test it',
        tone: RowTone.idle,
        trail: RowTrail.meter,
      ),
      MicState.heard => const CheckRowView(
        id: id,
        title: title,
        subtitle: 'We can hear you',
        tone: RowTone.ok,
        trail: RowTrail.meter,
      ),
      MicState.flat => const CheckRowView(
        id: id,
        title: title,
        subtitle: 'No sound for 5 seconds',
        tone: RowTone.warn,
        trail: RowTrail.meter,
        fix:
            'Say a few words. Still flat? Check these:\n'
            '· Is the mic muted (a switch on a headset or the keyboard)?\n'
            '· Is the right microphone chosen?\n'
            "· Is a Bluetooth headset you're wearing asleep?",
        actions: [FixAction('retry', 'Test again', primary: true)],
      ),
      MicState.denied => CheckRowView(
        id: id,
        title: title,
        subtitle: 'Needs your OK to hear you',
        tone: RowTone.bad,
        trail: RowTrail.meter,
        fix: 'We can ask once more. Without it $partner can\'t hear you in the room.',
        actions: const [
          FixAction('allow', 'Allow microphone', primary: true),
          FixAction('listen-only', 'Listen only'),
        ],
      ),
      MicState.blocked => CheckRowView(
        id: id,
        title: title,
        subtitle: "SyncTogether can't hear you",
        tone: RowTone.bad,
        trail: RowTrail.meter,
        fix:
            "Without it $partner can't hear you in the room. Turn it on in settings and this row "
            'will notice when you come back.',
        actions: const [
          FixAction('settings', 'Open settings', primary: true),
          FixAction('listen-only', 'Listen only'),
        ],
      ),
      MicState.restricted => const CheckRowView(
        id: id,
        title: title,
        subtitle: "This device doesn't allow it",
        tone: RowTone.warn,
        trail: RowTrail.meter,
        fix:
            'Screen Time, a school or work profile, or parental controls is switching the '
            "microphone off. It isn't something this app can change.",
        actions: [FixAction('listen-only', 'Listen only', primary: true)],
      ),
      MicState.failed => const CheckRowView(
        id: id,
        title: title,
        subtitle: "Couldn't open that microphone",
        tone: RowTone.warn,
        trail: RowTrail.meter,
        fix:
            'Another app may have it, or none is plugged in. A headset or a webcam with a '
            "microphone works, and we'll pick it up.",
        actions: [
          FixAction('retry', 'Try again', primary: true),
          FixAction('listen-only', 'Listen only'),
        ],
      ),
      MicState.paused => const CheckRowView(
        id: id,
        title: title,
        subtitle: 'Paused while you were away',
        tone: RowTone.idle,
        trail: RowTrail.meter,
        actions: [FixAction('restart', 'Restart', primary: true)],
      ),
    };
  }

  CheckRowView _soundRow() {
    const id = CheckId.sound;
    const title = 'Sound';
    return switch (sound) {
      SoundState.idle => const CheckRowView(
        id: id,
        title: title,
        subtitle: 'Play the test chime',
        tone: RowTone.idle,
        trail: RowTrail.playButton,
      ),
      SoundState.playing => const CheckRowView(
        id: id,
        title: title,
        subtitle: 'Playing…',
        tone: RowTone.busy,
      ),
      SoundState.confirm => const CheckRowView(
        id: id,
        title: title,
        subtitle: 'Did you hear the chime?',
        tone: RowTone.busy,
        fix: 'We played it on this device’s speaker or headphones.',
        actions: [FixAction('yes', 'Yes, I heard it', primary: true), FixAction('no', 'No')],
      ),
      SoundState.heard => const CheckRowView(
        id: id,
        title: title,
        subtitle: 'You can hear us',
        tone: RowTone.ok,
        trail: RowTrail.playButton,
      ),
      SoundState.notHeard => CheckRowView(
        id: id,
        title: title,
        subtitle: _soundGaveUp ? "Couldn't hear the chime" : "Let's find the sound",
        tone: RowTone.warn,
        trail: _soundGaveUp ? RowTrail.playButton : RowTrail.none,
        fix: _soundGaveUp
            ? null
            : '· Is the volume up? Press the volume key now.\n'
                  "· Are you on headphones or a Bluetooth speaker you're not wearing?\n"
                  '· Is the phone in a silent mode?',
        actions: _soundGaveUp ? const [] : const [FixAction('again', 'Play again', primary: true)],
      ),
      SoundState.failed => const CheckRowView(
        id: id,
        title: title,
        subtitle: "We couldn't play the chime",
        tone: RowTone.bad,
        fix:
            'Another app may have the audio, or the output device went away. Nothing about the '
            'film is affected.',
        actions: [FixAction('again', 'Try again', primary: true)],
      ),
    };
  }

  CheckRowView _lineRow() {
    const id = CheckId.connection;
    const title = 'Connection';
    final ms = latencyMs;
    final streaming = film().streams;
    return switch (line) {
      LineState.measuring => const CheckRowView(
        id: id,
        title: title,
        subtitle: 'Checking the line to the room…',
        tone: RowTone.busy,
      ),
      LineState.good => _goodLine(ms, streaming),
      LineState.slow => CheckRowView(
        id: id,
        title: title,
        subtitle: 'Slow · $ms ms to the room',
        tone: RowTone.warn,
        fix:
            'Playback and voice may lag. A few things usually help:\n'
            '· Move closer to your router, or switch to Wi-Fi\n'
            '· Close downloads and streaming on this network\n'
            '· Turn off a VPN',
        actions: const [
          FixAction('retry', 'Test again', primary: true),
          FixAction('network', 'Network settings'),
        ],
      ),
      LineState.verySlow => CheckRowView(
        id: id,
        title: title,
        subtitle: 'Very slow · $ms ms to the room',
        tone: RowTone.bad,
        fix:
            "This will be rough for voice and for staying in sync. You can still go in; we'll "
            'show a notice if it falls out of step.',
        actions: const [
          FixAction('retry', 'Test again', primary: true),
          FixAction('network', 'Network settings'),
        ],
      ),
      LineState.offline => const CheckRowView(
        id: id,
        title: title,
        subtitle: "You're offline",
        tone: RowTone.bad,
        fix:
            "Nothing here can work without a connection. We'll check again the moment one is back.",
        actions: [
          FixAction('retry', 'Try again', primary: true),
          FixAction('network', 'Network settings'),
        ],
      ),
      LineState.unreachable => const CheckRowView(
        id: id,
        title: title,
        subtitle: "Online, but can't reach the room",
        tone: RowTone.bad,
        fix:
            "The internet works, but the room server isn't answering. A VPN, a school or office "
            'network, or a Wi-Fi sign-in page often blocks it.',
        actions: [FixAction('retry', 'Try again', primary: true)],
      ),
    };
  }

  CheckRowView _goodLine(int? ms, bool streaming) {
    const id = CheckId.connection;
    final base = 'Good · $ms ms to the room';
    if (network.saver && !_saverOk) {
      return CheckRowView(
        id: id,
        title: 'Connection',
        subtitle: 'Data Saver may slow things down',
        tone: RowTone.warn,
        fix:
            'Low Data Mode or Data Saver limits background traffic, which can hold back voice '
            'and sync.',
        actions: const [
          FixAction('network', 'Open settings', primary: true),
          FixAction('saver-ok', 'Carry on'),
        ],
      );
    }
    if (streaming && network.transport == NetworkTransport.cellular && !_mobileOk) {
      return CheckRowView(
        id: id,
        title: 'Connection',
        subtitle: '$base, on mobile data',
        tone: RowTone.warn,
        fix:
            'Streaming a film for two hours can use roughly 1 to 3 GB, depending on the quality. '
            'Wi-Fi would be gentler on your plan.',
        actions: const [
          FixAction('mobile-ok', 'Use mobile data', primary: true),
          FixAction('retry', 'Check again'),
        ],
      );
    }
    return CheckRowView(id: id, title: 'Connection', subtitle: base, tone: RowTone.ok);
  }
}
