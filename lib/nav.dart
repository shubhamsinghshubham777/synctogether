import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import 'diagnostics.dart';

/// In-app navigation between the lobby's sub-pages (profile, leaderboard,
/// subscribe) as a real back stack: every forward step pushes, Back pops.
///
/// What stays on `go`: leaving a room (`go('/lobby')` - it must shrink the
/// stack, see `app_router.dart`), entering a room, login/redirect/deep-link
/// code. Those are scene changes, not drill-downs.

/// The location paths of every page currently in [router]'s stack, bottom
/// first and without query strings. Nested `go` locations contribute one entry
/// per route (`/lobby`, `/lobby/profile`); a pushed page contributes its own.
List<String> pageStackPaths(GoRouter router) {
  final configuration = router.routerDelegate.currentConfiguration;
  return [for (final match in configuration.matches) Uri.parse(match.matchedLocation).path];
}

/// How many pages sit above the topmost page whose path is [path], or null if
/// that page is not in the stack. 0 means it is already on top.
int? pagesAbove(List<String> stack, String path) {
  final index = stack.lastIndexOf(path);
  return index < 0 ? null : stack.length - 1 - index;
}

/// Forward navigation to a lobby sub-page.
///
/// If the page is already lower in the stack (profile -> leaderboard ->
/// profile), pop back down to it instead of stacking a duplicate, so Back
/// keeps retracing the way the user actually came. Otherwise push.
void openPage(BuildContext context, String path) {
  final router = GoRouter.of(context);
  final target = Uri.parse(path).path;
  final above = pagesAbove(pageStackPaths(router), target);
  if (above == null) {
    router.push(path);
    return;
  }
  trace('open page: pop to existing', category: 'room', data: {'path': target, 'pops': above});
  for (var i = 0; i < above && router.canPop(); i++) {
    router.pop();
  }
  // A different query (e.g. subscribe `?source=`) is still the same page; the
  // existing one stays as it was.
}

/// Back button: pop to the previous page, or [fallback] when there is nothing
/// below (cold start or deep link straight onto a sub-page).
void goBack(BuildContext context, {String fallback = '/lobby'}) {
  final router = GoRouter.of(context);
  if (router.canPop()) {
    router.pop();
  } else {
    trace('back with empty stack', category: 'room', data: {'fallback': fallback});
    router.go(fallback);
  }
}
