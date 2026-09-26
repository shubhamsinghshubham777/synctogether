import 'package:flutter/material.dart';

/// Design tokens for "Booth Light" - the projection booth.
///
/// Dark mode only, and deliberately so: the room is dark and the video is the
/// brightest thing on screen. ~90% of any surface is warm booth neutral; the
/// accents are spent with intent:
/// - **Beam** (amber, [primary]) means *live* - play, in sync, the one lit
///   button per screen. Text on it is [onAccent], never white.
/// - **Signal** (coral, [ember]) is on-air: mic hot, reactions, streaks.
/// - **Cue** (teal, [online]) is ready / loaded in the readiness gate.
/// - **Brass** ([premium]) is Patron only - engraved, never a gold gradient.
///
/// The token *names* predate this palette (the violet glass system); they are
/// kept so screens follow the new look without edits. New code should prefer
/// the Booth names ([canvas], [glassBase] = Seat, [aisle], [rail], [fg]).
abstract final class PTColors {
  // Booth neutrals. Warm, never pure black or white.
  static const canvas = Color(0xFF121010); // Booth
  static const screenBg = Color(0xFF121010);
  static const glassBase = Color(0xFF1C1917); // Seat - panels
  static const aisle = Color(0xFF27221F); // raised
  static const rail = Color(0xFF3A332E); // lines
  static const fg = Color(0xFFF4ECDF); // Screen - text, tickets
  static const railStrong = Color(0xFF5A4F44); // secondary button outline

  // The Screen text ramp, opaque so it reads identically on Booth and Seat.
  static const fgDim = Color(0xFFC9BDAC); // idle control glyphs, meta labels
  static const fgSoft = Color(0xFFB5A999); // sender names
  static const fgMute = Color(0xFF8F8476); // kickers, timecode totals
  static const dialogGlassBase = Color(0xFF1C1917);
  static const avatarRing = Color(0xFF121010);
  static const presenceRing = Color(0xFF1C1917);

  // Beam - the accent. Legacy names all resolve to it.
  static const primary = Color(0xFFFFB23F);
  static const textAccent = Color(0xFFFFB23F);
  static const gradientMid = Color(0xFFFFB23F);
  static const gradientEnd = Color(0xFFFFC266);
  static const deep = Color(0xFFD98E1F);
  static const accentBorder = Color(0xFFFFB23F);
  static const accentBorderSoft = Color(0x4DFFB23F);
  static const accentSoft = Color(0xFFFFC266); // hovered Beam
  static const accentBright = Color(0xFFFFE2B0);
  static const link = Color(0xFFFFC266);
  static const onAccent = Color(0xFF1A1206); // text/spinner on Beam

  /// Signal as printed ink on a paper ticket - darker than [ember] so it
  /// holds 4.5:1 on [fg].
  static const liveInk = Color(0xFFA33A22);

  // Semantic.
  static const online = Color(0xFF6FD6C4); // Cue - ready
  static const away = Color(0xFF8F8476);
  static const warning = Color(0xFFFFD27A);
  static const warningBorder = Color(0xFFFFB23F);
  static const danger = Color(0xFFFF8A70);
  static const dangerBorder = Color(0xFFFF6A4D);
  static const premium = Color(0xFFE8C877); // Brass
  static const premiumBorder = Color(0xFFA8893E);

  static const selectionHandle = Color(0xFFFFB23F);
  static const selectionHighlight = Color(0x59FFB23F);

  // Raised surfaces (menus, popovers, toasts, tiles). Elevation is lightness,
  // not blur: Seat -> Aisle.
  static const surfaceBase = Color(0xFF1C1917);
  static const menuSurface = Color(0xFF27221F);
  static const raised = Color(0xFF27221F);
  static const raisedStrong = Color(0xFF27221F);
  static const noticeSurface = Color(0xFF27221F);
  static const toastSurface = Color(0xFF27221F);
  static const tileTop = Color(0xFF27221F);
  static const tileBottom = Color(0xFF1C1917);
  static const splashGlow = Color(0xFF1C1917);

  // Scrims and shadows.
  static const ink = Color(0xFF000000); // video letterbox
  static const scrimBase = Color(0xFF0A0808);
  static const scrimTop = Color(0x8C0A0808);
  static const scrimClear = Color(0x000A0808);
  static const canvasScrim = Color(0x99121010);
  static const barrier = Color(0xB30A0808);
  static const shadowSoft = Color(0x59000000);
  static const shadow = Color(0x66000000);
  static const shadowStrong = Color(0xCC000000);
  static const veilTop = Color(0x99121010);
  static const veilMid = Color(0x5E121010);
  static const veilLow = Color(0x26121010);
  static const veilClear = Color(0x00121010);

