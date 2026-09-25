import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:synctogether/diagnostics.dart';

/// One installed face of a family: [name] is what libass is handed (a
/// PostScript or full name, which its font selector matches directly), [style]
/// is what the viewer reads ("Demi Bold Italic").
@immutable
class SystemFontFace {
  const SystemFontFace({
    required this.name,
    required this.style,
    required this.weight,
    required this.italic,
    this.path,
  });

  final String name;
  final String style;

  /// CSS-style 100-900.
  final int weight;
  final bool italic;

  /// Android only: the file, which has to be copied where libass can see it.
  final String? path;
}

@immutable
class SystemFontFamily {
  const SystemFontFamily(this.name, this.faces);
  final String name;
  final List<SystemFontFace> faces;

  /// Distinct upright weights, ascending - what the weight picker offers.
  List<int> get weights {
    final upright = faces.where((f) => !f.italic).map((f) => f.weight).toSet();
    final all = upright.isEmpty ? faces.map((f) => f.weight).toSet() : upright;
    return all.toList()..sort();
  }

  bool get hasItalic => faces.any((f) => f.italic);
}

/// The face of [family] closest to [weight]/[italic]: slant first (an italic
/// request prefers any italic over an exact-weight upright), then the nearest
/// weight, ties going heavier - the CSS matching rule, simplified.
SystemFontFace? resolveFace(SystemFontFamily family, int weight, bool italic) {
  if (family.faces.isEmpty) return null;
  final sameSlant = family.faces.where((f) => f.italic == italic).toList();
  final pool = sameSlant.isEmpty ? family.faces : sameSlant;
  SystemFontFace? best;
  for (final f in pool) {
    if (best == null) {
      best = f;
      continue;
    }
    final d = (f.weight - weight).abs(), bd = (best.weight - weight).abs();
    if (d < bd || (d == bd && f.weight > best.weight)) best = f;
  }
  return best;
}

/// NSFontManager's 0-15 weight scale to CSS (5 regular, 9 bold).
int cssWeightFromAppKit(int w) => switch (w) {
  <= 2 => 100,
  3 => 200,
  4 => 300,
  5 => 400,
  6 => 500,
  7 || 8 => 600,
  9 => 700,
  10 => 800,
  _ => 900,
};

/// Parses Android's `/system/etc/fonts.xml`. Only *named* families are
/// listed: the unnamed ones are per-script fallbacks nobody picks by name.
/// Aliases (`sans-serif-medium` -> `sans-serif` at 500) are skipped too - the
/// weight picker already offers them.
List<SystemFontFamily> parseAndroidFontsXml(String xml, String fontsDir) {
  final families = <SystemFontFamily>[];
  final familyRe = RegExp(r'<family\b([^>]*)>(.*?)</family>', dotAll: true);
  final fontRe = RegExp(r'<font\b([^>]*)>\s*([^<\s]+)', dotAll: true);
  String? attr(String attrs, String name) =>
      RegExp('\\b$name="([^"]*)"').firstMatch(attrs)?.group(1);
  for (final m in familyRe.allMatches(xml)) {
    final name = attr(m.group(1)!, 'name');
    if (name == null || name.isEmpty) continue;
    final faces = <SystemFontFace>[];
    for (final f in fontRe.allMatches(m.group(2)!)) {
      final attrs = f.group(1)!;
      final file = f.group(2)!;
      final weight = int.tryParse(attr(attrs, 'weight') ?? '') ?? 400;
      final italic = attr(attrs, 'style') == 'italic';
      faces.add(
        SystemFontFace(
          name: attr(attrs, 'postScriptName') ?? file.replaceFirst(RegExp(r'\.[^.]+$'), ''),
          style: '${_weightName(weight)}${italic ? ' Italic' : ''}',
          weight: weight,
          italic: italic,
          path: '$fontsDir/$file',
        ),
      );
    }
    if (faces.isNotEmpty) families.add(SystemFontFamily(name, faces));
  }
  return families;
}

