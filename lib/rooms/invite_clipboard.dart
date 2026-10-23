import '../ui/inputs.dart';

/// The room code in whatever an invite looks like once it has been copied: the
/// scheme link the join page puts on the clipboard, the shareable https link,
/// or the bare code the download page's "Copy code" button copies.
///
/// Anything else is null - the clipboard is the user's, and most of the time it
/// holds something unrelated. Pure, so the paste button's decision is testable
/// without a clipboard.
String? inviteCodeFromClipboard(String? text) {
  final raw = text?.trim();
  if (raw == null || raw.isEmpty || raw.length > 200) return null;

  String? candidate;
  final uri = Uri.tryParse(raw);
  if (uri != null && uri.hasScheme) {
    final isScheme = uri.scheme == 'synctogether' && uri.host == 'join';
    final isWeb =
        (uri.scheme == 'https' || uri.scheme == 'http') &&
        (uri.host == 'synctogether.app' || uri.host == 'localhost') &&
        uri.pathSegments.length >= 2 &&
        uri.pathSegments.first == 'join';
    if (!isScheme && !isWeb) return null;
    final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
    candidate = isScheme ? segments.firstOrNull : segments[1];
  } else {
    candidate = raw;
  }

  final code = candidate?.toUpperCase();
  if (code == null || code.length != PTCodeInput.length) return null;
  for (final rune in code.runes) {
    if (!PTCodeInput.alphabet.contains(String.fromCharCode(rune))) return null;
  }
  return code;
}
