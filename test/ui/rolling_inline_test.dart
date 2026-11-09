import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:synctogether/ui/rolling_text.dart';

void main() {
  testWidgets('rolling digits sit inline in a sentence and survive a change', (tester) async {
    Widget sentence(int n) => Directionality(
      textDirection: TextDirection.ltr,
      child: Center(
        child: Text.rich(
          TextSpan(
            children: [
              const TextSpan(text: 'Resend code in '),
              WidgetSpan(
                alignment: PlaceholderAlignment.baseline,
                baseline: TextBaseline.alphabetic,
                child: PTRollingText('$n', style: const TextStyle(fontSize: 14), dir: -1),
              ),
              const TextSpan(text: 's'),
            ],
          ),
          style: const TextStyle(fontSize: 14),
        ),
      ),
    );
    await tester.pumpWidget(sentence(29));
    await tester.pumpWidget(sentence(28));
    await tester.pump(const Duration(milliseconds: 60));
    expect(tester.takeException(), isNull);
    await tester.pumpAndSettle();
    expect(find.byType(PTRollingText), findsOneWidget);
  });
}
