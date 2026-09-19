import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:synctogether/analytics.dart';
import 'package:synctogether/diagnostics.dart';

/// Why something was reported.
///
/// The wire values are an allow-list the RPC re-checks, so a client cannot
/// invent a category and quietly sort itself out of the triage queue.
enum ReportReason {
  harassment('harassment', 'Harassment or bullying'),
  hateSpeech('hate_speech', 'Hate speech'),
  sexualContent('sexual_content', 'Sexual or explicit content'),
  violence('violence', 'Violence or threats'),
  // Media sharing redistributes a host's video file to the room, so a
  // copyright owner needs a route in as much as a bullied user does.
  copyright('copyright', 'Copyright infringement'),
  spam('spam', 'Spam or scams'),
  other('other', 'Something else');

  const ReportReason(this.wire, this.label);

  final String wire;
  final String label;
}

@immutable
class BlockedUser {
  const BlockedUser({
    required this.userId,
    required this.displayName,
    this.avatarUrl,
    required this.blockedAt,
  });

  final String userId;
  final String displayName;
  final String? avatarUrl;
  final DateTime blockedAt;

  factory BlockedUser.fromJson(Map<String, dynamic> json) => BlockedUser(
    userId: json['user_id'] as String,
    displayName: (json['display_name'] as String?) ?? 'Someone',
    avatarUrl: json['avatar_url'] as String?,
    blockedAt: DateTime.parse(json['created_at'] as String),
  );
}

/// Blocks and reports, held for the whole session rather than for one room.
///
/// A block is account-scoped on the server, so it has to be account-scoped
/// here too: the previous in-memory set lived on `RoomScreen`, was keyed on
/// *display name*, and evaporated the moment you left the room - which meant
/// the same person was unblocked by walking into the next room, and two people
/// sharing a name were blocked together.
class ModerationService extends ChangeNotifier {
  ModerationService();
  ModerationService._();
  static ModerationService instance = ModerationService._();

  SupabaseClient get _client => Supabase.instance.client;

  var _blocked = <String>{};
  var _blockedUsers = <BlockedUser>[];
  var _loading = false;

  /// User ids this account has blocked. The hot path - chat rendering, the
  /// facecam rail and the member list all consult it - so it stays a Set.
  Set<String> get blockedIds => _blocked;

  List<BlockedUser> get blockedUsers => List.unmodifiable(_blockedUsers);

  bool get loading => _loading;

  bool isBlocked(String? userId) => userId != null && _blocked.contains(userId);

  bool get hasBlocks => _blocked.isNotEmpty;

  Future<void> load() async {
    if (_client.auth.currentUser == null) {
      clear();
      return;
    }
    if (_loading) return;
    _loading = true;
    try {
      final rows = await _client.rpc('my_blocked_users');
      final list = (rows as List? ?? const [])
          .map((r) => BlockedUser.fromJson((r as Map).cast<String, dynamic>()))
          .toList(growable: false);
      _blockedUsers = list;
      _blocked = {for (final u in list) u.userId};
    } catch (e, s) {
      reportNonFatal(e, s, during: 'loading the blocked-user list');
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  /// Blocks [userId] and files the accompanying report server-side.
  ///
  /// The optimistic local insert is deliberate: "remove it from the feed
  /// instantly" is the guideline's wording, and waiting on a round trip to
  /// stop showing someone abusive is the wrong trade. A failure rolls it back
  /// and rethrows so the caller can say so.
  Future<void> block(
    String userId, {
    String? roomId,
    ReportReason reason = ReportReason.other,
    String? messageExcerpt,
  }) async {
    if (userId.isEmpty || _blocked.contains(userId)) return;
    _blocked = {..._blocked, userId};
    notifyListeners();
    try {
      await _client.rpc(
        'block_user',
        params: {
          'p_user_id': userId,
          'p_room_id': roomId,
          'p_reason': reason.wire,
          'p_message_excerpt': messageExcerpt,
        },
      );
      trace(
        'user blocked',
        category: 'moderation',
        data: {'target': userId, 'room_id': roomId, 'reason': reason.wire},
      );
      Analytics.instance.track('user_blocked', {'reason': reason.wire});
      unawaitedLoad();
    } catch (e, s) {
      _blocked = {..._blocked}..remove(userId);
      notifyListeners();
      reportNonFatal(e, s, during: 'blocking a user');
      rethrow;
    }
  }

  Future<void> unblock(String userId) async {
    if (!_blocked.contains(userId)) return;
    final previousIds = _blocked;
    final previousUsers = _blockedUsers;
    _blocked = {..._blocked}..remove(userId);
    _blockedUsers = _blockedUsers.where((u) => u.userId != userId).toList(growable: false);
    notifyListeners();
    try {
      await _client.rpc('unblock_user', params: {'p_user_id': userId});
      trace('user unblocked', category: 'moderation', data: {'target': userId});
      Analytics.instance.track('user_unblocked');
    } catch (e, s) {
      _blocked = previousIds;
      _blockedUsers = previousUsers;
      notifyListeners();
      reportNonFatal(e, s, during: 'unblocking a user');
      rethrow;
    }
  }

  /// Files a report without blocking. Throws so the caller can tell the user
  /// it did not go through - a report that silently vanishes is worse than no
  /// report button at all.
  Future<void> report({
    required String userId,
    required ReportReason reason,
    String? roomId,
    String? details,
    String? messageId,
    String? messageExcerpt,
  }) async {
    try {
      await _client.rpc(
        'report_content',
        params: {
          'p_reported_user_id': userId,
          'p_reason': reason.wire,
          'p_room_id': roomId,
          'p_details': details,
          'p_message_id': messageId,
          'p_message_excerpt': messageExcerpt,
        },
      );
      trace(
        'content reported',
        category: 'moderation',
        data: {'target': userId, 'room_id': roomId, 'reason': reason.wire},
      );
      Analytics.instance.track('content_reported', {'reason': reason.wire});
    } catch (e, s) {
      reportNonFatal(e, s, during: 'filing a content report');
      rethrow;
    }
  }

  void unawaitedLoad() {
    load().ignore();
  }

  void clear() {
    if (_blocked.isEmpty && _blockedUsers.isEmpty && !_loading) return;
    _blocked = <String>{};
    _blockedUsers = const [];
    _loading = false;
    notifyListeners();
  }

  @visibleForTesting
  void setBlockedForTesting(Set<String> ids) {
    _blocked = ids;
    notifyListeners();
  }
}
