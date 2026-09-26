import 'dart:async';
import '../../ui/booth_icons.g.dart';

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:synctogether/diagnostics.dart';
import 'package:synctogether/player/subtitles/subtitle_prefs.dart';
import 'package:synctogether/player/subtitles/subtitle_style.dart';
import 'package:synctogether/player/subtitles/system_fonts.dart';
import 'package:synctogether/ui/buttons.dart';
import 'package:synctogether/ui/glass.dart';
import 'package:synctogether/ui/inputs.dart';
import 'package:synctogether/ui/loader.dart';
import 'package:synctogether/ui/pt_theme.dart';

/// Opens the subtitle style sheet. It docks beside the video without dimming
/// it, because every change is applied to the playing video as it is made -
/// the video is the real preview, the card at the top only a stand-in for
/// moments with no line on screen.
Future<void> showSubtitleStyleDialog(BuildContext context, {SubtitlePrefs? prefs}) async {
  final p = prefs ?? SubtitlePrefs.instance;
  // Already loaded by the room's applier; the sheet follows prefs either way,
  // so opening never waits on disk.
  unawaited(p.load());
  final before = p.style;
  await showGlassDialog<void>(
    context: context,
    width: 400,
    sheetOnCompact: true,
    dimBackground: false,
    alignment: AlignmentDirectional.centerEnd,
    builder: (_) => SubtitleStyleSheet(prefs: p),
  );
  if (p.style != before) {
    final d = SubtitleStyle.defaults().toJson();
    trace(
      'subtitle style saved',
      category: 'media',
      data: {
        for (final e in p.style.toJson().entries)
          if (d[e.key] != e.value) e.key: e.value,
      },
    );
  }
}

class SubtitleStyleSheet extends StatefulWidget {
  const SubtitleStyleSheet({super.key, required this.prefs});
  final SubtitlePrefs prefs;

  @override
  State<SubtitleStyleSheet> createState() => _SubtitleStyleSheetState();
}

class _SubtitleStyleSheetState extends State<SubtitleStyleSheet> {
  SystemFontFamily? _family;

  SubtitlePrefs get _prefs => widget.prefs;
  SubtitleStyle get _style => _prefs.style;

  @override
  void initState() {
    super.initState();
    _prefs.addListener(_changed);
    unawaited(_loadFamily());
  }