  // Ambient glows - retired with the glass look. Transparent rather than
  // removed so nothing still referencing them paints a violet haze.
  static const glowDeep = Color(0x00000000);
  static const glowEnd = Color(0x00000000);
  static const glowIndigo = Color(0x00000000);

  // Banner / pill fills per kind. Opaque: nothing blurs behind them now.
  static const bannerSuccess = Color(0xFF15221F);
  static const bannerDanger = Color(0xFF2A1714);
  static const bannerInfo = Color(0xFF27221F);
  static const pillWarning = Color(0xFF2A2012);
  static const pillInfo = Color(0xFF1C1917);
  static const pillDanger = Color(0xFF2A1714);
  static const dangerSurface = Color(0xFF2A1714);

  // Notice (announcements, ad state).
  static const notice = Color(0xFFFFB23F);

  // Rewards: streak, podium metals, avatar frames. Signal carries streaks.
  static const streak = Color(0xFFFF6A4D);
  static const silver = Color(0xFFCBD5E1);
  static const bronze = Color(0xFFD08C60);
  static const ember = Color(0xFFFF6A4D); // Signal
  static const halo = Color(0xFF6FD6C4);
  static const indigo = Color(0xFF9B8CFF);
  static const cyan = Color(0xFF6FD6C4);
  static const laurelLight = Color(0xFFE9D5A1);
  static const laurel = Color(0xFFB08D57);

  // Subtitles. The viewer picks these and libass draws them into the video,
  // so they are the defaults and the offered swatches, not app chrome.
  static const subtitleText = Color(0xFFFFFFFF);
  static const subtitleOutline = Color(0xFF000000);
  static const subtitleShadow = Color(0xFF000000);
  static const subtitleSwatches = <Color>[
    Color(0xFFFFFFFF),
    Color(0xFFFFF4C2),
    Color(0xFFFDE047),
    Color(0xFF86EFAC),
    Color(0xFF7DD3FC),
    Color(0xFFF9A8D4),
    Color(0xFF9CA3AF),
    Color(0xFF000000),
  ];

  /// The glow on the single lit control: straight out, like light leaving a
  /// projector lens - never a drop shadow.
  static const beamSpill = <BoxShadow>[
    BoxShadow(color: Color(0x59FFB23F), blurRadius: 28, spreadRadius: -8),
  ];

  static Color black(double opacity) => Colors.black.withValues(alpha: opacity);

  /// Screen-tinted, not pure white - the warm cast is what keeps the booth
  /// from reading as a default dark theme.
  static Color white(double opacity) => fg.withValues(alpha: opacity);
  static Color glass(double opacity) => glassBase.withValues(alpha: opacity);
  static Color dialogGlass(double opacity) => dialogGlassBase.withValues(alpha: opacity);

  /// Per-user avatar colours - fixed per user (hash of the user id). Muted
  /// seat colours in two close shades, so they read as flat against the booth
  /// and never compete with Beam.
  static const avatarGradients = <List<Color>>[
    [Color(0xFF8468FF), Color(0xFF7A5CFF)],
    [Color(0xFF379577), Color(0xFF2E8A6E)],
    [Color(0xFFC25038), Color(0xFFB8462E)],
    [Color(0xFF4A79BA), Color(0xFF3F6FB0)],
    [Color(0xFFB0782E), Color(0xFFA56E26)],
    [Color(0xFFA8527A), Color(0xFF9D4870)],
    [Color(0xFF5E8A3E), Color(0xFF548036)],
    [Color(0xFF6F6258), Color(0xFF65584F)],
  ];

  static LinearGradient avatarGradientFor(String userId) {
    final colors = avatarGradients[userId.hashCode.abs() % avatarGradients.length];
    return LinearGradient(begin: .topLeft, end: .bottomRight, colors: colors);
  }
}

abstract final class PTFonts {
  static const display = 'Bricolage Grotesque'; // display & headings
  static const body = 'Hanken Grotesk'; // body & UI
  static const mono = 'JetBrains Mono'; // timecode, room codes, labels
}

/// Corner radii. Tight corners read as a film card or a light box; pills are
/// only for people and presence.
abstract final class PTRadius {
  static const double control = 4;
  static const double panel = 6;
  static const double pill = 999;
}

