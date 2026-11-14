import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:synctogether/ui/inputs.dart';

Widget _app(String? error) => MaterialApp(
  home: Scaffold(
    body: Column(
      children: [
        PTTextField(hint: 'Hint', errorText: error),
        const SizedBox(key: Key('below'), height: 10),
      ],
    ),
  ),
);

void main() {
  testWidgets('a validation message folds in and out and pushes what is below it gradually', (
    tester,
  ) async {
    double below() => tester.getTopLeft(find.byKey(const Key('below'))).dy;

    await tester.pumpWidget(_app(null));
    final rest = below();
    await tester.pumpWidget(_app('Hmm, that is not right.'));
    final tops = <double>[];
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 40));
      tops.add(below());
    }
    expect(tops.first, greaterThan(rest));
    expect(tops.toSet().length, greaterThan(2), reason: 'eases over frames: $tops');
    await tester.pumpAndSettle();
    final shown = below();
    expect(shown, greaterThan(tops.first));
    expect(find.text('Hmm, that is not right.'), findsOneWidget);

    await tester.pumpWidget(_app(null));
    await tester.pump(const Duration(milliseconds: 40));
    // Still folding, words intact, not popped.
    expect(find.text('Hmm, that is not right.'), findsOneWidget);
    expect(below(), lessThan(shown));
    expect(below(), greaterThan(rest));
    await tester.pumpAndSettle();
    expect(below(), closeTo(rest, 0.01));
    expect(find.text('Hmm, that is not right.'), findsNothing);
  });
}
