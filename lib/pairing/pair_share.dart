import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../diagnostics.dart';

/// The native share sheet, with the one detail every caller forgets: iPad and
/// macOS anchor the sheet to a rectangle, and without one it throws or lands in
/// a corner. The rectangle is the widget that was tapped.
Rect? _originOf(BuildContext context) {
  final box = context.findRenderObject();
  if (box is! RenderBox || !box.hasSize) return null;
  return box.localToGlobal(Offset.zero) & box.size;
}

/// Shares [text] through the platform's share sheet. False when the sheet could
/// not be shown - the caller then falls back to copying - and never throws:
/// sharing is a convenience, not something to crash a screen over.
Future<bool> shareText(BuildContext context, String text, {String? subject}) async {
  try {
    final result = await SharePlus.instance.share(
      ShareParams(text: text, subject: subject, sharePositionOrigin: _originOf(context)),
    );
    return result.status != ShareResultStatus.unavailable;
  } catch (e, s) {
    reportNonFatal(e, s, during: 'opening the share sheet');
    return false;
  }
}

/// Writes [bytes] to a temp file named [name] and shares it. Used for the
/// calendar file and the year card.
Future<bool> shareBytes(
  BuildContext context, {
  required List<int> bytes,
  required String name,
  required String mimeType,
  String? text,
}) async {
  try {
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/$name');
    await file.writeAsBytes(bytes, flush: true);
    if (!context.mounted) return false;
    final result = await SharePlus.instance.share(
      ShareParams(
        text: text,
        files: [XFile(file.path, mimeType: mimeType, name: name)],
        sharePositionOrigin: _originOf(context),
      ),
    );
    return result.status != ShareResultStatus.unavailable;
  } catch (e, s) {
    reportNonFatal(e, s, during: 'sharing a file');
    return false;
  }
}
