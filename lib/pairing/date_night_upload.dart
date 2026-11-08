import 'dart:async';

import 'package:flutter/foundation.dart';

import '../diagnostics.dart';
import '../player/local_video.dart';
import '../profile/profile_service.dart';
import '../rooms/media_sharing_service.dart';
import 'pair_models.dart';
import 'pair_service.dart';

enum UploadPhase { uploading, stopped, finished }

/// One date night's upload while this app is the one doing it. What the planner
/// sees live (the percentage, the time left); the partner sees the night's own
/// `uploadBytes`, which [DateNightUploader] reports every few seconds.
class DateNightUpload extends ChangeNotifier {
  DateNightUpload({
    required this.nightId,
    required this.video,
    required this.token,
    required this.session,
  });

  final String nightId;
  final LocalVideo video;
  CancellationToken token;
  StagedUploadSession session;

  int bytes = 0;
  int total = 0;
  int etaSeconds = 0;
  UploadPhase phase = UploadPhase.uploading;
  DateTime? _lastReport;

  double get fraction => total > 0 ? (bytes / total).clamp(0.0, 1.0) : 0.0;

  void _changed() => notifyListeners();
}

/// Uploads the file a date night is for, ahead of the night, and keeps going
/// after the plan form has closed. It is foreground work: the app has to stay open
/// until the night says Ready, and the screen says so.
///
/// It uses the same staged-upload slot as the lobby's pre-upload (size caps,
/// weekly allowance, abort penalties, clean-up all unchanged), with two
/// differences: a failure leaves the slot where it is so the same upload can
/// carry on from the parts the server already has, and the slot is adopted by the
/// night as soon as it exists, so nothing is promised before it was granted.
class DateNightUploader extends ChangeNotifier {
  DateNightUploader({
    MediaSharingService? media,
    PairService Function()? pair,
    this.reportEvery = const Duration(seconds: 4),
  }) : _mediaOverride = media,
       _pairOverride = pair;

  static DateNightUploader instance = DateNightUploader();

  final MediaSharingService? _mediaOverride;
  final PairService Function()? _pairOverride;

  /// How often progress is sent to the night. A missed report only leaves the
  /// partner's percentage a little behind; the upload itself never waits on it.
  final Duration reportEvery;

  MediaSharingService? _lazyMedia;
  MediaSharingService get _media => _mediaOverride ?? (_lazyMedia ??= MediaSharingService());
  PairService get _pair => _pairOverride?.call() ?? PairService.instance;

  final _active = <String, DateNightUpload>{};

  /// The live upload for [nightId], if this device is running it.
  DateNightUpload? forNight(String nightId) => _active[nightId];

  /// Start uploading [video] and create the night as soon as the slot exists. The
  /// returned future is the night being created, not the upload finishing: it
  /// completes with an error if the slot is refused (quota, size) or the night
  /// is, and the upload carries on in the background otherwise.
  Future<DateNight> start({
    required LocalVideo video,
    required String title,
    required DateTime startsAt,
  }) {
    return _launch(
      video: video,
      attach: (session) =>
          _pair.planNight(title: title, startsAt: startsAt, stagedId: session.stagedId),
    );
  }

  /// Choose the file again for a night that already exists (the upload stopped
  /// and could not be resumed, or the night had none).
  Future<DateNight> chooseAgain({required DateNight night, required LocalVideo video}) {
    return _launch(
      video: video,
      attach: (session) async {
        await _pair.attachStagedFile(night.id, session.stagedId);
        return night;
      },
      replacing: night.id,
    );
  }

  /// Carry on a stopped upload from the parts the server already has.
  Future<void> resume(String nightId) async {
    final upload = _active[nightId];
    if (upload == null || upload.phase != UploadPhase.stopped) return;
    upload.token = CancellationToken();
    upload.phase = UploadPhase.uploading;
    upload._changed();
    notifyListeners();
    _run(upload, resume: upload.session);
  }

  /// Stop uploading for [nightId] and let go of the file.
  Future<void> cancel(String nightId) async {
    final upload = _active.remove(nightId);
    if (upload == null) return;
    upload.token.cancel();
    upload.phase = UploadPhase.finished;
    upload._changed();
    unawaited(upload.video.release());
    notifyListeners();
  }

