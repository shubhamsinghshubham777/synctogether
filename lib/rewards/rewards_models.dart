/// Plain data for the gamification layer. Nothing here talks to Supabase, and
/// nothing here decides anything - see `rewards_logic.dart` for the decisions
/// and `rewards_service.dart` for the round trips.
library;

enum RewardGrade {
  bronze,
  silver,
  gold,
  secret;

  static RewardGrade fromWire(String? value) => switch (value) {
    'silver' => .silver,
    'gold' => .gold,
    'secret' => .secret,
    _ => .bronze,
  };
}

/// Cosmetic ring drawn around an avatar. Unlocks grant these and nothing else -
/// handing out extended reactions or bigger rooms for logging in would make the
/// subscription look optional, which is the one thing a reward must never do.
enum AvatarFrame {
  ember,
  halo,
  pulse,
  aurora,
  laurel,
  aurum;

  static AvatarFrame? fromWire(String? value) => switch (value) {
    'ember' => .ember,
    'halo' => .halo,
    'pulse' => .pulse,
    'aurora' => .aurora,
    'laurel' => .laurel,
    'aurum' => .aurum,
    _ => null,
  };

  String get label => switch (this) {
    .ember => 'Ember',
    .halo => 'Halo',
    .pulse => 'Pulse',
    .aurora => 'Aurora',
    .laurel => 'Laurel',
    .aurum => 'Aurum',
  };

  /// The only frame not earned by an achievement: Premium wears it by right,
  /// and the server enforces that in `equip_frame`.
  bool get isPremiumOnly => this == .aurum;
}

class Achievement {
  const Achievement({
    required this.id,
    required this.title,
    required this.description,
    required this.icon,
    required this.grade,
    required this.metric,
    required this.threshold,
    this.frame,
    this.unlocked = false,
    this.unlockedAt,
    this.seen = false,
  });

  final String id;
  final String title;
  final String description;

  /// A `material_symbols_icons` name, resolved client-side - the catalogue is a
  /// database table so a new badge is an insert, and a table cannot hold an
  /// `IconData`.
  final String icon;
  final RewardGrade grade;
  final String metric;
  final int threshold;
  final AvatarFrame? frame;
  final bool unlocked;
  final DateTime? unlockedAt;
  final bool seen;

  bool get isSecret => grade == .secret;

  factory Achievement.fromJson(Map<String, dynamic> json) => Achievement(
    id: json['id'] as String,
    title: json['title'] as String? ?? '',
    description: json['description'] as String? ?? '',
    icon: json['icon'] as String? ?? 'workspace_premium',
    grade: RewardGrade.fromWire(json['grade'] as String?),
    metric: json['metric'] as String? ?? '',
    threshold: (json['threshold'] as num?)?.toInt() ?? 1,
    frame: AvatarFrame.fromWire(
      (json['reward'] as Map?)?.cast<String, dynamic>()['frame'] as String?,
    ),
    unlocked: json['unlocked'] as bool? ?? false,
    unlockedAt: json['unlocked_at'] != null
        ? DateTime.tryParse(json['unlocked_at'] as String)
        : null,
    seen: json['seen'] as bool? ?? false,
  );
}

class StreakState {
  const StreakState({
    this.current = 0,
    this.longest = 0,
    this.freezes = 0,
    this.secondsToday = 0,
    this.minMinutes = 20,
    this.qualifiedToday = false,
    this.lastDay,
    this.lastFreezeDay,
  });

  final int current;
  final int longest;
  final int freezes;
  final int secondsToday;
  final int minMinutes;
  final bool qualifiedToday;
  final DateTime? lastDay;
  final DateTime? lastFreezeDay;

  Duration get today => Duration(seconds: secondsToday);

  factory StreakState.fromJson(Map<String, dynamic> json) => StreakState(
    current: (json['current'] as num?)?.toInt() ?? 0,
    longest: (json['longest'] as num?)?.toInt() ?? 0,
    freezes: (json['freezes'] as num?)?.toInt() ?? 0,
    secondsToday: (json['seconds_today'] as num?)?.toInt() ?? 0,
    minMinutes: (json['min_minutes'] as num?)?.toInt() ?? 20,
    qualifiedToday: json['qualified_today'] as bool? ?? false,
    lastDay: json['last_day'] != null ? DateTime.tryParse(json['last_day'] as String) : null,
    lastFreezeDay: json['last_freeze_day'] != null
        ? DateTime.tryParse(json['last_freeze_day'] as String)
        : null,
  );
}

