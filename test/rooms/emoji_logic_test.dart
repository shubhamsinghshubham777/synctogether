import 'package:flutter_test/flutter_test.dart';
import 'package:synctogether/rooms/emoji/emoji_data.g.dart';
import 'package:synctogether/rooms/emoji/emoji_logic.dart';
import 'package:synctogether/sync/sync_logic.dart';

final _now = DateTime.utc(2026, 9, 24, 12);

void main() {
  group('generated data', () {
    test('every group is populated and no emoji appears twice', () {
      expect(kEmojiGroups.map((g) => g.id), [
        'smileys',
        'people',
        'nature',
        'food',
        'travel',
        'activities',
        'objects',
        'symbols',
        'flags',
      ]);
      final seen = <String>{};
      for (final group in kEmojiGroups) {
        expect(group.entries, isNotEmpty, reason: group.id);
        for (final entry in group.entries) {
          expect(seen.add(entry.char), isTrue, reason: 'duplicate ${entry.char}');
        }
      }
      expect(seen.length, greaterThan(1800));
    });

    test('toneable entries carry five uniform variants built on their base', () {
      final thumbs = emojiEntryOf('👍')!;
      expect(thumbs.tones, ['👍🏻', '👍🏼', '👍🏽', '👍🏾', '👍🏿']);
      expect(thumbs.withTone(0), '👍');
      expect(thumbs.withTone(3), '👍🏽');
      for (final group in kEmojiGroups) {
        for (final entry in group.entries.where((e) => e.toneable)) {
          expect(entry.tones, hasLength(5), reason: entry.name);
          for (final tone in entry.tones!) {
            expect(tone, isNot(entry.char));
          }
        }
      }
      expect(emojiEntryOf('😂')!.toneable, isFalse);
    });

    test('a tone variant resolves back to its base entry', () {
      expect(emojiEntryOf('👍🏾')!.char, '👍');
    });
  });

  group('platform caps', () {
    test('macOS and iOS step by release', () {
      expect(emojiVersionCap('macos', 'Version 14.4.1 (Build 23E224)'), 15.1);
      expect(emojiVersionCap('macos', 'Version 13.6 (Build 22G120)'), 15.0);
      expect(emojiVersionCap('macos', 'Version 11.7 (Build 20G817)'), 13.1);
      expect(emojiVersionCap('ios', 'Version 17.4 (Build 21E213)'), 15.1);
      expect(emojiVersionCap('ios', 'Version 16.0 (Build 20A362)'), 14.0);
    });

    test('Windows keys on the build number and hides flags', () {
      expect(emojiVersionCap('windows', '"Windows 11 Pro" 10.0 (Build 22631)'), 15.0);
      expect(emojiVersionCap('windows', '"Windows 11 Pro" 10.0 (Build 22621)'), 14.0);
      expect(emojiVersionCap('windows', '"Windows 10 Pro" 10.0 (Build 19045)'), 12.0);
      expect(emojiVersionCap('windows', 'garbage'), 12.0);
      expect(emojiFlagsSupported('windows'), isFalse);
      expect(emojiFlagsSupported('macos'), isTrue);
    });

    test('the catalog drops what the cap excludes', () {
      final catalog = EmojiCatalog(versionCap: 12.0, flags: false);
      expect(catalog.groups.map((g) => g.id), isNot(contains('flags')));
      final all = catalog.groups.expand((g) => g.entries);
      expect(all.every((e) => e.version <= 12.0), isTrue);
      // 🫠 melting face is Emoji 14.0.
      expect(all.any((e) => e.char == '🫠'), isFalse);
      expect(
        EmojiCatalog(versionCap: 15.1).groups.expand((g) => g.entries).any((e) => e.char == '🫠'),
        isTrue,
      );
    });
  });

  group('search', () {
    final catalog = EmojiCatalog(versionCap: 15.1);

    test('matches keyword prefixes and ranks name hits first', () {
      final results = catalog.search('thumb');
      expect(results.first.char, '👍');
      expect(catalog.search('pizza').first.char, '🍕');
    });

    test('every query word must match', () {
      final results = catalog.search('red heart');
      expect(results.map((e) => e.char), contains('❤️'));
      expect(results.every((e) => '${e.name} ${e.keywords}'.contains('heart')), isTrue);
    });

    test('an empty query returns nothing', () {
      expect(catalog.search('   '), isEmpty);
    });
  });

  group('recognising emoji in text', () {
    test('finds emoji graphemes, ZWJ sequences and tones included', () {
      expect(emojiIn('great 👍🏽 film 👩🏽‍💻!'), ['👍🏽', '👩🏽‍💻']);
      expect(emojiIn('no emoji here'), isEmpty);
    });

    test('with or without VS16 is the same emoji', () {
      expect(isEmoji('❤'), isTrue);
      expect(isEmoji('❤️'), isTrue);
    });

    test('one to three emoji alone render large', () {
      expect(isEmojiOnly('😂'), isTrue);
      expect(isEmojiOnly(' 🔥 🔥 🔥 '), isTrue);
      expect(isEmojiOnly('🔥🔥🔥🔥'), isFalse);
      expect(isEmojiOnly('lol 😂'), isFalse);
      expect(isEmojiOnly(''), isFalse);
      expect(isEmojiOnly('1'), isFalse, reason: 'a keycap base is not an emoji on its own');
    });
  });

  group('usage and the quick bar', () {
    test('a score halves every half-life', () {
      final usage = EmojiUsage(4, _now);
      expect(usage.scoreAt(_now), 4);
      expect(usage.scoreAt(_now.add(kEmojiUsageHalfLife)), closeTo(2, 1e-9));
    });

    test('a sent message credits each emoji once', () {
      final usage = recordEmojiUse(const {}, ['😂', '😂', '🔥'], _now);
      expect(usage['😂']!.score, 1);
      expect(usage['🔥']!.score, 1);
      final later = recordEmojiUse(usage, ['😂'], _now.add(kEmojiUsageHalfLife));
      expect(later['😂']!.score, closeTo(1.5, 1e-9));
    });

    test('the table is trimmed to the highest scores', () {
      var usage = <String, EmojiUsage>{};
      final all = kEmojiGroups.first.entries
          .take(kEmojiUsageLimit + 10)
          .map((e) => e.char)
          .toList();
      usage = recordEmojiUse(usage, all, _now);
      usage = recordEmojiUse(usage, [all.last], _now);
      expect(usage.length, kEmojiUsageLimit);
      expect(usage.containsKey(all.last), isTrue);
    });

    test('fresh install shows the defaults', () {
      final slots = quickBarSlots(pins: List.filled(5, null), usage: const {}, now: _now);
      expect(slots.map((s) => s.emoji), kDefaultQuickEmoji);
      expect(slots.any((s) => s.pinned), isFalse);
    });

    test('defaults take the remembered tone', () {
      final slots = quickBarSlots(pins: List.filled(5, null), usage: const {}, now: _now, tone: 2);
      expect(slots[2].emoji, '👍🏼');
    });

    test('pins hold their slot; usage fills the rest by score; defaults top up', () {
      final usage = {
        '🍿': EmojiUsage(5, _now),
        '😭': EmojiUsage(3, _now),
        '🎉': EmojiUsage(9, _now.subtract(kEmojiUsageHalfLife * 3)), // decayed to ~1.1
      };
      final slots = quickBarSlots(pins: [null, '💀', null, null, null], usage: usage, now: _now);
      expect(slots, const [
        QuickSlot('🍿'),
        QuickSlot('💀', pinned: true),
        QuickSlot('😭'),
        QuickSlot('🎉'),
        QuickSlot('😂'),
      ]);
    });

    test('a pinned emoji is never repeated in an unpinned slot', () {
      final slots = quickBarSlots(
        pins: [null, null, null, null, '😂'],
        usage: {'😂': EmojiUsage(10, _now)},
        now: _now,
      );
      expect(slots.where((s) => s.emoji == '😂'), hasLength(1));
      expect(slots.last, const QuickSlot('😂', pinned: true));
      expect(slots, hasLength(5));
    });

    test('recents are most-recent-first, deduped and capped', () {
      var recents = <String>[];
      for (final e in ['😂', '🔥', '😂']) {
        recents = pushRecent(recents, e);
      }
      expect(recents, ['😂', '🔥']);
      for (final e in kEmojiGroups.first.entries.take(40)) {
        recents = pushRecent(recents, e.char);
      }
      expect(recents, hasLength(kRecentEmojiLimit));
    });
  });

  group('inserting into the composer', () {
    test('replaces the selection and lands the caret after the emoji', () {
      final result = insertEmoji('hello world', 6, 11, '🔥', maxCodepoints: 500)!;
      expect(result.text, 'hello 🔥');
      expect(result.caret, 'hello 🔥'.length);
    });

    test('an invalid selection appends', () {
      final result = insertEmoji('hi', -1, -1, '👍', maxCodepoints: 500)!;
      expect(result.text, 'hi👍');
    });

    test('refuses to cross the codepoint limit', () {
      expect(insertEmoji('a' * 498, 498, 498, '👩🏽‍💻', maxCodepoints: 500), isNull);
      expect(insertEmoji('a' * 498, 498, 498, '😂', maxCodepoints: 500), isNotNull);
    });
  });

  group('chat length', () {
    test('counts codepoints the way Postgres char_length does', () {
      expect('👩🏽‍💻'.runes.length, 4);
      expect(chatLengthOk('a' * 500), isTrue);
      expect(chatLengthOk('a' * 501), isFalse);
      // 126 of these are 126 graphemes - `maxLength: 500` would have let them
      // through - and 504 codepoints.
      expect(chatLengthOk('👩🏽‍💻' * 125), isTrue);
      expect(chatLengthOk('👩🏽‍💻' * 126), isFalse);
      expect(chatLengthOk('🇺🇸' * 251), isFalse);
    });
  });
}