  Future<DateNight> _launch({
    required LocalVideo video,
    required Future<DateNight> Function(StagedUploadSession session) attach,
    String? replacing,
  }) {
    final created = Completer<DateNight>();
    final token = CancellationToken();
    UploadProgress? early;
    var failedEarly = false;

    final run = _media.uploadStagedFile(
      source: video.uploadSource(),
      cancelToken: token,
      keepSlotOnFailure: true,
      onSessionCreated: (session) {
        unawaited(() async {
          try {
            final night = await attach(session);
            if (replacing != null) await cancel(replacing);
            final u = DateNightUpload(
              nightId: night.id,
              video: video,
              token: token,
              session: session,
            );
            _active[night.id] = u;
            final p = early;
            if (p != null) _onProgress(u, p);
            if (failedEarly) {
              // The connection dropped while the night was still being made.
              u.phase = UploadPhase.stopped;
              unawaited(_pair.reportUploadProgress(u.nightId, u.bytes, stopped: true));
            }
            notifyListeners();
            if (!created.isCompleted) created.complete(night);
          } catch (e) {
            // Refused (or the night could not be made): give the slot back.
            token.cancel();
            unawaited(
              _media.abortStagedUpload(
                stagedId: session.stagedId,
                uploadId: session.uploadId,
                r2Key: session.r2Key,
              ),
            );
            if (!created.isCompleted) created.completeError(e);
          }
        }());
      },
      onProgress: (p) {
        final u = _byToken(token);
        if (u == null) {
          early = p;
        } else {
          _onProgress(u, p);
        }
      },
    );

    run.then(
      (session) {
        final u = _byToken(token);
        if (u != null) unawaited(_finished(u));
      },
      onError: (Object e, StackTrace s) {
        if (token.isCancelled) return;
        final u = _byToken(token);
        if (u == null) {
          failedEarly = true;
          if (!created.isCompleted) created.completeError(e, s);
          return;
        }
        _stopped(u, e, s);
      },
    );
    return created.future;
  }

  DateNightUpload? _byToken(CancellationToken token) {
    for (final u in _active.values) {
      if (identical(u.token, token)) return u;
    }
    return null;
  }

  void _run(DateNightUpload upload, {StagedUploadSession? resume}) {
    final token = upload.token;
    _media
        .uploadStagedFile(
          source: upload.video.uploadSource(),
          cancelToken: token,
          keepSlotOnFailure: true,
          resume: resume,
          onProgress: (p) => _onProgress(upload, p),
        )
        .then(
          (_) => _finished(upload),
          onError: (Object e, StackTrace s) {
            if (token.isCancelled) return;
            _stopped(upload, e, s);
          },
        );
  }

  void _onProgress(DateNightUpload u, UploadProgress p) {
    u
      ..bytes = p.bytesUploaded
      ..total = p.totalBytes
      ..etaSeconds = p.etaSeconds;
    u._changed();
    final now = DateTime.now();
    final last = u._lastReport;
    if (last == null || now.difference(last) >= reportEvery) {
      u._lastReport = now;
      unawaited(_pair.reportUploadProgress(u.nightId, p.bytesUploaded));
    }
  }

  void _stopped(DateNightUpload u, Object e, StackTrace s) {
    u.phase = UploadPhase.stopped;
    u._changed();
    notifyListeners();
    trace(
      'date night upload stopped',
      category: 'media',
      data: {'night_id': u.nightId, 'bytes': u.bytes, 'total': u.total},
    );
    unawaited(_pair.reportUploadProgress(u.nightId, u.bytes, stopped: true));
    reportNonFatal(e, s, during: 'uploading a date night file');
  }

  Future<void> _finished(DateNightUpload u) async {
    u.phase = UploadPhase.finished;
    u.bytes = u.total;
    u._changed();
    _active.remove(u.nightId);
    notifyListeners();
    trace('date night upload finished', category: 'media', data: {'night_id': u.nightId});
    unawaited(u.video.release());
    // The allowance moved when the upload completed, and the night is Ready.
    unawaited(ProfileService.instance.load());
    unawaited(_pair.load());
  }
}
