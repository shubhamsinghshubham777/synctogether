import 'package:flutter_test/flutter_test.dart';
import 'package:synctogether/pairing/pair_pick.dart';

void main() {
  test('the hash is a fixed function, the same on every platform', () {
    // Pinned values: if these move, two phones on different platforms would
    // disagree about tonight's film.
    expect(stableHash(''), 0x811c9dc5);
    expect(stableHash('a'), 0xe40c292c);
    expect(stableHash('foobar'), 0xbf9cf968);
  });

  test('shared yeses are the intersection, sorted, without duplicates', () {
    expect(sharedYes(['c', 'a', 'b', 'a'], ['b', 'c', 'x']), ['b', 'c']);
    expect(sharedYes(['a'], ['b']), isEmpty);
    expect(sharedYes(const [], ['b']), isEmpty);
  });

  test('both phones pick the same film whoever computes it', () {
    final mine = ['f3', 'f1', 'f7', 'f9'];
    final theirs = ['f9', 'f7', 'f2'];
    expect(choosePick(mine, theirs), choosePick(theirs, mine));
    expect(['f7', 'f9'], contains(choosePick(mine, theirs)));
  });

  test('order of the answers does not change the pick', () {
    expect(
      choosePick(['a', 'b', 'c'], ['c', 'b', 'a']),
      choosePick(['c', 'a', 'b'], ['b', 'a', 'c']),
    );
  });

  test('no overlap means no match, and the fallback still chooses', () {
    expect(choosePick(['a'], ['b']), isNull);
    expect(choosePick(const [], const []), isNull);
    final either = choosePickFromEither(['a'], ['b']);
    expect(['a', 'b'], contains(either));
    expect(choosePickFromEither(['a'], ['b']), choosePickFromEither(['b'], ['a']));
    expect(choosePickFromEither(const [], const []), isNull);
  });

  test('a single shared yes is always the pick', () {
    expect(choosePick(['a', 'z'], ['z']), 'z');
  });

  test('picks go stale after half an hour', () {
    final t = DateTime.utc(2026, 11, 7, 20);
    expect(picksAreFresh(t, t.add(const Duration(minutes: 29))), isTrue);
    expect(picksAreFresh(t, t.add(const Duration(minutes: 31))), isFalse);
  });
}
