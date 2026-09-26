import 'dart:io' show Platform;
import '../../ui/booth_icons.g.dart';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:synctogether/rooms/emoji/emoji_logic.dart';
import 'package:synctogether/rooms/emoji/emoji_prefs.dart';
import 'package:synctogether/ui/buttons.dart';
import 'package:synctogether/ui/pt_motion.dart';
import 'package:synctogether/ui/pt_theme.dart';
import 'package:synctogether/ui/responsive.dart';

/// What this machine's emoji font can draw, built once.
final platformEmojiCatalog = EmojiCatalog(
  versionCap: emojiVersionCap(Platform.operatingSystem, Platform.operatingSystemVersion),
  flags: emojiFlagsSupported(Platform.operatingSystem),
);

const _kRecentId = 'recent';

const _groupIcons = <String, IconData>{
  _kRecentId: Symbols.history_rounded,
  'smileys': BoothIcons.mood,
  'people': Symbols.waving_hand_rounded,
  'nature': Symbols.pets_rounded,
  'food': Symbols.restaurant_rounded,
  'travel': Symbols.directions_car_rounded,
  'activities': Symbols.sports_soccer_rounded,
  'objects': Symbols.lightbulb_rounded,
  'symbols': Symbols.emoji_symbols_rounded,
  'flags': BoothIcons.flag,
};

const _toneSwatches = ['✋', '✋🏻', '✋🏼', '✋🏽', '✋🏾', '✋🏿'];

/// The full picker: search, category jump bar, sectioned grid, skin tones.
///
/// A surface only - it knows nothing about the chat field. [onPick] receives
/// the final string (tone applied); where it goes is the caller's business.
/// Presentation (popover, inline under the composer, inside the quick-bar
/// editor) is the caller's too, which is why this has no glass shell of its own.
class EmojiPicker extends StatefulWidget {
  EmojiPicker({
    super.key,
    required this.onPick,
    this.onCustomize,
    EmojiCatalog? catalog,
    EmojiPrefs? prefs,
  }) : catalog = catalog ?? platformEmojiCatalog,
       prefs = prefs ?? EmojiPrefs.instance;

  final ValueChanged<String> onPick;

  /// Opens the quick-bar editor. Null hides the affordance (the editor embeds
  /// a picker of its own and must not offer itself).
  final VoidCallback? onCustomize;
  final EmojiCatalog catalog;
  final EmojiPrefs prefs;

  @override
  State<EmojiPicker> createState() => _EmojiPickerState();
}

class _EmojiPickerState extends State<EmojiPicker> {
  final _search = TextEditingController();
  final _searchFocus = FocusNode();
  final _scroll = ScrollController();
  String _query = '';
  int _activeSection = 0;

  /// The toneable emoji whose variants are showing, or null for the global
  /// default-tone chooser; [_toneOpen] says whether either is up at all.
  EmojiEntry? _toneFor;
  bool _toneOpen = false;

  // Section offsets from the last layout; a pure function of cell size and
  // column count, so jumping never depends on lazily built slivers existing.
  List<double> _sectionOffsets = const [];

  static const _headerExtent = 30.0;

  @override
  void initState() {
    super.initState();
    widget.prefs.addListener(_onPrefs);
    widget.prefs.load();
    _scroll.addListener(_onScroll);
  }

