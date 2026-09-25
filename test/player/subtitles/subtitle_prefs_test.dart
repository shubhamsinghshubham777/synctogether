import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:synctogether/player/subtitles/subtitle_prefs.dart';
import 'package:synctogether/player/subtitles/subtitle_style.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('a saved style survives into a fresh instance', () async {
    final a = SubtitlePrefs();
    await a.load();
    a.update(SubtitleStyle.defaults().copyWith(scale: 1.6, fontFamily: () => 'Georgia'));
    await Future<void>.delayed(Duration.zero);

    final b = SubtitlePrefs();
    await b.load();
    expect(b.style.scale, 1.6);
    expect(b.style.fontFamily, 'Georgia');
  });

  test('a mid-drag update applies but does not persist', () async {
    final a = SubtitlePrefs();
    await a.load();
    a.update(SubtitleStyle.defaults().copyWith(scale: 2), persist: false);
    expect(a.style.scale, 2);
    await Future<void>.delayed(Duration.zero);

    final b = SubtitlePrefs();
    await b.load();
    expect(b.style, SubtitleStyle.defaults());
  });

  test('clear forgets the style, on disk and in memory', () async {
    final a = SubtitlePrefs();
    await a.load();
    a.update(SubtitleStyle.defaults().copyWith(blur: 5));
    await Future<void>.delayed(Duration.zero);
    await a.clear();
    expect(a.style, SubtitleStyle.defaults());

    final b = SubtitlePrefs();
    await b.load();
    expect(b.style, SubtitleStyle.defaults());
  });

  test('unreadable stored JSON falls back to the defaults', () async {
    SharedPreferences.setMockInitialValues({'pt.subtitles.style': '{not json'});
    final a = SubtitlePrefs();
    await a.load();
    expect(a.style, SubtitleStyle.defaults());
  });
}
