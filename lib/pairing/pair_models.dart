import 'package:flutter/foundation.dart';

DateTime? _time(Object? v) => v == null ? null : DateTime.tryParse('$v')?.toUtc();

/// The other half of a pair, as the server describes them. [timezone] is an
/// IANA name (`Europe/London`) or null while they have not opened the app on a
/// build that reports it.
@immutable
class PairPartner {
  const PairPartner({required this.id, required this.displayName, this.avatarUrl, this.timezone});

  factory PairPartner.fromJson(Map<String, dynamic> json) => PairPartner(
    id: json['id'] as String,
    displayName: json['display_name'] as String? ?? 'Your person',
    avatarUrl: json['avatar_url'] as String?,
    timezone: json['timezone'] as String?,
  );

  final String id;
  final String displayName;
  final String? avatarUrl;
  final String? timezone;
}

/// My pair, from `my_pair()`.
@immutable
class PairInfo {
  const PairInfo({
    required this.pairId,
    required this.since,
    required this.partner,
    this.reunionOn,
    this.reunionLabel,
    this.patron = false,
    this.roomId,
    this.roomCode,
  });

  factory PairInfo.fromJson(Map<String, dynamic> json) {
    final reunion = json['reunion_on'] as String?;
    return PairInfo(
      pairId: json['pair_id'] as String,
      since: _time(json['since']) ?? DateTime.now().toUtc(),
      partner: PairPartner.fromJson((json['partner'] as Map).cast<String, dynamic>()),
      // A date with no time of day: parsed as a calendar day, not an instant.
      reunionOn: reunion == null ? null : DateTime.tryParse(reunion),
      reunionLabel: json['reunion_label'] as String?,
      patron: json['patron'] as bool? ?? false,
      roomId: json['room_id'] as String?,
      roomCode: json['room_code'] as String?,
    );
  }

  final String pairId;
  final DateTime since;
  final PairPartner partner;
  final DateTime? reunionOn;
  final String? reunionLabel;

  /// Either partner has Patron. Decides who may schedule and how much history
  /// is shown - the server enforces both, this only shapes the affordance.
  final bool patron;
  final String? roomId;
  final String? roomCode;
}

enum PairInviteStatus {
  pending,
  expired,
  accepted,
  cancelled;

  static PairInviteStatus fromWire(String? v) =>
      values.firstWhere((s) => s.name == v, orElse: () => pending);
}

/// An invite as the accept screen and the lobby banner show it. [inviter] is
/// who sent it; for an invite I sent myself it is me.
@immutable
class PairInvite {
  const PairInvite({
    required this.code,
    required this.inviter,
    required this.expiresAt,
    this.status = PairInviteStatus.pending,
    this.isMine = false,
    this.createdAt,
  });

  factory PairInvite.fromJson(Map<String, dynamic> json) => PairInvite(
    code: json['code'] as String,
    inviter: PairPartner.fromJson((json['inviter'] as Map).cast<String, dynamic>()),
    status: PairInviteStatus.fromWire(json['status'] as String?),
    isMine: json['is_mine'] as bool? ?? false,
    createdAt: _time(json['created_at']),
    expiresAt: _time(json['expires_at']) ?? DateTime.now().toUtc(),
  );

  /// A row I own, from `create_pair_invite` (a bare `pair_invites` record).
  factory PairInvite.mine(Map<String, dynamic> row, PairPartner me) => PairInvite(
    code: row['code'] as String,
    inviter: me,
    isMine: true,
    createdAt: _time(row['created_at']),
    expiresAt: _time(row['expires_at']) ?? DateTime.now().toUtc(),
  );

  final String code;
  final PairPartner inviter;
  final PairInviteStatus status;
  final bool isMine;
  final DateTime? createdAt;
  final DateTime expiresAt;

  bool isLiveAt(DateTime now) => status == PairInviteStatus.pending && expiresAt.isAfter(now);
}

enum DateNightStatus {
  proposed,
  accepted,
  declined,
  cancelled;

  static DateNightStatus fromWire(String? v) =>
      values.firstWhere((s) => s.name == v, orElse: () => proposed);
}

@immutable
class DateNight {
  const DateNight({
    required this.id,
    required this.title,
    required this.startsAt,
    required this.proposedBy,
    required this.status,
  });

  factory DateNight.fromJson(Map<String, dynamic> json) => DateNight(
    id: json['id'] as String,
    title: json['title'] as String,
    startsAt: _time(json['starts_at']) ?? DateTime.now().toUtc(),
    proposedBy: json['proposed_by'] as String,
    status: DateNightStatus.fromWire(json['status'] as String?),
  );

  final String id;
  final String title;
  final DateTime startsAt;

  /// Whoever made the latest proposal. The other person answers it.
  final String proposedBy;
  final DateNightStatus status;
}

@immutable
class PairSession {
  const PairSession({required this.title, required this.startedAt, required this.seconds});

