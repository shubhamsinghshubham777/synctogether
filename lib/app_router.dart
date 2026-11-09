import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:media_kit/media_kit.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show AuthChangeEvent;

import 'auth/auth_service.dart';
import 'auth/login_screen.dart';
import 'pairing/date_night_plan.dart' show PlanNightScreen;
import 'pairing/date_night_screen.dart';
import 'pairing/history_screen.dart';
import 'pairing/streak_screen.dart';
import 'pairing/notification_settings_screen.dart';
import 'pairing/pair_accept_screen.dart';
import 'pairing/pair_screen.dart';
import 'pairing/pair_service.dart';
import 'pairing/push_service.dart';
import 'pairing/year_recap_screen.dart';
import 'profile/banned_screen.dart';
import 'profile/entitlement_service.dart';
import 'profile/profile_screen.dart';
import 'profile/profile_service.dart';
import 'profile/subscription_screen.dart';
import 'rewards/leaderboard_screen.dart';
import 'rewards/rewards_service.dart';
import 'rooms/lobby_screen.dart';
import 'rooms/moderation_service.dart';
import 'rooms/room_screen.dart';
import 'rooms/room_service.dart';
import 'ui/not_found_screen.dart';
import 'ui/pt_motion.dart';
import 'ui/responsive.dart';

/// Profile, subscribe and rooms are *sub-routes* of the lobby, so the lobby is always the
/// page beneath them in the navigator stack. That is what makes `go('/lobby')`
/// - every back button, leave, eviction and end-room exit - shrink the stack
/// and play the reverse (pop) transition. As sibling top-level routes, `go`
/// swaps the whole stack and Flutter animates it as a forward push instead.
const kRoomPathPrefix = '/lobby/room/';

String roomPath(String roomId) => '$kRoomPathPrefix$roomId';

/// Room id of the currently shown location, or null when not in a room.
String? roomIdOfPath(String path) =>
    path.startsWith(kRoomPathPrefix) ? path.substring(kRoomPathPrefix.length) : null;

const bool kDemoMode = bool.fromEnvironment('DEMO_MODE', defaultValue: false);
const bool kDemoRoom = bool.fromEnvironment('DEMO_ROOM', defaultValue: false);

/// Whether [uri] is an app-scheme link (`synctogether://join/<code>`,
/// `synctogether://auth-callback`) rather than a router location.
///
/// Flutter's engine forwards every incoming URL to the router as a route
/// (`FlutterDeepLinkingEnabled` defaults to true), so these reach go_router
/// too - where no route matches and "Page Not Found" covers the app. They are
/// consumed elsewhere (`app_links` in `MainApp`, supabase_flutter's own
/// listener for the auth callback), so the router must simply ignore them.
bool isAppSchemeLink(Uri uri) => uri.scheme == 'synctogether';

/// Where a router should stay when it is handed an app-scheme link: the
/// current location, or the lobby on a cold start with nothing shown yet.
String locationForAppSchemeLink(Uri? current) {
  final path = current?.toString() ?? '';
  return path.isEmpty ? '/lobby' : path;
}

/// The page for a location no route matches, in place of go_router's generic
/// "Page Not Found". Only the path is reported - never the query or fragment,
/// which can carry auth tokens.
Widget notFoundBuilder(BuildContext context, GoRouterState state) => PTHingeSafe(
  child: NotFoundScreen(location: state.uri.path, onHome: () => context.go('/lobby')),
);

