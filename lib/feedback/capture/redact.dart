/// Scrubbing for anything that leaves the device in a bug report. The trail
/// is built from `trace` calls that already avoid chat text and full paths, so
/// this is the second line of defence, not the first: it must hold even if a
/// future call site slips.
library;

final _email = RegExp(r'[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}');
final _jwt = RegExp(r'eyJ[A-Za-z0-9_\-]{8,}\.[A-Za-z0-9_\-]{8,}\.[A-Za-z0-9_\-]*');
final _bearer = RegExp(r'(Bearer|Basic)\s+[A-Za-z0-9._~+/\-]+=*', caseSensitive: false);
final _secretParam = RegExp(
  r'((?:token|access_token|refresh_token|apikey|api_key|key|secret|password|signature|sig|code)=)[^&\s"]+',
  caseSensitive: false,
);
final _longToken = RegExp(r'\b[A-Za-z0-9_\-]{40,}\b');
// Absolute paths: unix (/a/b), windows (C:\a\b), file:// URIs.
final _path = RegExp(r'(?:file:///?|[A-Za-z]:[\\/]|/)(?:[^\s/\\:"<>|]+[\\/])+([^\s/\\:"<>|]+)');

/// Keys whose values are user-written text and never travel.
const _droppedKeys = {'message', 'text', 'content', 'body', 'note', 'email', 'password', 'token'};

String redactText(String input) {
  var s = input;
  s = s.replaceAll(_jwt, '<token>');
  s = s.replaceAllMapped(_bearer, (m) => '${m[1]} <token>');
  s = s.replaceAllMapped(_secretParam, (m) => '${m[1]}<redacted>');
  s = s.replaceAll(_email, '<email>');
  s = s.replaceAllMapped(_path, (m) => m[1]!);
  s = s.replaceAll(_longToken, '<token>');
  return s;
}

/// Redacts a value tree (maps, lists, strings). Values under [_droppedKeys]
/// become `<omitted>`.
Object? redactValue(Object? v, {String? key}) {
  if (key != null && _droppedKeys.contains(key.toLowerCase())) return '<omitted>';
  return switch (v) {
    String s => redactText(s),
    Map m => {for (final e in m.entries) '${e.key}': redactValue(e.value, key: '${e.key}')},
    Iterable l => [for (final e in l) redactValue(e)],
    _ => v,
  };
}
