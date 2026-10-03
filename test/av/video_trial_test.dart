import 'package:flutter_test/flutter_test.dart';
import 'package:synctogether/av/video_trial.dart';
import 'package:synctogether/rooms/room_models.dart';

void main() {
  final now = DateTime.utc(2026, 10, 4, 12);

  group('videoTrialPhase', () {
    VideoTrialPhase at(AvLevel level, DateTime? endsAt, {bool refused = false}) =>
        videoTrialPhase(avLevel: level, endsAt: endsAt, now: now, refused: refused);

    test('only voice rooms have a trial', () {
      expect(at(.video, null), VideoTrialPhase.none);
      expect(at(.none, null), VideoTrialPhase.none);
      expect(at(.voice, null), VideoTrialPhase.available);
    });

    test('runs, then turns to the final stretch, then is spent', () {
      expect(at(.voice, now.add(const Duration(minutes: 9))), VideoTrialPhase.running);
      expect(at(.voice, now.add(const Duration(seconds: 60))), VideoTrialPhase.finalStretch);
      expect(at(.voice, now.add(const Duration(seconds: 1))), VideoTrialPhase.finalStretch);
      expect(at(.voice, now), VideoTrialPhase.spent);
      expect(at(.voice, now.subtract(const Duration(days: 1))), VideoTrialPhase.spent);
    });

    test('a server refusal stops the offer for the session', () {
      expect(at(.voice, null, refused: true), VideoTrialPhase.spent);
    });
  });

  test('countdown rounds up and never goes negative', () {
    expect(videoTrialCountdown(const Duration(minutes: 9, seconds: 42)), '9:42');
    expect(videoTrialCountdown(const Duration(milliseconds: 41200)), '0:42');
    expect(videoTrialCountdown(const Duration(milliseconds: 10)), '0:01');
    expect(videoTrialCountdown(const Duration(seconds: -3)), '0:00');
  });

  test('server answers map to outcomes, with friendly copy for refusals', () {
    expect(VideoTrialStart.fromWire('started').running, isTrue);
    expect(VideoTrialStart.fromWire('active').running, isTrue);
    expect(VideoTrialStart.fromWire('daily_cap'), VideoTrialStart.dailyCap);
    expect(VideoTrialStart.fromWire('surprise'), VideoTrialStart.unknown);
    for (final v in VideoTrialStart.values) {
      expect(v.message, isNot(contains('_')));
    }
  });
}
