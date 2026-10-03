import 'package:synctogether/rooms/room_models.dart';

/// The last stretch of a trial, when the rail chip turns Signal.
const kVideoTrialFinalStretch = Duration(minutes: 1);

/// How long the "faces off" note stays on the rail once a trial ends.
const kVideoTrialEndedNoteFor = Duration(seconds: 12);

/// The trial length shown on the camera key before anybody has started one.
/// The server's `tier_limits.video_trial_minutes` decides the real length;
/// this only labels the offer, so a drift costs a wrong badge, never access.
const kVideoTrialOfferMinutes = 10;

enum VideoTrialPhase {
  /// Not a room that has a trial: video rooms, guest rooms, no AV.
  none,

  /// A free room nobody has started the trial in yet.
  available,
  running,
  finalStretch,
  spent,
}

/// Where a room's video trial stands. A `voice` room is a free host's room,
/// which is the only kind with a trial; [refused] is set once the server has
/// said no for this session (the creator's daily allowance is used up), so
/// the key stops offering something it cannot give.
VideoTrialPhase videoTrialPhase({
  required AvLevel avLevel,
  required DateTime? endsAt,
  required DateTime now,
  bool refused = false,
}) {
  if (avLevel != .voice) return .none;
  if (endsAt == null) return refused ? .spent : .available;
  final left = endsAt.difference(now);
  if (left <= Duration.zero) return .spent;
  return left <= kVideoTrialFinalStretch ? .finalStretch : .running;
}

/// "9:42" - minutes and seconds left, rounded up so the chip never reads
/// 0:00 while the camera is still on.
String videoTrialCountdown(Duration left) {
  final secs = left.isNegative ? 0 : (left.inMilliseconds / 1000).ceil();
  return '${secs ~/ 60}:${(secs % 60).toString().padLeft(2, '0')}';
}

/// The server's answers to `start_video_trial`.
enum VideoTrialStart {
  started,
  active,
  notEligible,
  trialSpent,
  dailyCap,
  roomEnded,
  unknown;

  static VideoTrialStart fromWire(String? status) => switch (status) {
    'started' => started,
    'active' => active,
    'not_eligible' => notEligible,
    'trial_spent' => trialSpent,
    'daily_cap' => dailyCap,
    'room_ended' => roomEnded,
    _ => unknown,
  };

  bool get running => this == started || this == active;

  /// Copy for a refusal. Never the raw code.
  String get message => switch (this) {
    dailyCap => "This room's host has used today's video trials. Voice is still on.",
    trialSpent => 'This room already had its video trial. Voice is still on.',
    roomEnded => 'This room has wrapped up.',
    _ => "Couldn't switch video on just now. Voice is still on.",
  };
}
