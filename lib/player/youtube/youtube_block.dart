/// Why the YouTube player refused a video, in the two kinds the Room check can
/// say something useful about. Both are about the video, never the connection.
enum YouTubeBlock {
  /// 101/150: the owner turned off playing outside YouTube.
  embeddingOff,

  /// 100: removed, or made private.
  unavailable,
}

/// Classifies an IFrame API error code. Null for codes that are not a verdict on
/// the video (bad parameters, HTML5 player trouble), which stay a snack and a report.
YouTubeBlock? classifyYouTubeBlock(int? code) => switch (code) {
  101 || 150 => .embeddingOff,
  100 => .unavailable,
  _ => null,
};
