import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:synctogether/diagnostics.dart';
import 'package:synctogether/rooms/room_models.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const kGuestTier = 'guest';
const kFreeTier = 'free';
const kPremiumTier = 'premium';

/// How long this account's Patron seat runs, and whether it is known to
/// renew. [renews] is only ever true where the data proves it (an App Store
/// row with `auto_renew`); a Paddle cancellation is scheduled remotely and
/// leaves the local row untouched, so a Paddle seat reads "paid through".
@immutable
class PremiumTerm {
  const PremiumTerm({required this.until, required this.source, this.renews});

  final DateTime until;

  /// `paddle`, `apple` or `manual` - the rail whose date this is.
  final String source;
  final bool? renews;
}

/// The latest-ending entitlement among a Paddle/manual row and App Store
/// rows, each as its owner reads it back under RLS. Pure, for testing.
PremiumTerm? premiumTermFrom({
  Map<String, dynamic>? subscription,
  List<Map<String, dynamic>> apple = const [],
  required DateTime now,
}) {
  final terms = <PremiumTerm>[];
  final end = DateTime.tryParse('${subscription?['current_period_end']}');
  if (subscription != null &&
      subscription['tier'] == 'premium' &&
      end != null &&
      end.isAfter(now)) {
    terms.add(
      PremiumTerm(until: end, source: subscription['source'] == 'paddle' ? 'paddle' : 'manual'),
    );
  }
  for (final row in apple) {
    final until = DateTime.tryParse('${row['expires_at']}');
    if (row['revoked_at'] != null || until == null || !until.isAfter(now)) continue;
    terms.add(PremiumTerm(until: until, source: 'apple', renews: row['auto_renew'] as bool?));
  }
  if (terms.isEmpty) return null;
  terms.sort((a, b) => b.until.compareTo(a.until));
  return terms.first;
}

class TierLimits {
  const TierLimits({
    required this.tier,
    required this.maxLiveRooms,
    required this.maxMembers,
    required this.maxSessionMinutes,
    required this.maxTotalSessionMinutes,
    required this.avLevel,
    required this.persistentRoomCap,
    required this.dormantHours,
    required this.freeExtensionMinutes,
    this.mediaSharing = 'none',
    this.mediaSharingWeeklyBytes = 0,
  });

  static const fallback = TierLimits(
    tier: kFreeTier,
    maxLiveRooms: 4,
    maxMembers: 8,
    maxSessionMinutes: 240,
    maxTotalSessionMinutes: 240,
    avLevel: .voice,
    persistentRoomCap: 0,
    dormantHours: 24,
    freeExtensionMinutes: 0,
    mediaSharing: 'limited',
    mediaSharingWeeklyBytes: 2684354560,
  );

  final String tier;
  final int maxLiveRooms;
  final int maxMembers;
  final int maxSessionMinutes;
  final int maxTotalSessionMinutes;
  final AvLevel avLevel;
  final int persistentRoomCap;
  final int dormantHours;
  final int freeExtensionMinutes;
  final String mediaSharing;
  final int mediaSharingWeeklyBytes;

  bool get isPremium => tier == kPremiumTier;
  bool get isGuest => tier == kGuestTier;

  bool get picksExtensionLength => maxTotalSessionMinutes > maxSessionMinutes;

  bool get hasFreeExtension => !picksExtensionLength && freeExtensionMinutes > 0;

  bool get canShareMedia => mediaSharing != 'none';
  bool get hasUnlimitedSharing => mediaSharing == 'full';
  bool get hasWeeklyQuota => !hasUnlimitedSharing && mediaSharingWeeklyBytes > 0;
  int get mediaSharingMaxSizeBytes =>
      isPremium ? 10737418240 : 2147483648; // 10 GB for Premium, 2 GB for Free

  factory TierLimits.fromJson(Map<String, dynamic> json) => TierLimits(
    tier: json['tier'] as String,
    maxLiveRooms: (json['max_live_rooms'] as num).toInt(),
    maxMembers: (json['max_members'] as num).toInt(),
    maxSessionMinutes: (json['max_session_minutes'] as num).toInt(),
    maxTotalSessionMinutes: (json['max_total_session_minutes'] as num).toInt(),
    avLevel: AvLevel.fromWire(json['av_level'] as String?),
    persistentRoomCap: (json['persistent_room_cap'] as num?)?.toInt() ?? 0,
    dormantHours: (json['dormant_hours'] as num?)?.toInt() ?? 0,
    freeExtensionMinutes: (json['free_extension_minutes'] as num?)?.toInt() ?? 0,
    mediaSharing: json['media_sharing'] as String? ?? 'none',
    mediaSharingWeeklyBytes: (json['media_sharing_weekly_bytes'] as num?)?.toInt() ?? 0,
  );
}

bool tierWearsCrown(String? tier) => tier == kPremiumTier;

Set<String> premiumMembersFrom(Map<String, String> tiers) => {
  for (final entry in tiers.entries)
    if (tierWearsCrown(entry.value)) entry.key,
};