  @override
  void dispose() {
    _prefs.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  Future<void> _loadFamily() async {
    final name = _style.fontFamily;
    final family = name == null ? null : await SystemFonts.find(name);
    if (mounted) setState(() => _family = family);
  }

  void _set(SubtitleStyle s, {bool persist = true}) => _prefs.update(s, persist: persist);

  Future<void> _pickFont() async {
    final picked = await showGlassDialog<_FontChoice>(
      context: context,
      width: 420,
      scrollable: false,
      builder: (_) => _FontPicker(selected: _style.fontFamily),
    );
    if (picked == null) return;
    final family = picked.family;
    final weights = family?.weights ?? const [];
    // Keep the chosen weight if the new family has it, else its nearest.
    var weight = _style.weight;
    if (weights.isNotEmpty && !weights.contains(weight)) {
      weight = weights.reduce((a, b) => (a - weight).abs() <= (b - weight).abs() ? a : b);
    }
    setState(() => _family = family);
    _set(
      _style.copyWith(
        fontFamily: () => family?.name,
        weight: weight,
        italic: _style.italic && (family?.hasItalic ?? true),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = _style;
    final weights = _family?.weights ?? const [400, 700];
    return Column(
      mainAxisSize: .min,
      crossAxisAlignment: .stretch,
      spacing: 18,
      children: [
        GlassDialogHeader(
          eyebrow: 'Subtitles',
          title: 'Subtitle style',
          subtitle: 'The video is the preview. Changes land live.',
          onClose: () => Navigator.of(context).pop(),
        ),
        SubtitlePreview(style: s),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final preset in SubtitlePreset.all)
              _Chip(
                label: preset.name,
                selected: preset.apply(s) == s,
                onTap: () => _set(preset.apply(s)),
              ),
          ],
        ),
        _Section('Font', [
          _FontRow(family: s.fontFamily, onTap: _pickFont),
          if (weights.length > 1)
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final w in weights)
                  _Chip(
                    label: weightLabel(w),
                    selected: s.weight == w,
                    onTap: () => _set(s.copyWith(weight: w)),
                  ),
              ],
            ),
          PTCheckTile(
            label: 'Italic',
            value: s.italic,
            onChanged: (v) => _set(s.copyWith(italic: v)),
          ),
          _SliderRow(
            label: 'Size',
            value: s.scale,
            min: SubtitleStyle.minScale,
            max: SubtitleStyle.maxScale,
            format: (v) => '${(v * 100).round()}%',
            onChanged: (v, persist) => _set(s.copyWith(scale: v), persist: persist),
          ),
          _SliderRow(
            label: 'Letter spacing',
            value: s.letterSpacing,
            min: SubtitleStyle.minSpacing,
            max: SubtitleStyle.maxSpacing,
            format: (v) => v.toStringAsFixed(1),
            onChanged: (v, persist) => _set(s.copyWith(letterSpacing: v), persist: persist),
          ),
        ]),
        _Section('Text colour', [
          _ColorRow(
            color: s.textColor,
            onChanged: (c, persist) => _set(s.copyWith(textColor: c), persist: persist),
          ),
        ]),
        _Section('Outline', [
          _ColorRow(
            color: s.outlineColor,
            onChanged: (c, persist) => _set(s.copyWith(outlineColor: c), persist: persist),
          ),
          _SliderRow(
            label: 'Width',
            value: s.outlineSize,
            min: 0,
            max: SubtitleStyle.maxOutline,
            format: (v) => v.toStringAsFixed(1),
            onChanged: (v, persist) => _set(s.copyWith(outlineSize: v), persist: persist),
          ),
        ]),
        _Section('Shadow', [
          _ColorRow(
            color: s.shadowColor,
            onChanged: (c, persist) => _set(s.copyWith(shadowColor: c), persist: persist),
          ),
          _SliderRow(
            label: 'Distance',
            value: s.shadowOffset,
            min: 0,
            max: SubtitleStyle.maxShadowOffset,
            format: (v) => v.toStringAsFixed(1),
            onChanged: (v, persist) => _set(s.copyWith(shadowOffset: v), persist: persist),
          ),
          _SliderRow(
            label: 'Blur',
            value: s.blur,
            min: 0,
            max: SubtitleStyle.maxBlur,
            format: (v) => v.toStringAsFixed(1),
            onChanged: (v, persist) => _set(s.copyWith(blur: v), persist: persist),
          ),
          Text(
            'Blur softens the outline too, since subtitles draw them together.',
            style: PTText.caption,
          ),
        ]),
        _Section('Background box', [
          _ColorRow(
            color: s.backgroundColor,
            allowNone: true,
            onChanged: (c, persist) => _set(s.copyWith(backgroundColor: c), persist: persist),
          ),
        ]),
        _Section('Position', [
          _SliderRow(
            label: 'Height',
            value: 100 - s.position,
            min: 0,
            max: 100,
            format: (v) => v.round() == 0 ? 'Bottom' : '${v.round()}%',
            onChanged: (v, persist) => _set(s.copyWith(position: 100 - v), persist: persist),
          ),
          Row(
            spacing: 8,
            children: [
              Expanded(child: Text('Alignment', style: PTText.body.copyWith(fontSize: 14))),
              for (final (align, icon, tip) in [
                (SubtitleAlign.left, Symbols.format_align_left_rounded, 'Left'),
                (SubtitleAlign.center, Symbols.format_align_center_rounded, 'Centre'),
                (SubtitleAlign.right, Symbols.format_align_right_rounded, 'Right'),
              ])
                PTIconButton(
                  icon: icon,
                  size: 38,
                  iconSize: 19,
                  tooltip: tip,
                  active: s.align == align,
                  onPressed: () => _set(s.copyWith(align: align)),
                ),
            ],
          ),
        ]),
        PTToggleRow(
          title: 'Always use my style',
          subtitle:
              'Also restyles subtitles that bring their own fonts and colours. '
              'Leave off to keep signs and karaoke as they were made.',
          value: s.overrideEmbedded,
          onChanged: (v) => _set(s.copyWith(overrideEmbedded: v)),
        ),
        PTButtonBar(
          buttons: [
            PTButton(
              label: 'Reset',
              variant: .secondary,
              onPressed: () async {
                _prefs.reset();
                await _loadFamily();
              },
            ),
            PTButton(label: 'Done', onPressed: () => Navigator.of(context).pop()),
          ],
        ),
      ],
    );
  }
}

String weightLabel(int w) => switch (w) {
  <= 100 => 'Thin',
  <= 200 => 'Extra Light',
  <= 300 => 'Light',
  <= 400 => 'Regular',
  <= 500 => 'Medium',
  <= 600 => 'Semi Bold',
  <= 700 => 'Bold',
  <= 800 => 'Extra Bold',
  _ => 'Black',
};

