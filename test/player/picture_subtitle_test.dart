import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:synctogether/player/track_label.dart';

// The Casino Royale rip that prompted this: PGS first, SRT after.
final _tracks = [
  SubtitleTrack.no(),
  SubtitleTrack.auto(),
  const SubtitleTrack('1', 'Hindi BD-PGS', 'hin', codec: 'hdmv_pgs_subtitle'),
  const SubtitleTrack('2', null, 'eng', codec: 'hdmv_pgs_subtitle'),
  const SubtitleTrack('3', null, 'eng', codec: 'subrip'),
  const SubtitleTrack('4', null, 'spa', codec: 'dvd_subtitle'),
];

void main() {
  test('image formats are picture subtitles, text formats are not', () {
    expect(isBitmapSubtitle(_tracks[3]), isTrue);
    expect(isBitmapSubtitle(_tracks[5]), isTrue);
    expect(isBitmapSubtitle(_tracks[4]), isFalse);
    expect(isBitmapSubtitle(const SubtitleTrack('9', null, 'eng')), isFalse);
  });

  test('picture tracks say so in their label', () {
    expect(formatTrackLabel(_tracks[3]), 'English • Picture (Track 2)');
    expect(formatTrackLabel(_tracks[4]), 'English (Track 3)');
  });

  group('preferredTextSubtitle', () {
    test('swaps an auto-picked PGS track for text in the same language', () {
      expect(preferredTextSubtitle(_tracks, '2')?.id, '3');
    });

    test('leaves a text selection alone', () {
      expect(preferredTextSubtitle(_tracks, '3'), isNull);
    });

    test('never crosses languages', () {
      expect(preferredTextSubtitle(_tracks, '1'), isNull);
      expect(preferredTextSubtitle(_tracks, '4'), isNull);
    });

    test('off, auto and unknown ids are left alone', () {
      expect(preferredTextSubtitle(_tracks, 'no'), isNull);
      expect(preferredTextSubtitle(_tracks, null), isNull);
      expect(preferredTextSubtitle(_tracks, '42'), isNull);
    });

    test('a full text track beats a forced one', () {
      final tracks = [
        const SubtitleTrack('1', null, 'eng', codec: 'hdmv_pgs_subtitle'),
        const SubtitleTrack('2', 'English (Forced)', 'eng', codec: 'subrip'),
        const SubtitleTrack('3', 'English SDH', 'en', codec: 'ass'),
      ];
      expect(preferredTextSubtitle(tracks, '1')?.id, '3');
    });

    test('a forced track is still better than nothing restylable', () {
      final tracks = [
        const SubtitleTrack('1', null, 'eng', codec: 'hdmv_pgs_subtitle'),
        const SubtitleTrack('2', 'Forced', 'eng', codec: 'subrip'),
      ];
      expect(preferredTextSubtitle(tracks, '1')?.id, '2');
    });
  });
}