class RewardTotals {
  const RewardTotals({
    this.seconds = 0,
    this.sessions = 0,
    this.hosted = 0,
    this.coWatchers = 0,
    this.daysActive = 0,
    this.longestSessionSeconds = 0,
    this.reactions = 0,
    this.messages = 0,
    this.lifetimePoints = 0,
  });

  final int seconds;
  final int sessions;
  final int hosted;
  final int coWatchers;
  final int daysActive;
  final int longestSessionSeconds;
  final int reactions;
  final int messages;
  final int lifetimePoints;

  Duration get watched => Duration(seconds: seconds);

  factory RewardTotals.fromJson(Map<String, dynamic> json) => RewardTotals(
    seconds: (json['seconds'] as num?)?.toInt() ?? 0,
    sessions: (json['sessions'] as num?)?.toInt() ?? 0,
    hosted: (json['hosted'] as num?)?.toInt() ?? 0,
    coWatchers: (json['co_watchers'] as num?)?.toInt() ?? 0,
    daysActive: (json['days_active'] as num?)?.toInt() ?? 0,
    longestSessionSeconds: (json['longest_session_seconds'] as num?)?.toInt() ?? 0,
    reactions: (json['reactions'] as num?)?.toInt() ?? 0,
    messages: (json['messages'] as num?)?.toInt() ?? 0,
    lifetimePoints: (json['lifetime_points'] as num?)?.toInt() ?? 0,
  );
}

class RewardPoints {
  const RewardPoints({this.today = 0, this.week = 0, this.month = 0, this.all = 0});

  final int today;
  final int week;
  final int month;
  final int all;

  factory RewardPoints.fromJson(Map<String, dynamic> json) => RewardPoints(
    today: (json['today'] as num?)?.toInt() ?? 0,
    week: (json['week'] as num?)?.toInt() ?? 0,
    month: (json['month'] as num?)?.toInt() ?? 0,
    all: (json['all'] as num?)?.toInt() ?? 0,
  );
}

/// Whether the *global* boards are publishable yet. Same doctrine as
/// `website/lib/public-metrics.ts`: a board with fourteen names on it is worse
/// than no board, and it is screenshot-ready in a way an empty state is not.
class GlobalBoardStatus {
  const GlobalBoardStatus({this.open = false, this.participants = 0, this.minRequired = 200});

  final bool open;
  final int participants;
  final int minRequired;

  factory GlobalBoardStatus.fromJson(Map<String, dynamic> json) => GlobalBoardStatus(
    open: json['open'] as bool? ?? false,
    participants: (json['participants'] as num?)?.toInt() ?? 0,
    minRequired: (json['min_required'] as num?)?.toInt() ?? 200,
  );
}

/// A top-three finish in a monthly season. Permanent: the weekly board resets
/// and is forgotten, which is precisely why a placing that is kept forever is
/// what makes anybody care about a temporary board.
class SeasonAward {
  const SeasonAward({required this.season, required this.rank, this.points = 0});

  /// 'YYYY-MM'.
  final String season;
  final int rank;
  final int points;

  String get label => switch (rank) {
    1 => 'Season winner',
    2 => 'Season runner-up',
    _ => 'Season third',
  };

  /// "May 2026" from 'YYYY-MM'; falls back to the raw id rather than throwing
  /// on a shape this client has not seen.
  String get monthLabel {
    final parts = season.split('-');
    if (parts.length != 2) return season;
    final year = int.tryParse(parts[0]);
    final month = int.tryParse(parts[1]);
    if (year == null || month == null || month < 1 || month > 12) return season;
    const names = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];
    return '${names[month - 1]} $year';
  }

  factory SeasonAward.fromJson(Map<String, dynamic> json) => SeasonAward(
    season: json['season'] as String? ?? '',
    rank: (json['rank'] as num?)?.toInt() ?? 3,
    points: (json['points'] as num?)?.toInt() ?? 0,
  );
}

class RewardState {
  const RewardState({
    this.enabled = true,
    this.tier = 'free',
    this.publicProfile = false,
    this.handle,
    this.equippedFrame,
    this.streak = const StreakState(),
    this.totals = const RewardTotals(),
    this.points = const RewardPoints(),
    this.weekRank = 0,
    this.circleRank = 0,
    this.globalBoard = const GlobalBoardStatus(),
    this.achievements = const [],
    this.metrics = const {},
    this.frames = const {},
    this.seasons = const [],
  });

