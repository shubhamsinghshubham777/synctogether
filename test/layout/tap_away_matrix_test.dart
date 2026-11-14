import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:synctogether/auth/login_screen.dart';
import 'package:synctogether/mock/mock_dependencies.dart';
import 'package:synctogether/player/subtitles/subtitle_style_dialog.dart';
import 'package:synctogether/player/youtube_url_dialog.dart';
import 'package:synctogether/profile/entitlement_service.dart';
import 'package:synctogether/profile/profile_models.dart';
import 'package:synctogether/profile/profile_service.dart';
import 'package:synctogether/rewards/rewards_service.dart';
import 'package:synctogether/rooms/lobby_screen.dart';
import 'package:synctogether/rooms/room_service.dart';
import 'package:synctogether/rooms/widgets/report_dialog.dart';
import 'package:synctogether/ui/booth_icons.g.dart';
import 'package:synctogether/ui/buttons.dart';
import 'package:synctogether/ui/glass.dart';
import 'package:synctogether/ui/inputs.dart';

import '../support/screen_matrix.dart';
import 'layout_support.dart';

/// Tap-away-closes-the-keyboard, per screen that has a text field. One text
/// scale is enough: the rule is about hit regions, not text metrics. The room
/// chat's case lives with its harness in room_screen_matrix_test.dart.
void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    installMockDependencies();
    RewardsService.instance = FakeRewardsService();
    ProfileService.instance.setProfileForTesting(
      const Profile(id: 'user-1', displayName: 'Alex', isGuest: false, email: 'a@b.co'),
    );
    EntitlementService.instance.setLimitsForTesting(TierLimits.fallback);
  });
  tearDown(() {
    ProfileService.instance.setProfileForTesting(null);
    EntitlementService.instance.setLimitsForTesting(null);
  });

  const scales = [1.0];

  screenMatrix(
    'tap-away/login email',
    (tester, c, s) async {
      await pumpAtSize(tester, const LoginScreen(), c, textScale: s);
      await tester.pump(const Duration(milliseconds: 1500));
      tester.takeException();
      final email = find.byWidgetPredicate((w) => w is PTButton && w.icon == BoothIcons.mail);
      await tester.ensureVisible(email);
      await tester.tap(email);
      await tester.pump(const Duration(milliseconds: 400));
      await expectTapAwayClosesKeyboard(tester, c);
      await finishCase(tester);
    },
    textScales: scales,
    checkInsets: false,
  );

  screenMatrix(
    'tap-away/lobby forms',
    (tester, c, s) async {
      RoomService.instance = MockRoomService();
      await pumpAtSize(tester, const LobbyScreen(), c, textScale: s);
      await tester.pump(const Duration(milliseconds: 1500));
      // The open form's room-name field (phones show one form at a time).
      await expectTapAwayClosesKeyboard(tester, c, field: find.byType(EditableText).first);
      final toJoin = find.widgetWithText(PTButton, 'Enter a code');
      if (toJoin.evaluate().isNotEmpty) {
        await tester.ensureVisible(toJoin.first);
        await tester.tap(toJoin.first, warnIfMissed: false);
        await tester.pump(const Duration(seconds: 2));
        await tester.pump();
      }
      await expectTapAwayClosesKeyboard(
        tester,
        c,
        field: find.descendant(of: find.byType(PTCodeInput), matching: find.byType(EditableText)),
      );
      await finishCase(tester);
    },
    textScales: scales,
    checkInsets: false,
  );

  void dialog(String name, void Function(BuildContext) open) {
    screenMatrix(
      'tap-away/$name',
      (tester, c, s) async {
        await pumpDialogOpener(tester, c, s, open);
        await expectTapAwayClosesKeyboard(tester, c);
        await finishCase(tester);
      },
      textScales: scales,
      checkInsets: false,
    );
  }

  dialog(
    'youtube-url dialog',
    (ctx) => showGlassDialog<void>(context: ctx, builder: (_) => const YouTubeUrlDialog()),
  );
  dialog('report dialog', (ctx) => showReportDialog(ctx, targetName: 'Sam', roomCode: 'ABC123'));

  // The font search lives one level into the subtitle style dialog.
  screenMatrix(
    'tap-away/subtitle font search',
    (tester, c, s) async {
      await pumpDialogOpener(tester, c, s, (ctx) => showSubtitleStyleDialog(ctx));
      final row = find.text('Default font');
      await tester.ensureVisible(row.first);
      await tester.tap(row.first);
      await tester.pump(const Duration(milliseconds: 600));
      await expectTapAwayClosesKeyboard(tester, c);
      await finishCase(tester);
    },
    textScales: scales,
    checkInsets: false,
  );
}
