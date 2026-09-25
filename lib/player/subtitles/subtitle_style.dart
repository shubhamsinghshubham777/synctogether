import 'package:flutter/foundation.dart';
import 'package:synctogether/ui/pt_theme.dart';

enum SubtitleAlign { left, center, right }

/// How the viewer wants text subtitles drawn. Rendered by libass (mpv's
/// `sub-*` options) on every platform, so every field here is something libass
/// can actually do - see [toMpvProperties].
///
/// Colours are ARGB ints: they are the viewer's data, persisted as JSON, and
/// only the defaults come from [PTColors].
@immutable
class SubtitleStyle {
  const SubtitleStyle({
    required this.fontFamily,
    required this.weight,
    required this.italic,
    required this.scale,
    required this.textColor,
    required this.outlineColor,
    required this.outlineSize,
    required this.shadowColor,
    required this.shadowOffset,
    required this.blur,
    required this.backgroundColor,
    required this.position,
    required this.align,
    required this.letterSpacing,
    required this.overrideEmbedded,
  });

  /// mpv's own look: white, a 3px black outline, no shadow.
  factory SubtitleStyle.defaults() => SubtitleStyle(
    fontFamily: null,
    weight: 400,
    italic: false,
    scale: 1,
    textColor: PTColors.subtitleText.toARGB32(),
    outlineColor: PTColors.subtitleOutline.toARGB32(),
    outlineSize: 3,
    shadowColor: PTColors.subtitleShadow.withValues(alpha: 0.6).toARGB32(),
    shadowOffset: 0,
    blur: 0,
    backgroundColor: 0,
    position: 100,
    align: .center,
    letterSpacing: 0,
    overrideEmbedded: false,
  );

  static const int version = 1;

  // Ranges the UI offers and [fromJson] clamps to.
  static const minScale = 0.5, maxScale = 2.5;
  static const maxOutline = 6.0, maxShadowOffset = 8.0, maxBlur = 20.0;
  static const minSpacing = -2.0, maxSpacing = 10.0;

  /// Null is the platform default font.
  final String? fontFamily;

  /// CSS-style 100-900. libass only knows bold on/off, so this picks a *face*
  /// of [fontFamily] (see `resolveFace`) rather than being sent as a number.
  final int weight;
  final bool italic;

  /// Multiplier on mpv's 720p-relative base size.
  final double scale;
  final int textColor;
  final int outlineColor;
  final double outlineSize;
  final int shadowColor;
  final double shadowOffset;

  /// libass blurs the glyph edges - outline and shadow together, it has no
  /// shadow-only blur.
  final double blur;

  /// Alpha 0 = no box.
  final int backgroundColor;

  /// Vertical position, 0 top .. 100 bottom (mpv `sub-pos`).
  final double position;
  final SubtitleAlign align;
  final double letterSpacing;

  /// Also restyle ASS/SSA tracks that carry their own styling. Off keeps
  /// their typesetting (signs, karaoke) intact and only scales it.
  final bool overrideEmbedded;

  bool get hasBackground => (backgroundColor >>> 24) > 0;

  SubtitleStyle copyWith({
    String? Function()? fontFamily,
    int? weight,
    bool? italic,
    double? scale,
    int? textColor,
    int? outlineColor,
    double? outlineSize,
    int? shadowColor,
    double? shadowOffset,
    double? blur,
    int? backgroundColor,
    double? position,
    SubtitleAlign? align,
    double? letterSpacing,
    bool? overrideEmbedded,
  }) => SubtitleStyle(
    fontFamily: fontFamily != null ? fontFamily() : this.fontFamily,
    weight: weight ?? this.weight,
    italic: italic ?? this.italic,
    scale: scale ?? this.scale,
    textColor: textColor ?? this.textColor,
    outlineColor: outlineColor ?? this.outlineColor,
    outlineSize: outlineSize ?? this.outlineSize,
    shadowColor: shadowColor ?? this.shadowColor,
    shadowOffset: shadowOffset ?? this.shadowOffset,
    blur: blur ?? this.blur,
    backgroundColor: backgroundColor ?? this.backgroundColor,
    position: position ?? this.position,
    align: align ?? this.align,
    letterSpacing: letterSpacing ?? this.letterSpacing,
    overrideEmbedded: overrideEmbedded ?? this.overrideEmbedded,
  );

  Map<String, Object?> toJson() => {
    'v': version,
    'font': fontFamily,
    'weight': weight,
    'italic': italic,
    'scale': scale,
    'text': textColor,
    'outline': outlineColor,
    'outlineSize': outlineSize,
    'shadow': shadowColor,
    'shadowOffset': shadowOffset,
    'blur': blur,
    'bg': backgroundColor,
    'pos': position,
    'align': align.name,
    'spacing': letterSpacing,
    'override': overrideEmbedded,
  };

