import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:synctogether/mock/mock_dependencies.dart';
import 'package:synctogether/pairing/date_night_upload.dart';
import 'package:synctogether/pairing/pair_models.dart';
import 'package:synctogether/pairing/pair_service.dart';
import 'package:synctogether/player/local_video.dart';
import 'package:synctogether/rooms/media_sharing_service.dart';
import 'package:synctogether/rooms/upload_source.dart';

import '../support/fake_pair_service.dart';

/// A media service whose uploads this test steers: when the slot is granted, how
/// far it has got, and when it finishes or drops.
class _FakeMedia extends MediaSharingService {
  final calls = <String>[];
  final aborts = <String>[];
  final resumes = <StagedUploadSession?>[];
  Completer<StagedUploadSession> run = Completer();
  void Function(UploadProgress)? progress;
  CancellationToken? token;
  bool refuseSlot = false;

  static const session = StagedUploadSession(
    stagedId: 'slot-1',
    fileName: 'film.mkv',
    fileSize: 1000,
    uploadId: 'mp-1',
    r2Key: 'users/u/staged/film.mkv',
    totalParts: 4,
    partSizeBytes: 250,
  );

  @override
  Future<StagedUploadSession> uploadStagedFile({
    File? file,
    UploadSource? source,
    Duration? duration,
    void Function(UploadProgress)? onProgress,
    void Function(StagedUploadSession session)? onSessionCreated,
    CancellationToken? cancelToken,
    StagedUploadSession? resume,
    bool keepSlotOnFailure = false,
  }) {
    calls.add(resume == null ? 'start' : 'resume');
    resumes.add(resume);
    progress = onProgress;
    token = cancelToken;
    run = Completer();
    if (refuseSlot) {
      return Future.error(const MediaSharingException(code: 'quota_exceeded', message: 'No room.'));
    }
    if (resume == null) onSessionCreated?.call(session);
    return run.future;
  }

  @override
  Future<void> abortStagedUpload({
    required String stagedId,
    required String uploadId,
    required String r2Key,
    int bytesUploaded = 0,
  }) async {
    aborts.add(stagedId);
  }

  void emit(int bytes, {int total = 1000}) => progress?.call(
    UploadProgress(
      bytesUploaded: bytes,
      totalBytes: total,
      speedBps: 100,
      etaSeconds: 9,
      state: 'uploading',
    ),
  );
}

class _RefusingPair extends FakePairService {
  _RefusingPair() : super(pair: samePairInfo(patron: true));

  @override
  Future<DateNight> planNight({
    required String title,
    required DateTime startsAt,
    String? youtubeUrl,
    String? stagedId,
  }) async => throw StateError('invalid_time');
}

LocalVideo _video() => LocalVideo(
  name: 'film.mkv',
  mediaUri: '/m/film.mkv',
  path: '/m/film.mkv',
  origin: VideoOrigin.files,
  reference: const PathReference('/m/film.mkv'),
  sizeBytes: 1000,
);

