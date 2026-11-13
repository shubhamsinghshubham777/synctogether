import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:synctogether/feedback/bug_reports_api.dart';
import 'package:synctogether/feedback/capture/media_details.dart';
import 'package:synctogether/feedback/capture/probes.dart';
import 'package:synctogether/feedback/contract.dart';
import 'package:synctogether/feedback/fake_feedback_service.dart';
import 'package:synctogether/feedback/feedback_service.dart';
import 'package:synctogether/feedback/queue.dart';

class _Api implements BugReportsApi {
  @override
  bool signedIn = true;
  final contexts = <Map<String, Object?>>[];

  @override
  Future<String> submit({
    required String? category,
    required String? note,
    required Map<String, Object?> context,
    required String? sentryEventId,
  }) async {
    contexts.add(context);
    return 'BUG-0001';
  }

  @override
  Future<List<BugReportRow>> mine() async => const [];
  @override
  Future<void> setNotifyWhenFixed(String code, bool on) async {}
  @override
  Future<void> appendNote(String code, String text) async {}
}

void main() {
  group('extension and name', () {
    test('lower-cases and takes the last dot of the last segment', () {
      expect(mediaExtension('Movie.Final.Cut.MKV'), 'mkv');
      expect(mediaExtension('/Users/a.b/films/clip.mp4'), 'mp4');
      expect(mediaExtension(r'C:\Videos\clip.AVI'), 'avi');
    });

    test('ignores query strings and fragments', () {
      expect(mediaExtension('https://cdn.example.com/a/b/movie.webm?token=abc.def#t=10'), 'webm');
    });

    test('no extension, hidden files, trailing dot and junk give null', () {
      expect(mediaExtension('README'), isNull);
      expect(mediaExtension('.hidden'), isNull);
      expect(mediaExtension('movie.'), isNull);
      expect(mediaExtension('movie.not an ext'), isNull);
      expect(mediaExtension('movie.toolongext'), isNull);
      expect(mediaExtension(null), isNull);
      expect(mediaExtension('   '), isNull);
    });

    test('file name is the base name only, never a path or a query', () {
      expect(mediaFileName('/Users/maya/Movies/Night Show.mkv'), 'Night Show.mkv');
      expect(mediaFileName('https://x.test/v/clip.mp4?sig=SECRET'), 'clip.mp4');
      expect(mediaFileName('maya@example.com.mkv'), isNot(contains('maya')));
      expect(mediaFileName(''), isNull);
      expect(mediaFileName('${'ab ' * 100}.mkv')!.length, kMediaValueMax);
    });
  });

  group('size bucket', () {
    const mib = 1024 * 1024;
    const gib = 1024 * mib;
    test('boundaries', () {
      expect(sizeBucket(0), '<100 MB');
      expect(sizeBucket(100 * mib - 1), '<100 MB');
      expect(sizeBucket(100 * mib), '100 MB-1 GB');
      expect(sizeBucket(gib - 1), '100 MB-1 GB');
      expect(sizeBucket(gib), '1-4 GB');
      expect(sizeBucket(4 * gib - 1), '1-4 GB');
      expect(sizeBucket(4 * gib), '4-8 GB');
      expect(sizeBucket(8 * gib - 1), '4-8 GB');
      expect(sizeBucket(8 * gib), '>8 GB');
    });
  });

  group('bit depth', () {
    test('from the pixel format', () {
      expect(bitDepthOf('yuv420p'), 8);
      expect(bitDepthOf('yuv420p10le'), 10);
      expect(bitDepthOf('yuv444p12be'), 12);
      expect(bitDepthOf('p010'), 10);
      expect(bitDepthOf('nv12'), 8);
      expect(bitDepthOf(null), isNull);
      expect(bitDepthOf(''), isNull);
    });
  });

  group('mpv log lines', () {
    test('lose urls, paths and file names but keep the extension', () {
      expect(
        redactMpvLine("Opening 'https://cdn.example.com/a/Night Show.mkv?token=abc'"),
        isNot(contains('example.com')),
      );
      final line = redactMpvLine('[ffmpeg/demuxer] /Users/maya/Movies/Night.Show.2024.mkv: error');
      expect(line, isNot(contains('maya')));
      expect(line, isNot(contains('Night')));
      expect(line, contains('<file>.mkv'));
      expect(redactMpvLine('Can not open external file Subs/English.ass.'), contains('<file>.ass'));
      expect(redactMpvLine('mail me@example.com'), isNot(contains('me@')));
    });

    test('the buffer keeps the last ten warnings and errors only, without repeats', () {
      final b = MpvLogBuffer();
      b.add('info', 'hello');
      b.add('v', 'chatty');
      for (var i = 0; i < 15; i++) {
        b.add('warn', 'problem $i');
      }
      b.add('warn', 'problem 14');
      expect(b.lines.length, 10);
      expect(b.lines.first, 'problem 5');
      expect(b.lines.last, 'problem 14');
    });
  });

  group('sections', () {
    test('live sections carry the extension and never the name', () {
      final s = liveSections(
        const MediaFacts(
          mode: 'local',
          source: 'local',
          nameOrUri: '/Users/maya/Movies/Secret Film.MKV',
          position: Duration(seconds: 3852),
          duration: Duration(seconds: 6720),
          playing: true,
          subtitleFormats: ['subrip', 'ass', 'ass'],
          externalSubtitles: 1,
          audioTrackCount: 2,
          uploadState: 'ready',
        ),
      );
      expect(s['media'], {
        'mode': 'local',
        'source': 'local',
        'ext': 'mkv',
        'upload': 'ready',
        'pos_s': '3852',
        'dur_s': '6720',
        'playing': 'true',
        'buffering': 'false',
      });
      expect(s['subs'], {'tracks': '3', 'formats': 'subrip, ass', 'external': '1'});
      expect(s['audio'], {'tracks': '2'});
      expect(s.toString(), isNot(contains('Secret')));
      expect(s.toString(), isNot(contains('maya')));
    });

    test('youtube says only the mode and playback state', () {
      final s = liveSections(
        const MediaFacts(
          mode: 'youtube',
          source: 'youtube',
          nameOrUri: 'https://www.youtube.com/watch?v=dQw4w9WgXcQ',
          subtitleFormats: ['vtt'],
          audioTrackCount: 1,
        ),
      );
      expect(s.keys, ['media']);
      expect(s['media']!.containsKey('ext'), isFalse);
      expect(s.toString(), isNot(contains('dQw4')));
    });

    test('reads what mpv has and leaves out what it lacks', () async {
      final props = {
        'file-format': 'matroska,webm',
        'file-size': '${3 * 1024 * 1024 * 1024}',
        'video-format': 'hevc',
        'current-tracks/video/codec-profile': 'Main 10',
        'video-params/w': '3840',
        'video-params/h': '2160',
        'container-fps': '23.976',
        'video-params/pixelformat': 'yuv420p10le',
        'video-bitrate': '18400000',
        'video-params/primaries': 'bt.2020',
        'video-params/gamma': 'pq',
        'video-params/colormatrix': 'bt.2020-ncl',
        'video-params/colorlevels': 'limited',
        'audio-codec-name': 'eac3',
        'audio-params/hr-channels': '5.1',
        'audio-params/samplerate': '48000',
        'hwdec-current': 'videotoolbox',
        'current-vo': 'gpu-next',
      };
      final out = await readMpvSections((p) async => props[p]);
      expect(out['media'], {'container': 'matroska,webm', 'size': '1-4 GB'});
      expect(out['video'], {
        'codec': 'hevc',
        'profile': 'Main 10',
        'res': '3840x2160',
        'fps': '23.98',
        'pix': 'yuv420p10le',
        'bits': '10',
        'kbps': '18400',
      });
      expect(out['color'], {
        'primaries': 'bt.2020',
        'transfer': 'pq',
        'matrix': 'bt.2020-ncl',
        'range': 'limited',
        'hdr': 'hdr10',
      });
      expect(out['audio'], {'codec': 'eac3', 'ch': '5.1', 'rate': '48000'});
      expect(out['decode'], {'mode': 'hardware', 'hwdec': 'videotoolbox', 'vo': 'gpu-next'});

      // Sample of what a report line looks like for a human.
      // ignore: avoid_print
      print(
        out.entries
            .map(
              (e) => '${e.key}: ${e.value.entries.map((l) => '${l.key} ${l.value}').join(' · ')}',
            )
            .join('\n'),
      );
    });

    test('a missing, empty or throwing property just omits its line', () async {
      final out = await readMpvSections((p) async {
        if (p == 'video-format') throw StateError('no such property');
        if (p == 'hwdec-current') return 'no';
        if (p == 'audio-codec-name') return '';
        if (p == 'video-params/w') return '1920';
        if (p == 'video-params/h') return '1080';
        return null;
      });
      expect(out['video'], {'res': '1920x1080'});
      expect(out['decode'], {'mode': 'software'});
      expect(out.containsKey('audio'), isFalse);
      expect(out.containsKey('color'), isFalse);
    });

    test('a read that hangs is given up on', () async {
      final out = await readMpvSections((p) async {
        if (p == 'video-format') await Future<void>.delayed(const Duration(seconds: 5));
        return p == 'video-params/w' ? '640' : null;
      });
      expect(out['video']?.containsKey('codec') ?? false, isFalse);
    });

    test('the size cap drops the log and the tail sections first and keeps media', () {
      final big = {
        'media': {'mode': 'local'},
        'video': {'codec': 'h' * 100},
        'mpv': {'last': 'x' * 2000},
      };
      final out = capSections(big, max: 400);
      expect(out.containsKey('mpv'), isFalse);
      expect(out.keys, containsAll(['media', 'video']));
      final tiny = capSections({
        'media': {'mode': 'local'},
        'video': {'codec': 'h' * 500},
      }, max: 50);
      expect(tiny.keys, ['media']);
    });
  });

  group('the name stays out unless the user opts in', () {
    late Directory dir;
    setUp(() {
      SharedPreferences.setMockInitialValues({});
      dir = Directory.systemTemp.createTempSync('media_details_test');
    });
    tearDown(() => dir.deleteSync(recursive: true));

    RealFeedbackService svc(_Api api) => RealFeedbackService(
      api: api,
      queue: BugReportQueue(dir: () async => dir),
      screenshot: () async => null,
    );

    test('optional probe values are never in the snapshot', () {
      final undo = [
        FeedbackProbes.register('media', () => {'ext': 'mkv'}),
        FeedbackProbes.registerOptional('media.file_name', () => 'Secret Film.mkv'),
        FeedbackProbes.register('subs', () => {}),
      ];
      final snap = FeedbackProbes.snapshot();
      expect(snap.toString(), isNot(contains('Secret')));
      expect(snap.containsKey('subs'), isFalse, reason: 'empty probes are skipped');
      expect(FeedbackProbes.optional('media.file_name'), 'Secret Film.mkv');
      for (final u in undo) {
        u();
      }
      expect(FeedbackProbes.optional('media.file_name'), isNull);
    });

    test('a capture sends the name only when includeFileName is on', () async {
      const base = BugCapture(screenRoute: '/lobby/room/x', fileName: 'Secret Film.mkv');
      expect(base.includeFileName, isFalse);
      expect(base.fileNameToSend, isNull);
      expect(base.copyWith(includeFileName: true).fileNameToSend, 'Secret Film.mkv');
      expect(base.copyWith(clearFileName: true).fileName, isNull);

      final off = _Api();
      await svc(off).submit(base, category: null, includeScreenshot: false);
      expect(off.contexts.single.toString(), isNot(contains('Secret')));

      final on = _Api();
      await svc(
        on,
      ).submit(base.copyWith(includeFileName: true), category: null, includeScreenshot: false);
      expect(on.contexts.single['media_file_name'], 'Secret Film.mkv');
      expect((on.contexts.single['summary'] as Map)['file'], 'Secret Film.mkv');
    });

    test('the fake service drops the name unless included', () async {
      final fake = FakeFeedbackService();
      const c = BugCapture(screenRoute: '/lobby', fileName: 'Secret Film.mkv');
      await fake.submit(c, category: null, includeScreenshot: false);
      await fake.submit(
        c.copyWith(includeFileName: true),
        category: null,
        includeScreenshot: false,
      );
      expect(fake.submitted.first.fileName, isNull);
      expect(fake.submitted.last.fileName, 'Secret Film.mkv');
    });
  });
}
