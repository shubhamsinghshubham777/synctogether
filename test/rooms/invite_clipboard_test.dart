import 'package:flutter_test/flutter_test.dart';
import 'package:synctogether/rooms/invite_clipboard.dart';

void main() {
  test('reads the scheme link, the web link and a bare code', () {
    expect(inviteCodeFromClipboard('synctogether://join/X7K9P2'), 'X7K9P2');
    expect(inviteCodeFromClipboard('https://synctogether.app/join/x7k9p2'), 'X7K9P2');
    expect(inviteCodeFromClipboard('  x7k9p2 \n'), 'X7K9P2');
  });

  test('ignores everything else on the clipboard', () {
    expect(inviteCodeFromClipboard(null), isNull);
    expect(inviteCodeFromClipboard(''), isNull);
    expect(inviteCodeFromClipboard('hello world'), isNull);
    expect(inviteCodeFromClipboard('X7K9P0'), isNull); // 0 is not in the alphabet
    expect(inviteCodeFromClipboard('X7K9P'), isNull);
    expect(inviteCodeFromClipboard('https://evil.example/join/X7K9P2'), isNull);
    expect(inviteCodeFromClipboard('synctogether://auth-callback?code=X7K9P2'), isNull);
  });
}
