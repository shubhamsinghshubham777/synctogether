/// Why this device could not open the room's film, in the three words the Room
/// check can say something useful about. Never a reason to touch the file: the
/// fix is always a different copy (see "Never touch the file").
enum OpenFailure {
  /// mpv does not recognise the container or cannot decode the video.
  format,

  /// The system refused read access (moved to a protected folder, an unplugged
  /// drive, a lapsed sandbox grant).
  unreadable,

  /// It never reported a length: a damaged or still-arriving file, a slow drive.
  stalled,
}

/// Classifies what mpv (or the open call) said. Pure, so the wording each kind
/// gets is tested without a player. Anything unrecognised is [OpenFailure.stalled].
OpenFailure classifyOpenFailure(String? error) {
  final text = (error ?? '').toLowerCase();
  if (text.contains('failed to recognize file format') ||
      text.contains('unsupported format') ||
      text.contains('failed to initialize a decoder')) {
    return .format;
  }
  if (text.contains('operation not permitted') ||
      text.contains('permission denied') ||
      text.contains('not permitted')) {
    return .unreadable;
  }
  return .stalled;
}
