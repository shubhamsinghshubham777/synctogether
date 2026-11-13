import '../app_version.dart';

/// "Fixed from 1.4.2 onward" is a promise about every version at or above 1.4.2,
/// not about one build: a store can reject 1.4.2 and 1.4.3 ships instead, and
/// whoever is on 1.4.3 still has the fix. So the app compares, never matches.

/// `X.Y.Z` as three ints, tolerating a `+build` and a `-pre` suffix and a
/// leading `v`. Anything else is not a version.
List<int>? parseVersion(String? v) {
  if (v == null) return null;
  final m = RegExp(r'^v?(\d+)\.(\d+)\.(\d+)(?:[-+].*)?$').firstMatch(v.trim());
  if (m == null) return null;
  return [for (var i = 1; i <= 3; i++) int.parse(m.group(i)!)];
}

/// Whether [installed] is at or above [fixedIn]. A version that cannot be read
/// on either side counts as "not yet", which is the honest answer: we would
/// rather say "rolling out" than claim a fix the device may not have.
bool versionReached(String? installed, String? fixedIn) {
  final a = parseVersion(installed);
  final b = parseVersion(fixedIn);
  if (a == null || b == null) return false;
  for (var i = 0; i < 3; i++) {
    if (a[i] != b[i]) return a[i] > b[i];
  }
  return true;
}

/// Where a fix stands on this device.
enum FixState {
  /// The version that holds the fix is installed (or newer).
  onDevice,

  /// Fixed in code, not installed here yet.
  rollingOut,
}

FixState fixState(String? fixedIn, {String? installed}) =>
    versionReached(installed ?? AppVersion.current, fixedIn) ? .onDevice : .rollingOut;

/// The pill on a fixed report.
String fixedPill(String? fixedIn) => fixedIn == null ? 'FIXED' : 'FIXED FROM $fixedIn';

/// The one honest line under a fixed report.
String fixedLine(String? fixedIn, {String? installed}) {
  if (fixedIn == null) return 'Fixed. Thank you for flagging it.';
  return switch (fixState(fixedIn, installed: installed)) {
    .onDevice => "Fixed from $fixedIn onward, and it's on this device. Thank you for flagging it.",
    .rollingOut =>
      'Fixed from $fixedIn onward. Rolling out to your store soon. Thank you for flagging it.',
  };
}

/// Whether "Update now" belongs next to a fix: only while the fix is not here
/// yet, and only if the app can open a store page at all.
bool showUpdateFor(String? fixedIn, {String? installed, required bool canUpdate}) =>
    canUpdate && fixedIn != null && fixState(fixedIn, installed: installed) == FixState.rollingOut;

/// The closing sentence of the lobby's "Fixed" banner.
String fixedBannerTail(String? fixedIn, {String? installed}) {
  if (fixedIn == null) return 'Thanks for flagging it.';
  return switch (fixState(fixedIn, installed: installed)) {
    .onDevice => "It's on this device now.",
    .rollingOut => 'Rolling out to your store soon.',
  };
}
