import 'dart:async';

import 'package:flutter/foundation.dart';

import '../av/system_permissions.dart';
import '../diagnostics.dart';
import '../player/recent_format.dart';
import '../player/youtube/youtube_block.dart';
import '../rooms/open_failure.dart';
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

/// Where the Remind button is: nothing sent yet, in flight, or what came of it.
enum NudgeState { idle, sending, sent, throttled, notNow, failed }

/// Whether this connection can carry the film at its own bitrate. Only asked
/// for a streamed night file, and only ever answered in words: the file is never
/// transcoded or lowered to fit.
enum FilmFlow { unknown, testing, retesting, fine, mayBuffer, startAnyway, gone }

/// The server says the night's staged film no longer exists (it expired or was
/// taken down). Thrown by the throughput probe so the sheet can say so.
class FilmGoneException implements Exception {
  const FilmGoneException();
}

/// How much faster than the film's bitrate the link has to measure before the
/// film is called safe: a stream needs headroom for the link's own wobble.
const double kFilmHeadroom = 1.5;

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

enum FilmKind {
  none,
  link,
  fileReady,
  fileUploading,

  /// The planner's upload is held until Wi-Fi: they are on mobile data.
  fileWaitingWifi,
  fileStopped,
  local,
  youtubeInRoom,

  /// This device's remembered copy is gone (moved, deleted, a drive unplugged).
  copyMissing,

  /// Same name, a different length: two cuts that will drift apart.
  differentCut,

  /// This device tried the room's file and could not open it.
  cantOpen,

  /// YouTube won't play this video (embedding off, removed or private).
  videoBlocked,
}

/// The last part of a path: the row shows a file's name, never where it lived.
String baseName(String path) => path.split(RegExp(r'[/\\]')).last;

class FilmCheck {
  const FilmCheck(
    this.kind, {
    this.percent = 0,
    this.name,
    this.mine = false,
    this.bitrateBps,
    this.sharedCopy = false,
    this.yours,
    this.theirs,
    this.theirLabel,
    this.openFailure,
    this.youtubeBlock,
  });

  /// The host uploaded a copy this person can stream instead.
  final bool sharedCopy;

  /// [FilmKind.differentCut]: this device's length, the room's length, and who
  /// the room's copy is (a name, or null for "the room").
  final Duration? yours;
  final Duration? theirs;
  final String? theirLabel;

  /// [FilmKind.cantOpen]: what went wrong, in three kinds.
  final OpenFailure? openFailure;

  /// [FilmKind.videoBlocked]: why YouTube refused it.
  final YouTubeBlock? youtubeBlock;

  final FilmKind kind;

  /// What the file needs to stream, in bits per second, when known.
  final double? bitrateBps;
  final int percent;
  final String? name;

  /// This person is the one uploading it.
  final bool mine;

