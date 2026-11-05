// Copy for the Recent shelf (board 47): "2h 49m · 8.4 GB · Opened 2 hours ago".
// Pure functions of plain values so the wording is pinned by a test, not by eye.

/// "2h 49m", "12m", "0:42" - how long a video runs, in the row's metadata.
String formatRuntime(Duration d) {
  final total = d.inSeconds;
  if (total >= 3600) {
    final h = total ~/ 3600;
    final m = (total % 3600) ~/ 60;
    return m == 0 ? '${h}h' : '${h}h ${m}m';
  }
  if (total >= 60) return '${total ~/ 60}m';
  return '0:${total.toString().padLeft(2, '0')}';
}

/// "2:49:03", "12:08", "0:42" - the timecode badge on a thumbnail.
String formatTimecode(Duration d) {
  final total = d.inSeconds;
  final h = total ~/ 3600;
  final m = (total % 3600) ~/ 60;
  final s = total % 60;
  final ss = s.toString().padLeft(2, '0');
  return h > 0 ? '$h:${m.toString().padLeft(2, '0')}:$ss' : '$m:$ss';
}

/// "8.4 GB", "310 MB", "96 MB" - whole megabytes, one decimal from a gigabyte.
String formatSize(int bytes) {
  const kb = 1024, mb = kb * 1024, gb = mb * 1024;
  if (bytes >= gb) return '${(bytes / gb).toStringAsFixed(1)} GB';
  if (bytes >= mb) return '${(bytes / mb).round()} MB';
  if (bytes >= kb) return '${(bytes / kb).round()} KB';
  return '$bytes B';
}

/// "just now", "5 minutes ago", "2 hours ago", "yesterday", "3 days ago",
/// "last week", "3 weeks ago", "a while ago".
String formatOpened(DateTime when, DateTime now) {
  final d = now.difference(when);
  if (d.inMinutes < 1) return 'just now';
  if (d.inMinutes < 60) return d.inMinutes == 1 ? '1 minute ago' : '${d.inMinutes} minutes ago';
  if (d.inHours < 24) return d.inHours == 1 ? '1 hour ago' : '${d.inHours} hours ago';
  if (d.inDays == 1) return 'yesterday';
  if (d.inDays < 7) return '${d.inDays} days ago';
  if (d.inDays < 14) return 'last week';
  if (d.inDays < 60) return '${d.inDays ~/ 7} weeks ago';
  return 'a while ago';
}

/// The mono kicker on the empty room's "Reopen" line: "2H AGO", "3D AGO".
String formatAgoShort(DateTime when, DateTime now) {
  final d = now.difference(when);
  if (d.inMinutes < 1) return 'JUST NOW';
  if (d.inMinutes < 60) return '${d.inMinutes}M AGO';
  if (d.inHours < 24) return '${d.inHours}H AGO';
  if (d.inDays < 14) return '${d.inDays}D AGO';
  return '${d.inDays ~/ 7}W AGO';
}
