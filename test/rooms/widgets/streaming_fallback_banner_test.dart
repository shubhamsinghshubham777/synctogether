import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:synctogether/rooms/widgets/streaming_fallback_banner.dart';

void main() {
  testWidgets('says what happened and offers Use my copy', (tester) async {
    var used = 0;
    var dismissed = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StreamingFallbackBanner(onUseMyCopy: () => used++, onDismiss: () => dismissed++),
        ),
      ),
    );
    expect(find.text('Streaming the shared copy'), findsOneWidget);
    expect(find.textContaining("isn't on this device any more"), findsOneWidget);
    await tester.tap(find.text('Use my copy'));
    expect(used, 1);
    expect(dismissed, 0);
  });
}