  /// Anything missing, mistyped or out of range falls back to the default for
  /// that field, so a hand-edited or future-version blob degrades per field
  /// instead of throwing the whole style away.
  factory SubtitleStyle.fromJson(Map<String, Object?> json) {
    final d = SubtitleStyle.defaults();
    double num_(String k, double fallback, double lo, double hi) {
      final v = json[k];
      return v is num && v.isFinite ? v.toDouble().clamp(lo, hi) : fallback;
    }

    int color(String k, int fallback) {
      final v = json[k];
      return v is int ? v & 0xFFFFFFFF : fallback;
    }

    final font = json['font'];
    final weight = json['weight'];
    final italic = json['italic'];
    final override = json['override'];
    return SubtitleStyle(
      fontFamily: font is String && font.trim().isNotEmpty ? font : null,
      weight: weight is int ? ((weight / 100).round() * 100).clamp(100, 900) : d.weight,
      italic: italic is bool ? italic : d.italic,
      scale: num_('scale', d.scale, minScale, maxScale),
      textColor: color('text', d.textColor),
      outlineColor: color('outline', d.outlineColor),
      outlineSize: num_('outlineSize', d.outlineSize, 0, maxOutline),
      shadowColor: color('shadow', d.shadowColor),
      shadowOffset: num_('shadowOffset', d.shadowOffset, 0, maxShadowOffset),
      blur: num_('blur', d.blur, 0, maxBlur),
      backgroundColor: color('bg', d.backgroundColor),
      position: num_('pos', d.position, 0, 100),
      align: SubtitleAlign.values.asNameMap()[json['align']] ?? d.align,
      letterSpacing: num_('spacing', d.letterSpacing, minSpacing, maxSpacing),
      overrideEmbedded: override is bool ? override : d.overrideEmbedded,
    );
  }

  @override
  bool operator ==(Object other) => other is SubtitleStyle && mapEquals(other.toJson(), toJson());

  @override
  int get hashCode => Object.hashAll(toJson().values);
}

/// A named starting point in the style sheet. Presets keep the font, so
/// picking "Boxed" does not undo the typeface someone just chose.
class SubtitlePreset {
  const SubtitlePreset(this.name, this.apply);
  final String name;
  final SubtitleStyle Function(SubtitleStyle current) apply;

  static final all = <SubtitlePreset>[
    SubtitlePreset('Classic', (s) => _base(s)),
    SubtitlePreset(
      'Cinema',
      (s) => _base(s).copyWith(
        textColor: PTColors.subtitleSwatches[1].toARGB32(),
        outlineSize: 1.5,
        shadowOffset: 2,
        blur: 2,
        shadowColor: PTColors.subtitleShadow.withValues(alpha: 0.75).toARGB32(),
      ),
    ),
    SubtitlePreset(
      'Boxed',
      (s) => _base(s).copyWith(
        outlineSize: 0,
        backgroundColor: PTColors.subtitleShadow.withValues(alpha: 0.72).toARGB32(),
      ),
    ),
    SubtitlePreset('Minimal', (s) => _base(s).copyWith(outlineSize: 0.8, shadowOffset: 1, blur: 3)),
  ];

  static SubtitleStyle _base(SubtitleStyle s) {
    final d = SubtitleStyle.defaults();
    return d.copyWith(
      fontFamily: () => s.fontFamily,
      weight: s.weight,
      italic: s.italic,
      scale: s.scale,
      position: s.position,
      align: s.align,
      overrideEmbedded: s.overrideEmbedded,
    );
  }
}

/// mpv's colour syntax, `#AARRGGBB`.
String mpvColor(int argb) =>
    '#${(argb & 0xFFFFFFFF).toRadixString(16).padLeft(8, '0').toUpperCase()}';

String _n(double v) {
  final s = v.toStringAsFixed(2);
  return s.contains('.') ? s.replaceFirst(RegExp(r'\.?0+$'), '') : s;
}

/// The mpv option values that draw [style]. [font] is what libass should look
/// up - a resolved face name when one was found, else the family, else the
/// platform default - and [bold]/[italic] ask libass to synthesise what the
/// named face does not already carry.
///
/// Every key here exists in the bundled mpv 0.36: newer spellings
/// (`sub-outline-*`, `sub-border-style`) would silently no-op on it.
Map<String, String> toMpvProperties(
  SubtitleStyle style, {
  required String font,
  required bool bold,
  required bool italic,
}) => {
  'sub-font': font,
  'sub-bold': bold ? 'yes' : 'no',
  'sub-italic': italic ? 'yes' : 'no',
  'sub-scale': _n(style.scale),
  'sub-color': mpvColor(style.textColor),
  'sub-border-color': mpvColor(style.outlineColor),
  'sub-border-size': _n(style.outlineSize),
  'sub-shadow-color': mpvColor(style.shadowColor),
  'sub-shadow-offset': _n(style.shadowOffset),
  'sub-blur': _n(style.blur),
  // In 0.36 a non-transparent back colour switches libass to its opaque box
  // (BorderStyle 4); fully transparent draws nothing.
  'sub-back-color': mpvColor(style.backgroundColor),
  'sub-pos': style.position.round().toString(),
  'sub-align-x': style.align.name,
  'sub-spacing': _n(style.letterSpacing),
  'sub-ass-override': style.overrideEmbedded ? 'force' : 'scale',
};