GoRouter buildRouter([Player? player]) {
  late final GoRouter router;
  router = GoRouter(
    initialLocation: kDemoRoom ? '/lobby/room/demo-room-1' : '/lobby',
    refreshListenable: _AuthRefresh(),
    errorBuilder: notFoundBuilder,
    redirect: (context, state) {
      if (isAppSchemeLink(state.uri)) {
        // Keep whatever is on screen; the real handlers run off app_links.
        final configuration = router.routerDelegate.currentConfiguration;
        return locationForAppSchemeLink(configuration.isEmpty ? null : configuration.uri);
      }
      final signedIn = AuthService.instance.isSignedIn;
      final atLogin = state.matchedLocation == '/login';
      final atBanned = state.matchedLocation == '/banned';
      if (!signedIn) return atLogin ? null : '/login';

      final profile = ProfileService.instance.profile;
      if (profile != null && profile.isBanned) {
        return atBanned ? null : '/banned';
      }
      if (atBanned) return '/lobby';

      if (atLogin) return '/lobby';
      return null;
    },
    routes: [
      GoRoute(
        path: '/login',
        pageBuilder: (context, state) => _fadeThrough(state, const LoginScreen()),
      ),
      GoRoute(
        path: '/banned',
        pageBuilder: (context, state) => _fadeThrough(state, const BannedScreen()),
      ),
      GoRoute(
        path: '/lobby',
        pageBuilder: (context, state) =>
            _fadeThrough(state, const LobbyScreen(), twoPaneBook: true),
        routes: [
          GoRoute(
            path: 'profile',
            pageBuilder: (context, state) => _detail(state, const ProfileScreen()),
          ),
          GoRoute(
            path: 'pair',
            pageBuilder: (context, state) => _detail(state, const PairScreen()),
            routes: [
              GoRoute(
                path: 'accept/:code',
                pageBuilder: (context, state) =>
                    _detail(state, PairAcceptScreen(code: state.pathParameters['code']!)),
              ),
              GoRoute(
                path: 'nights',
                pageBuilder: (context, state) => _detail(state, const DateNightScreen()),
              ),
              GoRoute(
                path: 'plan-night',
                pageBuilder: (context, state) => _detail(state, const PlanNightScreen()),
              ),
              GoRoute(
                path: 'streak',
                pageBuilder: (context, state) => _detail(state, const StreakScreen()),
              ),
              GoRoute(
                path: 'history',
                pageBuilder: (context, state) => _detail(state, const HistoryScreen()),
              ),
              GoRoute(
                path: 'year',
                pageBuilder: (context, state) => _detail(state, const YearRecapScreen()),
              ),
              GoRoute(
                path: 'notifications',
                pageBuilder: (context, state) => _detail(state, const NotificationSettingsScreen()),
              ),
            ],
          ),
          GoRoute(
            path: 'leaderboard',
            pageBuilder: (context, state) => _detail(state, const LeaderboardScreen()),
          ),
          GoRoute(
            path: 'subscribe',
            pageBuilder: (context, state) => _detail(
              state,
              SubscriptionScreen(
                // go_router reuses the page for the same pattern; keying on
                // the demo state makes `?state=` switches rebuild it.
                key: kDemoMode ? ValueKey(state.uri.queryParameters['state']) : null,
                source: state.uri.queryParameters['source'],
                // Const-gated, so release builds drop the branch entirely.
                demoState: kDemoMode ? state.uri.queryParameters['state'] : null,
              ),
            ),
          ),
          GoRoute(
            path: 'room/:id',
            // Keyed by room id: go_router reuses the page for room A → room B
            // (same route pattern), and without the key the old room's State -
            // sync channel, countdown, chat - would survive the navigation.
            pageBuilder: (context, state) => _mobileOr(
              state,
              RoomScreen(
                key: ValueKey(
                  '${state.pathParameters['id']!}_${state.uri.queryParameters['chat']}_${state.uri.queryParameters['dialog']}',
                ),
                roomId: state.pathParameters['id']!,
                player: player,
                initialChatOpen: state.uri.queryParameters['chat'] == 'true',
                initialDialogOpen: state.uri.queryParameters['dialog'],
              ),
              _rise,
            ),
          ),
        ],
      ),
    ],
  );
  return router;
}

/// Every transition is fade-dominant and short. The room mounts a media_kit
/// texture and (in YouTube mode) a platform-view WebView, and heavy transforms
/// over those jank - so the translate legs stay small and nothing scales.
///
/// `key: state.pageKey` is not optional: it is what makes go_router treat a
/// re-navigation to the same location as the same page rather than a new one.
CustomTransitionPage<void> _page(
  GoRouterState state,
  Widget child,
  RouteTransitionsBuilder transitions,
) {
  return CustomTransitionPage<void>(
    key: state.pageKey,
    child: child,
    transitionDuration: PTMotion.page,
    reverseTransitionDuration: PTMotion.page,
    transitionsBuilder: transitions,
  );
}

/// Auth swaps the whole world, so login ⇄ lobby reads as a scene change rather
/// than navigation: no directional slide at all.
CustomTransitionPage<void> _fadeThrough(
  GoRouterState state,
  Widget child, {
  bool twoPaneBook = false,
}) {
  return _page(state, PTHingeSafe(twoPaneBook: twoPaneBook, child: child), (
    context,
    animation,
    secondary,
    child,
  ) {
    return FadeTransition(
      opacity: CurvedAnimation(parent: animation, curve: PTMotion.enter),
      child: child,
    );
  });
}

