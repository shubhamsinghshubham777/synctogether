import 'package:flutter_test/flutter_test.dart';
import 'package:synctogether/player/subtitles/subtitle_style.dart';

void main() {
  group('SubtitleStyle JSON', () {
    test('round-trips every field', () {
      final style = SubtitleStyle.defaults().copyWith(
        fontFamily: () => 'Avenir Next',
        weight: 600,
        italic: true,
        scale: 1.4,
        textColor: 0xFFFDE047,
        outlineColor: 0x80000000,
        outlineSize: 2.5,
        shadowColor: 0xC0000000,
        shadowOffset: 3,
        blur: 4,
        backgroundColor: 0xB8000000,
        position: 90,
        align: .left,
        letterSpacing: 1.5,
        overrideEmbedded: true,
      );
      expect(SubtitleStyle.fromJson(style.toJson()), style);
    });

    test('a corrupt or foreign blob degrades per field, not wholesale', () {
      final d = SubtitleStyle.defaults();
      final s = SubtitleStyle.fromJson({
        'v': 99,
        'font': '   ',
        'weight': 'bold',
        'scale': 40,
        'blur': -3,
        'pos': double.nan,
        'align': 'justify',
        'text': 0x1FFFFFFFF,
        'italic': true,
      });
      expect(s.fontFamily, isNull);
      expect(s.weight, d.weight);
      expect(s.scale, SubtitleStyle.maxScale);
      expect(s.blur, 0);
      expect(s.position, d.position);
      expect(s.align, d.align);
      expect(s.textColor, 0xFFFFFFFF);
      expect(s.italic, isTrue);
    });

    test('weight snaps to a CSS hundred inside 100-900', () {
      expect(SubtitleStyle.fromJson({'weight': 649}).weight, 600);
      expect(SubtitleStyle.fromJson({'weight': 1200}).weight, 900);
      expect(SubtitleStyle.fromJson({'weight': 0}).weight, 100);
    });

    test('empty JSON is the defaults', () {
      expect(SubtitleStyle.fromJson(const {}), SubtitleStyle.defaults());
    });
  });

  group('toMpvProperties', () {
    test('maps onto the mpv 0.36 option names and formats', () {
      final style = SubtitleStyle.defaults().copyWith(
        scale: 1.25,
        textColor: 0xFFFDE047,
        backgroundColor: 0x00000000,
        position: 87.6,
        align: .right,
        overrideEmbedded: true,
      );
      final props = toMpvProperties(
        style,
        font: 'Avenir Next Demi Bold',
        bold: false,
        italic: true,
      );
      expect(props, {
        'sub-font': 'Avenir Next Demi Bold',
        'sub-bold': 'no',
        'sub-italic': 'yes',
        'sub-scale': '1.25',
        'sub-color': '#FFFDE047',
        'sub-border-color': '#FF000000',
        'sub-border-size': '3',
        'sub-shadow-color': '#99000000',
        'sub-shadow-offset': '0',
        'sub-blur': '0',
        'sub-back-color': '#00000000',
        'sub-pos': '88',
        'sub-align-x': 'right',
        'sub-spacing': '0',
        'sub-ass-override': 'force',
      });
    });

    test('embedded ASS styling is kept unless overridden', () {
      final props = toMpvProperties(
        SubtitleStyle.defaults(),
        font: 'sans-serif',
        bold: false,
        italic: false,
      );
      expect(props['sub-ass-override'], 'scale');
    });

    test('never uses option names newer than the bundled mpv', () {
      final keys = toMpvProperties(
        SubtitleStyle.defaults(),
        font: 'x',
        bold: false,
        italic: false,
      ).keys;
      expect(keys.where((k) => k.contains('outline') || k == 'sub-border-style'), isEmpty);
    });

    test('mpvColor pads to #AARRGGBB', () {
      expect(mpvColor(0x0000000A), '#0000000A');
      expect(mpvColor(0xFFFFFFFF), '#FFFFFFFF');
    });
  });

  group('presets', () {
    test('keep the font, size and placement the viewer chose', () {
      final mine = SubtitleStyle.defaults().copyWith(
        fontFamily: () => 'Georgia',
        weight: 700,
        scale: 1.8,
        position: 60,
        align: .left,
      );
      for (final preset in SubtitlePreset.all) {
        final s = preset.apply(mine);
        expect(s.fontFamily, 'Georgia', reason: preset.name);
        expect(s.weight, 700, reason: preset.name);
        expect(s.scale, 1.8, reason: preset.name);
        expect(s.position, 60, reason: preset.name);
        expect(s.align, SubtitleAlign.left, reason: preset.name);
      }
    });

    test('Classic is the default look and Boxed draws a box', () {
      final d = SubtitleStyle.defaults();
      expect(SubtitlePreset.all.first.apply(d), d);
      final boxed = SubtitlePreset.all.firstWhere((p) => p.name == 'Boxed').apply(d);
      expect(boxed.hasBackground, isTrue);
      expect(boxed.outlineSize, 0);
    });
  });
}
