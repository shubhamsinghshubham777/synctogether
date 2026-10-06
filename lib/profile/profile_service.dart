import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:synctogether/auth/auth_service.dart';
import 'package:synctogether/diagnostics.dart';

import 'profile_models.dart';

class ProfileService extends ChangeNotifier {
  ProfileService();
  ProfileService._();
  static ProfileService instance = ProfileService._();

  SupabaseClient get _client => Supabase.instance.client;

  Profile? _profile;
  Profile? get profile => _profile;

  RealtimeChannel? _moderationChannel;

  /// A warn or ban is pushed over a private channel only this user can read,
  /// so it lands at once rather than at the next token refresh. `profiles` is
  /// readable by every signed-in user, so it is deliberately not published to
  /// Realtime for this.
  void _ensureModerationSubscribed(String uid) {
    if (_moderationChannel != null) return;
    try {
      _moderationChannel =
          _client
              .channel('user:$uid', opts: const RealtimeChannelConfig(private: true))
              .onBroadcast(
                event: 'moderation_changed',
                callback: (_) {
                  trace('moderation status changed', category: 'moderation');
                  unawaited(load());
                },
              )
            ..subscribe();
    } catch (e, s) {
      reportNonFatal(e, s, during: 'subscribing to the moderation channel');
    }
  }

  void _teardownModeration() {
    final channel = _moderationChannel;
    _moderationChannel = null;
    if (channel == null) return;
    try {
      _client.removeChannel(channel);
    } catch (e, s) {
      reportNonFatal(e, s, during: 'closing the moderation channel');
    }
  }

  Future<Profile?> load() async {
    final uid = _client.auth.currentUser?.id;
    if (uid == null) {
      _teardownModeration();
      _profile = null;
      notifyListeners();
      return null;
    }
    _ensureModerationSubscribed(uid);
    // The signup trigger creates the row; retry briefly for a brand-new user
    // whose trigger hasn't committed yet.
    for (var attempt = 0; attempt < 3; attempt++) {
      final row = await _client.from('profiles').select().eq('id', uid).maybeSingle();
      if (row != null) {
        // Moderation state is owner-only in its own table; absent means clean.
        final moderation = await _client
            .from('profile_moderation')
            .select()
            .eq('user_id', uid)
            .maybeSingle();
        _profile = Profile.fromJson({...row, ...?moderation});
        notifyListeners();
        return _profile;
      }
      await Future.delayed(const Duration(milliseconds: 400));
    }
    // If the client has a session token in storage but no profile row exists
    // after retries, the session is orphaned (e.g. database was reset or account purged).
    // Evict the stale session so the app safely routes back to sign-in.
    try {
      await AuthService.instance.signOut();
    } catch (e, s) {
      reportNonFatal(e, s, during: 'signing out orphaned session in ProfileService.load');
    }
    return null;
  }

  void clear() {
    _teardownModeration();
    _profile = null;
    notifyListeners();
  }

  @visibleForTesting
  void setProfileForTesting(Profile? p) {
    _profile = p;
    notifyListeners();
  }

  Future<void> updateDisplayName(String name) async {
    final uid = _client.auth.currentUser!.id;
    await _client.from('profiles').update({'display_name': name.trim()}).eq('id', uid);
    _profile = _profile?.copyWith(displayName: name.trim());
    notifyListeners();
  }

  /// Downscales/crops to a centered 512×512 JPEG and uploads to
  /// `avatars/<uid>.jpg`; stores a cache-busted public URL on the profile.
  Future<void> uploadAvatar(Uint8List bytes) async {
    final uid = _client.auth.currentUser!.id;

    final jpeg = await compute(processAvatar, bytes);
    await _client.storage
        .from('avatars')
        .uploadBinary(
          '$uid.jpg',
          jpeg,
          fileOptions: const FileOptions(contentType: 'image/jpeg', upsert: true),
        );

    final publicUrl = _client.storage.from('avatars').getPublicUrl('$uid.jpg');
    final busted = '$publicUrl?v=${DateTime.now().millisecondsSinceEpoch}';
    await _client.from('profiles').update({'avatar_url': busted}).eq('id', uid);
    _profile = _profile?.copyWith(avatarUrl: busted);
    notifyListeners();
  }

  Future<void> acknowledgeWarning() async {
    final uid = _client.auth.currentUser?.id;
    if (uid == null) return;
    try {
      await _client.rpc('acknowledge_warning');
      _profile = _profile?.copyWith(warningAcknowledged: true);
      notifyListeners();
    } catch (e, s) {
      reportNonFatal(e, s, during: 'acknowledging moderation warning');
      rethrow;
    }
  }
}

Uint8List processAvatar(Uint8List bytes) {
  var decoded = img.decodeImage(bytes);
  if (decoded == null) {
    throw const FormatException('unsupported_image');
  }
  decoded = img.bakeOrientation(decoded);
  final side = decoded.width < decoded.height ? decoded.width : decoded.height;
  final cropped = img.copyCrop(
    decoded,
    x: (decoded.width - side) ~/ 2,
    y: (decoded.height - side) ~/ 2,
    width: side,
    height: side,
  );
  final resized = img.copyResize(
    cropped,
    width: 512,
    height: 512,
    interpolation: img.Interpolation.cubic,
  );
  return Uint8List.fromList(img.encodeJpg(resized, quality: 85));
}