String _weightName(int w) => switch (w) {
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

/// The family (name id 1) and full name (id 4) inside a TrueType/OpenType
/// file, first face of a collection. libass on Android matches on these, not
/// on the fonts.xml alias the viewer picked, so the applier has to read them.
({String? family, String? full})? readFontNames(Uint8List bytes) {
  try {
    final data = ByteData.sublistView(bytes);
    var base = 0;
    if (bytes.length >= 16 && data.getUint32(0) == 0x74746366) {
      base = data.getUint32(12); // 'ttcf': offset of the first font
    }
    final numTables = data.getUint16(base + 4);
    int? nameOffset;
    for (var i = 0; i < numTables; i++) {
      final rec = base + 12 + i * 16;
      if (data.getUint32(rec) == 0x6E616D65) nameOffset = data.getUint32(rec + 8); // 'name'
    }
    if (nameOffset == null) return null;
    final count = data.getUint16(nameOffset + 2);
    final strings = nameOffset + data.getUint16(nameOffset + 4);
    final found = <int, (int, String)>{}; // nameId -> (rank, value)
    for (var i = 0; i < count; i++) {
      final r = nameOffset + 6 + i * 12;
      final platform = data.getUint16(r), encoding = data.getUint16(r + 2);
      final language = data.getUint16(r + 4), nameId = data.getUint16(r + 6);
      if (nameId != 1 && nameId != 4) continue;
      final length = data.getUint16(r + 8), offset = strings + data.getUint16(r + 10);
      final String value;
      final int rank;
      if (platform == 3 && (encoding == 1 || encoding == 10)) {
        value = String.fromCharCodes([
          for (var j = 0; j + 1 < length; j += 2) data.getUint16(offset + j),
        ]);
        rank = language == 0x409 ? 0 : 1;
      } else if (platform == 1 && encoding == 0) {
        value = String.fromCharCodes(bytes.sublist(offset, offset + length));
        rank = 2;
      } else {
        continue;
      }
      final prev = found[nameId];
      if (prev == null || rank < prev.$1) found[nameId] = (rank, value);
    }
    return (family: found[1]?.$2, full: found[4]?.$2);
  } catch (_) {
    return null;
  }
}

/// Installed font families, from each platform's own font manager (a small
/// method channel in the runner) or, on Android, fonts.xml. Cached for the
/// session; a failure degrades to the generic families, never to an error.
class SystemFonts {
  SystemFonts._();

  static const _channel = MethodChannel('app.synctogether/system_fonts');
  static Future<List<SystemFontFamily>>? _cache;

  static Future<List<SystemFontFamily>> list() => _cache ??= _load();

  static Future<SystemFontFamily?> find(String name) async {
    for (final f in await list()) {
      if (f.name == name) return f;
    }
    return null;
  }

  static Future<List<SystemFontFamily>> _load() async {
    try {
      final List<SystemFontFamily> families;
      if (Platform.isAndroid) {
        final xml = await File('/system/etc/fonts.xml').readAsString();
        families = parseAndroidFontsXml(xml, '/system/fonts');
      } else {
        final raw = await _channel.invokeListMethod<Map<Object?, Object?>>('list') ?? const [];
        families = [
          for (final f in raw)
            SystemFontFamily(f['family']! as String, [
              for (final face in (f['faces']! as List).cast<Map<Object?, Object?>>())
                SystemFontFace(
                  name: face['name']! as String,
                  style: face['style'] as String? ?? '',
                  weight: face['weight']! as int,
                  italic: face['italic']! as bool,
                ),
            ]),
        ];
      }
      // Hidden system families (".SF NS", "#GungSeo") are not for picking.
      final visible =
          families.where((f) => !f.name.startsWith('.') && !f.name.startsWith('#')).toList()
            ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      trace('system fonts listed', category: 'media', data: {'families': visible.length});
      if (visible.isNotEmpty) return visible;
    } catch (e) {
      trace('system font listing failed', category: 'media', data: {'error': '$e'});
    }
    _cache = null; // try again next time the picker opens
    return _generic;
  }

  static final _generic = [
    for (final name in ['sans-serif', 'serif', 'monospace']) SystemFontFamily(name, const []),
  ];
}
