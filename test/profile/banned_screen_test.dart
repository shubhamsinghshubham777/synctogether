import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:synctogether/profile/banned_screen.dart';
import 'package:synctogether/profile/profile_models.dart';
import 'package:synctogether/profile/profile_service.dart';

void main() {
  group('BannedScreen', () {
    tearDown(() {
      ProfileService.instance.setProfileForTesting(null);
    });

    testWidgets('renders account suspended with reason and contact support CTA', (tester) async {
      ProfileService.instance.setProfileForTesting(
        const Profile(
          id: 'user-banned',
          displayName: 'BannedUser',
          isGuest: false,
          strikesCount: 2,
          moderationStatus: 'banned',
          banReason: 'Repeatedly uploaded copyrighted movies without authorization.',
        ),
      );

      await tester.pumpWidget(MaterialApp(theme: ThemeData.dark(), home: const BannedScreen()));
      await tester.pumpAndSettle();

      expect(find.text('Account Suspended'), findsOneWidget);
      expect(
        find.text('Repeatedly uploaded copyrighted movies without authorization.'),
        findsOneWidget,
      );
      expect(find.text('Contact Support'), findsOneWidget);
      expect(find.text('Sign Out'), findsOneWidget);
    });
  });
}