  /// A date night's film, as both people read it now.
  factory FilmCheck.forNight(
    DateNight night,
    DateTime now, {
    required bool mine,
    bool waitingForWifi = false,
  }) {
    final view = fileViewOf(night, now);
    return switch (view.stage) {
      FileStage.ready => FilmCheck(
        FilmKind.fileReady,
        name: night.fileName,
        percent: 100,
        mine: mine,
        bitrateBps: night.fileBitrateBps,
      ),
      FileStage.uploading || FileStage.unfinished => FilmCheck(
        mine && waitingForWifi ? FilmKind.fileWaitingWifi : FilmKind.fileUploading,
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
      kind == FilmKind.fileWaitingWifi ||
      kind == FilmKind.link ||
      kind == FilmKind.youtubeInRoom;
}

// ---------------------------------------------------------------------------
// Device probes, behind an interface so the sheet is testable with no hardware
// ---------------------------------------------------------------------------

enum CameraOpen { ok, none, busy, denied, failed }

enum ChimeResult { played, failed }

enum AudioEventKind {
  /// A call, Siri or another app took the microphone.
  interrupted,

  /// It is free again.
  resumed,

  /// The input the system uses changed (a headset in or out).
  input,

  /// The output volume or where the sound goes changed (carries [AudioEvent.state]).
  state,
}

enum OutputKind { builtIn, bluetooth, airplay, wired, other }

/// Where the sound goes and how loud the system will make it.
class AudioState {
  const AudioState({
    this.volume,
    this.outputName,
    this.output = OutputKind.builtIn,
    this.canUseBuiltIn = true,
  });

  /// 0..1, or null where the system volume cannot be read.
  final double? volume;
  final String? outputName;
  final OutputKind output;

  /// This device has speakers of its own to go back to.
  final bool canUseBuiltIn;

  @override
  bool operator ==(Object other) =>
      other is AudioState &&
      other.volume == volume &&
      other.outputName == outputName &&
      other.output == output &&
      other.canUseBuiltIn == canUseBuiltIn;

  @override
  int get hashCode => Object.hash(volume, outputName, output, canUseBuiltIn);
}

/// Something the platform said about the audio route.
class AudioEvent {
  const AudioEvent(
    this.kind, {
    this.name,
    this.builtIn = true,
    this.bluetooth = false,
    this.canUseBuiltIn = true,
    this.state,
  });

  final AudioEventKind kind;

  /// [AudioEventKind.state]: what the system says now.
  final AudioState? state;

  /// [AudioEventKind.input]: what the system now listens through.
  final String? name;
  final bool builtIn;
  final bool bluetooth;

  /// This device has a microphone of its own to go back to (a Mac mini has none).
  final bool canUseBuiltIn;
}

/// What a person calls a camera. Phones name theirs for the machine ("Camera 0,
/// Facing front, Orientation 270"), so the facing is all that is kept; a webcam's
/// own name ("Brio 4K") already reads well.
String cameraName(String raw) {
  final r = raw.trim();
  if (r.isEmpty) return 'Camera';
  final facing = RegExp(r'facing\s+(front|back)', caseSensitive: false).firstMatch(r);
  if (facing == null) return r;
  return facing.group(1)!.toLowerCase() == 'front' ? 'Front camera' : 'Back camera';
}

/// One camera this device can open (a phone's front and back, a Mac's webcams).
class CameraChoice {
  const CameraChoice(this.id, this.label);
  final String id;
  final String label;
}

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

  /// Every camera that can be opened now. One is not a choice.
  Future<List<CameraChoice>> cameras();

  /// The camera the preview is showing, or null when it is off.
  String? get cameraId;

  /// Switches the preview to [id] and remembers it with the other AV preferences
  /// (the room opens the same camera).
  Future<CameraOpen> useCamera(String id);

  /// The person chose where the sound goes: this device's own speakers, or the
  /// output [name] the system picked. Saved as the preferred output.
  Future<void> chooseOutput({required bool builtIn, String? name});

  /// Fires when a camera is plugged in or removed.
  Stream<void> get camerasChanged;

  /// Interruptions and route changes, for as long as the sheet listens.
  Stream<AudioEvent> get audioEvents;

  /// The person chose which microphone to keep: this device's own, or the
  /// headset [name] the system switched to. Saved as the preferred device.
  Future<void> chooseInput({required bool builtIn, String? name});

  /// Fires if the camera stops by itself (unplugged, taken by another app).
  Stream<void> get cameraEnded;

  /// Bar levels 0..1; errors if the microphone cannot be opened.
  Stream<List<double>> micLevels();
  Future<ChimeResult> playChime();
  Future<LatencyReading> measureLatency();

  /// What this connection can carry from where the night's film is stored, in
  /// bits per second, or null when it could not be measured. Reads a few ranged
  /// samples of the real file; nothing is played, cached or kept.
  Future<double?> measureNightThroughput(String nightId);
}

// ---------------------------------------------------------------------------
// States
// ---------------------------------------------------------------------------

enum CamState { idle, starting, on, denied, blocked, restricted, none, busy, stopped, off, paused }

enum MicState {
  idle,

  /// A call, Siri or another app has the microphone. Resumes by itself.
  interrupted,
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
    this.partnerOnline = _alwaysOnline,
    this.nudge,
    this.measureFilm,
    this.useMobileData,
    this.thisDevice = 'this device',
    bool? windows,
  }) : windows = windows ?? (!kIsWeb && defaultTargetPlatform == TargetPlatform.windows);