/// A Flutter approximation of what libass will draw, over a still: for the
/// moments the real video has no line on screen. Sized against a 720p frame
/// the way mpv sizes subtitles.
class SubtitlePreview extends StatelessWidget {
  const SubtitlePreview({super.key, required this.style});
  final SubtitleStyle style;

  static const sample = 'The quick brown fox jumps over the lazy dog.';

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(PTRadius.panel),
      child: AspectRatio(
        aspectRatio: 16 / 9,
        child: LayoutBuilder(
          builder: (context, c) {
            final k = c.maxHeight / 720; // mpv's base: 38px at 720p
            final base = TextStyle(
              fontFamily: style.fontFamily,
              fontSize: 38 * style.scale * k,
              fontWeight: FontWeight.values[(style.weight ~/ 100 - 1).clamp(0, 8)],
              fontStyle: style.italic ? .italic : .normal,
              letterSpacing: style.letterSpacing * k,
              height: 1.2,
            );
            final align = switch (style.align) {
              .left => TextAlign.left,
              .center => TextAlign.center,
              .right => TextAlign.right,
            };
            final offset = style.shadowOffset * k;
            final blur = style.blur * k * 2;
            Widget line(TextStyle s) =>
                Text(sample, textAlign: align, textScaler: TextScaler.noScaling, style: s);
            Widget text = Stack(
              children: [
                if (offset > 0 || blur > 0)
                  Transform.translate(
                    offset: Offset(offset, offset),
                    child: line(
                      base.copyWith(
                        color: Color(style.shadowColor),
                        shadows: [Shadow(color: Color(style.shadowColor), blurRadius: blur)],
                      ),
                    ),
                  ),
                if (style.outlineSize > 0)
                  line(
                    base.copyWith(
                      foreground: Paint()
                        ..style = PaintingStyle.stroke
                        ..strokeWidth = style.outlineSize * k * 2
                        ..strokeJoin = StrokeJoin.round
                        ..color = Color(style.outlineColor),
                    ),
                  ),
                line(base.copyWith(color: Color(style.textColor))),
              ],
            );
            if (style.hasBackground) {
              text = DecoratedBox(
                decoration: BoxDecoration(color: Color(style.backgroundColor)),
                child: Padding(padding: EdgeInsets.all(4 * k), child: text),
              );
            }
            return Stack(
              fit: .expand,
              children: [
                Image.asset('assets/store/movie_still.jpg', fit: BoxFit.cover),
                Padding(
                  padding: EdgeInsets.fromLTRB(25 * k, 22 * k, 25 * k, 22 * k),
                  child: Align(
                    alignment: Alignment(switch (style.align) {
                      .left => -1,
                      .center => 0,
                      .right => 1,
                    }, style.position / 50 - 1),
                    child: text,
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section(this.title, this.children);
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: .stretch,
      spacing: 10,
      children: [
        // Hairline over a mono kicker: sections read as a programme, not cards.
        Container(
          padding: const EdgeInsets.only(top: 12),
          decoration: const BoxDecoration(
            border: Border(top: BorderSide(color: PTColors.rail)),
          ),
          child: Text(title.toUpperCase(), style: PTText.label),
        ),
        ...children,
      ],
    );
  }
}

class _SliderRow extends StatelessWidget {
  const _SliderRow({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.format,
    required this.onChanged,
  });

  final String label;
  final double value, min, max;
  final String Function(double) format;

  /// `persist` is false mid-drag and true on release.
  final void Function(double value, bool persist) onChanged;

  @override
  Widget build(BuildContext context) {
    double denorm(double t) => min + (max - min) * t;
    return Column(
      crossAxisAlignment: .stretch,
      spacing: 6,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: PTText.body.copyWith(fontSize: 13.5, color: PTColors.white(0.75)),
                overflow: .ellipsis,
              ),
            ),
            Text(format(value), style: PTText.caption),
          ],
        ),
        PTSlider(
          value: ((value - min) / (max - min)).clamp(0, 1),
          onChanged: (t) => onChanged(denorm(t), false),
          onChangeEnd: (t) => onChanged(denorm(t), true),
        ),
      ],
    );
  }
}

/// Swatches plus an opacity slider; the colour's alpha *is* the opacity.
class _ColorRow extends StatelessWidget {
  const _ColorRow({required this.color, required this.onChanged, this.allowNone = false});

  final int color;
  final bool allowNone;
  final void Function(int color, bool persist) onChanged;

