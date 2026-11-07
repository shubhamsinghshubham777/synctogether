/// Deep links the pairing feature owns, parsed without a router or a widget.
///
///   `synctogether://pair/<code>`          somebody's pair invite
///   `synctogether://push?route=<name>`    what a tapped notification opens
///
/// Both arrive through `app_links` (Windows toasts activate by protocol, and
/// the Apple and Android handlers build the same URL from the push payload), so
/// there is exactly one place that decides what they mean.
library;

const _alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';

/// The pair invite code in [uri], or null when it is not a pair link. Only the
/// server's own alphabet is accepted, so a stray path never reaches an RPC.
String? pairCodeFromLink(Uri uri) {
  if (uri.scheme != 'synctogether' || uri.host != 'pair') return null;
  final raw = uri.pathSegments.isNotEmpty ? uri.pathSegments.first : '';
  final code = raw.toUpperCase();
  if (code.length != 6) return null;
  return code.split('').every(_alphabet.contains) ? code : null;
}

/// Where a tapped notification goes.
sealed class PushTarget {
  const PushTarget();
}

/// Open (or resume) Our Room and go in.
class OpenOurRoom extends PushTarget {
  const OpenOurRoom();
}

/// Go to a lobby path.
class OpenPath extends PushTarget {
  const OpenPath(this.path);
  final String path;
}

/// What `synctogether://push?route=…` means, or null when it names nothing we
/// know (an old notification after a rename must not strand the person on a
/// 404: the caller falls back to the lobby).
PushTarget? pushTargetFromLink(Uri uri) {
  if (uri.scheme != 'synctogether' || uri.host != 'push') return null;
  return pushTargetForRoute(uri.queryParameters['route']);
}

/// The same mapping from the raw `route` a push payload carries (Apple and
/// Android deliver the payload to Dart directly, with no URL in between).
PushTarget? pushTargetForRoute(String? route) => switch (route) {
  'our-room' => const OpenOurRoom(),
  'date-night' => const OpenPath('/lobby/pair/nights'),
  'watchlist' => const OpenPath('/lobby/pair/watchlist'),
  'lobby' => const OpenPath('/lobby'),
  _ => null,
};
