import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:synctogether/feedback/bug_reports_api.dart';
import 'package:synctogether/feedback/capture/breadcrumb_log.dart';
import 'package:synctogether/feedback/capture/redact.dart';
import 'package:synctogether/feedback/capture/screenshot.dart';
import 'package:synctogether/feedback/contract.dart';
import 'package:synctogether/feedback/feedback_service.dart';
import 'package:synctogether/feedback/queue.dart';

class _Api implements BugReportsApi {
  _Api({this.signedIn = true});
  @override
  bool signedIn;
  Object? failWith;
  int calls = 0;
  final sent = <String?>[];

  @override
  Future<String> submit({
    required String? category,
    required String? note,
    required Map<String, Object?> context,
    required String? sentryEventId,
  }) async {
    calls++;
    if (failWith != null) throw failWith!;
    sent.add(note);
    return 'BUG-${calls.toString().padLeft(4, '0')}';
  }

  @override
  Future<List<BugReportRow>> mine() async => const [];

  final notified = <String, bool>{};
  final appended = <String, List<String>>{};
  Object? failChoices;

  @override
  Future<void> setNotifyWhenFixed(String code, bool on) async {
    if (failChoices != null) throw failChoices!;
    notified[code] = on;
  }

  @override
  Future<void> appendNote(String code, String text) async {
    if (failChoices != null) throw failChoices!;
    appended.putIfAbsent(code, () => []).add(text);
  }
}

class _RejectOnce extends _Api {
  _RejectOnce(this.inner, this.isFirst, this.flip);
  final _Api inner;
  final bool Function() isFirst;
  final void Function() flip;
  @override
  Future<String> submit({
    required String? category,
    required String? note,
    required Map<String, Object?> context,
    required String? sentryEventId,
  }) async {
    if (isFirst()) {
      flip();
      throw const BugReportRejected('context_too_large');
    }
    return 'BUG-0001';
  }
}

