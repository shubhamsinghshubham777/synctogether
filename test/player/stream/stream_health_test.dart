import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:synctogether/player/stream/stream_health.dart';
import 'package:synctogether/player/stream/stream_notice.dart';

const _req = 38000000; // 38 Mbps
final _t0 = DateTime(2026, 1, 1, 20);

Stall _stall(int endSecAgo, int lenSecs) {
  final end = _t0.subtract(Duration(seconds: endSecAgo));
  return Stall(end.subtract(Duration(seconds: lenSecs)), end);
}

StreamVerdict _eval({
  List<Stall> stalls = const [],
  DateTime? ongoing,
  double? bps = 20e6,
  int? req = _req,
}) => evaluateStreamHealth(
  stalls: stalls,
  now: _t0,
  ongoingStallStart: ongoing,
  measuredBps: bps,
  requiredBps: req,
);

void main() {
  group('evaluateStreamHealth: silence is the default', () {
    test('no stalls, no verdict - even with a slow measurement', () {
      expect(_eval(), StreamVerdict.healthy);
    });
    test('one short stall is not evidence', () {
      expect(_eval(stalls: [_stall(10, 3)]), StreamVerdict.healthy);
    });
    test('two stalls inside a minute are, when throughput is short', () {
      expect(_eval(stalls: [_stall(50, 2), _stall(5, 2)]), StreamVerdict.suspect);
    });
    test('two stalls more than a minute apart are not', () {
      expect(_eval(stalls: [_stall(100, 2), _stall(5, 2)]), StreamVerdict.healthy);
    });
    test('one stall over 8 s is, finished or still going', () {
      expect(_eval(stalls: [_stall(5, 9)]), StreamVerdict.suspect);
      expect(_eval(ongoing: _t0.subtract(const Duration(seconds: 9))), StreamVerdict.suspect);
      expect(_eval(ongoing: _t0.subtract(const Duration(seconds: 5))), StreamVerdict.healthy);
    });
    test('an ongoing stall plus one earlier counts as two', () {
      expect(
        _eval(stalls: [_stall(30, 2)], ongoing: _t0.subtract(const Duration(seconds: 2))),
        StreamVerdict.suspect,
      );
    });
    test('stalls with throughput at or above 0.9x required are our side of the story: healthy', () {
      expect(_eval(stalls: [_stall(50, 9), _stall(5, 9)], bps: _req * 0.9), StreamVerdict.healthy);
      expect(_eval(stalls: [_stall(50, 9), _stall(5, 9)], bps: _req * 0.89), StreamVerdict.suspect);
    });
    test('unknown throughput or bitrate means no claim at all', () {
      expect(_eval(stalls: [_stall(5, 20)], bps: null), StreamVerdict.healthy);
      expect(_eval(stalls: [_stall(5, 20)], req: null), StreamVerdict.healthy);
    });
  });

  group('classifyProbe', () {
    test('plenty of room means it is our path', () {
      expect(classifyProbe(probeBps: _req * 1.3, requiredBps: _req), ProbeOutcome.ourPath);
      expect(classifyProbe(probeBps: _req * 3, requiredBps: _req), ProbeOutcome.ourPath);
    });
    test('below the bitrate is the only case that blames the link', () {
      expect(classifyProbe(probeBps: _req * 0.99, requiredBps: _req), ProbeOutcome.userLink);
      expect(classifyProbe(probeBps: 22e6, requiredBps: _req), ProbeOutcome.userLink);
    });
    test('in between, or no measurement, stays neutral', () {
      expect(classifyProbe(probeBps: _req * 1.1, requiredBps: _req), ProbeOutcome.inconclusive);
      expect(classifyProbe(probeBps: null, requiredBps: _req), ProbeOutcome.inconclusive);
    });
  });

  test('formatMbps reads like a person', () {
    expect(formatMbps(38.4e6), 'about 38 Mbps');
    expect(formatMbps(21.6e6), 'about 22 Mbps');
    expect(formatMbps(400000), 'under 1 Mbps');
  });

  group('StreamHealthMonitor', () {
    test('records time to first frame and counts stalls only while playing', () {
      fakeAsync((fa) {
        final start = DateTime(2026);
        DateTime now() => start.add(fa.elapsed);
        final log = <String>[];
        final m = StreamHealthMonitor(
          requiredBps: _req,
          sampler: () async => const StreamSample(),
          onSuspect: (_) {},
          now: now,
          log: (msg, _) => log.add(msg),
        )..start();
        m.onBuffering(true); // initial load: not a stall
        fa.elapse(const Duration(seconds: 2));
        m.onFirstFrame();
        m.onBuffering(false);
        expect(m.firstFrameMs, 2000);
        expect(m.stallCount, 0);

        m.onPlaying(true);
        fa.elapse(const Duration(seconds: 5));
        m.onBuffering(true);
        fa.elapse(const Duration(seconds: 3));
        m.onBuffering(false);
        expect(m.stallCount, 1);
        expect(m.stallTotal, const Duration(seconds: 3));

        // Paused by the user: a buffering edge is not a stall.
        m.onPlaying(false);
        m.onBuffering(true);
        fa.elapse(const Duration(seconds: 4));
        m.onBuffering(false);
        expect(m.stallCount, 1);
        expect(
          log,
          containsAll(['stream first frame', 'stream stall started', 'stream stall ended']),
        );
        m.stop();
      });
    });

    test('flags a struggling stream once, then holds its tongue for the cooldown', () {
      fakeAsync((fa) {
        final start = DateTime(2026);
        DateTime now() => start.add(fa.elapsed);
        var bytes = 0;
        var busy = 0;
        final verdicts = <StreamHealthSnapshot>[];
        final m = StreamHealthMonitor(
          requiredBps: _req,
          // 10 Mbps of origin throughput while it was being asked: well short.
          sampler: () async {
            bytes += 1250000;
            busy += 1000000;
            return StreamSample(originBytes: bytes, busyMicros: busy);
          },
          onSuspect: verdicts.add,
          now: now,
          log: (_, _) {},
        )..start();
        m.onFirstFrame();
        m.onPlaying(true);
        for (var i = 0; i < 2; i++) {
          fa.elapse(const Duration(seconds: 6));
          m.onBuffering(true);
          fa.elapse(const Duration(seconds: 2));
          m.onBuffering(false);
        }
        fa.elapse(const Duration(seconds: 3));
        expect(verdicts, hasLength(1));
        expect(verdicts.single.measuredBps, closeTo(10e6, 1e6));
        expect(verdicts.single.stallsInWindow, 2);
        // Still stalling, but inside the cooldown: silent.
        m.onBuffering(true);
        fa.elapse(const Duration(seconds: 30));
        expect(verdicts, hasLength(1));
        m.stop();
      });
    });

    test('a fast origin never raises a verdict, however much it stalls', () {
      fakeAsync((fa) {
        final start = DateTime(2026);
        var bytes = 0;
        var busy = 0;
        var flagged = false;
        final m = StreamHealthMonitor(
          requiredBps: _req,
          sampler: () async {
            bytes += 12500000; // 100 Mbps
            busy += 1000000;
            return StreamSample(originBytes: bytes, busyMicros: busy);
          },
          onSuspect: (_) => flagged = true,
          now: () => start.add(fa.elapsed),
          log: (_, _) {},
        )..start();
        m.onFirstFrame();
        m.onPlaying(true);
        for (var i = 0; i < 4; i++) {
          fa.elapse(const Duration(seconds: 5));
          m.onBuffering(true);
          fa.elapse(const Duration(seconds: 9));
          m.onBuffering(false);
        }
        expect(flagged, isFalse);
        m.stop();
      });
    });
  });

  group('StreamNoticeController', () {
    StreamHealthSnapshot snap() => const StreamHealthSnapshot(
      requiredBps: _req,
      measuredBps: 10e6,
      stallsInWindow: 2,
      longestStall: Duration(seconds: 3),
    );

    test('our path: escalates silently and shows only the neutral note, at most twice', () async {
      var escalations = 0;
      final c = StreamNoticeController(
        probe: () async => _req * 2.0,
        escalate: () => escalations++,
      );
      expect(await c.onSuspect(snap()), ProbeOutcome.ourPath);
      expect(c.notice, StreamNotice.bufferingMore);
      expect(escalations, 1);
      c.dismiss();
      await c.onSuspect(snap());
      expect(c.notice, StreamNotice.bufferingMore);
      c.dismiss();
      await c.onSuspect(snap());
      expect(c.notice, StreamNotice.none, reason: 'the third time is silent');
      expect(escalations, 3);
    });

    test('inconclusive: helps quietly, says nothing', () async {
      var escalated = false;
      final c = StreamNoticeController(probe: () async => null, escalate: () => escalated = true);
      expect(await c.onSuspect(snap()), ProbeOutcome.inconclusive);
      expect(c.notice, StreamNotice.none);
      expect(escalated, isTrue);
    });

    test('link below the bitrate: one connection notice per file, never twice', () async {
      var escalations = 0;
      final c = StreamNoticeController(probe: () async => 22e6, escalate: () => escalations++);
      await c.onSuspect(snap());
      expect(c.notice, StreamNotice.connection);
      expect(c.capacityBps, 22e6);
      expect(c.requiredBps, _req);
      c.dismiss(); // Keep going
      await c.onSuspect(snap());
      expect(c.notice, StreamNotice.none, reason: 'already told them once for this file');
      expect(escalations, 1, reason: 'but still helps quietly');
      c.resetForNewFile();
      await c.onSuspect(snap());
      expect(c.notice, StreamNotice.connection, reason: 'a new file earns a new notice');
    });

    test('buffer ahead moves to the buffering state; a second probe cannot overlap', () async {
      var probes = 0;
      final c = StreamNoticeController(
        probe: () async {
          probes++;
          await Future<void>.delayed(const Duration(milliseconds: 20));
          return 22e6;
        },
        escalate: () {},
      );
      final a = c.onSuspect(snap());
      final b = c.onSuspect(snap());
      await Future.wait([a, b]);
      expect(probes, 1);
      c.startBufferAhead();
      expect(c.notice, StreamNotice.bufferingAhead);
      c.dismiss();
      expect(c.notice, StreamNotice.none);
    });
  });
}