  factory PairSession.fromJson(Map<String, dynamic> json) => PairSession(
    title: json['title'] as String?,
    startedAt: _time(json['started_at']) ?? DateTime.now().toUtc(),
    seconds: (json['seconds'] as num?)?.toInt() ?? 0,
  );

  final String? title;
  final DateTime startedAt;
  final int seconds;
}

/// `pair_history()`: the visible rows, and how many are kept behind the lock.
@immutable
class PairHistory {
  const PairHistory({this.items = const [], this.lockedCount = 0, this.patron = false});

  factory PairHistory.fromJson(Map<String, dynamic> json) => PairHistory(
    items: [
      for (final r in (json['items'] as List? ?? const []))
        PairSession.fromJson((r as Map).cast<String, dynamic>()),
    ],
    lockedCount: (json['locked_count'] as num?)?.toInt() ?? 0,
    patron: json['patron'] as bool? ?? false,
  );

  static const empty = PairHistory();

  final List<PairSession> items;
  final int lockedCount;
  final bool patron;
}

@immutable
class PairStats {
  const PairStats({
    this.streakWeeks = 0,
    this.bestStreakWeeks = 0,
    this.doneThisWeek = false,
    this.nights = 0,
    this.hours = 0,
    this.films = 0,
  });

  factory PairStats.fromJson(Map<String, dynamic> json) => PairStats(
    streakWeeks: (json['streak_weeks'] as num?)?.toInt() ?? 0,
    bestStreakWeeks: (json['best_streak_weeks'] as num?)?.toInt() ?? 0,
    doneThisWeek: json['done_this_week'] as bool? ?? false,
    nights: (json['nights'] as num?)?.toInt() ?? 0,
    hours: (json['hours'] as num?)?.toDouble() ?? 0,
    films: (json['films'] as num?)?.toInt() ?? 0,
  );

  static const empty = PairStats();

  final int streakWeeks;
  final int bestStreakWeeks;
  final bool doneThisWeek;
  final int nights;
  final double hours;
  final int films;
}

/// Which notifications a person wants. Server defaults: everything on.
@immutable
class PushPrefs {
  const PushPrefs({
    this.calls = true,
    this.dateNights = true,
    this.reunion = true,
    this.quietHours = true,
  });

  factory PushPrefs.fromJson(Map<String, dynamic> json) => PushPrefs(
    calls: json['calls'] as bool? ?? true,
    dateNights: json['date_nights'] as bool? ?? true,
    reunion: json['reunion'] as bool? ?? true,
    quietHours: json['quiet_hours'] as bool? ?? true,
  );

  final bool calls;
  final bool dateNights;
  final bool reunion;
  final bool quietHours;

  PushPrefs withKey(String key, bool value) => switch (key) {
    'calls' => PushPrefs(
      calls: value,
      dateNights: dateNights,
      reunion: reunion,
      quietHours: quietHours,
    ),
    'date_nights' => PushPrefs(
      calls: calls,
      dateNights: value,
      reunion: reunion,
      quietHours: quietHours,
    ),
    'reunion' => PushPrefs(
      calls: calls,
      dateNights: dateNights,
      reunion: value,
      quietHours: quietHours,
    ),
    'quiet_hours' => PushPrefs(
      calls: calls,
      dateNights: dateNights,
      reunion: reunion,
      quietHours: value,
    ),
    _ => this,
  };
}

/// Friendly copy for every pairing RPC error. The real cause goes to Sentry
/// elsewhere; this is only what a person reads.
enum PairErrorCode {
  signInRequired('sign_in_required', 'Pairing lives on an account. Sign in and try again.'),
  alreadyPaired('already_paired', "You're already paired. Unpair first to pair with someone new."),
  partnerAlreadyPaired('partner_already_paired', 'They paired with someone else in the meantime.'),
  cannotPairSelf('cannot_pair_self', "That's your own invite. Send it to your person instead."),
  inviteNotFound('invite_not_found', "Hmm, we couldn't find that invite."),
  inviteExpired('invite_expired', 'That invite has expired. Ask for a fresh one.'),
  inviteUsed('invite_used', 'That invite was already used.'),
  inviteCancelled('invite_cancelled', 'That invite was cancelled. Ask for a fresh one.'),
  notPaired('not_paired', "You're not paired yet."),
  patronRequired(
    'patron_required',
    'Planning a date night needs Patron on either side. Answering one never does.',
  ),
  invalidTime('invalid_time', 'Pick a time at least a few minutes from now.'),
  invalidTitle('invalid_title', 'Give it a name first.'),
  nightNotOpen('night_not_open', 'That date night has already been answered.'),
  accountBanned('account_banned', 'Your account has been suspended from using rooms.'),
  notAuthenticated('not_authenticated', 'Your session has expired. Please sign in again.'),
  unknown('unknown', 'Something went sideways. Give it another try.');

  const PairErrorCode(this.code, this.message);

  final String code;
  final String message;

  static PairErrorCode fromError(Object error) {
    final text = error.toString();
    for (final value in values) {
      if (value != unknown && text.contains(value.code)) return value;
    }
    return unknown;
  }
}