/// Entering the theater: the room rises into place, and sinks back down on
/// every `go('/lobby')` exit - leave, eviction, end-room - because the nested
/// lobby→room stack makes those genuine pops.
CustomTransitionPage<void> _rise(GoRouterState state, Widget child) {
  return _page(state, child, (context, animation, secondary, child) {
    final curved = CurvedAnimation(
      parent: animation,
      curve: PTMotion.enter,
      reverseCurve: PTMotion.exit,
    );
    return FadeTransition(
      opacity: curved,
      child: SlideTransition(
        position: Tween(begin: const Offset(0, 0.035), end: Offset.zero).animate(curved),
        child: child,
      ),
    );
  });
}

/// Sub-pages of the lobby. On a phone or tablet they are the platform's own
/// pages, so the system back works the way the OS teaches it: iOS gets the
/// edge swipe (CupertinoPage), Android its predictive back (MaterialPage).
/// Desktop has no such gesture and keeps the short shared-axis fade.
Page<void> _detail(GoRouterState state, Widget child) =>
    _mobileOr(state, PTHingeSafe(child: child), _sharedAxis);

/// The room also uses the platform page on mobile. Its `PopScope(canPop:
/// false)` still owns the exit (it routes a back gesture through
/// `_leaveRoom`), so the swipe can never strand the membership.
Page<void> _mobileOr(
  GoRouterState state,
  Widget child,
  CustomTransitionPage<void> Function(GoRouterState, Widget) desktop,
) {
  if (kIsWeb) return desktop(state, child);
  return switch (defaultTargetPlatform) {
    TargetPlatform.iOS => CupertinoPage<void>(key: state.pageKey, child: child),
    TargetPlatform.android => MaterialPage<void>(key: state.pageKey, child: child),
    _ => desktop(state, child),
  };
}

/// Sibling detail page - a subtle horizontal shared axis.
CustomTransitionPage<void> _sharedAxis(GoRouterState state, Widget child) {
  return _page(state, child, (context, animation, secondary, child) {
    final curved = CurvedAnimation(
      parent: animation,
      curve: PTMotion.enter,
      reverseCurve: PTMotion.exit,
    );
    return FadeTransition(
      opacity: curved,
      child: SlideTransition(
        position: Tween(begin: const Offset(0.03, 0), end: Offset.zero).animate(curved),
        child: child,
      ),
    );
  });
}

/// Whether an auth event is a reason to (re-)register this device for push: a
/// sign-in, a refresh, and a cold start that restored a session. Signing out, or
/// a start with nobody signed in, is not.
@visibleForTesting
bool authEventStartsPush(AuthChangeEvent event, {required bool hasSession}) => switch (event) {
  AuthChangeEvent.signedIn || AuthChangeEvent.tokenRefreshed || AuthChangeEvent.userUpdated => true,
  AuthChangeEvent.initialSession => hasSession,
  _ => false,
};

/// Re-runs router redirects on every auth event; also keeps the loaded
/// profile in step with the session (signedOut wipes it).
class _AuthRefresh extends ChangeNotifier {
  _AuthRefresh() {
    ProfileService.instance.addListener(notifyListeners);
    _sub = AuthService.instance.onAuthStateChange.listen((state) {
      switch (state.event) {
        case AuthChangeEvent.signedIn:
        case AuthChangeEvent.tokenRefreshed:
        case AuthChangeEvent.userUpdated:
          ProfileService.instance.load();
          EntitlementService.instance.load();
          RewardsService.instance.load();
          PairService.instance.load();
          PushService.instance.onSignedIn();
          // Blocks are account-scoped, so they have to be in place before the
          // first room renders rather than fetched when one is opened.
          ModerationService.instance.load();
        case AuthChangeEvent.initialSession:
          // A cold start with a stored session announces itself like this, not as
          // signedIn, and nothing else registers this device with the server after
          // a relaunch (a token refresh only comes about hourly). Without this a
          // reinstall's new token, or a corrected environment, never arrives.
          if (authEventStartsPush(state.event, hasSession: state.session != null)) {
            PushService.instance.onSignedIn();
          }
        case AuthChangeEvent.signedOut:
          ProfileService.instance.clear();
          EntitlementService.instance.clear();
          RewardsService.instance.clear();
          PairService.instance.clear();
          RoomService.instance.clear();
          ModerationService.instance.clear();
        default:
          break;
      }
      notifyListeners();
    });
  }

  late final StreamSubscription _sub;

  @override
  void dispose() {
    ProfileService.instance.removeListener(notifyListeners);
    _sub.cancel();
    super.dispose();
  }
}
