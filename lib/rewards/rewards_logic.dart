/// The gamification decisions, as free functions over plain values.
///
/// This file is the same seam `lib/sync/sync_logic.dart` established, and it
/// exists for the same reason: scoring rules, streak copy and the session's
/// superlatives are exactly the kind of thing that must be testable without a
/// room, a network or a clock. Nothing here imports Flutter or Supabase.
library;

import 'rewards_models.dart';

/// Mirrors `public.streak_multiplier`. The client never scores anything - the
/// server does - but the board publishes its own formula, so the UI has to be
/// able to state it, and a copy that can drift is a copy worth testing.
double streakMultiplier(int streak) {
  if (streak >= 30) return 1.50;
  if (streak >= 7) return 1.25;
  if (streak >= 3) return 1.10;
  return 1.00;
}

/// The next multiplier band, for the "two more days and you're on 1.25x" nudge.
/// Null once the top band is reached.
({int days, double multiplier})? nextStreakBand(int streak) {
  if (streak < 3) return (days: 3 - streak, multiplier: 1.10);
  if (streak < 7) return (days: 7 - streak, multiplier: 1.25);
  if (streak < 30) return (days: 30 - streak, multiplier: 1.50);
  return null;
}

/// How far through today's qualifying minutes we are, 0..1.
double streakDayProgress(StreakState streak) {
  final target = streak.minMinutes * 60;
  if (target <= 0) return 1;
  return (streak.secondsToday / target).clamp(0.0, 1.0);
}

/// A streak with one day left to save it. This is the only state the UI is
/// allowed to nag about, and even then only when the app is already open - a
/// streak that summons you is the reason streaks have a bad reputation.
bool streakAtRisk(StreakState streak, DateTime today) {
  if (streak.current <= 0 || streak.lastDay == null) return false;
  final gap = DateTime(
    today.year,
    today.month,
    today.day,
  ).difference(DateTime(streak.lastDay!.year, streak.lastDay!.month, streak.lastDay!.day)).inDays;
  return gap >= 1 && !streak.qualifiedToday;
}

/// Progress toward a locked achievement, 0..1, from the metric bundle the
/// server already sends with `my_rewards`.
double achievementProgress(Achievement achievement, Map<String, int> metrics) {
  if (achievement.unlocked) return 1;
  if (achievement.threshold <= 0) return 0;
  final have = metrics[achievement.metric] ?? 0;
  return (have / achievement.threshold).clamp(0.0, 1.0);
}

/// The locked achievement closest to falling, for the "you're nearly there"
/// line. Secrets never show - that is what makes them worth screenshotting.
Achievement? nextAchievement(List<Achievement> achievements, Map<String, int> metrics) {
  Achievement? best;
  var bestProgress = 0.0;
  for (final a in achievements) {
    if (a.unlocked || a.isSecret) continue;
    final progress = achievementProgress(a, metrics);
    if (progress <= 0 || progress >= 1) continue;
    if (progress > bestProgress) {
      bestProgress = progress;
      best = a;
    }
  }
  return best;
}

String rankOrdinal(int rank) {
  if (rank <= 0) return '-';
  final mod100 = rank % 100;
  if (mod100 >= 11 && mod100 <= 13) return '${rank}th';
  return switch (rank % 10) {
    1 => '${rank}st',
    2 => '${rank}nd',
    3 => '${rank}rd',
    _ => '${rank}th',
  };
}

/// "4h 12m", "38m", "2m". Never "0h 0m" - a zero reads as broken.
String formatWatchTime(Duration duration) {
  final totalMinutes = duration.inMinutes;
  if (totalMinutes < 1) return 'under a minute';
  final hours = totalMinutes ~/ 60;
  final minutes = totalMinutes % 60;
  if (hours == 0) return '${minutes}m';
  if (minutes == 0) return '${hours}h';
  return '${hours}h ${minutes}m';
}

/// Rounded hours for the big stat tiles. Below an hour it stays in minutes,
/// because "0.3 hours" is a worse way of saying eighteen minutes.
String formatWatchHours(Duration duration) {
  if (duration.inMinutes < 60) return '${duration.inMinutes}m';
  final hours = duration.inMinutes / 60;
  if (hours < 10) return '${hours.toStringAsFixed(1)}h';
  return '${hours.round()}h';
}

String formatPoints(int points) {
  if (points < 1000) return '$points';
  if (points < 1000000) {
    final thousands = points / 1000;
    return '${thousands < 10 ? thousands.toStringAsFixed(1) : thousands.round()}k';
  }
  return '${(points / 1000000).toStringAsFixed(1)}M';
}

// ---------------------------------------------------------------------------
// Session superlatives
// ---------------------------------------------------------------------------

/// The silly per-person awards a recap card is built around. These are the
/// reason somebody screenshots a recap, and each one costs a single counter
/// `RoomScreen` is already in a position to keep.
enum SuperlativeKey {
  reactions,
  chat,
  pauser,
  camera,
  rideOrDie,
  steady,
  nightOwl,
  firstIn,
  host;

  /// Must match the allow-list in `public.create_recap`. The client picks the
  /// winner; it does not get to invent the award.
  String get wire => switch (this) {
    .reactions => 'reactions',
    .chat => 'chat',
    .pauser => 'pauser',
    .camera => 'camera',
    .rideOrDie => 'ride_or_die',
    .steady => 'steady',
    .nightOwl => 'night_owl',
    .firstIn => 'first_in',
    .host => 'host',
  };

