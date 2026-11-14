import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:synctogether/ui/adaptive_action_bar.dart';
import 'package:synctogether/ui/booth_icons.g.dart';
import 'package:synctogether/ui/buttons.dart';

/// A tappable box: hit-testable only while the bar actually shows it.
Widget _box(Key key, {double width = 40, double height = 30, VoidCallback? onTap}) =>
    GestureDetector(
      key: key,
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: SizedBox(width: width, height: height),
    );

Finder _shown(String key) => find.byKey(ValueKey(key)).hitTestable();

AdaptiveActionBar _bar({
  int items = 4,
  double itemWidth = 40,
  List<int>? priorities,
  List<VoidCallback?>? taps,
  double minName = 80,
  double pinnedHeight = 30,
}) {
  return AdaptiveActionBar(
    pinned: [
      _box(const ValueKey('avatar'), width: 30, height: pinnedHeight),
      AdaptiveFlex(minWidth: minName, child: _box(const ValueKey('name'), width: 200)),
    ],
    foldable: [
      for (var i = 0; i < items; i++)
        AdaptiveAction(
          label: 'Item $i',
          icon: BoothIcons.star,
          priority: priorities?[i] ?? 0,
          onTap: taps?[i],
          inline: _box(ValueKey('item$i'), width: itemWidth),
        ),
    ],
  );
}

Future<void> _pump(
  WidgetTester tester,
  Widget bar, {
  required double width,
  double textScale = 1,
  bool intrinsic = false,
  TargetPlatform platform = TargetPlatform.macOS,
}) async {
  // `flutter test` defaults to Android, i.e. touch; the sizes below are pointer's.
  debugDefaultTargetPlatformOverride = platform;
  tester.view
    ..physicalSize = const Size(800, 600)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: width,
            child: intrinsic ? IntrinsicHeight(child: bar) : bar,
          ),
        ),
      ),
    ),
  );
}

Finder get _more => find.byIcon(BoothIcons.moreHoriz).hitTestable();

