import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:synctogether/av/system_permissions.dart';
import 'package:synctogether/pairing/pair_models.dart';
import 'package:synctogether/pairing/pre_show_check_logic.dart';
import 'package:synctogether/player/youtube/youtube_block.dart';
import 'package:synctogether/rooms/open_failure.dart';

import '../support/fake_pre_show_probes.dart';

PreShowCheckController make(
  FakeProbes probes, {
  FilmCheck film = const FilmCheck(FilmKind.fileReady),
  bool includeAv = true,
  bool Function()? partnerOnline,
  Future<NudgeResult> Function()? nudge,
  Future<double?> Function()? measureFilm,
  void Function()? useMobileData,
}) => PreShowCheckController(
  useMobileData: useMobileData,
  nudge: nudge,
  measureFilm: measureFilm,
  probes: probes,
  film: () => film,
  includeAv: includeAv,
  partner: 'Sam',
  partnerOnline: partnerOnline ?? () => true,
);

CheckRowView row(PreShowCheckController c, CheckId id) => c.rows.firstWhere((r) => r.id == id);

Future<void> settle() => Future<void>.delayed(Duration.zero);

void main() {
  group('Windows blocking the camera or microphone', () {
    PreShowCheckController win(FakeProbes p) => PreShowCheckController(
      probes: p,
      film: () => const FilmCheck(FilmKind.none),
      partner: 'Sam',
      windows: true,
    );

    test('says whose switch it is and where it lives', () async {
      final p = FakeProbes(camera: PermissionState.blocked, mic: PermissionState.blocked);
      final c = win(p);
      await c.start();
      await settle();
      final m = row(c, CheckId.mic);
      expect(m.subtitle, 'Windows is blocking the microphone');
      expect(m.fix, contains('Let desktop apps access your microphone'));
      expect(m.actions.map((a) => a.label), ['Open Settings', 'Listen only']);
      final cam = row(c, CheckId.camera);
      expect(cam.subtitle, 'Windows is blocking the camera');
      expect(cam.actions.map((a) => a.label), ['Open Settings', 'Voice only']);
      c.dispose();
    });

    test('other platforms keep their own words', () async {
      final p = FakeProbes(mic: PermissionState.blocked);
      final c = PreShowCheckController(
        probes: p,
        film: () => const FilmCheck(FilmKind.none),
        partner: 'Sam',
        windows: false,
      );
      await c.start();
      await settle();
      expect(row(c, CheckId.mic).subtitle, "SyncTogether can't hear you");
      c.dispose();
    });
  });

  group('the sound row knows the volume and where it goes', () {
    Future<(PreShowCheckController, FakeProbes)> open() async {
      final p = FakeProbes();
      final c = PreShowCheckController(
        probes: p,
        film: () => const FilmCheck(FilmKind.none),
        partner: 'Sam',
        thisDevice: 'this iPhone',
      );
      await c.start();
      await settle();
      return (c, p);
    }

    void say(FakeProbes p, AudioState s) {
      p.audio.add(AudioEvent(AudioEventKind.state, state: s));
    }

    test('a volume at zero is named, with the one fix that works', () async {
      final (c, p) = await open();
      say(p, const AudioState(volume: 0, outputName: 'iPhone Speaker'));
      await settle();
      final r = row(c, CheckId.sound);
      expect(r.subtitle, 'Your volume is at zero');
      expect(r.fix, contains('volume keys'));
      expect(r.actions.map((a) => a.label), ['Play the chime']);
      say(p, const AudioState(volume: 0.5, outputName: 'iPhone Speaker'));
      await settle();
      expect(
        row(c, CheckId.sound).subtitle,
        'Play the test chime',
        reason: 're-checks as it moves',
      );
      c.dispose();
    });

    test('a volume that cannot be read says nothing', () async {
      final (c, p) = await open();
      say(p, const AudioState(outputName: 'Speakers'));
      await settle();
      expect(row(c, CheckId.sound).subtitle, 'Play the test chime');
      c.dispose();
    });

    test('sound going to a Bluetooth speaker is said before the film starts', () async {
      final (c, p) = await open();
      say(p, const AudioState(volume: 0.6, outputName: 'JBL Flip 6', output: OutputKind.bluetooth));
      await settle();
      final r = row(c, CheckId.sound);
      expect(r.subtitle, 'Playing on JBL Flip 6 (Bluetooth)');
      expect(r.flagged, isFalse);
      expect(r.actions.map((a) => a.label), ['Use this iPhone', 'Keep JBL Flip 6']);
      c.dispose();
    });

    test('answering once is enough, and a different speaker asks again', () async {
      final (c, p) = await open();
      const jbl = AudioState(volume: 0.6, outputName: 'JBL Flip 6', output: OutputKind.bluetooth);
      say(p, jbl);
      await settle();
      await c.act(CheckId.sound, 'out-keep');
      expect(p.calls, contains('output:keep:JBL Flip 6'));
      expect(row(c, CheckId.sound).subtitle, 'Play the test chime');
      say(p, const AudioState(volume: 0.6, outputName: 'Kitchen', output: OutputKind.airplay));
      await settle();
      expect(row(c, CheckId.sound).subtitle, 'Playing on Kitchen (AirPlay)');
      await c.act(CheckId.sound, 'out-builtin');
      expect(p.calls, contains('output:builtin'));
      c.dispose();
    });

    test('a device with no speakers of its own offers only to keep', () async {
      final (c, p) = await open();
      say(
        p,
        const AudioState(
          volume: 0.6,
          outputName: 'Studio Display',
          output: OutputKind.other,
          canUseBuiltIn: false,
        ),
      );
      await settle();
      expect(row(c, CheckId.sound).actions.map((a) => a.label), ['Keep Studio Display']);
      c.dispose();
    });

    test('once the chime was heard the row is quiet about it', () async {
      final (c, p) = await open();
      c.heardChime(true);
      say(p, const AudioState(volume: 0, outputName: 'Speakers'));
      await settle();
      expect(row(c, CheckId.sound).subtitle, 'You can hear us');
      c.dispose();
    });
  });

  group('the microphone route changes under the sheet', () {
    Future<(PreShowCheckController, FakeProbes)> listening() async {
      final p = FakeProbes(mic: PermissionState.granted);
      final c = PreShowCheckController(
        probes: p,
        film: () => const FilmCheck(FilmKind.none),
        partner: 'Sam',
        thisDevice: 'this iPhone',
      );
      await c.start();
      await settle();
      return (c, p);
    }

    test('a call takes the mic: paused with its words, then back by itself', () async {
      final (c, p) = await listening();
      expect(c.mic, MicState.listening);
      p.audio.add(const AudioEvent(AudioEventKind.interrupted));
      await settle();
      var r = row(c, CheckId.mic);
      expect(c.mic, MicState.interrupted);
      expect(r.subtitle, 'Paused: something else is using it');
      expect(r.actions.map((a) => a.label), ['Restart now']);
      final opens = p.count('mic-open');
      p.audio.add(const AudioEvent(AudioEventKind.resumed));
      await settle();
      expect(c.mic, MicState.listening, reason: 'no tap needed');
      expect(p.count('mic-open'), opens + 1);
      r = row(c, CheckId.mic);
      expect(r.subtitle, 'Say something to test it');
      c.dispose();
    });

    test('"Restart now" does not wait for the call to end', () async {
      final (c, p) = await listening();
      p.audio.add(const AudioEvent(AudioEventKind.interrupted));
      await settle();
      await c.act(CheckId.mic, 'restart');
      expect(c.mic, MicState.listening);
      c.dispose();
    });

    test('an interruption before the meter is on says nothing', () async {
      final p = FakeProbes();
      final c = make(p);
      await c.start();
      await settle();
      p.audio.add(const AudioEvent(AudioEventKind.interrupted));
      await settle();
      expect(c.mic, MicState.idle);
      c.dispose();
    });

    test('a headset says so once, with two real choices', () async {
      final (c, p) = await listening();
      p.audio.add(
        const AudioEvent(
          AudioEventKind.input,
          name: 'AirPods Pro',
          builtIn: false,
          bluetooth: true,
        ),
      );
      await settle();
      final r = row(c, CheckId.mic);
      expect(r.subtitle, 'Switched to AirPods Pro');
      expect(r.flagged, isFalse, reason: 'a heads-up, not a warning');
      expect(r.fix, contains('Bluetooth headsets cut call quality'));
      expect(r.actions.map((a) => a.label), ['Use this iPhone', 'Keep AirPods Pro']);
      c.dispose();
    });

    test('a device with no mic of its own offers only to keep the new one', () async {
      final (c, p) = await listening();
      p.audio.add(
        const AudioEvent(
          AudioEventKind.input,
          name: 'USB Audio CODEC',
          builtIn: false,
          canUseBuiltIn: false,
        ),
      );
      await settle();
      expect(row(c, CheckId.mic).actions.map((a) => a.label), ['Keep USB Audio CODEC']);
      c.dispose();
    });

    test('using the phone\'s own mic saves it and clears the note', () async {
      final (c, p) = await listening();
      p.audio.add(const AudioEvent(AudioEventKind.input, name: 'AirPods Pro', builtIn: false));
      await settle();
      await c.act(CheckId.mic, 'mic-builtin');
      expect(p.calls, contains('input:builtin'));
      expect(row(c, CheckId.mic).subtitle, isNot(startsWith('Switched')));
      c.dispose();
    });

    test('keeping the headset saves it and clears the note', () async {
      final (c, p) = await listening();
      p.audio.add(const AudioEvent(AudioEventKind.input, name: 'AirPods Pro', builtIn: false));
      await settle();
      await c.act(CheckId.mic, 'mic-keep');
      expect(p.calls, contains('input:keep:AirPods Pro'));
      expect(c.headset, isNull);
      c.dispose();
    });

    test('taking the headset out clears the note', () async {
      final (c, p) = await listening();
      p.audio.add(const AudioEvent(AudioEventKind.input, name: 'AirPods Pro', builtIn: false));
      await settle();
      p.audio.add(const AudioEvent(AudioEventKind.input, name: 'iPhone Microphone'));
      await settle();
      expect(c.headset, isNull);
      expect(row(c, CheckId.mic).subtitle, isNot(startsWith('Switched')));
      c.dispose();
    });
  });

  group('more than one camera', () {
    const front = CameraChoice('front', 'Front Camera');
    const back = CameraChoice('back', 'Back Camera');

    Future<(PreShowCheckController, FakeProbes)> on(List<CameraChoice> cams) async {
      final p = FakeProbes(camera: PermissionState.granted, cameraList: cams);
      final c = make(p);
      await c.start();
      await settle();
      return (c, p);
    }

    test('a phone\'s machine names become plain ones, a webcam keeps its own', () {
      expect(cameraName('Camera 0, Facing front, Orientation 270'), 'Front camera');
      expect(cameraName('Camera 1, Facing back, Orientation 90'), 'Back camera');
      expect(cameraName('Logitech BRIO 4K'), 'Logitech BRIO 4K');
      expect(cameraName(''), 'Camera');
    });

    test('one camera is not a choice', () async {
      final (c, _) = await on(const [front]);
      final r = row(c, CheckId.camera);
      expect(r.subtitle, 'Front Camera · you look good');
      expect(r.actions, isEmpty);
      expect(r.fix, isNull);
      c.dispose();
    });

    test('two cameras name the one in use and offer the other', () async {
      final (c, _) = await on(const [front, back]);
      final r = row(c, CheckId.camera);
      expect(r.tone, RowTone.ok);
      expect(r.fix, 'Front Camera is selected. Switch if the picture is wrong.');
      expect(r.actions.map((a) => a.label), ['Back Camera']);
      c.dispose();
    });

    test('picking one switches the preview and the row follows', () async {
      final (c, p) = await on(const [front, back]);
      await c.act(CheckId.camera, 'cam:back');
      expect(p.calls, contains('camera-use:back'));
      final r = row(c, CheckId.camera);
      expect(r.subtitle, 'Back Camera · you look good');
      expect(r.actions.map((a) => a.label), ['Front Camera']);
      c.dispose();
    });

    test('a camera that will not open becomes the busy row, not a silent failure', () async {
      final (c, p) = await on(const [front, back]);
      p.cameraOpens = CameraOpen.busy;
      await c.act(CheckId.camera, 'cam:back');
      expect(c.cam, CamState.busy);
      c.dispose();
    });

    test('plugging one in updates the row live', () async {
      final (c, p) = await on(const [front]);
      p.cameraList = const [front, back];
      p.changed.add(null);
      await settle();
      expect(row(c, CheckId.camera).actions.map((a) => a.label), ['Back Camera']);
      c.dispose();
    });

    test('voice only drops the choices', () async {
      final (c, _) = await on(const [front, back]);
      c.voiceOnly();
      await settle();
      expect(c.cameraChoices, isEmpty);
      c.dispose();
    });
  });

  group('an upload waiting for Wi-Fi', () {
    const waiting = FilmCheck(FilmKind.fileWaitingWifi, percent: 38, mine: true);

    test('says so, with the percentage, and offers mobile data', () {
      var used = 0;
      final c = make(FakeProbes(), film: waiting, useMobileData: () => used++);
      final r = row(c, CheckId.film);
      expect(r.subtitle, 'Uploading 38% · waiting for Wi-Fi');
      expect(r.tone, RowTone.warn);
      expect(r.progress, 0.38);
      expect(r.fix, contains('carries on by itself'));
      expect(r.actions.map((a) => a.id), ['use-mobile-data']);
      c.act(CheckId.film, 'use-mobile-data');
      expect(used, 1);
      c.dispose();
    });
  });

  group('the film is gone from our servers', () {
    FilmCheck ready({bool mine = false, String name = 'a.mkv'}) =>
        FilmCheck(FilmKind.fileReady, name: name, bitrateBps: 4e6, mine: mine);
    Future<double?> gone() async => throw const FilmGoneException();

    test('the planner is pointed back to Date nights, the partner asked to re-upload', () async {
      final mine = make(FakeProbes(), film: ready(mine: true), measureFilm: gone);
      await mine.testFilm();
      var r = row(mine, CheckId.film);
      expect(mine.filmFlow, FilmFlow.gone);
      expect(r.subtitle, "This film isn't available anymore");
      expect(r.tone, RowTone.bad);
      expect(r.actions.map((a) => a.id), ['nights']);
      expect(r.fix, contains('still here'));

      final theirs = make(FakeProbes(), film: ready(), measureFilm: gone);
      await theirs.testFilm();
      r = row(theirs, CheckId.film);
      expect(r.actions, isEmpty);
      expect(r.fix, contains('Ask Sam to upload it again'));
      mine.dispose();
      theirs.dispose();
    });

    test('a different film attached afterwards is not judged by the old verdict', () async {
      var film = ready();
      final c = PreShowCheckController(
        probes: FakeProbes(),
        film: () => film,
        includeAv: true,
        partner: 'Sam',
        partnerOnline: () => true,
        measureFilm: () async => throw const FilmGoneException(),
      );
      await c.testFilm();
      expect(row(c, CheckId.film).subtitle, "This film isn't available anymore");
      film = ready(name: 'b.mkv');
      expect(row(c, CheckId.film).subtitle, isNot("This film isn't available anymore"));
      c.dispose();
    });
  });

  group('a blocked YouTube video', () {
    test('codes sort into the two verdicts, anything else is not one', () {
      expect(classifyYouTubeBlock(101), YouTubeBlock.embeddingOff);
      expect(classifyYouTubeBlock(150), YouTubeBlock.embeddingOff);
      expect(classifyYouTubeBlock(100), YouTubeBlock.unavailable);
      expect(classifyYouTubeBlock(2), isNull);
      expect(classifyYouTubeBlock(null), isNull);
    });

    test('says whose side it is and offers another video or a file', () {
      for (final (block, words) in [
        (YouTubeBlock.embeddingOff, "YouTube won't play this one here"),
        (YouTubeBlock.unavailable, 'This video is gone'),
      ]) {
        final c = make(FakeProbes(), film: FilmCheck(FilmKind.videoBlocked, youtubeBlock: block));
        final r = row(c, CheckId.film);
        expect(r.subtitle, words);
        expect(r.tone, RowTone.bad);
        expect(r.fix, contains('Sam'));
        expect(r.actions.map((a) => a.id), ['pick-youtube', 'find-file']);
        expect(r.actions.any((a) => a.label.toLowerCase().contains('convert')), isFalse);
      }
    });
  });

  group("we can't open this file", () {
    FilmCheck cant(OpenFailure kind, {bool shared = false}) =>
        FilmCheck(FilmKind.cantOpen, name: 'a.mkv', openFailure: kind, sharedCopy: shared);

    test('each kind says what it is, in words', () {
      final cases = {
        OpenFailure.format: "This format won't play here",
        OpenFailure.unreadable: "We can't read this file",
        OpenFailure.stalled: "This file won't start",
      };
      cases.forEach((kind, words) {
        final c = make(FakeProbes(), film: cant(kind));
        final r = row(c, CheckId.film);
        expect(r.subtitle, words);
        expect(r.tone, RowTone.bad);
        c.dispose();
      });
    });

    test('the format row promises no conversion, and never offers one', () {
      final c = make(FakeProbes(), film: cant(OpenFailure.format, shared: true));
      final r = row(c, CheckId.film);
      expect(r.fix, contains('never convert'));
      final labels = [for (final a in r.actions) a.label.toLowerCase()];
      expect(labels, ['use the shared copy', 'pick another file']);
      expect(labels.any((l) => l.contains('convert') || l.contains('transcode')), isFalse);
      c.dispose();
    });

    test('without a shared copy the only way out is another file', () {
      final c = make(FakeProbes(), film: cant(OpenFailure.unreadable));
      final r = row(c, CheckId.film);
      expect([for (final a in r.actions) a.label], ['Pick another file']);
      expect(r.actions.single.primary, isTrue);
      c.dispose();
    });

    test('it blocks nothing but is flagged', () {
      final c = make(FakeProbes(), film: cant(OpenFailure.stalled));
      expect(c.clean, isFalse);
      c.dispose();
    });
  });

  group('your copy: missing, or a different cut', () {
    test('a missing copy names the file only, never where it lived', () {
      final c = make(
        FakeProbes(),
        film: const FilmCheck(
          FilmKind.copyMissing,
          name: '/Volumes/Old Drive/Movies/Spirited Away.mkv',
        ),
      );
      final r = row(c, CheckId.film);
      expect(r.subtitle, "We can't find Spirited Away.mkv");
      expect(r.subtitle, isNot(contains('Volumes')));
      expect(r.tone, RowTone.warn);
      expect([for (final a in r.actions) a.label], ['Find the file']);
      c.dispose();
    });

    test('Windows paths are cut to the name too', () {
      expect(baseName(r'C:\\Users\\me\\Downloads\\Film.mp4'), 'Film.mp4');
      expect(baseName('Film.mp4'), 'Film.mp4');
    });

    test('the shared copy is offered only when the host uploaded one', () {
      final c = make(
        FakeProbes(),
        film: const FilmCheck(FilmKind.copyMissing, name: 'a.mkv', sharedCopy: true),
      );
      expect(
        [for (final a in row(c, CheckId.film).actions) a.label],
        ['Find the file', 'Use the shared copy'],
      );
      c.dispose();
    });

    test('a different cut names both lengths and who has the other one', () {
      final c = make(
        FakeProbes(),
        film: const FilmCheck(
          FilmKind.differentCut,
          yours: Duration(hours: 1, minutes: 49),
          theirs: Duration(hours: 1, minutes: 52),
          theirLabel: 'Sam',
          sharedCopy: true,
        ),
      );
      final r = row(c, CheckId.film);
      expect(r.subtitle, "Yours is 1h 49m, Sam's is 1h 52m");
      expect(r.fix, contains('never re-encode'));
      expect([for (final a in r.actions) a.label], ["Use Sam's copy", 'Keep mine']);
      c.dispose();
    });

    test('with no shared copy the choice is pick another or keep mine; no label says the room', () {
      final c = make(
        FakeProbes(),
        film: const FilmCheck(
          FilmKind.differentCut,
          yours: Duration(hours: 1, minutes: 49, seconds: 3),
          theirs: Duration(hours: 1, minutes: 49, seconds: 40),
        ),
      );
      final r = row(c, CheckId.film);
      expect(r.subtitle, "Yours is 1:49:03, the room's is 1:49:40");
      expect([for (final a in r.actions) a.label], ['Pick another', 'Keep mine']);
      c.dispose();
    });

    test('the controller leaves these to the room: no state change, no probe', () async {
      final probes = FakeProbes();
      final c = make(probes, film: const FilmCheck(FilmKind.copyMissing, name: 'a.mkv'));
      await c.act(CheckId.film, 'find-file');
      await c.act(CheckId.film, 'use-shared');
      expect(probes.calls, isEmpty);
      c.dispose();
    });
  });

  group('the film may buffer', () {
    // A 2 GB film over two hours needs about 2.2 Mbps; use round numbers.
    const need = 4e6;
    const ready = FilmCheck(FilmKind.fileReady, bitrateBps: need);

    test('a link well above the bitrate says nothing', () async {
      final c = make(FakeProbes(), film: ready, measureFilm: () async => 20e6);
      await c.testFilm();
      expect(c.filmFlow, FilmFlow.fine);
      expect(row(c, CheckId.film).subtitle, 'Ready on both sides');
      c.dispose();
    });

    test('a link under the bitrate with headroom warns, in words, and never offers less', () async {
      final c = make(FakeProbes(), film: ready, measureFilm: () async => 5e6);
      await c.testFilm();
      final film = row(c, CheckId.film);
      expect(film.subtitle, 'This film may stutter on your connection');
      expect(film.tone, RowTone.warn);
      expect(film.fix, contains('4.0 Mbps'));
      expect(film.fix, contains('5.0 Mbps'));
      expect(film.fix, contains('never lower'));
      expect([for (final a in film.actions) a.label], ['Start anyway', 'Test again']);
      expect(c.clean, isFalse);
      c.dispose();
    });

    test('Start anyway quiets the warning; Test again measures again', () async {
      final readings = [5e6, 30e6];
      var calls = 0;
      final c = make(
        FakeProbes(),
        film: ready,
        measureFilm: () async {
          calls++;
          return readings.removeAt(0);
        },
      );
      await c.testFilm();
      await c.act(CheckId.film, 'film-anyway');
      expect(row(c, CheckId.film).flagged, isFalse);
      expect(row(c, CheckId.film).subtitle, 'Ready · may pause to catch up');
      await c.act(CheckId.film, 'film-retest');
      expect(calls, 2);
      expect(c.filmFlow, FilmFlow.fine);
      expect(row(c, CheckId.film).subtitle, 'Ready on both sides');
      c.dispose();
    });

    test('a retest shows it is testing, then the new answer', () async {
      final gate = Completer<double?>();
      var first = true;
      final c = make(
        FakeProbes(),
        film: ready,
        measureFilm: () => first ? Future.value(1e6) : gate.future,
      );
      await c.testFilm();
      first = false;
      final pending = c.testFilm();
      expect(row(c, CheckId.film).subtitle, 'Testing your connection again…');
      expect(row(c, CheckId.film).tone, RowTone.busy);
      gate.complete(1e6);
      await pending;
      expect(row(c, CheckId.film).tone, RowTone.warn);
      c.dispose();
    });

    test('the first test is silent while it runs, and a failed one is not a verdict', () async {
      final gate = Completer<double?>();
      final c = make(FakeProbes(), film: ready, measureFilm: () => gate.future);
      final pending = c.testFilm();
      expect(row(c, CheckId.film).subtitle, 'Ready on both sides');
      gate.complete(null);
      await pending;
      expect(c.filmFlow, FilmFlow.unknown);
      expect(row(c, CheckId.film).flagged, isFalse);
      c.dispose();
    });

    test('nothing is measured for a room, a link, or a film with no known bitrate', () async {
      var calls = 0;
      Future<double?> probe() async {
        calls++;
        return 1;
      }

      await make(FakeProbes(), film: ready).testFilm();
      await make(FakeProbes(), film: const FilmCheck(FilmKind.link), measureFilm: probe).testFilm();
      await make(
        FakeProbes(),
        film: const FilmCheck(FilmKind.fileReady),
        measureFilm: probe,
      ).testFilm();
      expect(calls, 0);
    });

    test('a probe that throws is not a verdict either', () async {
      final c = make(FakeProbes(), film: ready, measureFilm: () async => throw StateError('x'));
      await c.testFilm();
      expect(c.filmFlow, FilmFlow.unknown);
      c.dispose();
    });

    test('start() runs the check without being asked', () async {
      final probes = FakeProbes();
      final c = make(probes, film: ready, measureFilm: () async => 1e6);
      await c.start();
      await settle();
      expect(c.filmFlow, FilmFlow.mayBuffer);
      c.dispose();
    });

    test('a night derives its bitrate from size and length', () {
      DateNight n({int? ms}) => DateNight(
        id: 'n',
        title: 't',
        startsAt: DateTime.utc(2030),
        proposedBy: 'u',
        status: DateNightStatus.accepted,
        attachKind: 'file',
        fileName: 'f.mkv',
        fileSize: 1000000000,
        fileDurationMs: ms,
        uploadState: 'ready',
      );
      expect(n(ms: 8000000).fileBitrateBps, 1e6);
      expect(n().fileBitrateBps, isNull);
      expect(n(ms: 0).fileBitrateBps, isNull);
      expect(
        DateNight.fromJson({
          'id': 'n',
          'title': 't',
          'starts_at': '2030-01-01T00:00:00Z',
          'proposed_by': 'u',
          'status': 'accepted',
          'file_duration_ms': 8000000,
          'file_size': 1000000000,
        }).fileDurationMs,
        8000000,
      );
      final f = FilmCheck.forNight(n(ms: 8000000), DateTime.utc(2030), mine: false);
      expect(f.bitrateBps, 1e6);
    });
  });

  group('the film waits for a partner who is not on', () {
    test('ready on this side, partner away: neutral, not a warning', () {
      final c = make(FakeProbes(), partnerOnline: () => false);
      final film = row(c, CheckId.film);
      expect(film.subtitle, 'Ready on your side · waiting for Sam');
      expect(film.tone, RowTone.idle);
      expect(film.flagged, isFalse);
      expect(film.actions, isEmpty);
      c.dispose();
    });

    test('the row follows the partner coming online', () {
      var online = false;
      final c = make(FakeProbes(), partnerOnline: () => online);
      expect(row(c, CheckId.film).tone, RowTone.idle);
      online = true;
      c.refresh();
      expect(row(c, CheckId.film).subtitle, 'Ready on both sides');
      expect(row(c, CheckId.film).tone, RowTone.ok);
      c.dispose();
    });

    test('the Remind button sends one nudge and then says so', () async {
      var sent = 0;
      final c = make(
        FakeProbes(),
        partnerOnline: () => false,
        nudge: () async {
          sent++;
          return NudgeResult.sent;
        },
      );
      expect(row(c, CheckId.film).actions.map((a) => a.label), ['Remind Sam']);
      expect(row(c, CheckId.film).fix, contains("hasn't opened the app yet"));
      await c.act(CheckId.film, 'nudge');
      expect(sent, 1);
      expect(row(c, CheckId.film).actions, isEmpty, reason: 'one reminder is enough');
      expect(row(c, CheckId.film).fix, startsWith('Reminder sent.'));
      expect(
        row(c, CheckId.film).flagged,
        isFalse,
        reason: 'a reminder never turns the row into a warning',
      );
      c.dispose();
    });

    test('a throttled nudge says one is enough; a failed one can be tried again', () async {
      final answers = [NudgeResult.throttled];
      final c = make(
        FakeProbes(),
        partnerOnline: () => false,
        nudge: () async => answers.removeAt(0),
      );
      await c.act(CheckId.film, 'nudge');
      expect(row(c, CheckId.film).fix, contains('a moment ago'));
      expect(row(c, CheckId.film).actions, isEmpty);
      c.dispose();

      final f = make(
        FakeProbes(),
        partnerOnline: () => false,
        nudge: () async => throw StateError('offline'),
      );
      await f.act(CheckId.film, 'nudge');
      expect(row(f, CheckId.film).fix, startsWith("Couldn't send that"));
      expect(row(f, CheckId.film).actions.map((a) => a.id), [
        'nudge',
      ], reason: 'so it can be tried again');
      f.dispose();
    });

    test('a room check has nobody to remind', () {
      final c = make(FakeProbes(), partnerOnline: () => false, includeAv: false);
      expect(row(c, CheckId.film).actions, isEmpty);
      expect(row(c, CheckId.film).fix, isNull);
      c.dispose();
    });

    test('a film that is still uploading keeps its warning whoever is on', () {
      final c = make(
        FakeProbes(),
        film: const FilmCheck(FilmKind.fileUploading, percent: 40, mine: true),
        partnerOnline: () => false,
      );
      expect(row(c, CheckId.film).tone, RowTone.warn);
      c.dispose();
    });
  });

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

    test('a held upload reads as waiting for Wi-Fi only for the planner', () {
      final now = DateTime.now().toUtc();
      final n = night(kind: 'file', upload: 'uploading', bytes: 38, size: 100);
      expect(
        FilmCheck.forNight(n, now, mine: true, waitingForWifi: true).kind,
        FilmKind.fileWaitingWifi,
      );
      expect(
        FilmCheck.forNight(n, now, mine: false, waitingForWifi: true).kind,
        FilmKind.fileUploading,
        reason: 'the partner just sees it still arriving',
      );
    });

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
