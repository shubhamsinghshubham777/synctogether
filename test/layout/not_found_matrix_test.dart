import 'package:flutter_test/flutter_test.dart';
import 'package:synctogether/ui/not_found_screen.dart';

import '../support/screen_matrix.dart';
import 'layout_support.dart';

void main() {
  screenMatrix('not-found', (tester, c, s) async {
    await pumpAtSize(
      tester,
      NotFoundScreen(location: '/nope', onHome: () {}),
      c,
      textScale: s,
    );
    await tester.pump(const Duration(milliseconds: 500)); // entrance
    expect(find.text('Back to lobby'), findsOneWidget);
    // At 2.0x on a small screen the button may sit below the fold; it must be
    // reachable, not clipped away.
    await tester.ensureVisible(find.text('Back to lobby'));
    await tester.pump();
    await finishCase(tester);
  });
}
