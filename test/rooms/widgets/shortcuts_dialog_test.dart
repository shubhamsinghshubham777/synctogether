import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:synctogether/rooms/widgets/shortcuts_dialog.dart';

void main() {
  testWidgets('ShortcutsDialog displays H and ? shortcuts', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: ShortcutsDialog())));

    expect(find.text('Keyboard shortcuts'), findsOneWidget);
    expect(find.text('Show or hide room controls'), findsOneWidget);
    expect(find.text('Show keyboard shortcuts'), findsOneWidget);
    expect(find.text('H'), findsOneWidget);
    expect(find.text('?'), findsOneWidget);
  });
}