  @override
  void dispose() {
    widget.prefs.removeListener(_onPrefs);
    _search.dispose();
    _searchFocus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _onPrefs() {
    if (mounted) setState(() {});
  }

  void _onScroll() {
    if (_sectionOffsets.isEmpty || !_scroll.hasClients) return;
    final at = _scroll.offset + 1;
    var index = 0;
    for (var i = 0; i < _sectionOffsets.length; i++) {
      if (_sectionOffsets[i] <= at) index = i;
    }
    if (index != _activeSection) setState(() => _activeSection = index);
  }

  List<EmojiGroup> get _sections => [
    if (widget.prefs.recent.isNotEmpty)
      EmojiGroup(_kRecentId, 'Recent', [
        for (final emoji in widget.prefs.recent)
          // A recent is stored exactly as picked (tone included); wrap it so
          // it renders verbatim rather than re-toned.
          EmojiEntry(emoji, emojiEntryOf(emoji)?.name ?? emoji, '', 0),
      ]),
    ...widget.catalog.groups,
  ];

  void _pick(EmojiEntry entry, {int? tone}) {
    final char = entry.version == 0 ? entry.char : entry.withTone(tone ?? widget.prefs.tone);
    widget.prefs.notePicked(char);
    widget.onPick(char);
  }

  void _openTones(EmojiEntry? entry) => setState(() {
    _toneFor = entry;
    _toneOpen = true;
  });

  void _closeTones() => setState(() => _toneOpen = false);

  void _jumpTo(int index) {
    if (_query.isNotEmpty) {
      _search.clear();
      setState(() => _query = '');
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients || index >= _sectionOffsets.length) return;
      _scroll.jumpTo(math.min(_sectionOffsets[index], _scroll.position.maxScrollExtent));
      setState(() => _activeSection = index);
    });
  }

  @override
  Widget build(BuildContext context) {
    final touch = inputOf(context) == PTInput.touch;
    final cell = touch ? 44.0 : 38.0;
    final sections = _sections;
    // A dense tool surface: text inside it tops out at 1.3x, and a short slot
    // sheds the search field and then the category bar before the grid.
    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1.3,
      child: LayoutBuilder(
        builder: (context, box) => Column(
          children: [
            if (box.maxHeight >= 150)
              Padding(padding: const EdgeInsets.fromLTRB(10, 10, 10, 6), child: _searchField()),
            if (box.maxHeight >= 100) _categoryBar(sections),
            AnimatedSize(
              duration: PTMotion.functional(context, PTMotion.state),
              curve: PTMotion.enter,
              alignment: .topCenter,
              child: _toneOpen ? _toneRow(cell) : const SizedBox(width: double.infinity),
            ),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final columns = math.max(4, (constraints.maxWidth - 12) ~/ cell);
                  if (_query.isNotEmpty) return _results(columns, cell);
                  _sectionOffsets = _offsets(sections, columns, cell);
                  return CustomScrollView(
                    controller: _scroll,
                    slivers: [
                      for (final section in sections) ...[
                        SliverToBoxAdapter(child: _sectionHeader(section.label)),
                        _grid(section.entries, columns, cell),
                      ],
                      const SliverToBoxAdapter(child: SizedBox(height: 8)),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<double> _offsets(List<EmojiGroup> sections, int columns, double cell) {
    var y = 0.0;
    return [
      for (final section in sections)
        () {
          final at = y;
          y += _headerExtent + (section.entries.length / columns).ceil() * cell;
          return at;
        }(),
    ];
  }

  Widget _searchField() => Container(
    height: 36,
    decoration: BoxDecoration(
      color: PTColors.white(0.07),
      border: Border.all(color: PTColors.white(0.1)),
      borderRadius: BorderRadius.circular(PTRadius.panel),
    ),
    child: Row(
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 11, right: 6),
          child: Icon(Symbols.search_rounded, size: 17, color: PTColors.white(0.45)),
        ),
        Expanded(
          child: TextField(
            controller: _search,
            focusNode: _searchFocus,
            onChanged: (value) => setState(() => _query = value.trim()),
            style: PTText.body.copyWith(fontSize: 13),
            cursorColor: PTColors.textAccent,
            decoration: InputDecoration(
              hintText: 'Search emoji',
              hintStyle: PTText.body.copyWith(fontSize: 13, color: PTColors.white(0.4)),
              border: InputBorder.none,
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(vertical: 9),
            ),
          ),
        ),
        if (_query.isNotEmpty)
          PTIconButton(
            icon: BoothIcons.close,
            size: 30,
            iconSize: 15,
            glass: false,
            color: PTColors.white(0.5),
            tooltip: 'Clear search',
            onPressed: () {
              _search.clear();
              setState(() => _query = '');
            },
          ),
      ],
    ),
  );

  Widget _categoryBar(List<EmojiGroup> sections) {
    final active = _query.isEmpty ? _activeSection : -1;
    return Container(
      height: 38,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: PTColors.white(0.07))),
      ),
      child: Row(
        children: [
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: .horizontal,
              child: Row(
                children: [
                  for (var i = 0; i < sections.length; i++)
                    PTIconButton(
                      icon: _groupIcons[sections[i].id] ?? Symbols.category_rounded,
                      size: 32,
                      iconSize: 17,
                      glass: false,
                      active: i == active,
                      color: i == active ? Colors.white : PTColors.white(0.5),
                      tooltip: sections[i].label,
                      onPressed: () => _jumpTo(i),
                    ),
                ],
              ),
            ),
          ),
          Tooltip(
            message: 'Skin tone',
            child: PTPressable(
              onTap: () => _toneOpen && _toneFor == null ? _closeTones() : _openTones(null),
              child: SizedBox.square(
                dimension: 32,
                child: Center(
                  child: Text(
                    _toneSwatches[widget.prefs.tone],
                    style: PTText.emoji.copyWith(fontSize: 17),
                  ),
                ),
              ),
            ),
          ),
          if (widget.onCustomize != null)
            PTIconButton(
              icon: Symbols.tune_rounded,
              size: 32,
              iconSize: 17,
              glass: false,
              color: PTColors.white(0.55),
              tooltip: 'Customize quick bar',
              onPressed: widget.onCustomize,
            ),
        ],
      ),
    );
  }

  /// Either the variants of one emoji (long-press) or the default-tone chooser.
  Widget _toneRow(double cell) {
    final entry = _toneFor;
    final options = entry == null ? _toneSwatches : [entry.char, ...entry.tones!];
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(10, 6, 4, 6),
      decoration: BoxDecoration(
        color: PTColors.white(0.04),
        border: Border(bottom: BorderSide(color: PTColors.white(0.07))),
      ),
      child: Row(
        children: [
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: .horizontal,
              child: Row(
                children: [
                  for (var tone = 0; tone < options.length; tone++)
                    EmojiCell(
                      emoji: options[tone],
                      extent: cell,
                      selected: tone == widget.prefs.tone,
                      label: entry == null ? 'Default skin tone ${tone + 1}' : null,
                      onTap: () {
                        widget.prefs.setTone(tone);
                        if (entry != null) _pick(entry, tone: tone);
                        _closeTones();
                      },
                    ),
                ],
              ),
            ),
          ),
          PTIconButton(
            icon: BoothIcons.close,
            size: 30,
            iconSize: 15,
            glass: false,
            color: PTColors.white(0.5),
            tooltip: 'Close',
            onPressed: _closeTones,
          ),
        ],
      ),
    );
  }

  Widget _sectionHeader(String label) => SizedBox(
    height: _headerExtent,
    child: Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
      child: Text(
        label.toUpperCase(),
        maxLines: 1,
        overflow: .ellipsis,
        style: PTText.finePrint.copyWith(fontSize: 10.5, letterSpacing: 0.8, fontWeight: .w600),
      ),
    ),
  );

  Widget _grid(List<EmojiEntry> entries, int columns, double cell) => SliverPadding(
    padding: const EdgeInsets.symmetric(horizontal: 6),
    sliver: SliverGrid.builder(
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: columns,
        mainAxisExtent: cell,
      ),
      itemCount: entries.length,
      itemBuilder: (context, index) => _cellFor(entries[index], cell),
    ),
  );

  Widget _cellFor(EmojiEntry entry, double cell) {
    final recent = entry.version == 0;
    return EmojiCell(
      emoji: recent ? entry.char : entry.withTone(widget.prefs.tone),
      extent: cell,
      label: entry.name,
      onTap: () => _pick(entry),
      onHold: !recent && entry.toneable ? () => _openTones(entry) : null,
    );
  }

  Widget _results(int columns, double cell) {
    final results = widget.catalog.search(_query);
    if (results.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text('No emoji for "$_query".', textAlign: .center, style: PTText.caption),
        ),
      );
    }
    return CustomScrollView(
      slivers: [
        const SliverToBoxAdapter(child: SizedBox(height: 6)),
        _grid(results, columns, cell),
      ],
    );
  }
}

