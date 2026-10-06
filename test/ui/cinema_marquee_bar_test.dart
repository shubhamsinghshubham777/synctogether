import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:synctogether/ui/cinema_marquee_bar.dart';
import 'package:window_manager/window_manager.dart';

void main() {
  group('CinemaMarqueeBar', () {
    testWidgets('renders on macOS with traffic light inset and drag area', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      try {
        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(
              body: CinemaMarqueeBar(
                leading: Text('Leading'),
                center: Text('Center Marquee'),
                trailing: Text('Trailing'),
              ),
            ),
          ),
        );

        expect(find.text('Leading'), findsOneWidget);
        expect(find.text('Center Marquee'), findsOneWidget);
        expect(find.text('Trailing'), findsOneWidget);
        expect(find.byType(DragToMoveArea), findsOneWidget);

        // Verify traffic light inset exists on macOS
        final inset = find.byWidgetPredicate(
          (w) => w is SizedBox && w.width == CinemaMarqueeBar.macOsTrafficLightInset,
        );
        expect(inset, findsOneWidget);

        // Verify Windows caption buttons are NOT present on macOS
        expect(find.byTooltip('Close'), findsNothing);
        expect(find.byTooltip('Minimize'), findsNothing);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('renders on Windows with caption buttons and no traffic light inset', (
      tester,
    ) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      try {
        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(
              body: CinemaMarqueeBar(leading: Text('Win Leading'), trailing: Text('Win Trailing')),
            ),
          ),
        );

        expect(find.text('Win Leading'), findsOneWidget);
        expect(find.text('Win Trailing'), findsOneWidget);
        expect(find.byType(DragToMoveArea), findsOneWidget);

        // No traffic light inset on Windows
        final inset = find.byWidgetPredicate(
          (w) => w is SizedBox && w.width == CinemaMarqueeBar.macOsTrafficLightInset,
        );
        expect(inset, findsNothing);

        // Windows caption buttons are present
        expect(find.byTooltip('Minimize'), findsOneWidget);
        expect(find.byTooltip('Maximize'), findsOneWidget);
        expect(find.byTooltip('Close'), findsOneWidget);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('renders SizedBox.shrink on mobile platform', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      try {
        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(body: CinemaMarqueeBar(leading: Text('Android Leading'))),
          ),
        );

        expect(find.text('Android Leading'), findsNothing);
        expect(find.byType(DragToMoveArea), findsNothing);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('renders custom child on desktop', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      try {
        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(body: CinemaMarqueeBar(child: Text('Custom Full Bar Child'))),
          ),
        );

        expect(find.text('Custom Full Bar Child'), findsOneWidget);
        expect(find.byType(DragToMoveArea), findsOneWidget);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('defaults to 52px height matching macOS unified title bar', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      try {
        await tester.pumpWidget(const MaterialApp(home: Scaffold(body: CinemaMarqueeBar())));

        expect(tester.getSize(find.byType(CinemaMarqueeBar)).height, 52.0);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('removes macOS traffic light inset in fullscreen mode', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      try {
        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(
              body: CinemaMarqueeBar(fullscreen: true, leading: Text('Fullscreen Leading')),
            ),
          ),
        );

        expect(find.text('Fullscreen Leading'), findsOneWidget);
        // Traffic light inset should NOT be present when fullscreen
        final inset = find.byWidgetPredicate(
          (w) => w is SizedBox && w.width == CinemaMarqueeBar.macOsTrafficLightInset,
        );
        expect(inset, findsNothing);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('omits Windows caption buttons and drag area in fullscreen mode', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      try {
        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(
              body: CinemaMarqueeBar(fullscreen: true, leading: Text('Win Fullscreen')),
            ),
          ),
        );

        expect(find.text('Win Fullscreen'), findsOneWidget);
        expect(find.byTooltip('Minimize'), findsNothing);
        expect(find.byTooltip('Maximize'), findsNothing);
        expect(find.byTooltip('Close'), findsNothing);
        expect(find.byType(DragToMoveArea), findsNothing);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });
  });
}
