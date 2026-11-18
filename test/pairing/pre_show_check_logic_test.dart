import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:synctogether/av/system_permissions.dart';
import 'package:synctogether/pairing/pair_models.dart';
import 'package:synctogether/pairing/pre_show_check_logic.dart';

import '../support/fake_pre_show_probes.dart';

PreShowCheckController make(
  FakeProbes probes, {
  FilmCheck film = const FilmCheck(FilmKind.fileReady),
  bool includeAv = true,
}) =>
    PreShowCheckController(probes: probes, film: () => film, includeAv: includeAv, partner: 'Sam');

CheckRowView row(PreShowCheckController c, CheckId id) => c.rows.firstWhere((r) => r.id == id);

Future<void> settle() => Future<void>.delayed(Duration.zero);

void main() {
  group('permissions are asked only when the person taps', () {
    test('opening the sheet asks nothing and starts nothing that is not allowed', () async {
      final p = FakeProbes();
      final c = make(p);
      await c.start();
      await settle();
      expect(p.calls.where((c) => c.startsWith('request')), isEmpty);
      expect(p.count('camera-open'), 0);
      expect(p.count('mic-open'), 0);
      expect(row(c, CheckId.camera).tone, RowTone.idle);
      expect(row(c, CheckId.camera).actions.map((a) => a.id), ['allow', 'voice']);
      expect(row(c, CheckId.mic).actions.map((a) => a.id), ['allow']);
      c.dispose();
    });

    test('already allowed: the preview starts by itself, with no prompt', () async {
      final p = FakeProbes(camera: PermissionState.granted, mic: PermissionState.granted);
      final c = make(p);
      await c.start();
      await settle();
      expect(p.calls.where((c) => c.startsWith('request')), isEmpty);
      expect(row(c, CheckId.camera).tone, RowTone.ok);
      expect(c.mic, MicState.listening);
      c.dispose();
    });

    test('tapping Turn on camera asks once, then opens the preview', () async {
      final p = FakeProbes();
      final c = make(p);
      await c.start();
      await c.act(CheckId.camera, 'allow');
      expect(p.count('request:camera'), 1);
      expect(c.cam, CamState.on);
      c.dispose();
    });
  });

  group('camera: every way it can go wrong has words and a fix', () {
    test('refused on iPhone: the system will not ask again, so the fix is settings', () async {
      final p = FakeProbes()..onRequestCamera = PermissionState.blocked;
      final c = make(p);
      await c.start();
      await c.act(CheckId.camera, 'allow');
      final r = row(c, CheckId.camera);
      expect(c.cam, CamState.blocked);
      expect(r.tone, RowTone.bad);
      expect(r.actions.map((a) => a.id), ['settings', 'voice']);
      await c.act(CheckId.camera, 'settings');
      expect(p.calls, contains('settings:camera'));
      c.dispose();
    });

    test('coming back from settings with it allowed starts the preview on its own', () async {
      final p = FakeProbes(camera: PermissionState.blocked);
      final c = make(p);
      await c.start();
      expect(c.cam, CamState.blocked);
      p.camera = PermissionState.granted;
      await c.foreground();
      await settle();
      expect(c.cam, CamState.on);
      c.dispose();
    });

    test('restricted by the device offers no settings button that would lead nowhere', () async {
      final p = FakeProbes(camera: PermissionState.restricted);
      final c = make(p);
      await c.start();
      final r = row(c, CheckId.camera);
      expect(r.tone, RowTone.warn, reason: 'a state, not an error');
      expect(r.actions.map((a) => a.id), ['voice']);
      c.dispose();
    });

    test('no camera, another app has it, or the camera stops mid-check', () async {
      for (final (open, expected) in [
        (CameraOpen.none, CamState.none),
        (CameraOpen.busy, CamState.busy),
      ]) {
        final p = FakeProbes(camera: PermissionState.granted, mic: PermissionState.granted)
          ..cameraOpens = open;
        final c = make(p);
        await c.start();
        await settle();
        expect(c.cam, expected);
        expect(row(c, CheckId.camera).actions.map((a) => a.id), contains('retry'));
        c.dispose();
      }
      final p = FakeProbes(camera: PermissionState.granted);
      final c = make(p);
      await c.start();
      await settle();
      p.ended.add(null);
      await settle();
      expect(c.cam, CamState.stopped);
      expect(row(c, CheckId.camera).actions.map((a) => a.id), ['restart', 'voice']);
      c.dispose();
    });

    test('voice only is a choice, not a failure', () async {
      final p = FakeProbes(camera: PermissionState.granted);
      final c = make(p);
      await c.start();
      await settle();
      await c.act(CheckId.camera, 'voice');
      expect(c.cam, CamState.off);
      expect(row(c, CheckId.camera).flagged, isFalse);
      expect(p.calls, contains('camera-close'), reason: 'the camera is released');
      c.dispose();
    });
  });

  group('microphone', () {
    test('silence for five seconds says so, and a voice clears it', () {
      fakeAsync((async) {
        final p = FakeProbes(mic: PermissionState.granted);
        final c = make(p);
        c.start();
        async.flushMicrotasks();
        expect(c.mic, MicState.listening);
        async.elapse(PreShowCheckController.flatAfter + const Duration(milliseconds: 100));
        expect(c.mic, MicState.flat);
        expect(row(c, CheckId.mic).fix, contains('Is the mic muted'));
        p.levels.add([0.6]);
        async.flushMicrotasks();
        expect(c.mic, MicState.heard);
        expect(row(c, CheckId.mic).tone, RowTone.ok);
        c.dispose();
      });
    });

    test('a microphone that will not open is its own state, not a permission one', () async {
      final p = FakeProbes(mic: PermissionState.granted, micFails: true);
      final c = make(p);
      await c.start();
      await settle();
      await settle();
      expect(c.mic, MicState.failed);
      c.dispose();
    });

    test('blocked sends the person to settings and keeps the room usable', () async {
      final p = FakeProbes(mic: PermissionState.blocked);
      final c = make(p);
      await c.start();
      expect(row(c, CheckId.mic).actions.map((a) => a.id), ['settings', 'listen-only']);
      expect(c.clean, isFalse);
      c.dispose();
    });
  });

  group('leaving the front and closing release the devices', () {
    test('backgrounding releases both and says paused, never restarting by itself', () async {
      final p = FakeProbes(camera: PermissionState.granted, mic: PermissionState.granted);
      final c = make(p);
      await c.start();
      await settle();
      await c.background();
      expect(c.cam, CamState.paused);
      expect(c.mic, MicState.paused);
      expect(p.calls, contains('camera-close'));
      final opens = p.count('camera-open');
      await c.foreground();
      await settle();
      expect(p.count('camera-open'), opens, reason: 'no camera on without a tap');
      expect(row(c, CheckId.camera).actions.map((a) => a.id), ['restart']);
      c.dispose();
    });

    test('closing the sheet releases the camera', () async {
      final p = FakeProbes(camera: PermissionState.granted);
      final c = make(p);
      await c.start();
      await settle();
      final before = p.count('camera-close');
      c.dispose();
      await settle();
      expect(p.count('camera-close'), greaterThan(before));
    });
  });

  group('sound', () {
    test('the chime asks whether it was heard, and no leads to a checklist', () async {
      final p = FakeProbes();
      final c = make(p);
      await c.act(CheckId.sound, 'play');
      expect(c.sound, SoundState.confirm);
      await c.act(CheckId.sound, 'no');
      expect(row(c, CheckId.sound).fix, contains('volume'));
      await c.act(CheckId.sound, 'again');
      await c.act(CheckId.sound, 'yes');
      expect(row(c, CheckId.sound).tone, RowTone.ok);
      c.dispose();
    });

    test('a chime that will not play is a failure of its own', () async {
      final p = FakeProbes(chime: ChimeResult.failed);
      final c = make(p);
      await c.act(CheckId.sound, 'play');
      expect(row(c, CheckId.sound).tone, RowTone.bad);
      c.dispose();
    });

    test('saying no twice stops asking, and never blocks', () async {
      final p = FakeProbes();
      final c = make(p);
      await c.act(CheckId.sound, 'play');
      await c.act(CheckId.sound, 'no');
      await c.act(CheckId.sound, 'no');
      expect(row(c, CheckId.sound).actions, isEmpty);
      expect(row(c, CheckId.sound).tone, RowTone.warn);
      expect(c.offline, isFalse);
      c.dispose();
    });
  });

  group('connection', () {
    test('thresholds: good, slow, very slow', () {
      expect(lineStateFor(48), LineState.good);
      expect(lineStateFor(380), LineState.slow);
      expect(lineStateFor(1200), LineState.verySlow);
    });

    test('good reads in words first and milliseconds second', () async {
      final p = FakeProbes();
      final c = make(p);
      await c.start();
      await settle();
      expect(row(c, CheckId.connection).subtitle, 'Good · 48 ms to the room');
      c.dispose();
    });

    test('offline withholds "anyway": there is nothing to take seats for', () async {
      final p = FakeProbes(
        latency: const LatencyReading.failed(),
        network: const NetworkInfo(transport: NetworkTransport.none),
      );
      final c = make(p);
      await c.start();
      await settle();
      expect(c.line, LineState.offline);
      expect(c.offline, isTrue);
      expect(row(c, CheckId.connection).actions.map((a) => a.id), ['retry', 'network']);
      c.dispose();
    });

    test('online but unreachable is told apart from offline', () async {
      final p = FakeProbes(latency: const LatencyReading.failed());
      final c = make(p);
      await c.start();
      await settle();
      expect(c.line, LineState.unreachable);
      expect(c.offline, isFalse);
      c.dispose();
    });

    test('mobile data is a courtesy, and only for a film that streams', () async {
      final cell = FakeProbes(network: const NetworkInfo(transport: NetworkTransport.cellular));
      final streaming = make(cell);
      await streaming.start();
      await settle();
      expect(row(streaming, CheckId.connection).subtitle, contains('mobile data'));
      await streaming.act(CheckId.connection, 'mobile-ok');
      expect(row(streaming, CheckId.connection).tone, RowTone.ok);
      streaming.dispose();

      final local = make(cell, film: const FilmCheck(FilmKind.local));
      await local.start();
      await settle();
      expect(row(local, CheckId.connection).tone, RowTone.ok, reason: 'nothing streams');
      local.dispose();
    });

    test('Data Saver is named, with the page that turns it off', () async {
      final p = FakeProbes(
        network: const NetworkInfo(transport: NetworkTransport.wifi, saver: true),
      );
      final c = make(p);
      await c.start();
      await settle();
      expect(row(c, CheckId.connection).subtitle, contains('Data Saver'));
      await c.act(CheckId.connection, 'network');
      expect(p.calls, contains('network-settings'));
      c.dispose();
    });
  });

  group('the film row', () {
    DateNight night({String kind = 'none', String upload = 'none', int bytes = 0, int? size}) =>
        DateNight(
          id: 'n',
          title: 'Spirited Away',
          startsAt: DateTime.now().toUtc().add(const Duration(minutes: 10)),
          proposedBy: 'me',
          status: DateNightStatus.accepted,
          attachKind: kind,
          youtubeUrl: kind == 'youtube' ? 'https://youtu.be/x' : null,
          fileName: kind == 'file' ? 'film.mkv' : null,
          fileSize: size,
          uploadState: upload,
          uploadBytes: bytes,
        );

    test('nothing attached, a link, a finished file, one arriving, one stalled', () {
      final now = DateTime.now().toUtc();
      FilmCheck f(DateNight n, {bool mine = false}) => FilmCheck.forNight(n, now, mine: mine);
      expect(f(night()).kind, FilmKind.none);
      expect(f(night(kind: 'youtube')).kind, FilmKind.link);
      expect(f(night(kind: 'file', upload: 'ready')).kind, FilmKind.fileReady);
      final arriving = f(night(kind: 'file', upload: 'uploading', bytes: 84, size: 100));
      expect(arriving.kind, FilmKind.fileUploading);
      expect(arriving.percent, 84);
      expect(
        f(night(kind: 'file', upload: 'stopped', bytes: 38, size: 100)).kind,
        FilmKind.fileStopped,
      );
    });

    test('arriving on the partner side warns without blocking; stalled says why', () async {
      final p = FakeProbes();
      final c = make(p, film: const FilmCheck(FilmKind.fileUploading, percent: 84));
      expect(row(c, CheckId.film).subtitle, contains("Sam's side"));
      expect(row(c, CheckId.film).tone, RowTone.warn);
      expect(c.offline, isFalse);
      c.dispose();
      final stalled = make(p, film: const FilmCheck(FilmKind.fileStopped, percent: 38, mine: true));
      expect(row(stalled, CheckId.film).tone, RowTone.bad);
      expect(row(stalled, CheckId.film).actions.map((a) => a.id), ['nights']);
      stalled.dispose();
    });
  });

  test('the room check has no camera or microphone rows', () {
    final c = make(FakeProbes(), includeAv: false);
    expect(c.rows.map((r) => r.id), [CheckId.film, CheckId.sound, CheckId.connection]);
    c.dispose();
  });
}
