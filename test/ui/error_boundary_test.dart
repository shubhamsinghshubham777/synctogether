import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:synctogether/ui/error_boundary.dart';

class _Bomb extends StatelessWidget {
  const _Bomb({required this.armed});
  final bool Function() armed;

  @override
  Widget build(BuildContext context) {
    if (armed()) throw StateError('boom');
    return const Text('healthy');
  }
}

void main() {
  late ErrorWidgetBuilder original;
  setUp(() {
    original = ErrorWidget.builder;
    ErrorWidget.builder = (d) => PTErrorFallback(details: d);
  });
  tearDown(() => ErrorWidget.builder = original);

  testWidgets('a build failure swaps in the recovery view; retry re-mounts the child', (
    tester,
  ) async {
    var armed = true;
    var exited = false;
    await tester.pumpWidget(
      MaterialApp(
        home: PTErrorBoundary(
          where: 'test',
          onExit: () => exited = true,
          exitLabel: 'Leave room',
          child: _Bomb(armed: () => armed),
        ),
      ),
    );
    expect(tester.takeException(), isA<StateError>());
    await tester.pump();

    expect(find.text('Something hit a snag.'), findsOneWidget);
    expect(find.text('Leave room'), findsOneWidget);

    armed = false;
    await tester.tap(find.text('Try again'));
    await tester.pump();
    expect(find.text('healthy'), findsOneWidget);
    expect(find.text('Something hit a snag.'), findsNothing);

    armed = true;
    await tester.tap(find.byType(Text).first); // no-op: child is a Text
    expect(exited, isFalse);
  });

  testWidgets('compact boundary leaves siblings alone', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Column(
          children: [
            const Text('sibling'),
            Expanded(
              child: PTErrorBoundary(
                where: 'chat',
                compact: true,
                child: _Bomb(armed: () => true),
              ),
            ),
          ],
        ),
      ),
    );
    tester.takeException();
    await tester.pump();
    expect(find.text('sibling'), findsOneWidget);
    expect(find.text('This part hit a snag.'), findsOneWidget);
  });
}
