import 'dart:math' as math;

import 'package:flutter/widgets.dart' show StringCharacters;

import 'emoji_data.g.dart';
import 'emoji_models.dart';

export 'emoji_models.dart';

/// Pure decisions behind the chat emoji picker and quick bar - the
/// `sync_logic.dart` seam, so they are testable without a widget, a
/// shared_preferences store or a clock.

/// The highest Emoji version the platform's own colour font draws. We render
/// with the OS font (Apple Color Emoji / Segoe UI Emoji / Noto Color Emoji) and
/// never bundle one, so anything newer than this would render as a box - it is
/// hidden from the picker instead. Received messages still show whatever the
/// sender typed; that is the OS's call, not ours.
///
/// [osVersion] is `Platform.operatingSystemVersion`. Unparseable input falls
/// back to the platform's floor, which understates rather than overstates.
double emojiVersionCap(String os, String osVersion) {
  final (major, minor) = _majorMinor(osVersion);
  return switch (os) {
    'macos' => _atLeast(major, minor, [(14, 4, 15.1), (13, 3, 15.0), (12, 3, 14.0)], 13.1),
    'ios' => _atLeast(major, minor, [(17, 4, 15.1), (16, 4, 15.0), (15, 4, 14.0)], 13.1),
    'windows' => _windowsCap(osVersion),
    // Flutter draws with the system's NotoColorEmoji, which is frozen per
    // Android release, and Dart's osVersion there is the kernel's - so there is
    // nothing to key on. 13.1 is Android 12 (2021).
    'android' => 13.1,
    _ => 15.1,
  };
}

/// Windows ships no flag glyphs at all: Segoe UI Emoji renders a regional
/// indicator pair as two letters, so the Flags group would be a page of "US".
bool emojiFlagsSupported(String os) => os != 'windows';

double _windowsCap(String osVersion) {
  final build = int.tryParse(RegExp(r'Build (\d+)').firstMatch(osVersion)?.group(1) ?? '');
  if (build == null) return 12.0;
  if (build >= 22631) return 15.0; // Windows 11 23H2
  if (build >= 22000) return 14.0; // Windows 11 21H2/22H2
  return 12.0; // Windows 10
}

(int, int) _majorMinor(String osVersion) {
  final match = RegExp(r'(\d+)\.(\d+)').firstMatch(osVersion);
  if (match == null) return (0, 0);
  return (int.parse(match.group(1)!), int.parse(match.group(2)!));
}

double _atLeast(int major, int minor, List<(int, int, double)> table, double floor) {
  for (final (tMajor, tMinor, cap) in table) {
    if (major > tMajor || (major == tMajor && minor >= tMinor)) return cap;
  }
  return floor;
}

String _normalize(String emoji) => emoji.replaceAll('\u{FE0F}', '');

/// The picker's view of the generated data, filtered to what this platform can
/// draw. Search runs over a lowercase index built once, on first use.
class EmojiCatalog {
  EmojiCatalog({
    required this.versionCap,
    this.flags = true,
    List<EmojiGroup> source = kEmojiGroups,
  }) : groups = [
         for (final group in source)
           if (flags || group.id != 'flags')
             EmojiGroup(group.id, group.label, [
               for (final entry in group.entries)
                 if (entry.version <= versionCap) entry,
             ]),
       ];

  final double versionCap;
  final bool flags;
  final List<EmojiGroup> groups;

  late final List<(EmojiEntry, List<String>)> _index = [
    for (final group in groups)
      for (final entry in group.entries)
        (entry, '${entry.name} ${entry.keywords}'.toLowerCase().split(RegExp(r'[\s:,_\-]+'))),
  ];

  /// Every query word must prefix some word of the name or keywords. Name hits
  /// rank ahead of keyword-only hits; ties keep Unicode's order.
  List<EmojiEntry> search(String query, {int limit = 120}) {
    final words = query.toLowerCase().trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty);
    if (words.isEmpty) return const [];
    final ranked = <(int, int, EmojiEntry)>[];
    var order = 0;
    for (final (entry, haystack) in _index) {
      order++;
      if (!words.every((w) => haystack.any((h) => h.startsWith(w)))) continue;
      final name = entry.name.toLowerCase();
      final first = words.first;
      final rank = name.startsWith(first)
          ? 0
          : name.split(' ').any((w) => w.startsWith(first))
          ? 1
          : 2;
      ranked.add((rank, order, entry));
    }
    ranked.sort((a, b) => a.$1 != b.$1 ? a.$1.compareTo(b.$1) : a.$2.compareTo(b.$2));
    return [for (final r in ranked.take(limit)) r.$3];
  }
}

/// Every emoji string the data knows, tones included, keyed without VS16 so
/// "❤" and "❤️" are one. Unfiltered by platform: this recognises emoji in
/// messages, where what the sender typed is what it is.
final Map<String, EmojiEntry> _known = {
  for (final group in kEmojiGroups)
    for (final entry in group.entries) ...{
      _normalize(entry.char): entry,
      for (final tone in entry.tones ?? const <String>[]) _normalize(tone): entry,
    },
};

EmojiEntry? emojiEntryOf(String emoji) => _known[_normalize(emoji)];