RealFeedbackService _service(_Api api, Directory dir, {DateTime Function()? now}) =>
    RealFeedbackService(
      api: api,
      queue: BugReportQueue(dir: () async => dir),
      now: now,
      screenshot: () async => null,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    dir = Directory.systemTemp.createTempSync('fb_test');
    BreadcrumbLog.clear();
  });
  tearDown(() => dir.deleteSync(recursive: true));

  group('redaction', () {
    test('paths shrink to basename, emails and tokens vanish', () {
      expect(redactText('open /Users/maya/Movies/Film.mkv now'), 'open Film.mkv now');
      expect(redactText(r'C:\Users\maya\Videos\clip.mp4'), 'clip.mp4');
      expect(redactText('mail maya@example.com'), 'mail <email>');
      expect(redactText('Bearer abc.def-123'), 'Bearer <token>');
      expect(redactText('GET /x?access_token=abc123&a=1'), contains('access_token=<redacted>'));
      expect(redactText('eyJhbGciOiJIUzI1.eyJzdWIiOiIxMjM0.sigsigsig'), '<token>');
    });

    test('chat-like keys are dropped from data trees', () {
      final out =
          redactValue({
                'message': 'hello',
                'room': 'K7Q2ZP',
                'nested': {'text': 'x', 'ms': 3},
              })
              as Map;
      expect(out['message'], '<omitted>');
      expect(out['room'], 'K7Q2ZP');
      expect((out['nested'] as Map)['text'], '<omitted>');
      expect((out['nested'] as Map)['ms'], 3);
    });

    test('breadcrumb log is a capped ring and renders redacted', () {
      for (var i = 0; i < 130; i++) {
        BreadcrumbLog.record(
          'step $i',
          category: 'sync',
          data: {'file': '/a/b/c$i.mkv', 'text': 'secret'},
        );
      }
      expect(BreadcrumbLog.length, BreadcrumbLog.capacity);
      final out = BreadcrumbLog.render();
      expect(out, contains('step 129'));
      expect(out, isNot(contains('step 29 ')));
      expect(out, isNot(contains('secret')));
      expect(out, isNot(contains('/a/b/')));
    });
  });

  group('limits', () {
    test('screenshot ladder steps the ratio down until it fits', () async {
      final tried = <double>[];
      final out = await fitScreenshot(
        (r) async {
          tried.add(r);
          return Uint8List(r > 0.8 ? 2000 : 500);
        },
        startRatio: 2,
        maxBytes: 1000,
      );
      expect(tried, [2, 1, 0.75]);
      expect(out!.length, 500);
      expect(
        await fitScreenshot((r) async => Uint8List(5000), startRatio: 1, maxBytes: 1000),
        isNull,
      );
    });

    test('context cap keeps the follow-up reference', () {
      final out = capContext({'route': '/lobby', 'follow_up_of': 'BUG-1C0D', 'huge': 'x' * 20000});
      expect(out['follow_up_of'], 'BUG-1C0D');
      expect(out.containsKey('huge'), isFalse);
    });

    test('context cap drops the largest entries first and keeps route', () {
      final big = {
        'route': '/lobby',
        'app': {'v': 1},
        'huge': 'x' * 20000,
        'small': 'y',
      };
      final out = capContext(big);
      expect(out.containsKey('huge'), isFalse);
      expect(out['route'], '/lobby');
      expect(out['truncated'], true);
      expect(out['small'], 'y');
    });
  });

  group('submit and queue', () {
    const capture = BugCapture(screenRoute: '/lobby', logsText: 'log');

    test('sent when the server accepts', () async {
      final api = _Api();
      final res = await _service(
        api,
        dir,
      ).submit(capture, category: .video, note: ' hi ', includeScreenshot: false);
      expect(res, isA<Sent>());
      expect(api.sent, ['hi']);
      expect(await BugReportQueue(dir: () async => dir).load(), isEmpty);
    });

    test('second report inside 30 s is rate limited locally', () async {
      var t = DateTime(2026, 1, 1);
      final svc = _service(_Api(), dir, now: () => t);
      await svc.submit(capture, category: null, includeScreenshot: false);
      t = t.add(const Duration(seconds: 10));
      final res = await svc.submit(capture, category: null, includeScreenshot: false);
      expect(res, isA<RateLimited>());
      expect((res as RateLimited).retryIn, const Duration(seconds: 20));
    });

    test('server rate limit maps to RateLimited', () async {
      final api = _Api()..failWith = const BugReportRateLimited();
      final res = await _service(
        api,
        dir,
      ).submit(capture, category: null, includeScreenshot: false);
      expect(res, isA<RateLimited>());
    });

    test('failure queues once, flush sends it and clears the queue', () async {
      final api = _Api()..failWith = const SocketException('offline');
      final svc = _service(api, dir);
      final res = await svc.submit(
        capture.copyWith(screenshotPng: Uint8List.fromList([1, 2, 3])),
        category: .sync,
        note: 'drifts',
        includeScreenshot: true,
      );
      expect(res, isA<Queued>());
      final q = BugReportQueue(dir: () async => dir);
      final queued = await q.load();
      expect(queued, hasLength(1));
      expect(await q.screenshotOf(queued.single), [1, 2, 3]);
      expect(await q.logsOf(queued.single), 'log');

      api.failWith = null;
      await svc.flushQueue();
      expect(api.sent, ['drifts']);
      expect(await q.load(), isEmpty);
      expect(dir.listSync(), isEmpty);
    });

    test('queue dedupes by id and caps entries', () async {
      final q = BugReportQueue(dir: () async => dir);
      QueuedReport r(String id) => QueuedReport(
        id: id,
        category: null,
        note: null,
        context: const {},
        createdAt: DateTime(2026),
      );
      await q.add(r('a'));
      await q.add(r('a'));
      expect(await q.load(), hasLength(1));
      for (var i = 0; i < 15; i++) {
        await q.add(r('id$i'));
      }
      final all = await q.load();
      expect(all, hasLength(BugReportQueue.maxEntries));
      expect(all.last.id, 'id14');
    });

    test('signed out keeps the report, sign-in lets the backoff retry send it', () async {
      final api = _Api(signedIn: false)..failWith = const SocketException('offline');
      final svc = RealFeedbackService(
        api: api,
        queue: BugReportQueue(dir: () async => dir),
        screenshot: () async => null,
        retryBackoff: const [Duration(milliseconds: 40)],
      );
      await svc.submit(capture, category: null, note: 'later', includeScreenshot: false);
      expect(await BugReportQueue(dir: () async => dir).load(), hasLength(1));
      api.signedIn = true;
      api.failWith = null;
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(api.sent, ['later']);
      svc.dispose();
    });

    test(
      'a sent report is set to notify by default, and a failure there never re-queues',
      () async {
        final api = _Api();
        final svc = _service(api, dir);
        final res = await svc.submit(capture, category: .chat, note: 'x', includeScreenshot: false);
        expect(res, isA<Sent>());
        expect(api.notified, {(res as Sent).code: true});

        final failing = _Api()..failChoices = const SocketException('flaky');
        final svc2 = _service(failing, dir, now: () => DateTime(2030));
        final res2 = await svc2.submit(capture, category: null, includeScreenshot: false);
        expect(res2, isA<Sent>());
        expect(await BugReportQueue(dir: () async => dir).load(), isEmpty);
      },
    );

    test('a code goes straight to the server; a queued id is kept on the device', () async {
      final api = _Api()..failWith = const SocketException('offline');
      final svc = _service(api, dir);
      final queued =
          await svc.submit(capture, category: null, note: 'later', includeScreenshot: false)
              as Queued;
      // The success screen toggles and adds details before the report has a code.
      await svc.setNotifyWhenFixed(queued.localId, false);
      await svc.appendNote(queued.localId, '  it was the second film  ');
      await svc.appendNote(queued.localId, 'and again');
      expect(api.notified, isEmpty);
      expect(api.appended, isEmpty);
      final q = await BugReportQueue(dir: () async => dir).load();
      expect(q.single.notifyWhenFixed, isFalse);
      expect(q.single.appendix, 'it was the second film\n\nand again');

      api.failWith = null;
      await svc.flushQueue();
      // Opted out: no notify call. Details travel with the code the report got.
      expect(api.notified, isEmpty);
      expect(api.appended.values.single, ['it was the second film\n\nand again']);

      await svc.setNotifyWhenFixed('BUG-0001', true);
      await svc.appendNote('BUG-0001', 'one more thing');
      expect(api.notified['BUG-0001'], isTrue);
      expect(api.appended['BUG-0001'], ['one more thing']);
    });

    test('a rejected payload is not queued and lands minimal', () async {
      final api = _Api()..failWith = const BugReportRejected('context_too_large');
      var first = true;
      final svc = _service(_RejectOnce(api, () => first, () => first = false), dir);
      final res = await svc.submit(capture, category: .chat, note: 'x', includeScreenshot: false);
      expect(res, isA<Sent>());
      expect(await BugReportQueue(dir: () async => dir).load(), isEmpty);
    });
  });

  group('breadcrumb summary and logs', () {
    setUp(BreadcrumbLog.clear);

    test('the "last" preview skips our own feedback steps and shows a repeat once', () {
      BreadcrumbLog.record('joined room', category: 'room');
      BreadcrumbLog.record('connected', category: 'av');
      for (var i = 0; i < 3; i++) {
        BreadcrumbLog.record('bug report opened', category: 'feedback');
      }
      BreadcrumbLog.record('connected', category: 'av');
      BreadcrumbLog.record('connected', category: 'av');
      expect(BreadcrumbLog.lastLabels(3), ['room.joined room', 'av.connected']);
    });

    test('only feedback steps means an empty preview, not a line of noise', () {
      BreadcrumbLog.record('bug report opened', category: 'feedback');
      expect(BreadcrumbLog.lastLabels(3), isEmpty);
    });

    test('logs.txt keeps feedback steps but collapses a run into one counted line', () {
      final t = DateTime.utc(2026, 1, 1, 10, 0, 0);
      BreadcrumbLog.record('joined room', category: 'room', at: t);
      for (var i = 0; i < 3; i++) {
        BreadcrumbLog.record(
          'bug report opened',
          category: 'feedback',
          at: t.add(Duration(seconds: i + 1)),
        );
      }
      final lines = BreadcrumbLog.render().split('\n');
      expect(lines, hasLength(2));
      expect(lines[1], contains('[feedback] bug report opened'));
      expect(lines[1], endsWith('(x3)'));
    });

    test('the same message with different data is two steps', () {
      BreadcrumbLog.record('opened', category: 'feedback', data: {'route': '/lobby'});
      BreadcrumbLog.record('opened', category: 'feedback', data: {'route': '/room'});
      expect(BreadcrumbLog.render().split('\n'), hasLength(2));
    });
  });
}