  static bool _alwaysOnline() => true;

  final PreShowProbes probes;

  /// Read each time the rows are built, so a night that changes under the sheet
  /// (an upload advancing, a film attached) shows at once.
  final FilmCheck Function() film;

  /// A room's own check has no camera or microphone rows: the room's bar owns them.
  final bool includeAv;
  final String partner;

  /// Whether the other person is on right now. Read each time the rows are
  /// built. A film that is ready on this side is only *neutral* until they are:
  /// nothing is wrong, there is just nobody to confirm it with.
  final bool Function() partnerOnline;

  /// Sends the other person one reminder (a push). Null where there is no one to
  /// remind: a room's own check.
  final Future<NudgeResult> Function()? nudge;
  NudgeState nudgeState = NudgeState.idle;

  /// What this connection can carry, in bits per second (null: could not tell).
  /// Null here means no throughput check at all: a room's own check, and a film
  /// that is not a streamed night file.
  final Future<double?> Function()? measureFilm;

  /// Lets this person's held upload spend mobile data (the planner said so).
  final void Function()? useMobileData;

  /// What to call the device in "Use this iPhone".
  final String thisDevice;

  /// Windows has one privacy switch for desktop apps, not a prompt: a blocked
  /// camera or microphone is explained in its own words (board 94c H).
  final bool windows;

  StreamSubscription<AudioEvent>? _audioSub;

  /// The system's volume and output, as last said; null until it speaks.
  AudioState? audio;

  /// The output the person already answered for (so it is not asked twice).
  String? _outputAnswered;

  /// The headset the system switched to, until the person answers.
  String? headset;
  bool headsetIsBluetooth = false;
  bool _canUseBuiltIn = true;
  FilmFlow filmFlow = FilmFlow.unknown;

  /// The file name the server said is gone, so a newly attached film is not
  /// judged by the old one's verdict.
  String? _goneName;
  double? filmCapacityBps;

  /// Rebuild the sheet after something outside the controller changed (the
  /// partner's presence). Not a probe: nothing is measured.
  void refresh() {
    if (!_disposed) notifyListeners();
  }

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
  StreamSubscription<void>? _camChangeSub;

  /// The cameras on offer while the preview is on, and which one it shows.
  List<CameraChoice> cameraChoices = const [];
  String? cameraId;
  Timer? _flatTimer;
  bool _disposed = false;

  /// How long a live microphone may stay silent before we say so.
  static const flatAfter = Duration(seconds: 5);

  // ------------------------------------------------------------- lifecycle