bool isEmoji(String grapheme) => _known.containsKey(_normalize(grapheme));

/// The emoji in [text], in order, one per grapheme.
List<String> emojiIn(String text) => [
  for (final grapheme in text.characters)
    if (isEmoji(grapheme)) grapheme,
];

/// A message of one to three emoji and nothing else renders large, bubble-less.
bool isEmojiOnly(String text) {
  final graphemes = text.characters.where((g) => g.trim().isNotEmpty).toList();
  return graphemes.isNotEmpty && graphemes.length <= 3 && graphemes.every(isEmoji);
}

/// The quick bar's starting seven, until usage or pins replace them.
const kDefaultQuickEmoji = ['😂', '❤️', '👍', '😮', '🔥', '😭', '🎉'];
const kQuickSlotCount = 7;
const kRecentEmojiLimit = 32;

/// A score halves after this long unused, so last month's favourite gives way.
const kEmojiUsageHalfLife = Duration(days: 14);

/// How many emoji the usage table keeps. Enough to rank against, small enough
/// that the prefs blob never grows.
const kEmojiUsageLimit = 64;

class EmojiUsage {
  const EmojiUsage(this.score, this.at);

  final double score;
  final DateTime at;

  double scoreAt(DateTime now) {
    final elapsed = now.difference(at);
    if (elapsed <= Duration.zero) return score;
    return score * math.pow(0.5, elapsed.inSeconds / kEmojiUsageHalfLife.inSeconds);
  }
}

/// Credits each emoji in a *sent* message once (typed-then-deleted never
/// counts). Returns a new map, trimmed to [kEmojiUsageLimit].
Map<String, EmojiUsage> recordEmojiUse(
  Map<String, EmojiUsage> usage,
  Iterable<String> sent,
  DateTime now,
) {
  final next = Map.of(usage);
  for (final emoji in sent.toSet()) {
    next[emoji] = EmojiUsage((next[emoji]?.scoreAt(now) ?? 0) + 1, now);
  }
  if (next.length <= kEmojiUsageLimit) return next;
  final kept = next.entries.toList()
    ..sort((a, b) => b.value.scoreAt(now).compareTo(a.value.scoreAt(now)));
  return Map.fromEntries(kept.take(kEmojiUsageLimit));
}

class QuickSlot {
  const QuickSlot(this.emoji, {this.pinned = false});

  final String emoji;
  final bool pinned;

  @override
  bool operator ==(Object other) =>
      other is QuickSlot && other.emoji == emoji && other.pinned == pinned;

  @override
  int get hashCode => Object.hash(emoji, pinned);

  @override
  String toString() => pinned ? '📌$emoji' : emoji;
}

/// Pinned slots stay exactly where they were put; the rest take the
/// highest-scoring unpinned emoji in score order; anything still empty falls
/// back to [defaults] (with the remembered [tone] applied), so the bar is
/// always full, fresh install included.
List<QuickSlot> quickBarSlots({
  required List<String?> pins,
  required Map<String, EmojiUsage> usage,
  required DateTime now,
  int tone = 0,
  List<String> defaults = kDefaultQuickEmoji,
}) {
  final taken = <String>{
    for (final pin in pins.take(kQuickSlotCount))
      if (pin != null) _normalize(pin),
  };
  final ranked = usage.entries.where((e) => !taken.contains(_normalize(e.key))).toList()
    ..sort((a, b) {
      final byScore = b.value.scoreAt(now).compareTo(a.value.scoreAt(now));
      return byScore != 0 ? byScore : a.key.compareTo(b.key);
    });
  final fill = [
    for (final e in ranked) e.key,
    for (final d in defaults) emojiEntryOf(d)?.withTone(tone) ?? d,
  ];
  final slots = <QuickSlot>[];
  var next = 0;
  for (var i = 0; i < kQuickSlotCount; i++) {
    final pin = i < pins.length ? pins[i] : null;
    if (pin != null) {
      slots.add(QuickSlot(pin, pinned: true));
      continue;
    }
    while (next < fill.length && taken.contains(_normalize(fill[next]))) {
      next++;
    }
    if (next >= fill.length) break;
    taken.add(_normalize(fill[next]));
    slots.add(QuickSlot(fill[next++]));
  }
  return slots;
}

/// Most recent first, deduped, capped.
List<String> pushRecent(List<String> recents, String emoji) => [
  emoji,
  ...recents.where((e) => _normalize(e) != _normalize(emoji)),
].take(kRecentEmojiLimit).toList();

/// Replaces the selection in [text] (or inserts at the caret; appends when
/// there is no valid selection) and returns the new text and caret offset.
/// Null when the result would exceed [maxCodepoints].
({String text, int caret})? insertEmoji(
  String text,
  int selectionStart,
  int selectionEnd,
  String emoji, {
  required int maxCodepoints,
}) {
  var start = math.min(selectionStart, selectionEnd);
  var end = math.max(selectionStart, selectionEnd);
  if (start < 0 || end > text.length) start = end = text.length;
  final next = text.replaceRange(start, end, emoji);
  if (next.runes.length > maxCodepoints) return null;
  return (text: next, caret: start + emoji.length);
}