/// One tappable glyph, shared with the quick bar. Hold (long-press, or right-click on a pointer) is the
/// secondary action - skin tones in the picker, customising in the quick bar.
class EmojiCell extends StatefulWidget {
  const EmojiCell({
    super.key,
    required this.emoji,
    required this.extent,
    required this.onTap,
    this.onHold,
    this.label,
    this.selected = false,
  });

  final String emoji;
  final double extent;
  final VoidCallback onTap;
  final VoidCallback? onHold;
  final String? label;
  final bool selected;

  @override
  State<EmojiCell> createState() => _EmojiCellState();
}

class _EmojiCellState extends State<EmojiCell> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final pointer = inputOf(context) == PTInput.pointer;
    final glyph = SizedBox.square(
      dimension: widget.extent,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: widget.selected
              ? PTColors.white(0.14)
              : _hovered
              ? PTColors.white(0.08)
              : null,
          borderRadius: BorderRadius.circular(PTRadius.control),
        ),
        // Icon-like: the glyph does not grow with the text scale, or a 2x user
        // gets a grid of clipped halves.
        child: Center(
          child: MediaQuery.withNoTextScaling(
            child: Text(widget.emoji, style: PTText.emoji.copyWith(fontSize: widget.extent * 0.58)),
          ),
        ),
      ),
    );
    Widget cell = MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: .opaque,
        onTap: widget.onTap,
        onLongPress: widget.onHold,
        onSecondaryTap: widget.onHold,
        child: glyph,
      ),
    );
    // Names as tooltips on pointer only: touch has no hover, and a long-press
    // tooltip would fight the long-press tone chooser.
    if (pointer && widget.label != null) {
      cell = Tooltip(
        message: widget.label!,
        waitDuration: const Duration(milliseconds: 600),
        child: cell,
      );
    }
    return Semantics(button: true, label: widget.label ?? widget.emoji, child: cell);
  }
}