/// `testWidgets` that clears the platform override before the framework's
/// invariant check, which runs ahead of `addTearDown`.
void _t(String name, Future<void> Function(WidgetTester tester) body) {
  testWidgets(name, (tester) async {
    try {
      await body(tester);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
}

void main() {
  group('planFolds', () {
    test('folds lowest priority first and stops as soon as the rest fit', () {
      final folded = planFolds(
        available: 200,
        fixed: 100,
        fixedCount: 2,
        foldWidths: [40, 40, 40],
        order: [2, 1, 0],
        moreWidth: 30,
        spacing: 10,
      );
      // 100 + 120 + 5 gaps*10 = 270 > 200. Fold 2: 100+80+30+40 = 250. Fold 1:
      // 100+40+30+30 = 200 fits.
      expect(folded, {2, 1});
    });

    test('nothing folds when it all fits, and nothing folds on an unbounded width', () {
      expect(
        planFolds(
          available: 1000,
          fixed: 100,
          fixedCount: 2,
          foldWidths: [40],
          order: [0],
          moreWidth: 30,
          spacing: 8,
        ),
        isEmpty,
      );
      expect(
        planFolds(
          available: double.infinity,
          fixed: 100,
          fixedCount: 2,
          foldWidths: [40],
          order: [0],
          moreWidth: 30,
          spacing: 8,
        ),
        isEmpty,
      );
    });
  });

  _t('everything fits: every item inline and no More button', (tester) async {
    await _pump(tester, _bar(), width: 500);
    for (final k in ['avatar', 'name', 'item0', 'item1', 'item2', 'item3']) {
      expect(_shown(k), findsOneWidget, reason: k);
    }
    expect(find.byIcon(BoothIcons.moreHoriz), findsOneWidget); // built, not shown
    expect(_more, findsNothing);
  });

  _t('folds progressively, last in the list first, as the width shrinks', (tester) async {
    // avatar 30 + name 80 (min) + 4 x 40 + 5 gaps x 8 = 310 with all inline.
    // Each fold frees 48; More costs 38. 252 = 2 pinned + 2 inline + More.
    final expected = {
      310.0: [true, true, true, true, false],
      300.0: [true, true, true, false, true],
      260.0: [true, true, false, false, true],
      210.0: [true, false, false, false, true],
      200.0: [false, false, false, false, true],
    };
    for (final MapEntry(key: width, value: visible) in expected.entries) {
      await _pump(tester, _bar(), width: width);
      final shown = [
        for (var i = 0; i < 4; i++) _shown('item$i').evaluate().isNotEmpty,
        _more.evaluate().isNotEmpty,
      ];
      expect(shown, visible, reason: 'width $width');
      expect(tester.takeException(), isNull);
    }
  });

  _t('priority overrides list order: a tag listed first folds first', (tester) async {
    await _pump(tester, _bar(priorities: [-1, 0, 0, 0]), width: 300);
    expect(_shown('item0'), findsNothing);
    for (final k in ['item1', 'item2', 'item3']) {
      expect(_shown(k), findsOneWidget, reason: k);
    }
    expect(_more, findsOneWidget);
  });

  _t('pinned never folds, and the flexible name keeps its minimum width', (tester) async {
    for (final width in [300.0, 160.0]) {
      await _pump(tester, _bar(), width: width);
      expect(_shown('avatar'), findsOneWidget, reason: '$width');
      expect(_shown('name'), findsOneWidget, reason: '$width');
      expect(tester.getSize(find.byKey(const ValueKey('name'))).width, greaterThanOrEqualTo(80));
    }
  });

  _t('tiny width: only pinned plus More remain', (tester) async {
    await _pump(tester, _bar(), width: 130);
    expect(_shown('avatar'), findsOneWidget);
    expect(_shown('name'), findsOneWidget);
    for (var i = 0; i < 4; i++) {
      expect(_shown('item$i'), findsNothing);
    }
    expect(_more, findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  _t('text scale 2.0 folds sooner and never overflows', (tester) async {
    Widget textBar() => AdaptiveActionBar(
      pinned: [
        AdaptiveFlex(
          minWidth: 60,
          child: Text('Watcher', key: const ValueKey('name'), overflow: TextOverflow.ellipsis),
        ),
      ],
      foldable: [
        for (var i = 0; i < 3; i++)
          AdaptiveAction(
            label: 'Tag $i',
            icon: BoothIcons.star,
            inline: Padding(
              key: ValueKey('item$i'),
              padding: const EdgeInsets.all(4),
              child: Text('TAG$i'),
            ),
          ),
      ],
    );
    await _pump(tester, textBar(), width: 300);
    expect(_more, findsNothing);
    await _pump(tester, textBar(), width: 300, textScale: 2);
    expect(_more, findsOneWidget);
    expect(_shown('name'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  _t('works under IntrinsicHeight, and a folded tall item does not set the height', (tester) async {
    final bar = AdaptiveActionBar(
      pinned: [
        _box(const ValueKey('avatar'), width: 30, height: 44),
        AdaptiveFlex(minWidth: 60, child: _box(const ValueKey('name'), width: 200)),
      ],
      foldable: [
        AdaptiveAction(
          label: 'Tall',
          icon: BoothIcons.star,
          inline: _box(const ValueKey('tall'), width: 100, height: 90),
        ),
      ],
    );
    await _pump(tester, bar, width: 400, intrinsic: true);
    expect(tester.takeException(), isNull);
    expect(tester.getSize(find.byType(AdaptiveActionBar)).height, 90);

    await _pump(tester, bar, width: 150, intrinsic: true);
    expect(tester.takeException(), isNull);
    expect(_shown('tall'), findsNothing);
    // The More button (30, or 44 on touch) and the 44 avatar decide it.
    expect(tester.getSize(find.byType(AdaptiveActionBar)).height, 44);
  });

  _t('overflow popover lists folded items and their callbacks fire', (tester) async {
    final fired = <int>[];
    await _pump(
      tester,
      _bar(taps: [() => fired.add(0), () => fired.add(1), () => fired.add(2), () => fired.add(3)]),
      width: 130,
    );
    await tester.tap(_more);
    await tester.pumpAndSettle();
    for (var i = 0; i < 4; i++) {
      expect(find.text('Item $i'), findsOneWidget);
    }
    await tester.tap(find.text('Item 2'));
    await tester.pumpAndSettle();
    expect(fired, [2]);
    expect(find.text('Item 2'), findsNothing, reason: 'the list closes after a pick');
  });

  _t('informational rows show their value and are not tappable', (tester) async {
    final bar = AdaptiveActionBar(
      pinned: [AdaptiveFlex(minWidth: 60, child: _box(const ValueKey('name'), width: 200))],
      foldable: [
        AdaptiveAction(
          label: 'Status',
          value: 'Ready',
          icon: BoothIcons.check,
          inline: _box(const ValueKey('chip'), width: 200),
        ),
      ],
    );
    await _pump(tester, bar, width: 150);
    await tester.tap(_more);
    await tester.pumpAndSettle();
    expect(find.text('Ready'), findsOneWidget);
    await tester.tap(find.text('Status'));
    await tester.pumpAndSettle();
    expect(find.text('Status'), findsOneWidget, reason: 'still open: nothing was chosen');
  });

  _t('touch: More keeps a 44 px target and has no tooltip; pointer is the reverse', (tester) async {
    await _pump(tester, _bar(), width: 130, platform: TargetPlatform.iOS);
    final label = find.byWidgetPredicate((w) => w is Semantics && w.properties.label == 'More');
    expect(label, findsOneWidget);
    final size = tester.getSize(label);
    expect(size.width, greaterThanOrEqualTo(kMinTouchTarget));
    expect(size.height, greaterThanOrEqualTo(kMinTouchTarget));
    expect(find.byType(Tooltip), findsNothing);

    await _pump(tester, _bar(), width: 130);
    expect(find.byType(Tooltip), findsOneWidget);
  });

  _t('semantics: inline items carry their label, folded ones are not exposed', (tester) async {
    final handle = tester.ensureSemantics();
    await _pump(tester, _bar(taps: [() {}, () {}, () {}, () {}]), width: 250);
    expect(find.bySemanticsLabel('Item 0'), findsOneWidget);
    expect(find.bySemanticsLabel('Item 3'), findsNothing);
    expect(find.bySemanticsLabel('More'), findsOneWidget);
    handle.dispose();
  });
}
