import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:synctogether/profile/profile_models.dart';
import 'package:synctogether/profile/profile_service.dart';
import 'package:synctogether/profile/widgets/warning_dialog.dart';

void main() {
  group('WarningDialog', () {
    tearDown(() {
      ProfileService.instance.setProfileForTesting(null);
    });

    testWidgets('renders strike 1 warning details and acknowledge button', (tester) async {
      ProfileService.instance.setProfileForTesting(
        const Profile(
          id: 'user-warned',
          displayName: 'WarnedUser',
          isGuest: false,
          strikesCount: 1,
          moderationStatus: 'warned',
          warningReason: 'Uploaded commercial movie in violation of copyright policies.',
          warningAcknowledged: false,
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(),
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () => showWarningDialog(context),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.text('Moderation Warning'), findsOneWidget);
      expect(find.text('STRIKE 1 OF 2 ISSUED'), findsOneWidget);
      expect(
        find.text('Uploaded commercial movie in violation of copyright policies.'),
        findsOneWidget,
      );
      expect(find.text('I Understand & Agree'), findsOneWidget);
    });
  });
}
