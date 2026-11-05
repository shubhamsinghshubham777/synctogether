import 'package:flutter_test/flutter_test.dart';
import 'package:synctogether/rooms/room_models.dart';
import 'package:synctogether/sync/sync_logic.dart';

final _epoch = DateTime.utc(2026, 7, 31, 12);

PresentMember _m(
  String file, {
  Duration? duration,
  String? confirmed,
  ReadyStatus ready = ReadyStatus.ready,
}) => PresentMember(
  userId: 'a',
  displayName: 'a',
  role: 'member',
  joinedAt: _epoch,
  readyStatus: ready,
  loadedFileName: file,
  loadedDuration: duration,
  confirmedMedia: confirmed,
);

RoomMedia _media(String name, {Duration? duration, DateTime? at}) =>
    RoomMedia(kind: RoomMediaKind.local, name: name, duration: duration, updatedAt: at);

const _film = Duration(hours: 2, minutes: 1, seconds: 10);

GateMatch? _match(String loaded, String room, {Duration? l, Duration? r}) =>
    gateMatchOf(_m(loaded, duration: l), _media(room, duration: r));

void main() {
  group('mediaStem', () {
    test('strips extension, case, separators, year and quality tags', () {
      expect(mediaStem('The.Movie.2005.1080p.BluRay.x264.mkv').title, 'the movie');
      expect(mediaStem('The Movie (2005) [720p] WEB-DL.mp4').title, 'the movie');
      expect(mediaStem('The_Movie-2005.AAC.5.1.avi').title, 'the movie');
    });
    test('re-download suffix is ignored', () {
      expect(mediaStem('Movie (1).mkv').title, 'movie');
    });
    test('a name that is only a year stays a title', () {
      expect(mediaStem('1917.mkv').title, '1917');
    });
    test('unknown extensions are not stripped', () {
      expect(mediaStem('Dr. Strange').title, 'dr strange');
    });
    test('episode markers are kept', () {
      expect(mediaStem('Show.S01E02.720p.mkv').markers, {'s01e02'});
    });
  });

  group('gateMatchOf', () {
    test('exact name', () {
      expect(_match('Movie.mkv', 'Movie.mkv'), GateMatch.exactName);
    });
    test('same movie, different container', () {
      expect(_match('Movie.mp4', 'Movie.mkv'), GateMatch.sameTitle);
    });
    test('case and release tags differ', () {
      expect(_match('movie.2005.720p.mp4', 'Movie (2005) 1080p.mkv'), GateMatch.sameTitle);
    });
    test('different years of the same title (a remake) do not match by name', () {
      expect(_match('Movie.2005.mkv', 'Movie.2019.mkv'), isNull);
    });
    test('a sequel is not the same title', () {
      expect(_match('Movie 2.mkv', 'Movie.mkv'), isNull);
    });
    test('renamed file matches by duration', () {
      expect(_match('IMG_4411.mp4', 'Movie.mkv', l: _film, r: _film), GateMatch.sameLength);
    });
    test('within +-1.5 s matches, beyond does not', () {
      const edge = Duration(milliseconds: 1500);
      expect(_match('x.mp4', 'Movie.mkv', l: _film + edge, r: _film), GateMatch.sameLength);
      expect(_match('x.mp4', 'Movie.mkv', l: _film - edge, r: _film), GateMatch.sameLength);
      expect(_match('x.mp4', 'Movie.mkv', l: _film + edge * 1.1, r: _film), isNull);
    });
    test('PAL speed-up (24 to 25 fps) does not match by length alone', () {
      final pal = Duration(milliseconds: (_film.inMilliseconds * 24 / 25).round());
      expect(_match('x.mp4', 'Movie.mkv', l: pal, r: _film), isNull);
    });
    test('PAL speed-up still matches when the name agrees', () {
      final pal = Duration(milliseconds: (_film.inMilliseconds * 24 / 25).round());
      expect(_match('Movie.avi', 'Movie.mkv', l: pal, r: _film), GateMatch.sameTitle);
    });
    test('different movie, different length: no match', () {
      expect(_match('Other.mkv', 'Movie.mkv', l: _film * 0.5, r: _film), isNull);
    });
    test('different movie of the same length matches by length (override-free path)', () {
      expect(_match('Other.mkv', 'Movie.mkv', l: _film, r: _film), GateMatch.sameLength);
    });
    test('two episodes of equal length do not match by length', () {
      const ep = Duration(minutes: 22);
      expect(_match('Show.S01E01.mkv', 'Show.S01E02.mkv', l: ep, r: ep), isNull);
    });
    test('a missing duration on either side is never evidence', () {
      expect(_match('x.mp4', 'Movie.mkv', l: null, r: _film), isNull);
      expect(_match('x.mp4', 'Movie.mkv', l: _film, r: null), isNull);
      expect(_match('x.mp4', 'Movie.mkv', l: Duration.zero, r: Duration.zero), isNull);
    });
    test('older client (name only) is judged on its name', () {
      expect(_match('Movie.mkv', 'Movie.mkv', r: _film), GateMatch.exactName);
      expect(_match('Movie.mp4', 'Movie.mkv', r: _film), GateMatch.sameTitle);
      expect(_match('weird.mp4', 'Movie.mkv', r: _film), isNull);
    });
    test('no loaded name never matches', () {
      expect(gateMatchOf(_m('x').withPrivacyMode(false), RoomMedia.none), isNull);
    });
  });

  group('confirmation override', () {
    final at = DateTime.utc(2026, 8, 1);
    test('honoured for the media it was given for', () {
      final media = _media('Movie.mkv', at: at);
      expect(
        gateMatchOf(_m('weird.mp4', confirmed: gateMediaKey(media)), media),
        GateMatch.confirmed,
      );
      expect(memberSatisfiesGate(_m('weird.mp4', confirmed: gateMediaKey(media)), media), isTrue);
    });
    test('void once the room picks something else', () {
      final old = _media('Movie.mkv', at: at);
      final next = _media('Movie.mkv', at: at.add(const Duration(seconds: 5)));
      final member = _m('weird.mp4', confirmed: gateMediaKey(old));
      expect(memberSatisfiesGate(member, next), isFalse);
      expect(memberSatisfiesGate(member, _media('Other.mkv', at: at)), isFalse);
    });
    test('does not make a member who is still loading ready', () {
      final media = _media('Movie.mkv', at: at);
      expect(
        memberSatisfiesGate(
          _m('weird.mp4', confirmed: gateMediaKey(media), ready: ReadyStatus.loading),
          media,
        ),
        isFalse,
      );
    });
  });

  group('presence wire format', () {
    test('mergePresence reads duration and confirmation, tolerating absence', () {
      final merged = mergePresence([
        {
          'user_id': 'new',
          'ready_status': 'ready',
          'loaded_file_name': 'a.mp4',
          'loaded_duration_ms': 7270000,
          'confirmed_media': '1:Movie.mkv',
        },
        {'user_id': 'old', 'ready_status': 'ready', 'loaded_file_name': 'b.mkv'},
        {'user_id': 'zero', 'loaded_duration_ms': 0},
      ]);
      final byId = {for (final m in merged) m.userId: m};
      expect(byId['new']!.loadedDuration, const Duration(milliseconds: 7270000));
      expect(byId['new']!.confirmedMedia, '1:Movie.mkv');
      expect(byId['old']!.loadedDuration, isNull);
      expect(byId['zero']!.loadedDuration, isNull);
    });
  });

  test('gateBlockersOf uses the match rule', () {
    final media = _media('Movie.mkv', duration: _film);
    final blockers = gateBlockersOf(media, [
      _m('Movie.mp4'),
      _m('IMG.mp4', duration: _film),
      _m('nope.mp4', duration: _film * 2),
    ]);
    expect(blockers.map((m) => m.loadedFileName), ['nope.mp4']);
  });
}
