import 'package:flutter/widgets.dart';

import 'pt_theme.dart';

/// Cap height over the em, read from each bundled font's OS/2 table
/// (sCapHeight / unitsPerEm). Weights of a family share it.
double _capHeightEm(String? family) => switch (family) {
  PTFonts.display => 0.66, // Bricolage Grotesque
  PTFonts.mono => 0.73, // JetBrains Mono
  _ => 0.697, // Hanken Grotesk, and anything set in the body font
};

/// The vertical shift that puts an icon on the cap-height centre of text set in
/// [style], at the user's system text size.
///
/// A row centres an icon on the text's line box, but the words are not centred in
/// it: the baseline sits where the font's ascent puts it (rounded to whole pixels by
/// the engine), and the letters rise a cap height above it. So the centre of the
/// capitals is `baseline - cap / 2`, measured here from the same layout the text
/// itself gets - the real baseline at the real, scaled size - so it holds when the
/// system font size changes. The icon font is centred on its own box (its line box is
/// exactly its size; see `test/ui/booth_icons_metrics_test.dart`), so this is all
/// that is left.
double opticalShift(BuildContext context, TextStyle style) {
  final scaler = MediaQuery.textScalerOf(context);
  final painter = TextPainter(
    text: TextSpan(text: 'M', style: style),
    textScaler: scaler,
    textDirection: TextDirection.ltr,
  )..layout();
  final baseline = painter.computeDistanceToActualBaseline(TextBaseline.alphabetic);
  final cap = scaler.scale(style.fontSize ?? 14) * _capHeightEm(style.fontFamily);
  final shift = baseline - cap / 2 - painter.height / 2;
  painter.dispose();
  return shift;
}

/// An icon that sits optically centred on the words beside it: use it in a row with
/// text, passing that text's style as [beside]. It follows the system text size.
class PTOpticalIcon extends StatelessWidget {
  const PTOpticalIcon(this.icon, {super.key, required this.beside, this.size, this.color});

  final IconData icon;
  final TextStyle beside;
  final double? size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Transform.translate(
      offset: Offset(0, opticalShift(context, beside)),
      child: Icon(icon, size: size, color: color),
    );
  }
}
