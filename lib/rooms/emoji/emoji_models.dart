/// One picker cell. Skin-tone variants are folded into their base: [tones],
/// when present, is always the five uniform variants light → dark.
class EmojiEntry {
  const EmojiEntry(this.char, this.name, this.keywords, this.version, {this.tones});

  final String char;
  final String name;

  /// CLDR's English keywords, space-separated (multi-word keywords split too -
  /// search matches word prefixes, so that loses nothing).
  final String keywords;

  /// The Emoji version that introduced it, e.g. 13.1. Compared against the
  /// platform font's cap so nobody is offered a box.
  final double version;
  final List<String>? tones;

  bool get toneable => tones != null;

  /// [tone] 0 is the default yellow; 1-5 index [tones].
  String withTone(int tone) => tone == 0 || tones == null ? char : tones![tone - 1];
}

class EmojiGroup {
  const EmojiGroup(this.id, this.label, this.entries);

  final String id;
  final String label;
  final List<EmojiEntry> entries;
}
