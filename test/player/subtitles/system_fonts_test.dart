import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:synctogether/player/subtitles/system_fonts.dart';

SystemFontFace _face(int weight, {bool italic = false}) => SystemFontFace(
  name: 'F-$weight${italic ? 'i' : ''}',
  style: '',
  weight: weight,
  italic: italic,
);

void main() {
  group('resolveFace', () {
    final family = SystemFontFamily('F', [
      _face(300),
      _face(400),
      _face(700),
      _face(400, italic: true),
    ]);

    test('exact match', () => expect(resolveFace(family, 700, false)!.name, 'F-700'));

    test('nearest weight, ties go heavier', () {
      expect(resolveFace(family, 600, false)!.name, 'F-700');
      expect(resolveFace(family, 350, false)!.name, 'F-400');
      expect(resolveFace(family, 900, false)!.name, 'F-700');
    });

    test('slant beats weight', () {
      expect(resolveFace(family, 700, true)!.name, 'F-400i');
    });

    test('an empty family resolves to nothing', () {
      expect(resolveFace(const SystemFontFamily('x', []), 400, false), isNull);
    });

    test('weights lists upright faces once, ascending', () {
      expect(family.weights, [300, 400, 700]);
      expect(family.hasItalic, isTrue);
    });
  });

  test('AppKit weight scale maps regular to 400 and bold to 700', () {
    expect(cssWeightFromAppKit(5), 400);
    expect(cssWeightFromAppKit(9), 700);
    expect(cssWeightFromAppKit(2), 100);
    expect(cssWeightFromAppKit(14), 900);
  });

  group('parseAndroidFontsXml', () {
    const xml = '''
<familyset version="23">
  <family name="sans-serif">
    <font weight="400" style="normal" postScriptName="Roboto-Regular">Roboto-Regular.ttf
      <axis tag="wdth" stylevalue="100" />
    </font>
    <font weight="700" style="normal">Roboto-Bold.ttf</font>
    <font weight="400" style="italic">Roboto-Italic.ttf</font>
  </family>
  <alias name="sans-serif-medium" to="sans-serif" weight="500" />
  <family name="serif">
    <font weight="400" style="normal">NotoSerif-Regular.ttf</font>
  </family>
  <family lang="und-Arab" variant="elegant">
    <font weight="400" style="normal">NotoNaskhArabic-Regular.ttf</font>
  </family>
</familyset>''';

    test('lists named families with their faces and files', () {
      final families = parseAndroidFontsXml(xml, '/system/fonts');
      expect(families.map((f) => f.name), ['sans-serif', 'serif']);
      final sans = families.first;
      expect(sans.faces, hasLength(3));
      expect(sans.faces.first.name, 'Roboto-Regular');
      expect(sans.faces.first.path, '/system/fonts/Roboto-Regular.ttf');
      expect(sans.faces[1].name, 'Roboto-Bold');
      expect(sans.faces[1].weight, 700);
      expect(sans.faces[2].italic, isTrue);
      expect(sans.faces[2].style, 'Regular Italic');
    });
  });

  test('readFontNames reads the name table of a real font', () {
    final names = readFontNames(File('assets/fonts/Outfit-400.ttf').readAsBytesSync());
    expect(names, isNotNull);
    expect(names!.family, startsWith('Outfit'));
    expect(names.full, startsWith('Outfit'));
  });

  test('readFontNames refuses garbage without throwing', () {
    expect(readFontNames(Uint8List.fromList(List.filled(40, 7))), isNull);
    expect(readFontNames(Uint8List(0)), isNull);
  });
}