class EntitlementService extends ChangeNotifier {
  EntitlementService();
  EntitlementService._();
  static EntitlementService instance = EntitlementService._();

  SupabaseClient get _client => Supabase.instance.client;

  RealtimeChannel? _subscriptionChannel;
  Timer? _debounceTimer;

  TierLimits? _limits;

  TierLimits? get limits => _limits;

  TierLimits get limitsOrFallback => _limits ?? TierLimits.fallback;

  Set<String> _premiumSources = const {};

  /// Which payment rails entitle this account: `paddle`, `apple`, `manual`.
  /// Both can be true at once - someone can hold a web and an App Store
  /// subscription - and the subscription screen uses it to say where each is
  /// managed and to stop a second purchase through the other rail.
  Set<String> get premiumSources => _premiumSources;

  PremiumTerm? _premiumTerm;

  /// When the Patron seat runs until; null when not premium, or for a grant
  /// with no end date.
  PremiumTerm? get premiumTerm => _premiumTerm;

  String get tier => _limits?.tier ?? kFreeTier;
  bool get isPremium => _limits?.isPremium ?? false;

  Future<TierLimits?> load() async {
    try {
      final user = _client.auth.currentUser;
      if (user == null) {
        clear();
        return null;
      }
      _ensureRealtimeSubscribed(user.id);
      final row = await _client.rpc('my_entitlement');
      if (row == null) return _limits;
      final map = row is List
          ? (row.first as Map).cast<String, dynamic>()
          : (row as Map).cast<String, dynamic>();
      _limits = TierLimits.fromJson(map);
      _premiumSources = _limits!.isPremium ? await _loadPremiumSources() : const {};
      _premiumTerm = _limits!.isPremium ? await _loadPremiumTerm(user.id) : null;
      notifyListeners();
      return _limits;
    } catch (e, s) {
      reportNonFatal(e, s, during: 'loading the caller entitlement');
      return _limits;
    }
  }

  Future<Set<String>> _loadPremiumSources() async {
    try {
      final rows = await _client.rpc('my_premium_sources');
      return {for (final r in (rows as List? ?? const [])) r as String};
    } catch (e, s) {
      reportNonFatal(e, s, during: 'loading premium sources');
      return _premiumSources;
    }
  }

  Future<PremiumTerm?> _loadPremiumTerm(String userId) async {
    try {
      final results = await Future.wait<Object?>([
        _client
            .from('subscriptions')
            .select('tier, source, current_period_end')
            .eq('user_id', userId)
            .maybeSingle(),
        _client
            .from('apple_subscriptions')
            .select('expires_at, revoked_at, auto_renew')
            .eq('user_id', userId),
      ]);
      return premiumTermFrom(
        subscription: (results[0] as Map?)?.cast<String, dynamic>(),
        apple: [
          for (final r in (results[1] as List? ?? const [])) (r as Map).cast<String, dynamic>(),
        ],
        now: DateTime.now(),
      );
    } catch (e, s) {
      reportNonFatal(e, s, during: 'loading the premium term');
      return _premiumTerm;
    }
  }

  void _ensureRealtimeSubscribed(String userId) {
    if (_subscriptionChannel != null) return;
    try {
      final channel = _client.channel('public:subscriptions:$userId');
      // Both rails: a Paddle webhook writes `subscriptions`, an App Store
      // purchase or renewal writes `apple_subscriptions`.
      for (final table in const ['subscriptions', 'apple_subscriptions']) {
        channel.onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: table,
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'user_id',
            value: userId,
          ),
          callback: (payload) {
            trace(
              'subscription realtime update received',
              category: 'auth',
              data: {'table': table, 'eventType': payload.eventType.name},
            );
            _debounceTimer?.cancel();
            _debounceTimer = Timer(const Duration(milliseconds: 200), () {
              refresh();
            });
          },
        );
      }
      _subscriptionChannel = channel..subscribe();
    } catch (e, s) {
      reportNonFatal(e, s, during: 'subscribing to subscription realtime channel');
    }
  }

  /// Forces a reload of the entitlement and returns the updated limits.
  Future<TierLimits?> refresh() => load();

  /// Grants premium for [months] via debug RPC on the local stack.
  Future<void> debugGrantPremium({int months = 1}) async {
    try {
      await _client.rpc('debug_grant_premium', params: {'p_months': months});
      await refresh();
    } catch (e, s) {
      reportNonFatal(e, s, during: 'granting debug premium');
      rethrow;
    }
  }

  void clear() {
    _debounceTimer?.cancel();
    _debounceTimer = null;
    if (_subscriptionChannel != null) {
      try {
        _client.removeChannel(_subscriptionChannel!);
      } catch (e, s) {
        reportNonFatal(e, s, during: 'cleaning up subscription realtime channel');
      }
      _subscriptionChannel = null;
    }
    _premiumSources = const {};
    _premiumTerm = null;
    if (_limits == null) return;
    _limits = null;
    notifyListeners();
  }

  @visibleForTesting
  void setLimitsForTesting(TierLimits? limits, {PremiumTerm? term}) {
    _limits = limits;
    _premiumTerm = term;
    notifyListeners();
  }
}
