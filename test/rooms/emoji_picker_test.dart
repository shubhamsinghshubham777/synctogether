import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:synctogether/rooms/emoji/emoji_prefs.dart';
import 'package:synctogether/rooms/widgets/emoji_picker.dart';
import 'package:synctogether/rooms/widgets/room_chat_panel.dart';
import 'package:synctogether/sync/sync_service.dart';

import '../sync/fakes.dart';

SyncService _sync() => SyncService(
  FakeSyncPlayer(),
  room: testRoom(),
  profile: testProfile('me'),
  role: 'host',
  backend: FakeSyncBackend(),
);

Future<List<String>> _pump(WidgetTester tester, {List<ChatMessage> messages = const []}) async {
  final sent = <String>[];
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Align(
          alignment: Alignment.bottomRight,
          child: SizedBox(
            width: 360,
            height: 520,
            child: RoomChatPanel(
              sync: _sync(),
              messages: messages,
              typingNames: const [],
              watchingCount: 2,
              onClose: () {},
              onSend: sent.add,
              onCopied: () {},
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return sent;
}

Finder get _field =>
    find.byWidgetPredicate((w) => w is TextField && w.decoration?.hintText == 'Say something…');

String _text(WidgetTester tester) => tester.widget<TextField>(_field).controller!.text;

Finder get _pickerButton => find.byTooltip('Emoji');

Future<TestGesture> _mouse(WidgetTester tester) async {
  final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
  await mouse.addPointer(location: Offset.zero);
  addTearDown(mouse.removePointer);
  return mouse;
}

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await EmojiPrefs.instance.clear();
  });

  group('quick bar', () {
    testWidgets('starts on the default five, and a tap inserts without sending', (tester) async {
      final sent = await _pump(tester);
      for (final emoji in ['😂', '❤️', '👍', '😮', '🔥']) {
        expect(find.text(emoji), findsOneWidget);
      }
      await tester.tap(find.text('🔥'));
      await tester.pump();
      expect(_text(tester), '🔥');
      expect(sent, isEmpty);
    });

    testWidgets('a sent emoji climbs onto the bar, and only after the send', (tester) async {
      final sent = await _pump(tester);
      await tester.enterText(_field, 'popcorn time 🍿');
      await tester.pump();
      expect(find.text('🍿'), findsNothing, reason: 'the bar never reorders mid-compose');
      await tester.testTextInput.receiveAction(TextInputAction.send);
      await tester.pumpAndSettle();
      expect(sent, ['popcorn time 🍿']);
      expect(find.text('🍿'), findsOneWidget);
      expect(EmojiPrefs.instance.usage.keys, contains('🍿'));
    });
  });

  group('touch', () {
    testWidgets('the button swaps the keyboard for an inline picker', (tester) async {
      await _pump(tester);
      await tester.tap(_field);
      await tester.pump();
      expect(tester.testTextInput.isVisible, isTrue);

      await tester.tap(_pickerButton);
      await tester.pumpAndSettle();
      expect(find.byType(EmojiPicker), findsOneWidget);
      expect(tester.testTextInput.isVisible, isFalse);

      await tester.tap(find.text('😀'));
      await tester.pump();
      expect(_text(tester), '😀');
      expect(EmojiPrefs.instance.recent.first, '😀');

      // Back to the keyboard.
      await tester.tap(find.byTooltip('Close emoji'));
      await tester.pumpAndSettle();
      expect(find.byType(EmojiPicker), findsNothing);
    });
  });

  group('pointer', () {
    final macOS = TargetPlatformVariant.only(TargetPlatform.macOS);

    testWidgets('hover opens after the intent delay and closes after the grace', (tester) async {
      await _pump(tester);
      final mouse = await _mouse(tester);
      await mouse.moveTo(tester.getCenter(_pickerButton));
      await tester.pump(kEmojiHoverOpenDelay - const Duration(milliseconds: 50));
      expect(find.byType(EmojiPicker), findsNothing, reason: 'sweeping past must not open it');
      await tester.pump(const Duration(milliseconds: 60));
      await tester.pumpAndSettle();
      expect(find.byType(EmojiPicker), findsOneWidget);

      // Onto the picker: the grace window covers the gap, and it stays.
      await mouse.moveTo(tester.getCenter(find.byType(EmojiPicker)));
      await tester.pump(const Duration(seconds: 1));
      expect(find.byType(EmojiPicker), findsOneWidget);

      await mouse.moveTo(const Offset(5, 5));
      await tester.pump(kEmojiHoverCloseDelay - const Duration(milliseconds: 50));
      expect(find.byType(EmojiPicker), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 60));
      await tester.pumpAndSettle();
      expect(find.byType(EmojiPicker), findsNothing);
    }, variant: macOS);

    testWidgets('a click keeps it open until Esc, which leaves the field focused', (tester) async {
      await _pump(tester);
      final mouse = await _mouse(tester);
      await mouse.moveTo(tester.getCenter(_pickerButton));
      await tester.tap(_pickerButton, kind: PointerDeviceKind.mouse);
      await tester.pumpAndSettle();
      await mouse.moveTo(const Offset(5, 5));
      await tester.pump(const Duration(seconds: 1));
      expect(find.byType(EmojiPicker), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byType(EmojiPicker), findsNothing);
      expect(tester.widget<TextField>(_field).focusNode!.hasFocus, isTrue);
    }, variant: macOS);

    testWidgets('Cmd+E toggles it from the field', (tester) async {
      await _pump(tester);
      await tester.tap(_field);
      await tester.pump();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyE);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
      await tester.pumpAndSettle();
      expect(find.byType(EmojiPicker), findsOneWidget);
    }, variant: macOS);

    testWidgets('picking inserts at the caret and keeps typing focus', (tester) async {
      await _pump(tester);
      await tester.enterText(_field, 'ab');
      tester.widget<TextField>(_field).controller!.selection = const TextSelection.collapsed(
        offset: 1,
      );
      await tester.tap(_pickerButton, kind: PointerDeviceKind.mouse);
      await tester.pumpAndSettle();
      await tester.tap(find.text('😀'), kind: PointerDeviceKind.mouse);
      await tester.pump();
      expect(_text(tester), 'a😀b');
      expect(tester.widget<TextField>(_field).focusNode!.hasFocus, isTrue);
    }, variant: macOS);

    testWidgets('search narrows the grid', (tester) async {
      await _pump(tester);
      await tester.tap(_pickerButton, kind: PointerDeviceKind.mouse);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byWidgetPredicate((w) => w is TextField && w.decoration?.hintText == 'Search emoji'),
        'pizza',
      );
      await tester.pumpAndSettle();
      expect(find.text('🍕'), findsOneWidget);
      expect(find.text('😀'), findsNothing);
    }, variant: macOS);
  });

  testWidgets('the field refuses to pass the server codepoint limit', (tester) async {
    await _pump(tester);
    await tester.enterText(_field, 'a' * 498);
    await tester.pump();
    await tester.enterText(_field, '${'a' * 498}👩🏽‍💻');
    await tester.pump();
    expect(_text(tester).runes.length, 498);
    expect(find.text('498/500'), findsOneWidget);
  });

  testWidgets('an emoji-only message renders large, without a bubble', (tester) async {
    await _pump(
      tester,
      messages: [
        ChatMessage(
          senderId: 'other',
          displayName: 'Riya',
          content: '🔥🔥',
          sentAt: DateTime.utc(2026, 9, 24),
        ),
      ],
    );
    final text = tester.widget<Text>(find.text('🔥🔥'));
    expect(text.style!.fontSize, 34);
  });
}