  String get title => switch (this) {
    .reactions => 'Reaction Machine',
    .chat => 'Chatterbox',
    .pauser => 'The Pauser',
    .camera => 'On Camera',
    .rideOrDie => 'Ride or Die',
    .steady => 'Rock Solid',
    .nightOwl => 'Night Owl',
    .firstIn => 'First In',
    .host => 'Host With The Most',
  };

  String get blurb => switch (this) {
    .reactions => 'Never stopped reacting.',
    .chat => 'Said the most.',
    .pauser => 'Kept finding the pause button.',
    .camera => 'Kept the camera on.',
    .rideOrDie => 'There from first frame to last.',
    .steady => 'Never once held everyone up.',
    .nightOwl => 'Still going past 2am.',
    .firstIn => 'Got there first.',
    .host => 'Ran the room.',
  };

  String get icon => switch (this) {
    .reactions => 'celebration',
    .chat => 'forum',
    .pauser => 'pause_circle',
    .camera => 'videocam',
    .rideOrDie => 'favorite',
    .steady => 'verified',
    .nightOwl => 'bedtime',
    .firstIn => 'flag',
    .host => 'stadia_controller',
  };
}

class Superlative {
  const Superlative({required this.key, required this.userId, required this.displayName});

  final SuperlativeKey key;
  final String userId;
  final String displayName;

  Map<String, Object?> toWire() => {'key': key.wire, 'user_id': userId};
}

/// What one member did during one session. Mutable on purpose: `RoomScreen`
/// increments these from the streams it is already listening to.
class MemberTally {
  MemberTally({required this.userId, required this.displayName});

  final String userId;
  String displayName;

  int messages = 0;
  int reactions = 0;
  int transportActions = 0;
  int gateHolds = 0;
  bool cameraOn = false;
  bool presentAtStart = false;
  bool presentAtEnd = false;
}

/// Minimums exist so an award means something. "Reaction Machine" for a single
/// emoji is worse than no award at all.
const _kMinReactions = 5;
const _kMinMessages = 5;
const _kMinTransport = 4;
const kRideOrDieMinimum = Duration(minutes: 30);

/// Picks at most [max] awards, at most one per person, highest-priority award
/// first. Deterministic: ties break on user id, so two clients rendering the
/// same session agree, and a test can assert an exact list.
List<Superlative> superlativesFor({
  required Iterable<MemberTally> tallies,
  required Duration sessionLength,
  bool crossedTwoAm = false,
  String? hostId,
  int max = 3,
}) {
  final members = tallies.toList()..sort((a, b) => a.userId.compareTo(b.userId));
  if (members.length < 2) return const [];

  MemberTally? top(int Function(MemberTally) value, int minimum) {
    MemberTally? best;
    for (final m in members) {
      if (value(m) < minimum) continue;
      if (best == null || value(m) > value(best)) best = m;
    }
    return best;
  }

  final candidates = <(SuperlativeKey, MemberTally?)>[
    (.reactions, top((m) => m.reactions, _kMinReactions)),
    (.chat, top((m) => m.messages, _kMinMessages)),
    (.pauser, top((m) => m.transportActions, _kMinTransport)),
    (.camera, members.where((m) => m.cameraOn).firstOrNull),
    (
      .rideOrDie,
      sessionLength >= kRideOrDieMinimum
          ? members.where((m) => m.presentAtStart && m.presentAtEnd).firstOrNull
          : null,
    ),
    (
      .steady,
      members.where((m) => m.gateHolds == 0 && m.presentAtStart && m.presentAtEnd).firstOrNull,
    ),
    (.nightOwl, crossedTwoAm ? top((m) => m.reactions + m.messages + m.transportActions, 0) : null),
    (.firstIn, members.where((m) => m.presentAtStart).firstOrNull),
    (.host, hostId == null ? null : members.where((m) => m.userId == hostId).firstOrNull),
  ];

  final taken = <String>{};
  final out = <Superlative>[];
  for (final (key, winner) in candidates) {
    if (out.length >= max) break;
    if (winner == null || !taken.add(winner.userId)) continue;
    out.add(Superlative(key: key, userId: winner.userId, displayName: winner.displayName));
  }
  return out;
}

/// A session too short or too solitary to be worth a card. Offering a recap for
/// four minutes alone is how a delightful thing becomes an annoying one.
const kRecapMinimumLength = Duration(minutes: 5);

bool sessionWorthRecapping({
  required Duration length,
  required int peakMembers,
  required bool isGuest,
}) => !isGuest && peakMembers >= 2 && length >= kRecapMinimumLength;

/// The session facts a recap is built from. No media name, no file path, no
/// YouTube id, no chat content - the analytics privacy boundary applies here
/// verbatim, and a recap is a *public* URL, which makes it stricter still.
class SessionRecap {
  const SessionRecap({
    required this.roomId,
    required this.length,
    required this.peakMembers,
    required this.messages,
    required this.reactions,
    required this.modes,
    required this.facecamUsed,
    required this.cleanGate,
    required this.participantIds,
    required this.superlatives,
    this.topEmoji,
  });

  final String roomId;
  final Duration length;
  final int peakMembers;
  final int messages;
  final int reactions;
  final Set<String> modes;
  final bool facecamUsed;
  final bool cleanGate;
  final List<String> participantIds;
  final List<Superlative> superlatives;
  final String? topEmoji;
}
