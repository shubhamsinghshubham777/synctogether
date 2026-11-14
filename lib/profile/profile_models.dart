class Profile {
  const Profile({
    required this.id,
    required this.displayName,
    required this.isGuest,
    this.email,
    this.authProvider,
    this.avatarUrl,
    this.createdAt,
    this.freeExtensionUsed = false,
    this.r2UploadBytes7d = 0,
    this.r2UploadWindowStart,
    this.r2CooldownUntil,
    this.strikesCount = 0,
    this.moderationStatus = 'clean',
    this.warningReason,
    this.warningAcknowledged = true,
    this.lastWarnedAt,
    this.bannedAt,
    this.banReason,
    this.needsOnboarding = false,
  });

  final String id;
  final String displayName;
  final bool isGuest;
  final String? email;

  /// How this account signs in (`google`, `apple`, `email`), from the auth session.
  final String? authProvider;

  /// The line under the locked email row, naming where the address comes from.
  String get emailNote => switch (authProvider) {
    'google' => "Linked to your Google account, so it can't be changed.",
    'apple' => "Linked to your Apple ID, so it can't be changed.",
    _ => "This is the email you sign in with, so it can't be changed.",
  };
  final String? avatarUrl;
  final DateTime? createdAt;

  final bool freeExtensionUsed;
  final int r2UploadBytes7d;
  final DateTime? r2UploadWindowStart;
  final DateTime? r2CooldownUntil;

  final int strikesCount;
  final String moderationStatus;
  final String? warningReason;
  final bool warningAcknowledged;
  final DateTime? lastWarnedAt;
  final DateTime? bannedAt;
  final String? banReason;

  /// True only when the server says this account has never finished or skipped
  /// the first-night flow (`onboarded_at` present and null). A row without the
  /// column (an older backend) counts as onboarded, so nobody is shown it by accident.
  final bool needsOnboarding;

  bool get isBanned => moderationStatus == 'banned';
  bool get isWarned => moderationStatus == 'warned';
  bool get needsWarningAcknowledgment => isWarned && !warningAcknowledged;

  int remainingWeeklyBytes(int weeklyLimit) {
    if (weeklyLimit <= 0) return -1;
    if (r2UploadWindowStart == null) return weeklyLimit;
    final now = DateTime.now();
    if (now.difference(r2UploadWindowStart!).inDays >= 7) {
      return weeklyLimit;
    }
    return (weeklyLimit - r2UploadBytes7d).clamp(0, weeklyLimit);
  }

  Duration? get timeUntilQuotaReset {
    if (r2UploadWindowStart == null) return null;
    final resetAt = r2UploadWindowStart!.add(const Duration(days: 7));
    final diff = resetAt.difference(DateTime.now());
    return diff.isNegative ? Duration.zero : diff;
  }

  static String formatBytes(int bytes) {
    if (bytes < 0) return '∞ B';
    if (bytes == 0) return '0 B';
    const suffixes = ['B', 'KB', 'MB', 'GB', 'TB'];
    var i = 0;
    double count = bytes.toDouble();
    while (count >= 1024 && i < suffixes.length - 1) {
      count /= 1024;
      i++;
    }
    return '${count.toStringAsFixed(count >= 10 || i == 0 ? 0 : 1)} ${suffixes[i]}';
  }

  factory Profile.fromJson(Map<String, dynamic> json) {
    return Profile(
      id: json['id'] as String,
      displayName: json['display_name'] as String,
      isGuest: json['is_guest'] as bool,
      email: json['email'] as String?,
      authProvider: json['auth_provider'] as String?,
      avatarUrl: json['avatar_url'] as String?,
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'] as String)
          : null,
      freeExtensionUsed: json['free_extension_used'] as bool? ?? false,
      r2UploadBytes7d: (json['r2_upload_bytes_7d'] as num?)?.toInt() ?? 0,
      r2UploadWindowStart: json['r2_upload_window_start'] != null
          ? DateTime.tryParse(json['r2_upload_window_start'] as String)
          : null,
      r2CooldownUntil: json['r2_cooldown_until'] != null
          ? DateTime.tryParse(json['r2_cooldown_until'] as String)
          : null,
      strikesCount: (json['strikes_count'] as num?)?.toInt() ?? 0,
      moderationStatus: (json['moderation_status'] as String?) ?? 'clean',
      warningReason: json['warning_reason'] as String?,
      warningAcknowledged: json['warning_acknowledged'] as bool? ?? true,
      lastWarnedAt: json['last_warned_at'] != null
          ? DateTime.tryParse(json['last_warned_at'] as String)
          : null,
      bannedAt: json['banned_at'] != null ? DateTime.tryParse(json['banned_at'] as String) : null,
      banReason: json['ban_reason'] as String?,
      needsOnboarding: json.containsKey('onboarded_at') && json['onboarded_at'] == null,
    );
  }

  Profile copyWith({
    String? displayName,
    String? avatarUrl,
    bool? freeExtensionUsed,
    int? r2UploadBytes7d,
    DateTime? r2UploadWindowStart,
    DateTime? r2CooldownUntil,
    int? strikesCount,
    String? moderationStatus,
    String? warningReason,
    bool? warningAcknowledged,
    DateTime? lastWarnedAt,
    DateTime? bannedAt,
    String? banReason,
    bool? needsOnboarding,
  }) {
    return Profile(
      id: id,
      displayName: displayName ?? this.displayName,
      isGuest: isGuest,
      email: email,
      authProvider: authProvider,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      createdAt: createdAt,
      freeExtensionUsed: freeExtensionUsed ?? this.freeExtensionUsed,
      r2UploadBytes7d: r2UploadBytes7d ?? this.r2UploadBytes7d,
      r2UploadWindowStart: r2UploadWindowStart ?? this.r2UploadWindowStart,
      r2CooldownUntil: r2CooldownUntil ?? this.r2CooldownUntil,
      strikesCount: strikesCount ?? this.strikesCount,
      moderationStatus: moderationStatus ?? this.moderationStatus,
      warningReason: warningReason ?? this.warningReason,
      warningAcknowledged: warningAcknowledged ?? this.warningAcknowledged,
      lastWarnedAt: lastWarnedAt ?? this.lastWarnedAt,
      bannedAt: bannedAt ?? this.bannedAt,
      banReason: banReason ?? this.banReason,
      needsOnboarding: needsOnboarding ?? this.needsOnboarding,
    );
  }
}
