import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/screen_matrix.dart';

/// The hinge assertions the matrix relies on must be able to fail: a screen
/// drawn straight across a hinge is caught, and one kept in a pane is not.
void main() {
  final book = kScreenMatrix.firstWhere((c) => c.name == 'iphone-duo-book');
  final tabletop = kScreenMatrix.firstWhere((c) => c.name == 'iphone-duo-tabletop');

  Widget acrossTheWindow() => Scaffold(
    body: Center(
      child: Column(
        mainAxisSize: .min,
        children: [
          const Text('Open a room'),
          TextButton(onPressed: () {}, child: const Text('Take your seat')),
        ],
      ),
    ),
  );

  for (final c in [book, tabletop]) {
    testWidgets('a screen centred across the ${c.name} fold is caught', (tester) async {
      await pumpAtSize(tester, acrossTheWindow(), c);
      expect(() => expectClearOfHinge(tester, c), throwsA(isA<TestFailure>()));
      debugDefaultTargetPlatformOverride = null;
    });

    testWidgets('the same screen in one pane is clear of the ${c.name} fold', (tester) async {
      await pumpAtSize(tester, acrossTheWindow(), c, singlePane: true);
      expectClearOfHinge(tester, c);
      debugDefaultTargetPlatformOverride = null;
    });
  }
}
