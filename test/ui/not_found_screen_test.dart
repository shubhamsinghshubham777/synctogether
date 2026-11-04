import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:synctogether/ui/not_found_screen.dart';
import 'package:synctogether/ui/pt_theme.dart';

void main() {
  Widget host(Widget child) => MaterialApp(theme: buildPTTheme(), home: child);

  testWidgets('shows the website 404 copy and sends the user home', (tester) async {
    var home = 0;
    await tester.pumpWidget(host(NotFoundScreen(location: '/nope', onHome: () => home++)));
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('ERROR 404'), findsOneWidget);
    expect(find.text('Lost in sync'), findsOneWidget);
    expect(find.textContaining("doesn't exist"), findsOneWidget);
    // Friendly copy only: never go_router's raw exception text.
    expect(find.textContaining('GoException'), findsNothing);

    await tester.tap(find.text('Back to lobby'));
    expect(home, 1);
  });
}
