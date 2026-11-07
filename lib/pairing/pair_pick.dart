/// "Pick tonight": each person says yes or pass to the same list, privately, and
/// the films both said yes to are the match.
///
/// Both phones run this on their own and must land on the *same* film, so the
/// choice is a pure function of the two answer sets - never `Random` - and the
/// hash is our own rather than `String.hashCode`, which Dart does not promise
/// is the same on two platforms.
library;

/// FNV-1a over UTF-16 code units, 32-bit. Stable everywhere.
int stableHash(String s) {
  var h = 0x811c9dc5;
  for (final unit in s.codeUnits) {
    h ^= unit;
    h = (h * 0x01000193) & 0xffffffff;
  }
  return h;
}

/// The ids both people said yes to, in a stable order.
List<String> sharedYes(Iterable<String> mine, Iterable<String> theirs) {
  final other = theirs.toSet();
  return ([
    for (final id in mine.toSet())
      if (other.contains(id)) id,
  ]..sort());
}

/// The film both phones pick from the shared yeses, or null when there are
/// none. The two answer sets are combined order-independently, so it does not
/// matter whose phone computes it.
String? choosePick(Iterable<String> mine, Iterable<String> theirs) {
  final shared = sharedYes(mine, theirs);
  if (shared.isEmpty) return null;
  final seed = ([...mine.toSet(), ...theirs.toSet()]..sort()).join('|');
  return shared[stableHash(seed) % shared.length];
}

/// Fallback when nothing matches: one film from everything either said yes to,
/// so a mismatched evening still ends with a choice rather than a shrug.
String? choosePickFromEither(Iterable<String> mine, Iterable<String> theirs) {
  final all = ({...mine, ...theirs}.toList()..sort());
  if (all.isEmpty) return null;
  return all[stableHash(all.join('|')) % all.length];
}

/// A partner's answers are only good for a short while: an old broadcast from
/// last week must not decide tonight.
bool picksAreFresh(DateTime sentAt, DateTime now) =>
    now.difference(sentAt) < const Duration(minutes: 30);
