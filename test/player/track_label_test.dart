import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:synctogether/player/track_label.dart';
import 'package:synctogether/player/youtube/pt_youtube_controller.dart';

void main() {
  group('formatTrackLabel - SubtitleTrack', () {
    test('formats special synthetic tracks', () {
      expect(formatTrackLabel(SubtitleTrack.no()), 'Off');
      expect(formatTrackLabel(SubtitleTrack.auto()), 'Auto');
    });

    test('formats tracks with watermark title and language', () {
      final t1 = SubtitleTrack('1', '~Anup', 'hin');
      final t2 = SubtitleTrack('2', '~Anup', 'hin');
      final t4 = SubtitleTrack('4', '~Anup', 'eng');

      expect(formatTrackLabel(t1), 'Hindi • ~Anup (Track 1)');
      expect(formatTrackLabel(t2), 'Hindi • ~Anup (Track 2)');
      expect(formatTrackLabel(t4), 'English • ~Anup (Track 4)');
    });

    test('dedupes title when it matches language name', () {
      final t = SubtitleTrack('1', 'English', 'eng');
      expect(formatTrackLabel(t), 'English (Track 1)');

      final tCase = SubtitleTrack('2', 'english', 'en');
      expect(formatTrackLabel(tCase), 'English (Track 2)');
    });

    test('retains descriptive title alongside language', () {
      final t = SubtitleTrack('1', 'Director Commentary', 'eng');
      expect(formatTrackLabel(t), 'English • Director Commentary (Track 1)');
    });

    test('formats track when language is missing but title exists', () {
      final t = SubtitleTrack('3', 'SubRip Full', null);
      expect(formatTrackLabel(t), 'SubRip Full (Track 3)');
    });

    test('formats track when both language and title are missing', () {
      final t = SubtitleTrack('5', null, null);
      expect(formatTrackLabel(t), 'Track 5');
    });

    test('formats external or non-numeric tracks without Track prefix', () {
      final t = SubtitleTrack.uri('file:///path/to/sub.srt', title: 'Custom SRT', language: 'spa');
      expect(formatTrackLabel(t), 'Spanish • Custom SRT');
    });
  });

  group('formatTrackLabel - AudioTrack', () {
    test('formats special synthetic tracks', () {
      expect(formatTrackLabel(AudioTrack.no()), 'Off');
      expect(formatTrackLabel(AudioTrack.auto()), 'Auto');
    });

    test('formats audio track with channels', () {
      final t = AudioTrack('1', '~Anup', 'hin', channels: '5.1');
      expect(formatTrackLabel(t), 'Hindi • ~Anup • 5.1 (Track 1)');

      final tStereo = AudioTrack('2', 'Original', 'eng', channels: 'stereo');
      expect(formatTrackLabel(tStereo), 'English • Original • Stereo (Track 2)');
    });
  });

  group('resolveLanguageName', () {
    test('resolves standard 2-letter and 3-letter ISO codes', () {
      expect(resolveLanguageName('eng'), 'English');
      expect(resolveLanguageName('en'), 'English');
      expect(resolveLanguageName('hin'), 'Hindi');
      expect(resolveLanguageName('hi'), 'Hindi');
      expect(resolveLanguageName('spa'), 'Spanish');
      expect(resolveLanguageName('es'), 'Spanish');
      expect(resolveLanguageName('jpn'), 'Japanese');
      expect(resolveLanguageName('ja'), 'Japanese');
      expect(resolveLanguageName('tam'), 'Tamil');
      expect(resolveLanguageName('tel'), 'Telugu');
    });

    test('returns null for null or empty input', () {
      expect(resolveLanguageName(null), isNull);
      expect(resolveLanguageName(''), isNull);
      expect(resolveLanguageName('   '), isNull);
    });

    test('capitalizes unknown languages cleanly', () {
      expect(resolveLanguageName('xyz'), 'XYZ');
      expect(resolveLanguageName('klingon'), 'Klingon');
    });
  });

  group('isTrackSelected', () {
    test('matches synthetic and regular tracks by id', () {
      expect(isTrackSelected(SubtitleTrack.auto(), SubtitleTrack.auto()), isTrue);
      expect(isTrackSelected(SubtitleTrack.no(), SubtitleTrack.no()), isTrue);
      expect(isTrackSelected(SubtitleTrack.auto(), SubtitleTrack.no()), isFalse);

      final t1 = SubtitleTrack('1', 'T1', 'eng');
      final t1Clone = SubtitleTrack('1', 'Different Title', 'eng');
      final t2 = SubtitleTrack('2', 'T2', 'eng');

      expect(isTrackSelected(t1, t1Clone), isTrue);
      expect(isTrackSelected(t1, t2), isFalse);
      expect(isTrackSelected(t1, null), isFalse);
    });

    test('matches YouTube caption tracks', () {
      final off1 = PTYouTubeCaptionTrack.off();
      final off2 = PTYouTubeCaptionTrack.off();
      expect(isTrackSelected(off1, off2), isTrue);

      const en = PTYouTubeCaptionTrack(id: 'en-std', displayName: 'English', languageCode: 'en');
      const enClone = PTYouTubeCaptionTrack(
        id: 'en-std',
        displayName: 'English (auto)',
        languageCode: 'en',
      );
      const hi = PTYouTubeCaptionTrack(id: 'hi-std', displayName: 'Hindi', languageCode: 'hi');

      expect(isTrackSelected(en, enClone), isTrue);
      expect(isTrackSelected(en, hi), isFalse);
      expect(isTrackSelected(en, off1), isFalse);
    });
  });

  group('formatTrackLabel - PTYouTubeCaptionTrack', () {
    test('formats Off track', () {
      expect(formatTrackLabel(PTYouTubeCaptionTrack.off()), 'Off');
    });

    test('formats language name and display name', () {
      const t1 = PTYouTubeCaptionTrack(
        id: 'en-asr',
        displayName: 'English (auto-generated)',
        languageCode: 'en',
      );
      expect(formatTrackLabel(t1), 'English (auto-generated)');

      const t2 = PTYouTubeCaptionTrack(id: 'hi-std', displayName: 'Hindi', languageCode: 'hi');
      expect(formatTrackLabel(t2), 'Hindi');

      const t3 = PTYouTubeCaptionTrack(
        id: 'es-cc',
        displayName: 'Spanish [CC]',
        languageCode: 'es',
      );
      expect(formatTrackLabel(t3), 'Spanish [CC]');
    });
  });
}