  /// Reads where everything stands. Asks nothing: a permission that is already
  /// granted starts its preview, one that is not waits for a tap.
  Future<void> start() async {
    unawaited(measure());
    unawaited(testFilm());
    if (!includeAv) return;
    _audioSub = probes.audioEvents.listen(_onAudioEvent);
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
    _audioSub?.cancel();
    _audioSub = null;
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
    cam = _camAfter(opened);
    trace('camera preview', category: 'av', data: {'result': opened.name});
    if (cam == CamState.on) {
      unawaited(_loadCameras());
      await _camChangeSub?.cancel();
      _camChangeSub = probes.camerasChanged.listen((_) => unawaited(_loadCameras()));
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

  CamState _camAfter(CameraOpen opened) => switch (opened) {
    CameraOpen.ok => CamState.on,
    CameraOpen.none => CamState.none,
    CameraOpen.busy => CamState.busy,
    CameraOpen.denied => CamState.blocked,
    CameraOpen.failed => CamState.busy,
  };

  Future<void> _loadCameras() async {
    try {
      final list = await probes.cameras();
      if (_disposed || cam != CamState.on) return;
      cameraChoices = list;
      cameraId = probes.cameraId;
      notifyListeners();
    } catch (e, s) {
      reportNonFatal(e, s, during: 'listing the pre-show cameras');
    }
  }

  /// The person picked another camera: the preview follows at once, and the
  /// choice is kept for the room.
  Future<void> selectCamera(String id) async {
    if (_disposed || cam != CamState.on || id == cameraId) return;
    final opened = await probes.useCamera(id);
    if (_disposed) return;
    trace('camera chosen', category: 'av', data: {'result': opened.name});
    if (opened == CameraOpen.ok) {
      cameraId = probes.cameraId ?? id;
    } else {
      cam = _camAfter(opened);
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
    unawaited(_camChangeSub?.cancel());
    _camChangeSub = null;
    cameraChoices = const [];
    cameraId = null;
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

  bool get _micRunning =>
      mic == MicState.listening ||
      mic == MicState.heard ||
      mic == MicState.flat ||
      mic == MicState.starting;

  void _onAudioEvent(AudioEvent e) {
    if (_disposed) return;
    switch (e.kind) {
      case AudioEventKind.interrupted:
        if (!_micRunning) return;
        _releaseMic();
        mic = MicState.interrupted;
        trace('microphone taken by something else', category: 'av');
        notifyListeners();
      case AudioEventKind.resumed:
        if (mic != MicState.interrupted) return;
        trace('microphone free again', category: 'av');
        unawaited(startMic());
      case AudioEventKind.state:
        final s = e.state;
        if (s == null || s == audio) return;
        final was = audio;
        audio = s;
        if (was != null && (was.outputName != s.outputName || was.output != s.output)) {
          trace(
            'sound output changed',
            category: 'av',
            data: {'kind': s.output.name, 'name': s.outputName},
          );
        }
        if (was != null && (was.volume ?? 1) > 0 && (s.volume ?? 1) <= 0) {
          trace('system volume is zero', category: 'av');
        }
        notifyListeners();
      case AudioEventKind.input:
        // Only said while the meter is on: before that there is nothing to
        // have switched from.
        if (!_micRunning) return;
        final was = headset;
        headset = e.builtIn ? null : (e.name ?? 'a headset');
        headsetIsBluetooth = e.bluetooth;
        _canUseBuiltIn = e.canUseBuiltIn;
        trace(
          'microphone input changed',
          category: 'av',
          data: {'builtIn': e.builtIn, 'bluetooth': e.bluetooth, 'name': e.name},
        );
        notifyListeners();
        // The meter follows the new input, quietly.
        if (was != headset || !e.builtIn) unawaited(startMic());
    }
  }

  Future<void> _chooseInput({required bool builtIn}) async {
    final name = headset;
    headset = null;
    notifyListeners();
    try {
      await probes.chooseInput(builtIn: builtIn, name: name);
    } catch (e, s) {
      reportNonFatal(e, s, during: 'choosing the microphone');
    }
    trace('microphone kept', category: 'av', data: {'builtIn': builtIn});
    if (!_disposed && _micRunning) unawaited(startMic());
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

  /// Streams a sample of the film from where this person would stream it and
  /// compares it with what the film needs. Quiet unless the answer is "may
  /// buffer": a first test never changes the row while it runs.
  Future<void> testFilm() async {
    final f = film();
    final need = f.bitrateBps;
    final measure = measureFilm;
    if (measure == null || f.kind != FilmKind.fileReady || need == null) return;
    if (filmFlow == FilmFlow.testing || filmFlow == FilmFlow.retesting) return;
    final again = filmFlow == FilmFlow.mayBuffer || filmFlow == FilmFlow.startAnyway;
    filmFlow = again ? FilmFlow.retesting : FilmFlow.testing;
    notifyListeners();
    double? bps;
    try {
      bps = await measure();
    } on FilmGoneException {
      if (_disposed) return;
      filmFlow = FilmFlow.gone;
      _goneName = f.name;
      trace('night film is gone from storage', category: 'media');
      notifyListeners();
      return;
    } catch (_) {
      // The probe already reported it. No reading is not a verdict.
      bps = null;
    }
    if (_disposed) return;
    // A retest that got no reading keeps the last number it had.
    filmCapacityBps = bps ?? filmCapacityBps;
    filmFlow = bps == null
        ? (again ? FilmFlow.mayBuffer : FilmFlow.unknown)
        : bps < need * kFilmHeadroom
        ? FilmFlow.mayBuffer
        : FilmFlow.fine;
    trace(
      'film throughput judged',
      category: 'media',
      data: {
        'verdict': filmFlow.name,
        'needMbps': (need / 1e6).toStringAsFixed(1),
        'haveMbps': bps == null ? null : (bps / 1e6).toStringAsFixed(1),
      },
    );
    notifyListeners();
  }

  // ----------------------------------------------------------------- actions

  /// A fix button was tapped. Actions that leave the sheet (`nights`) are the
  /// widget's to carry out: the controller has no router.
  Future<void> act(CheckId row, String action) async {
    trace('pre-show action', category: 'ui', data: {'row': row.name, 'action': action});
    switch ((row, action)) {
      case (.film, 'nudge'):
        await _sendNudge();
      case (.film, 'find-file') ||
          (.film, 'use-shared') ||
          (.film, 'keep-mine') ||
          (.film, 'pick-youtube'):
        // These leave the sheet: the widget closes it and the room carries them out.
        break;
      case (.film, 'use-mobile-data'):
        useMobileData?.call();
        notifyListeners();
      case (.film, 'film-retest'):
        await testFilm();
      case (.film, 'film-anyway'):
        filmFlow = FilmFlow.startAnyway;
        notifyListeners();
      case (.camera, 'allow') || (.camera, 'retry') || (.camera, 'restart'):
        await startCamera();
      case (.camera, 'settings'):
        await probes.openPermissionSettings(.camera);
      case (.camera, final String a) when a.startsWith('cam:'):
        await selectCamera(a.substring(4));
      case (.camera, 'voice'):
        voiceOnly();
      case (.mic, 'allow') || (.mic, 'retry') || (.mic, 'restart'):
        await startMic();
      case (.mic, 'settings'):
        await probes.openPermissionSettings(.mic);
      case (.sound, 'out-builtin') || (.sound, 'out-keep'):
        final name = audio?.outputName;
        _outputAnswered = name;
        notifyListeners();
        try {
          await probes.chooseOutput(builtIn: action == 'out-builtin', name: name);
        } catch (e, s) {
          reportNonFatal(e, s, during: 'choosing the sound output');
        }
        trace('sound output answered', category: 'av', data: {'builtIn': action == 'out-builtin'});
      case (.mic, 'mic-builtin'):
        await _chooseInput(builtIn: true);
      case (.mic, 'mic-keep'):
        await _chooseInput(builtIn: false);
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

  Future<void> _sendNudge() async {
    final send = nudge;
    if (send == null || nudgeState == NudgeState.sending) return;
    nudgeState = NudgeState.sending;
    notifyListeners();
    try {
      final result = await send();
      nudgeState = switch (result) {
        NudgeResult.sent => NudgeState.sent,
        NudgeResult.throttled => NudgeState.throttled,
        NudgeResult.notNow => NudgeState.notNow,
      };
    } catch (_) {
      // The service already reported it; the person is told in words, once.
      nudgeState = NudgeState.failed;
    }
    notifyListeners();
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

  String _nudgeCopy() => switch (nudgeState) {
    NudgeState.sent =>
      "Reminder sent. $partner's own sheet shows the film the moment they open it.",
    NudgeState.throttled => 'You reminded $partner a moment ago. One is enough for now.',
    NudgeState.notNow =>
      "A reminder only makes sense around the night itself, so that one didn't go.",
    NudgeState.failed => "Couldn't send that. Check your connection and try again.",
    _ =>
      "$partner hasn't opened the app yet. That is normal ahead of a date night. "
          'A reminder is one gentle push.',
  };

  static String _mbps(double bps) {
    final m = bps / 1e6;
    return m >= 10 ? m.round().toString() : m.toStringAsFixed(1);
  }

  /// The warning for a film this connection may not carry. Never offers a lower
  /// quality: the file is the file.
  CheckRowView? _bufferRow(FilmCheck f) {
    final need = f.bitrateBps;
    if (f.kind != FilmKind.fileReady || need == null) return null;
    if (filmFlow == FilmFlow.retesting) {
      return const CheckRowView(
        id: CheckId.film,
        title: 'The film',
        subtitle: 'Testing your connection again…',
        tone: RowTone.busy,
      );
    }
    final have = filmCapacityBps;
    if (filmFlow == FilmFlow.startAnyway) {
      return const CheckRowView(
        id: CheckId.film,
        title: 'The film',
        subtitle: 'Ready · may pause to catch up',
        tone: RowTone.idle,
      );
    }
    if (filmFlow != FilmFlow.mayBuffer) return null;
    return CheckRowView(
      id: CheckId.film,
      title: 'The film',
      subtitle: 'This film may stutter on your connection',
      tone: RowTone.warn,
      fix:
          'It needs about ${_mbps(need)} Mbps and this connection managed '
          '${have == null ? 'less' : 'about ${_mbps(have)} Mbps'}. It plays at full '
          'quality, so it may pause now and then to catch up. A better connection '
          'fixes it; we never lower the picture.',
      actions: const [
        FixAction('film-anyway', 'Start anyway', primary: true),
        FixAction('film-retest', 'Test again'),
      ],
    );
  }

  static String _cut(Duration a, Duration b) {
    final x = formatRuntime(a);
    return x == formatRuntime(b) ? formatTimecode(a) : x;
  }

  CheckRowView _filmRow() {
    final f = film();
    if (filmFlow == FilmFlow.gone && f.kind == FilmKind.fileReady && f.name == _goneName) {
      return _goneRow(f);
    }
    final buffer = _bufferRow(f);
    if (buffer != null) return buffer;
    return switch (f.kind) {
      FilmKind.copyMissing => CheckRowView(
        id: CheckId.film,
        title: 'The film',
        subtitle: f.name == null ? "We can't find your copy" : "We can't find ${baseName(f.name!)}",
        tone: RowTone.warn,
        fix: "It may have been moved, renamed or deleted, or it lived on a drive that isn't connected.",
        actions: [
          const FixAction('find-file', 'Find the file', primary: true),
          if (f.sharedCopy) const FixAction('use-shared', 'Use the shared copy'),
        ],
      ),
      FilmKind.differentCut => _differentCutRow(f),
      FilmKind.cantOpen => _cantOpenRow(f),
      FilmKind.videoBlocked => _videoBlockedRow(f),
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
      FilmKind.fileReady when !partnerOnline() => CheckRowView(
        id: CheckId.film,
        title: 'The film',
        subtitle: 'Ready on your side · waiting for $partner',
        tone: RowTone.idle,
        fix: nudge == null ? null : _nudgeCopy(),
        actions:
            nudge == null || nudgeState == NudgeState.sent || nudgeState == NudgeState.throttled
            ? const []
            : [
                FixAction(
                  'nudge',
                  nudgeState == NudgeState.sending ? 'Sending…' : 'Remind $partner',
                  primary: true,
                ),
              ],
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
      FilmKind.fileWaitingWifi => CheckRowView(
        id: CheckId.film,
        title: 'The film',
        subtitle: 'Uploading ${f.percent}% · waiting for Wi-Fi',
        tone: RowTone.warn,
        trail: RowTrail.progress,
        progress: f.percent / 100,
        fix:
            "You're on mobile data, so the upload is paused. It carries on by itself "
            'when Wi-Fi is back, or you can use data now. Keep the app open either way.',
        actions: useMobileData == null
            ? const []
            : const [FixAction('use-mobile-data', 'Use mobile data', primary: true)],
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

  /// The staged film no longer exists. The night survives; only the file is
  /// gone, and a file cannot be added to a planned night, so the planner's way
  /// back is a new night (or a YouTube link on this one).
  CheckRowView _goneRow(FilmCheck f) => CheckRowView(
    id: CheckId.film,
    title: 'The film',
    subtitle: "This film isn't available anymore",
    tone: RowTone.bad,
    fix: f.mine
        ? 'Uploaded films are removed after a while, or when the host takes them down. '
              'The date night itself is still here. Plan it again with the film, or '
              'switch it to a YouTube link.'
        : 'Uploaded films are removed after a while, or when the host takes them down. '
              'The date night itself is still here. Ask $partner to upload it again.',
    actions: f.mine ? const [FixAction('nights', 'Open Date nights', primary: true)] : const [],
  );

  /// The video is the problem, so it is the same on every device; the fix is a
  /// different video or a file, never a workaround.
  CheckRowView _videoBlockedRow(FilmCheck f) {
    final (subtitle, fix) = switch (f.youtubeBlock ?? YouTubeBlock.unavailable) {
      YouTubeBlock.embeddingOff => (
        "YouTube won't play this one here",
        "Its owner turned off playing outside YouTube. That's their setting, so it "
            "will be the same for $partner. It isn't your connection.",
      ),
      YouTubeBlock.unavailable => (
        'This video is gone',
        "It was removed or made private. That's on YouTube's side and the same for "
            '$partner.',
      ),
    };
    return CheckRowView(
      id: CheckId.film,
      title: 'The film',
      subtitle: subtitle,
      tone: RowTone.bad,
      fix: fix,
      actions: const [
        FixAction('pick-youtube', 'Pick another video', primary: true),
        FixAction('find-file', 'Choose a local file'),
      ],
    );
  }

  /// Never offers to convert: every action is a different copy.
  CheckRowView _cantOpenRow(FilmCheck f) {
    final (subtitle, fix) = switch (f.openFailure ?? OpenFailure.stalled) {
      OpenFailure.format => (
        "This format won't play here",
        "This device can't decode the video inside the file. We never convert your "
            'film, so the picture and sound stay exactly as they were.',
      ),
      OpenFailure.unreadable => (
        "We can't read this file",
        "The system wouldn't let SyncTogether open it. It may have moved to a "
            "protected folder, or lived on a drive that isn't connected.",
      ),
      OpenFailure.stalled => (
        "This file won't start",
        'It never reported a length. A damaged download, or a file on a slow drive, '
            'does this. A different copy usually fixes it.',
      ),
    };
    return CheckRowView(
      id: CheckId.film,
      title: 'The film',
      subtitle: subtitle,
      tone: RowTone.bad,
      fix: fix,
      actions: [
        if (f.sharedCopy) const FixAction('use-shared', 'Use the shared copy', primary: true),
        FixAction('find-file', 'Pick another file', primary: !f.sharedCopy),
      ],
    );
  }

  CheckRowView _differentCutRow(FilmCheck f) {
    final mine = f.yours ?? Duration.zero;
    final theirs = f.theirs ?? Duration.zero;
    final who = f.theirLabel ?? 'the room';
    final their = f.theirLabel == null ? "the room's" : "${f.theirLabel}'s";
    return CheckRowView(
      id: CheckId.film,
      title: 'The film',
      subtitle: 'Yours is ${_cut(mine, theirs)}, $their is ${_cut(theirs, mine)}',
      tone: RowTone.warn,
      fix:
          "Two different cuts will drift apart in the film's first minutes. We never "
          're-encode your file; pick which one everyone will watch.',
      actions: [
        if (f.sharedCopy)
          FixAction(
            'use-shared',
            f.theirLabel == null ? 'Use the shared copy' : "Use $who's copy",
            primary: true,
          )
        else
          const FixAction('find-file', 'Pick another', primary: true),
        const FixAction('keep-mine', 'Keep mine'),
      ],
    );
  }

  CheckRowView _camOnRow() {
    CameraChoice? mine;
    for (final c in cameraChoices) {
      if (c.id == cameraId) mine = c;
    }
    final many = cameraChoices.length > 1 && mine != null;
    return CheckRowView(
      id: CheckId.camera,
      title: 'Camera',
      subtitle: mine == null ? 'You look good' : '${mine.label} · you look good',
      tone: RowTone.ok,
      trail: RowTrail.thumb,
      fix: many ? '${mine.label} is selected. Switch if the picture is wrong.' : null,
      actions: many
          ? [
              for (final c in cameraChoices)
                if (c.id != cameraId) FixAction('cam:${c.id}', c.label),
            ]
          : const [],
    );
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
      CamState.on => _camOnRow(),
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
      CamState.blocked when windows => const CheckRowView(
        id: id,
        title: title,
        subtitle: 'Windows is blocking the camera',
        tone: RowTone.bad,
        fix:
            'Turn on "Let desktop apps access your camera" in Settings › Privacy & security › '
            'Camera. It applies to the microphone too, and this row checks again when you come '
            'back.',
        actions: [
          FixAction('settings', 'Open Settings', primary: true),
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
    final h = headset;
    if (h != null && (mic == MicState.listening || mic == MicState.heard || mic == MicState.flat)) {
      return CheckRowView(
        id: CheckId.mic,
        title: 'Microphone',
        subtitle: 'Switched to $h',
        tone: RowTone.idle,
        trail: RowTrail.meter,
        fix: headsetIsBluetooth
            ? "Bluetooth headsets cut call quality. If $partner says you sound muffled, pick "
                  "$thisDevice's own mic instead."
            : _canUseBuiltIn
            ? "Your microphone changed. If $partner says you sound off, pick $thisDevice's own "
                  'mic instead.'
            : 'Your microphone changed. We use it from now on.',
        actions: [
          if (_canUseBuiltIn) FixAction('mic-builtin', 'Use $thisDevice', primary: true),
          FixAction('mic-keep', 'Keep $h', primary: !_canUseBuiltIn),
        ],
      );
    }
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
      MicState.interrupted => CheckRowView(
        id: id,
        title: title,
        subtitle: 'Paused: something else is using it',
        tone: RowTone.idle,
        trail: RowTrail.meter,
        fix:
            "A phone call, Siri or another app has the microphone. We'll restart the meter "
            "when it's free.",
        actions: const [FixAction('restart', 'Restart now', primary: true)],
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
      MicState.blocked when windows => CheckRowView(
        id: id,
        title: title,
        subtitle: 'Windows is blocking the microphone',
        tone: RowTone.bad,
        trail: RowTrail.meter,
        fix:
            'Turn on "Let desktop apps access your microphone" in Settings › Privacy & security '
            "› Microphone. Without it $partner can't hear you; this row checks again when you "
            'come back.',
        actions: const [
          FixAction('settings', 'Open Settings', primary: true),
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

  CheckRowView? _soundHeadsUp() {
    final a = audio;
    if (a == null || sound == SoundState.playing || sound == SoundState.heard) return null;
    final v = a.volume;
    if (v != null && v <= 0.001) {
      return const CheckRowView(
        id: CheckId.sound,
        title: 'Sound',
        subtitle: 'Your volume is at zero',
        tone: RowTone.warn,
        trail: RowTrail.playButton,
        fix: 'Turn it up with the volume keys, then play the chime again.',
        actions: [FixAction('play', 'Play the chime', primary: true)],
      );
    }
    final name = a.outputName;
    if (a.output != OutputKind.builtIn &&
        name != null &&
        name != _outputAnswered &&
        (sound == SoundState.idle || sound == SoundState.notHeard)) {
      final tag = switch (a.output) {
        OutputKind.bluetooth => ' (Bluetooth)',
        OutputKind.airplay => ' (AirPlay)',
        _ => '',
      };
      return CheckRowView(
        id: CheckId.sound,
        title: 'Sound',
        subtitle: 'Playing on $name$tag',
        tone: RowTone.idle,
        trail: RowTrail.playButton,
        fix: a.output == OutputKind.bluetooth || a.output == OutputKind.airplay
            ? "A Bluetooth speaker or AirPlay target is connected. If that isn't what you meant, "
                  'switch back.'
            : "Sound is going to a connected device. If that isn't what you meant, switch back.",
        actions: [
          if (a.canUseBuiltIn) FixAction('out-builtin', 'Use $thisDevice', primary: true),
          FixAction('out-keep', 'Keep $name', primary: !a.canUseBuiltIn),
        ],
      );
    }
    return null;
  }

  CheckRowView _soundRow() {
    final headsUp = _soundHeadsUp();
    if (headsUp != null) return headsUp;
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
