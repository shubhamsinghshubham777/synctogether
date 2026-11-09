import 'package:flutter/foundation.dart';

DateTime? _time(Object? v) => v == null ? null : DateTime.tryParse('$v')?.toUtc();

/// The other half of a pair, as the server describes them. [timezone] is an
/// IANA name (`Europe/London`) or null while they have not opened the app on a
/// build that reports it.
@immutable
class PairPartner {
  const PairPartner({
    required this.id,
    required this.displayName,
    this.avatarUrl,
    this.timezone,
    this.realName,
    this.nickname,
  });

  /// [displayName] is what *I* call them: my private nickname for them when I
  /// have set one, their own name otherwise. Everything that names the partner
  /// reads it, so a nickname shows up everywhere at once. [realName] is theirs.
  factory PairPartner.fromJson(Map<String, dynamic> json) {
    final real = json['display_name'] as String? ?? 'Your person';
    final nick = (json['nickname'] as String?)?.trim();
    final has = nick != null && nick.isNotEmpty;
    return PairPartner(
      id: json['id'] as String,
      displayName: has ? nick : real,
      avatarUrl: json['avatar_url'] as String?,
      timezone: json['timezone'] as String?,
      realName: real,
      nickname: has ? nick : null,
    );
  }

  final String id;
  final String displayName;
  final String? avatarUrl;
  final String? timezone;

  /// Their own display name, as they set it; null where it is not known apart
  /// from [displayName] (an invite, which has no nickname).
  final String? realName;

  /// My private name for them, or null.
  final String? nickname;

  String get nameTheyChose => realName ?? displayName;

  PairPartner withNickname(String? value) {
    final trimmed = value?.trim();
    final has = trimmed != null && trimmed.isNotEmpty;
    return PairPartner(
      id: id,
      displayName: has ? trimmed : nameTheyChose,
      avatarUrl: avatarUrl,
      timezone: timezone,
      realName: nameTheyChose,
      nickname: has ? trimmed : null,
    );
  }
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
    this.reunionSharedEdit = true,
    this.reunionSetBy,
    this.showReunion = true,
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
      reunionSharedEdit: json['reunion_shared_edit'] as bool? ?? true,
      reunionSetBy: json['reunion_set_by'] as String?,
      showReunion: json['show_reunion'] as bool? ?? true,
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

  /// Whether the other person may change the date, and who set it. With sharing off only
  /// the person who set it can edit or clear it.
  final bool reunionSharedEdit;
  final String? reunionSetBy;

  /// My own lobby preference: whether the countdown shows on my lobby.
  final bool showReunion;

  /// Whether [me] may change or clear the date right now.
  bool canEditReunion(String? me) =>
      reunionSetBy == null || reunionSharedEdit || reunionSetBy == me;

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
    this.inviterPaired = false,
    this.createdAt,
  });

  factory PairInvite.fromJson(Map<String, dynamic> json) => PairInvite(
    code: json['code'] as String,
    inviter: PairPartner.fromJson((json['inviter'] as Map).cast<String, dynamic>()),
    status: PairInviteStatus.fromWire(json['status'] as String?),
    isMine: json['is_mine'] as bool? ?? false,
    inviterPaired: json['inviter_paired'] as bool? ?? false,
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

  /// The sender has since paired with somebody. Whatever else is true of the
  /// invite, there is nobody to pair with now.
  final bool inviterPaired;
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
    this.attachKind = 'none',
    this.youtubeUrl,
    this.fileName,
    this.fileSize,
    this.uploadState = 'none',
    this.uploadBytes = 0,
    this.movedFrom,
    this.updatedAt,
  });

  factory DateNight.fromJson(Map<String, dynamic> json) => DateNight(
    id: json['id'] as String,
    title: json['title'] as String,
    startsAt: _time(json['starts_at']) ?? DateTime.now().toUtc(),
    proposedBy: json['proposed_by'] as String,
    status: DateNightStatus.fromWire(json['status'] as String?),
    attachKind: json['attach_kind'] as String? ?? 'none',
    youtubeUrl: json['youtube_url'] as String?,
    fileName: json['file_name'] as String?,
    fileSize: (json['file_size'] as num?)?.toInt(),
    uploadState: json['upload_state'] as String? ?? 'none',
    uploadBytes: (json['upload_bytes'] as num?)?.toInt() ?? 0,
    movedFrom: _time(json['moved_from']),
    updatedAt: _time(json['updated_at']),
  );

  final String id;
  final String title;
  final DateTime startsAt;

  /// Whoever made the latest proposal. The other person answers it.
  final String proposedBy;
  final DateNightStatus status;

  /// What the planner attached: `none` ("we'll choose together"), `youtube`, or
  /// `file`. When the night starts Our Room opens with it loaded.
  final String attachKind;
  final String? youtubeUrl;

  /// A file's name and size, and how its upload stands: `uploading`, `ready`, or
  /// `stopped` (the connection dropped). `uploadBytes` is how far it has got, as
  /// the planner's app last reported it.
  final String? fileName;
  final int? fileSize;
  final String uploadState;
  final int uploadBytes;

  /// Where this night was moved from while its new time waits for an answer.
  final DateTime? movedFrom;

  /// When the night last changed: how long ago it was cancelled or declined.
  final DateTime? updatedAt;

  bool get hasLink => attachKind == 'youtube' && youtubeUrl != null;
  bool get hasFile => attachKind == 'file';
  bool get fileReady => hasFile && uploadState == 'ready';
  bool get fileUploading => hasFile && uploadState == 'uploading';
  bool get fileStopped => hasFile && uploadState == 'stopped';

  /// Whether something is attached that will be in the room: a link, or a file
  /// that has finished.
  bool get attachmentReady => hasLink || fileReady;

  /// 0 to 1: how much of the file has arrived. A finished upload is 1.
  double get uploadFraction {
    if (fileReady) return 1;
    final size = fileSize;
    if (size == null || size <= 0) return 0;
    return (uploadBytes / size).clamp(0.0, 1.0);
  }

  /// Whole percent, never 100 until it is truly done.
  int get uploadPercent => fileReady ? 100 : (uploadFraction * 100).floor().clamp(0, 99);
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
  tooManyAttempts(
    'too_many_attempts',
    "That's a lot of tries. Give it an hour, then ask for a fresh code.",
  ),
  inviteExpired('invite_expired', 'That invite has expired. Ask for a fresh one.'),
  inviteUsed('invite_used', 'That invite was already used.'),
  inviteCancelled('invite_cancelled', 'That invite was cancelled. Ask for a fresh one.'),
  invalidNickname('invalid_nickname', 'Keep that to 40 characters.'),
  uploadInProgress(
    'upload_in_progress',
    'You already have an upload going. Let it finish first, or choose together.',
  ),
  stagedInvalid('staged_media_invalid', 'That upload timed out. Pick the file again.'),
  invalidAttachment('invalid_attachment', 'Pick a link or a file, not both.'),
  invalidLink('invalid_link', "Hmm, that doesn't look like a YouTube link."),
  notPlanner('not_planner', 'Only whoever planned the night can change that.'),
  invalidEmail('invalid_email', "Hmm, that doesn't look like an email address."),
  tooManyInvites(
    'too_many_invites',
    "That's a lot of invites for one day. Share your link instead, or try again tomorrow.",
  ),
  notPaired('not_paired', "You're not paired yet."),
  patronRequired(
    'patron_required',
    'Planning a date night needs Patron on either side. Answering one never does.',
  ),
  reunionLocked(
    'reunion_locked',
    'That date is kept by whoever set it. Ask them to change it, or to let you edit.',
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
