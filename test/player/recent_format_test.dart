import 'package:flutter_test/flutter_test.dart';
import 'package:synctogether/player/recent_format.dart';

void main() {
  test('runtime reads like the board: 2h 49m, 12m, 0:42', () {
    expect(formatRuntime(const Duration(hours: 2, minutes: 49, seconds: 3)), '2h 49m');
    expect(formatRuntime(const Duration(hours: 3)), '3h');
    expect(formatRuntime(const Duration(minutes: 12, seconds: 8)), '12m');
    expect(formatRuntime(const Duration(seconds: 42)), '0:42');
  });

  test('the thumbnail badge is a timecode', () {
    expect(formatTimecode(const Duration(hours: 2, minutes: 49, seconds: 3)), '2:49:03');
    expect(formatTimecode(const Duration(minutes: 12, seconds: 8)), '12:08');
    expect(formatTimecode(const Duration(seconds: 42)), '0:42');
  });

  test('sizes are whole megabytes and one-decimal gigabytes', () {
    expect(formatSize(96 * 1024 * 1024), '96 MB');
    expect(formatSize(310 * 1024 * 1024), '310 MB');
    expect(formatSize((8.4 * 1024 * 1024 * 1024).round()), '8.4 GB');
    expect(formatSize(2048), '2 KB');
    expect(formatSize(12), '12 B');
  });

  test('opened-at wording steps from minutes to weeks', () {
    final now = DateTime(2026, 11, 6, 12);
    String at(Duration ago) => formatOpened(now.subtract(ago), now);
    expect(at(const Duration(seconds: 20)), 'just now');
    expect(at(const Duration(minutes: 5)), '5 minutes ago');
    expect(at(const Duration(hours: 1)), '1 hour ago');
    expect(at(const Duration(hours: 2)), '2 hours ago');
    expect(at(const Duration(days: 1)), 'yesterday');
    expect(at(const Duration(days: 3)), '3 days ago');
    expect(at(const Duration(days: 9)), 'last week');
    expect(at(const Duration(days: 21)), '3 weeks ago');
    expect(at(const Duration(days: 90)), 'a while ago');
  });

  test('the empty room kicker is short and upper case', () {
    final now = DateTime(2026, 11, 6, 12);
    expect(formatAgoShort(now.subtract(const Duration(hours: 2)), now), '2H AGO');
    expect(formatAgoShort(now.subtract(const Duration(days: 3)), now), '3D AGO');
    expect(formatAgoShort(now.subtract(const Duration(minutes: 7)), now), '7M AGO');
    expect(formatAgoShort(now.subtract(const Duration(seconds: 3)), now), 'JUST NOW');
  });
}