  @override
  Widget build(BuildContext context) {
    final rgb = color & 0x00FFFFFF;
    final alpha = (color >>> 24) / 255;
    int withAlpha(int rgb, double a) => ((a * 255).round() << 24) | rgb;
    return Column(
      crossAxisAlignment: .stretch,
      spacing: 10,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final swatch in PTColors.subtitleSwatches)
              _Swatch(
                color: swatch,
                selected: alpha > 0 && (swatch.toARGB32() & 0x00FFFFFF) == rgb,
                onTap: () => onChanged(
                  withAlpha(swatch.toARGB32() & 0x00FFFFFF, alpha > 0 ? alpha : 0.75),
                  true,
                ),
              ),
          ],
        ),
        _SliderRow(
          label: allowNone ? 'Opacity (0 = off)' : 'Opacity',
          value: alpha,
          min: 0,
          max: 1,
          format: (v) => v == 0 && allowNone ? 'Off' : '${(v * 100).round()}%',
          onChanged: (v, persist) => onChanged(withAlpha(rgb, v), persist),
        ),
      ],
    );
  }
}

class _Swatch extends StatelessWidget {
  const _Swatch({required this.color, required this.selected, required this.onTap});
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(PTRadius.control),
            border: Border.all(
              color: selected ? PTColors.primary : PTColors.rail,
              width: selected ? 2.5 : 1,
            ),
          ),
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label, required this.selected, required this.onTap});
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: selected ? PTColors.aisle : Colors.transparent,
            border: Border.all(color: selected ? PTColors.primary : PTColors.rail),
            borderRadius: BorderRadius.circular(PTRadius.control),
          ),
          child: Text(
            label,
            style: PTText.body.copyWith(
              fontSize: 13,
              fontWeight: selected ? .w600 : .w400,
              color: selected ? PTColors.primary : PTColors.white(0.8),
            ),
          ),
        ),
      ),
    );
  }
}

class _FontRow extends StatelessWidget {
  const _FontRow({required this.family, required this.onTap});
  final String? family;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
          decoration: BoxDecoration(
            border: Border.all(color: PTColors.rail),
            borderRadius: BorderRadius.circular(PTRadius.control),
          ),
          child: Row(
            spacing: 10,
            children: [
              Icon(Symbols.font_download_rounded, size: 18, color: PTColors.white(0.6)),
              Expanded(
                child: Text(
                  family ?? 'Default font',
                  overflow: .ellipsis,
                  style: PTText.body.copyWith(fontSize: 14.5, fontFamily: family),
                ),
              ),
              Icon(BoothIcons.chevronRight, size: 18, color: PTColors.white(0.5)),
            ],
          ),
        ),
      ),
    );
  }
}

/// A picked font; a null [family] is "Default font".
class _FontChoice {
  const _FontChoice(this.family);
  final SystemFontFamily? family;
}

class _FontPicker extends StatefulWidget {
  const _FontPicker({required this.selected});
  final String? selected;

  @override
  State<_FontPicker> createState() => _FontPickerState();
}

class _FontPickerState extends State<_FontPicker> {
  final _query = TextEditingController();
  late final Future<List<SystemFontFamily>> _families = SystemFonts.list();

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final height = (MediaQuery.sizeOf(context).height * 0.55).clamp(200.0, 460.0);
    return Column(
      mainAxisSize: .min,
      crossAxisAlignment: .stretch,
      spacing: 14,
      children: [
        GlassDialogHeader(
          eyebrow: 'Subtitles',
          title: 'Font',
          onClose: () => Navigator.of(context).pop(),
        ),
        PTTextField(
          controller: _query,
          hint: 'Search fonts',
          prefixIcon: Symbols.search_rounded,
          onChanged: (_) => setState(() {}),
        ),
        SizedBox(
          height: height,
          child: FutureBuilder<List<SystemFontFamily>>(
            future: _families,
            builder: (context, snap) {
              final all = snap.data;
              if (all == null) return const Center(child: PTLoader(size: 20));
              final q = _query.text.trim().toLowerCase();
              final shown = [
                null,
                ...all.where((f) => q.isEmpty || f.name.toLowerCase().contains(q)),
              ];
              return ListView.builder(
                itemCount: shown.length,
                itemBuilder: (context, i) {
                  final f = shown[i];
                  final selected = f?.name == widget.selected;
                  return MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: GestureDetector(
                      onTap: () => Navigator.of(context).pop(_FontChoice(f)),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                        decoration: BoxDecoration(
                          color: selected ? PTColors.aisle : Colors.transparent,
                          border: Border.all(
                            color: selected ? PTColors.primary : Colors.transparent,
                          ),
                          borderRadius: BorderRadius.circular(PTRadius.control),
                        ),
                        child: Text(
                          f?.name ?? 'Default font',
                          overflow: .ellipsis,
                          // Each family previews in itself.
                          style: PTText.body.copyWith(fontSize: 16, fontFamily: f?.name),
                        ),
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}