abstract final class PTText {
  static const display = TextStyle(
    fontFamily: PTFonts.display,
    fontSize: 40,
    fontWeight: .w800,
    letterSpacing: -1.0,
    height: 1.0,
    color: PTColors.fg,
  );
  static const screenTitle = TextStyle(
    fontFamily: PTFonts.display,
    fontSize: 26,
    fontWeight: .w800,
    letterSpacing: -0.5,
    color: PTColors.fg,
  );
  static const cardHeading = TextStyle(
    fontFamily: PTFonts.display,
    fontSize: 19,
    fontWeight: .w700,
    letterSpacing: -0.3,
    color: PTColors.fg,
  );
  static const panelHeading = TextStyle(
    fontFamily: PTFonts.display,
    fontSize: 15,
    fontWeight: .w600,
    color: PTColors.fg,
  );
  static TextStyle body = TextStyle(
    fontFamily: PTFonts.body,
    fontSize: 15,
    fontWeight: .w400,
    color: PTColors.white(0.92),
  );
  static const buttonLabel = TextStyle(
    fontFamily: PTFonts.body,
    fontSize: 15,
    fontWeight: .w600,
    color: PTColors.fg,
  );
  static TextStyle caption = TextStyle(
    fontFamily: PTFonts.body,
    fontSize: 13,
    fontWeight: .w500,
    color: PTColors.white(0.6),
  );
  static TextStyle finePrint = TextStyle(
    fontFamily: PTFonts.body,
    fontSize: 12,
    fontWeight: .w400,
    color: PTColors.white(0.4),
  );
  static const code = TextStyle(
    fontFamily: PTFonts.mono,
    fontSize: 22,
    fontWeight: .w600,
    letterSpacing: 3.96,
    color: PTColors.textAccent,
  );

  /// Emoji render in the platform's own colour font - nothing is bundled
  /// (Apple's set cannot be redistributed; see the chat emoji notes in
  /// CLAUDE.md). The fallback list names each OS's font so a glyph never
  /// resolves through a body font's monochrome emoji first. Opaque white, so
  /// the colour font draws at full saturation.
  static const emoji = TextStyle(
    fontSize: 22,
    height: 1.15,
    color: Colors.white,
    fontFamilyFallback: ['Apple Color Emoji', 'Segoe UI Emoji', 'Noto Color Emoji'],
  );
  static TextStyle mono = TextStyle(
    fontFamily: PTFonts.mono,
    fontSize: 13,
    fontWeight: .w400,
    color: PTColors.white(0.75),
  );

  /// The `// LABEL` motif: uppercase mono at wide tracking, for eyebrows,
  /// section kickers and timecode metadata. Uppercase the string yourself.
  static TextStyle label = TextStyle(
    fontFamily: PTFonts.mono,
    fontSize: 11,
    fontWeight: .w400,
    letterSpacing: 1.5,
    color: PTColors.white(0.55),
  );
}

ThemeData buildPTTheme() {
  const scheme = ColorScheme.dark(
    primary: PTColors.primary,
    secondary: PTColors.ember,
    surface: PTColors.screenBg,
    error: PTColors.danger,
    onPrimary: PTColors.onAccent,
    onSurface: PTColors.fg,
  );

  final base = ThemeData(
    useMaterial3: true,
    brightness: .dark,
    colorScheme: scheme,
    scaffoldBackgroundColor: PTColors.screenBg,
    fontFamily: PTFonts.body,
    splashFactory: InkSparkle.splashFactory,
  );

  return base.copyWith(
    textTheme: base.textTheme.apply(bodyColor: PTColors.white(0.92), displayColor: PTColors.fg),
    sliderTheme: SliderThemeData(
      trackHeight: 4,
      activeTrackColor: PTColors.primary,
      inactiveTrackColor: PTColors.aisle,
      thumbColor: PTColors.fg,
      overlayColor: PTColors.primary.withValues(alpha: 0.15),
      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
      overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
    ),
    dividerTheme: DividerThemeData(color: PTColors.white(0.09), thickness: 1, space: 1),
    // Fallback only - every toast in the app goes through `showPTSnack`, which
    // supplies its own surface (see banners.dart). This just keeps a bare
    // `showSnackBar` from any future caller looking foreign.
    snackBarTheme: SnackBarThemeData(
      backgroundColor: PTColors.dialogGlass(0.95),
      contentTextStyle: PTText.body,
      behavior: .floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(PTRadius.panel)),
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: PTColors.dialogGlass(0.95),
        borderRadius: BorderRadius.circular(PTRadius.control),
        border: Border.all(color: PTColors.rail),
      ),
      textStyle: PTText.caption.copyWith(color: PTColors.white(0.85)),
    ),
    textSelectionTheme: const TextSelectionThemeData(
      cursorColor: PTColors.textAccent,
      selectionColor: PTColors.selectionHighlight,
      selectionHandleColor: PTColors.selectionHandle,
    ),
  );
}