  /// Understating is the safe direction: a client that failed to load shows no
  /// streak rather than a streak the server does not agree with.
  static const empty = RewardState();

  final bool enabled;
  final String tier;
  final bool publicProfile;
  final String? handle;
  final AvatarFrame? equippedFrame;
  final StreakState streak;
  final RewardTotals totals;
  final RewardPoints points;
  final int weekRank;
  final int circleRank;
  final GlobalBoardStatus globalBoard;
  final List<Achievement> achievements;
  final Map<String, int> metrics;
  final Set<AvatarFrame> frames;
  final List<SeasonAward> seasons;

  bool get isGuest => tier == 'guest';
  bool get isPremium => tier == 'premium';

  List<Achievement> get unlocked => [
    for (final a in achievements)
      if (a.unlocked) a,
  ];
  List<Achievement> get locked => [
    for (final a in achievements)
      if (!a.unlocked) a,
  ];

  Set<AvatarFrame> get availableFrames => {...frames, if (isPremium) AvatarFrame.aurum};

  factory RewardState.fromJson(Map<String, dynamic> json) {
    final metrics = <String, int>{};
    for (final entry
        in (json['metrics'] as Map?)?.cast<String, dynamic>().entries ??
            const <MapEntry<String, dynamic>>[]) {
      final value = (entry.value as num?)?.toInt();
      if (value != null) metrics[entry.key] = value;
    }
    final rank = (json['rank'] as Map?)?.cast<String, dynamic>() ?? const {};
    return RewardState(
      enabled: json['enabled'] as bool? ?? true,
      tier: json['tier'] as String? ?? 'free',
      publicProfile: json['public_profile'] as bool? ?? false,
      handle: json['handle'] as String?,
      equippedFrame: AvatarFrame.fromWire(json['equipped_frame'] as String?),
      streak: StreakState.fromJson((json['streak'] as Map?)?.cast<String, dynamic>() ?? const {}),
      totals: RewardTotals.fromJson((json['totals'] as Map?)?.cast<String, dynamic>() ?? const {}),
      points: RewardPoints.fromJson((json['points'] as Map?)?.cast<String, dynamic>() ?? const {}),
      weekRank: (rank['week'] as num?)?.toInt() ?? 0,
      circleRank: (rank['circle'] as num?)?.toInt() ?? 0,
      globalBoard: GlobalBoardStatus.fromJson(
        (json['global_board'] as Map?)?.cast<String, dynamic>() ?? const {},
      ),
      achievements: [
        for (final row in (json['achievements'] as List?) ?? const [])
          Achievement.fromJson((row as Map).cast<String, dynamic>()),
      ],
      metrics: metrics,
      frames: {
        for (final f in (json['frames'] as List?) ?? const [])
          if (AvatarFrame.fromWire(f as String?) case final frame?) frame,
      },
      seasons: [
        for (final row in (json['seasons'] as List?) ?? const [])
          SeasonAward.fromJson((row as Map).cast<String, dynamic>()),
      ],
    );
  }
}

enum LeaderboardScope {
  circle,
  global;

  String get wire => name;

  String get title => switch (this) {
    .circle => 'Your circle',
    .global => 'Everyone',
  };
}

enum LeaderboardPeriod {
  week,
  month,
  all;

  String get wire => name;

  String get title => switch (this) {
    .week => 'This week',
    .month => 'This month',
    .all => 'All time',
  };
}

class LeaderboardRow {
  const LeaderboardRow({
    required this.rank,
    required this.userId,
    required this.displayName,
    required this.points,
    this.avatarUrl,
    this.handle,
    this.frame,
    this.isPremium = false,
    this.streak = 0,
    this.seconds = 0,
    this.isMe = false,
  });

  final int rank;
  final String userId;
  final String displayName;
  final int points;
  final String? avatarUrl;
  final String? handle;
  final AvatarFrame? frame;
  final bool isPremium;
  final int streak;
  final int seconds;
  final bool isMe;

  Duration get watched => Duration(seconds: seconds);

  factory LeaderboardRow.fromJson(Map<String, dynamic> json) => LeaderboardRow(
    rank: (json['rank'] as num?)?.toInt() ?? 0,
    userId: json['user_id'] as String? ?? '',
    displayName: json['display_name'] as String? ?? 'Watcher',
    points: (json['points'] as num?)?.toInt() ?? 0,
    avatarUrl: json['avatar_url'] as String?,
    handle: json['handle'] as String?,
    frame: AvatarFrame.fromWire(json['frame'] as String?),
    isPremium: json['is_premium'] as bool? ?? false,
    streak: (json['streak'] as num?)?.toInt() ?? 0,
    seconds: (json['seconds'] as num?)?.toInt() ?? 0,
    isMe: json['is_me'] as bool? ?? false,
  );
}