void main() {
  late _FakeMedia media;
  late FakePairService pair;

  DateNightUploader uploader({Duration every = const Duration(hours: 1)}) =>
      DateNightUploader(media: media, pair: () => pair, reportEvery: every);

  setUp(() {
    installMockDependencies();
    media = _FakeMedia();
    pair = FakePairService(pair: samePairInfo(patron: true));
    PairService.instance = pair;
  });

  Future<void> settle() => Future<void>.delayed(Duration.zero);

  test('the night is made as soon as the slot exists, and the upload carries on', () async {
    final up = uploader();
    final night = await up.start(
      video: _video(),
      title: 'Spirited Away',
      startsAt: DateTime.now().add(const Duration(days: 2)),
    );
    expect(pair.calls, contains('planNight:Spirited Away::slot-1'), reason: 'adopts the slot');
    expect(night.hasFile, isTrue);
    expect(up.forNight(night.id), isNotNull, reason: 'and this device is running the upload');
    expect(up.forNight(night.id)!.phase, UploadPhase.uploading);
    expect(media.run.isCompleted, isFalse, reason: 'start did not wait for the bytes');
  });

  test('progress reaches the planner at once and the night only every few seconds', () async {
    final up = uploader();
    final night = await up.start(
      video: _video(),
      title: 'Film',
      startsAt: DateTime.now().add(const Duration(days: 2)),
    );
    media.emit(250);
    media.emit(500);
    media.emit(750);
    final live = up.forNight(night.id)!;
    expect(live.fraction, 0.75, reason: 'the planner sees every step');
    expect(live.etaSeconds, 9);
    expect(
      pair.calls.where((c) => c.startsWith('reportUploadProgress')),
      ['reportUploadProgress:${night.id}:250:false'],
      reason: 'the first report goes out, the rest wait for the interval',
    );
  });

  test('with a short interval the next report follows', () async {
    final up = uploader(every: Duration.zero);
    final night = await up.start(
      video: _video(),
      title: 'Film',
      startsAt: DateTime.now().add(const Duration(days: 2)),
    );
    media.emit(250);
    media.emit(500);
    expect(pair.calls.where((c) => c.startsWith('reportUploadProgress')), [
      'reportUploadProgress:${night.id}:250:false',
      'reportUploadProgress:${night.id}:500:false',
    ]);
  });

  test('finishing clears the live upload', () async {
    final up = uploader();
    final night = await up.start(
      video: _video(),
      title: 'Film',
      startsAt: DateTime.now().add(const Duration(days: 2)),
    );
    media.run.complete(_FakeMedia.session);
    await settle();
    expect(up.forNight(night.id), isNull);
  });

  test(
    'a dropped connection is a stopped upload, reported, and resumable on the same slot',
    () async {
      final up = uploader();
      final night = await up.start(
        video: _video(),
        title: 'Film',
        startsAt: DateTime.now().add(const Duration(days: 2)),
      );
      media.emit(400);
      media.run.completeError(const SocketException('connection dropped'));
      await settle();

      final live = up.forNight(night.id)!;
      expect(live.phase, UploadPhase.stopped);
      expect(pair.calls, contains('reportUploadProgress:${night.id}:400:true'));
      expect(media.aborts, isEmpty, reason: 'the slot is kept for a resume');

      await up.resume(night.id);
      expect(media.calls.last, 'resume');
      expect(media.resumes.last?.stagedId, 'slot-1', reason: 'on the same slot, not a new one');
      expect(up.forNight(night.id)!.phase, UploadPhase.uploading);
      media.run.complete(_FakeMedia.session);
      await settle();
      expect(up.forNight(night.id), isNull);
    },
  );

  test('a slot that is refused makes no night and says why', () async {
    media.refuseSlot = true;
    final up = uploader();
    await expectLater(
      up.start(
        video: _video(),
        title: 'Film',
        startsAt: DateTime.now().add(const Duration(days: 2)),
      ),
      throwsA(isA<MediaSharingException>()),
    );
    expect(pair.calls.where((c) => c.startsWith('planNight')), isEmpty);
  });

  test('if the night cannot be made, the slot is given back', () async {
    pair = _RefusingPair();
    PairService.instance = pair;
    final up = uploader();
    await expectLater(
      up.start(
        video: _video(),
        title: 'Film',
        startsAt: DateTime.now().add(const Duration(days: 2)),
      ),
      throwsA(isA<StateError>()),
    );
    await settle();
    expect(media.aborts, ['slot-1'], reason: 'otherwise it would hold the upload lock');
    expect(media.token!.isCancelled, isTrue);
  });

  test('cancelling stops the upload and forgets it', () async {
    final up = uploader();
    final night = await up.start(
      video: _video(),
      title: 'Film',
      startsAt: DateTime.now().add(const Duration(days: 2)),
    );
    await up.cancel(night.id);
    expect(media.token!.isCancelled, isTrue);
    expect(up.forNight(night.id), isNull);
  });

  test('choosing the file again adopts a fresh slot for the same night', () async {
    final up = uploader();
    final night = await up.start(
      video: _video(),
      title: 'Film',
      startsAt: DateTime.now().add(const Duration(days: 2)),
    );
    media.run.completeError(const SocketException('gone'));
    await settle();
    expect(up.forNight(night.id)!.phase, UploadPhase.stopped);

    await up.chooseAgain(night: night, video: _video());
    expect(pair.calls, contains('attachStagedFile:${night.id}:slot-1'));
    expect(up.forNight(night.id)!.phase, UploadPhase.uploading, reason: 'a live upload again');
  });
}
