import 'package:flutter_test/flutter_test.dart';
import 'package:synctogether/auth/login_screen.dart';
import 'package:synctogether/ui/booth_icons.g.dart';
import 'package:synctogether/ui/buttons.dart';

import '../support/screen_matrix.dart';
import 'layout_support.dart';

void main() {
  screenMatrix('login/providers', (tester, c, s) async {
    await pumpAtSize(tester, const LoginScreen(), c, textScale: s);
    await tester.pump(const Duration(milliseconds: 1500)); // entrance choreography
    await finishCase(tester);
  });

  screenMatrix('login/email', (tester, c, s) async {
    await pumpAtSize(tester, const LoginScreen(), c, textScale: s);
    // Reaching the email view is not under test; its layout is.
    tester.takeException();
    // The label steps down to "Email" when the full one will not fit.
    final email = find.byWidgetPredicate((w) => w is PTButton && w.icon == BoothIcons.mail);
    // If this cannot be scrolled into view, the screen is clipping its own
    // primary actions - a real failure.
    await tester.ensureVisible(email);
    await tester.pump();
    await tester.tap(email);
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Sign in with email'), findsOneWidget);
    await finishCase(tester);
  });
}
