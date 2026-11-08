import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:synctogether/mock/mock_dependencies.dart';
import 'package:synctogether/pairing/date_night_plan.dart';
import 'package:synctogether/pairing/pair_service.dart';
import 'package:synctogether/player/local_video.dart';
import 'package:synctogether/profile/entitlement_service.dart';
import 'package:synctogether/profile/profile_models.dart';
import 'package:synctogether/profile/profile_service.dart';
import 'package:synctogether/ui/pt_theme.dart';

import '../support/fake_pair_service.dart';

const _gb = 1024 * 1024 * 1024;

/// A free account that has already used most of its week.
class _SpentProfiles extends MockProfileService {
  @override
  Profile? get profile => Profile(
    id: 'user-alex',
    displayName: 'Alex',
    isGuest: false,
    r2UploadBytes7d: (2.2 * _gb).round(),
    r2UploadWindowStart: DateTime.now().subtract(const Duration(days: 2)),
  );
}

/// A Patron: full sharing, no weekly allowance to spend.
class _PatronTier extends MockEntitlementService {
  static const patronLimits = TierLimits(
    tier: kPremiumTier,
    maxLiveRooms: 20,
    maxMembers: 16,
    maxSessionMinutes: 240,
    maxTotalSessionMinutes: 1440,
    avLevel: .video,
    persistentRoomCap: 20,
    dormantHours: 24,
    freeExtensionMinutes: 0,
    mediaSharing: 'full',
    mediaSharingWeeklyBytes: 0,
  );

  @override
  TierLimits get limitsOrFallback => patronLimits;
}

LocalVideo _video(int bytes) => LocalVideo(
  name: 'spirited_away_1080p.mkv',
  mediaUri: '/m/spirited_away_1080p.mkv',
  path: '/m/spirited_away_1080p.mkv',
  origin: VideoOrigin.files,
  reference: const PathReference('/m/spirited_away_1080p.mkv'),
  sizeBytes: bytes,
);

Future<PlanNightController> _open(WidgetTester tester, {required int bytes}) async {
  PairService.instance = FakePairService(pair: samePairInfo(patron: true, partnerZone: null));
  final form = PlanNightController(PairService.instance.pair!)
    ..video = _video(bytes)
    ..fileSize = bytes
    ..attach = PlanAttach.file;
  addTearDown(form.dispose);
  tester.view.physicalSize = const Size(900, 3000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: buildPTTheme(),
      home: Scaffold(
        body: SingleChildScrollView(child: PlanNightBody(form: form)),
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 300));
  return form;
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    installMockDependencies();
  });

  testWidgets('the file option sits between the link and choosing together', (tester) async {
    await _open(tester, bytes: _gb);
    final link = tester.getTopLeft(find.text('A YouTube link')).dy;
    final file = tester.getTopLeft(find.text('A file from this device')).dy;
    final together = tester.getTopLeft(find.text("We'll choose together")).dy;
    expect(link < file && file < together, isTrue);
    expect(find.text('Uploads after you send. Sam streams it.'), findsOneWidget);
  });

  testWidgets('a file that fits shows its name, size and what is left, and can be sent', (
    tester,
  ) async {
    final form = await _open(tester, bytes: (1.8 * _gb).round());
    expect(find.text('spirited_away_1080p.mkv'), findsOneWidget);
    expect(find.text('1.8 GB'), findsOneWidget);
    expect(find.text("This week's upload allowance"), findsOneWidget);
    expect(find.text('2.5 GB left'), findsOneWidget);
    expect(find.textContaining('Keep SyncTogether open until'), findsOneWidget);
    expect(form.fileCheck, FileCheck.ok);
    expect(form.canSend, isTrue);
    expect(form.sendLabel, 'Send to Sam, start upload');
  });

  testWidgets('over the per-file cap says so, offers another file, and cannot be sent', (
    tester,
  ) async {
    final form = await _open(tester, bytes: 3 * _gb);
    expect(
      find.textContaining('That file is over the 2.0 GB a free seat can share.'),
      findsOneWidget,
    );
    expect(find.text('Pick a smaller file'), findsOneWidget);
    expect(form.fileCheck, FileCheck.overCap);
    expect(form.canSend, isFalse, reason: 'Send stays off until it is resolved');
  });

  testWidgets(
    'with too little of the week left it says how much, when it resets, and offers a way out',
    (tester) async {
      ProfileService.instance = _SpentProfiles();
      final form = await _open(tester, bytes: (1.2 * _gb).round());
      expect(find.textContaining('is left this week and that file is 1.2 GB.'), findsOneWidget);
      expect(find.textContaining('Your week resets'), findsOneWidget);
      expect(find.text('Pick a smaller file'), findsOneWidget);
      expect(find.text('Send without a file'), findsOneWidget);
      expect(form.fileCheck, FileCheck.overWeek);
      expect(form.canSend, isFalse);

      await tester.tap(find.text('Send without a file'));
      await tester.pump();
      expect(form.attach, PlanAttach.none, reason: 'the night goes ahead without a film');
      expect(form.canSend, isTrue);
    },
  );

  testWidgets('a Patron planner sees the unlimited card and no bar', (tester) async {
    EntitlementService.instance = _PatronTier();
    final form = await _open(tester, bytes: 7 * _gb);
    expect(find.text('UNLIMITED'), findsOneWidget);
    expect(find.textContaining('Patron seats upload files up to 10 GB'), findsOneWidget);
    expect(find.text("This week's upload allowance"), findsNothing);
    expect(form.fileCheck, FileCheck.ok);
  });

  group('the file rules on their own', () {
    test('no file chosen means nothing to check', () {
      expect(fileCheckFor(null, hasFile: false), FileCheck.none);
      expect(fileCheckFor(5, hasFile: false), FileCheck.none);
    });

    test('a file exactly at the cap fits, one byte over does not', () {
      const free = TierLimits(
        tier: kFreeTier,
        maxLiveRooms: 4,
        maxMembers: 8,
        maxSessionMinutes: 240,
        maxTotalSessionMinutes: 240,
        avLevel: .voice,
        persistentRoomCap: 0,
        dormantHours: 24,
        freeExtensionMinutes: 0,
        mediaSharing: 'limited',
        mediaSharingWeeklyBytes: 5 * _gb,
      );
      final cap = free.mediaSharingMaxSizeBytes;
      const profile = Profile(id: 'a', displayName: 'A', isGuest: false);
      expect(fileCheckFor(cap, hasFile: true, limits: free, profile: profile), FileCheck.ok);
      expect(
        fileCheckFor(cap + 1, hasFile: true, limits: free, profile: profile),
        FileCheck.overCap,
      );
    });
  });
}