/// A recap this account has published, as the management list sees it.
/// Deliberately without the payload - taking something down does not require
/// rendering it again.
class SharedRecap {
  const SharedRecap({
    required this.id,
    required this.createdAt,
    this.roomName,
    this.seconds = 0,
    this.people = 0,
    this.views = 0,
    this.expiresAt,
  });

  final String id;
  final DateTime createdAt;
  final String? roomName;
  final int seconds;
  final int people;
  final int views;
  final DateTime? expiresAt;

  Duration get length => Duration(seconds: seconds);

  factory SharedRecap.fromJson(Map<String, dynamic> json) => SharedRecap(
    id: json['id'] as String,
    createdAt: DateTime.tryParse(json['created_at'] as String? ?? '') ?? DateTime.now(),
    roomName: json['room_name'] as String?,
    seconds: (json['seconds'] as num?)?.toInt() ?? 0,
    people: (json['people'] as num?)?.toInt() ?? 0,
    views: (json['views'] as num?)?.toInt() ?? 0,
    expiresAt: json['expires_at'] != null ? DateTime.tryParse(json['expires_at'] as String) : null,
  );
}

/// Why a heartbeat earned nothing. Every one of these is a normal answer, not a
/// failure - only [unknown] is worth reporting.
enum HeartbeatOutcome {
  credited,
  anchored,
  noElapsed,
  dailyCap,
  guest,
  optedOut,
  solo,
  noMedia,
  idle,
  roomEnded,
  notAMember,
  roomNotFound,
  disabled,
  unknown;

  static HeartbeatOutcome fromWire(String? reason) => switch (reason) {
    null => .credited,
    'anchored' => .anchored,
    'no_elapsed' => .noElapsed,
    'daily_cap' => .dailyCap,
    'guest' => .guest,
    'opted_out' => .optedOut,
    'solo' => .solo,
    'no_media' => .noMedia,
    'idle' => .idle,
    'room_ended' => .roomEnded,
    'not_a_member' => .notAMember,
    'room_not_found' => .roomNotFound,
    'disabled' => .disabled,
    _ => .unknown,
  };
}

class HeartbeatResult {
  const HeartbeatResult({
    this.outcome = HeartbeatOutcome.unknown,
    this.grantedSeconds = 0,
    this.secondsToday = 0,
    this.pointsToday = 0,
    this.streak = 0,
    this.longestStreak = 0,
    this.freezes = 0,
    this.streakFrozen = false,
    this.dayQualified = false,
    this.needsUpgrade = false,
    this.unlocked = const [],
  });

  static const none = HeartbeatResult();

  final HeartbeatOutcome outcome;
  final int grantedSeconds;
  final int secondsToday;
  final int pointsToday;
  final int streak;
  final int longestStreak;
  final int freezes;
  final bool streakFrozen;
  final bool dayQualified;
  final bool needsUpgrade;
  final List<Achievement> unlocked;

  bool get credited => outcome == .credited;

  factory HeartbeatResult.fromJson(Map<String, dynamic> json) => HeartbeatResult(
    outcome: (json['credited'] as bool? ?? false)
        ? HeartbeatOutcome.credited
        : HeartbeatOutcome.fromWire(json['reason'] as String?),
    grantedSeconds: (json['granted_seconds'] as num?)?.toInt() ?? 0,
    secondsToday: (json['seconds_today'] as num?)?.toInt() ?? 0,
    pointsToday: (json['points_today'] as num?)?.toInt() ?? 0,
    streak: (json['streak'] as num?)?.toInt() ?? 0,
    longestStreak: (json['longest_streak'] as num?)?.toInt() ?? 0,
    freezes: (json['freezes'] as num?)?.toInt() ?? 0,
    streakFrozen: json['streak_frozen'] as bool? ?? false,
    dayQualified: json['day_qualified'] as bool? ?? false,
    needsUpgrade: json['upgrade'] as bool? ?? false,
    unlocked: [
      for (final row in (json['unlocked'] as List?) ?? const [])
        Achievement.fromJson({...(row as Map).cast<String, dynamic>(), 'unlocked': true}),
    ],
  );
}
