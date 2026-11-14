import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:synctogether/rooms/room_models.dart';
import 'package:synctogether/rooms/widgets/room_overflow_menu.dart';
import 'package:synctogether/sync/sync_service.dart';

void main() {
  group('RoomOverflowMenu', () {
    testWidgets('in Our Room there is no invite, no remote lock and no end-for-everyone', (
      tester,
    ) async {
      final data = ValueNotifier<RoomMenuData?>(
        RoomMenuData(
          members: [
            RoomMember(
              roomId: 'room-1',
              userId: 'me',
              role: 'host',
              joinedAt: DateTime(2026, 1, 1),
            ),
            RoomMember(
              roomId: 'room-1',
              userId: 'sam',
              role: 'host',
              joinedAt: DateTime(2026, 1, 1),
            ),
          ],
          present: const [],
          media: RoomMedia.none,
          transportLock: false,
          selfId: 'me',
          selfIsHost: true,
          ourRoom: true,
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showRoomOverflowMenu(
                  context: context,
                  data: data,
                  onCopyInvite: () {},
                  onLeave: () {},
                  onEndRoom: () {},
                  onExtendRoom: () {},
                  onTransportLockChanged: (_) {},
                  onKick: (_) {},
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.text('THE TWO OF YOU'), findsOneWidget);
      expect(find.text('Copy invite link'), findsNothing);
      expect(find.text('Take the remote'), findsNothing);
      expect(find.text('End for everyone'), findsNothing);
      expect(find.text('Leave room'), findsOneWidget, reason: 'leaving is still one tap');
      expect(find.text('Extend room'), findsOneWidget);
    });

    testWidgets('displays Extend room for host and invokes callback on tap', (tester) async {
      var extendTapped = false;
      final data = ValueNotifier<RoomMenuData?>(
        RoomMenuData(
          members: [
            RoomMember(
              roomId: 'room-1',
              userId: 'user-host',
              role: 'host',
              joinedAt: DateTime(2026, 1, 1),
            ),
          ],
          present: [
            PresentMember(
              userId: 'user-host',
              displayName: 'Host User',
              role: 'host',
              joinedAt: DateTime(2026, 1, 1),
            ),
          ],
          media: RoomMedia.none,
          transportLock: false,
          selfId: 'user-host',
          selfIsHost: true,
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showRoomOverflowMenu(
                  context: context,
                  data: data,
                  onCopyInvite: () {},
                  onLeave: () {},
                  onEndRoom: () {},
                  onExtendRoom: () => extendTapped = true,
                  onTransportLockChanged: (_) {},
                  onKick: (_) {},
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.text('Extend room'), findsOneWidget);

      await tester.tap(find.text('Extend room'));
      await tester.pumpAndSettle();

      expect(extendTapped, isTrue);
    });

    testWidgets('does not display Extend room for non-host members', (tester) async {
      final data = ValueNotifier<RoomMenuData?>(
        RoomMenuData(
          members: [
            RoomMember(
              roomId: 'room-1',
              userId: 'user-watcher',
              role: 'member',
              joinedAt: DateTime(2026, 1, 1),
            ),
          ],
          present: [
            PresentMember(
              userId: 'user-watcher',
              displayName: 'Watcher User',
              role: 'member',
              joinedAt: DateTime(2026, 1, 1),
            ),
          ],
          media: RoomMedia.none,
          transportLock: false,
          selfId: 'user-watcher',
          selfIsHost: false,
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showRoomOverflowMenu(
                  context: context,
                  data: data,
                  onCopyInvite: () {},
                  onLeave: () {},
                  onEndRoom: () {},
                  onExtendRoom: () {},
                  onTransportLockChanged: (_) {},
                  onKick: (_) {},
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.text('Extend room'), findsNothing);
    });

    testWidgets('triggers onReportConcern when tapped', (tester) async {
      var reportTapped = false;
      final data = ValueNotifier<RoomMenuData?>(
        RoomMenuData(
          members: [
            RoomMember(
              roomId: 'room-1',
              userId: 'user-1',
              role: 'member',
              joinedAt: DateTime(2026, 1, 1),
            ),
          ],
          present: [
            PresentMember(
              userId: 'user-1',
              displayName: 'Alice',
              role: 'member',
              joinedAt: DateTime(2026, 1, 1),
            ),
          ],
          media: RoomMedia.none,
          transportLock: false,
          selfId: 'user-1',
          selfIsHost: false,
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showRoomOverflowMenu(
                  context: context,
                  data: data,
                  onCopyInvite: () {},
                  onLeave: () {},
                  onEndRoom: () {},
                  onReportConcern: () => reportTapped = true,
                  onTransportLockChanged: (_) {},
                  onKick: (_) {},
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.text('Report a concern'), findsOneWidget);
      await tester.tap(find.text('Report a concern'));
      await tester.pumpAndSettle();

      expect(reportTapped, isTrue);
    });

    testWidgets('displays Make host button when self can assign host and invokes callback on tap', (
      tester,
    ) async {
      // Tooltips are attached on pointer input only (touch has no hover), and
      // `flutter test` defaults to Android.
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      RoomMember? assignedMember;
      final data = ValueNotifier<RoomMenuData?>(
        RoomMenuData(
          members: [
            RoomMember(
              roomId: 'room-1',
              userId: 'user-host',
              role: 'host',
              joinedAt: DateTime(2026, 1, 1),
            ),
            RoomMember(
              roomId: 'room-1',
              userId: 'user-member',
              role: 'member',
              joinedAt: DateTime(2026, 1, 2),
            ),
          ],
          present: [
            PresentMember(
              userId: 'user-host',
              displayName: 'Host User',
              role: 'host',
              joinedAt: DateTime(2026, 1, 1),
            ),
            PresentMember(
              userId: 'user-member',
              displayName: 'Member User',
              role: 'member',
              joinedAt: DateTime(2026, 1, 2),
            ),
          ],
          media: RoomMedia.none,
          transportLock: false,
          selfId: 'user-host',
          selfIsHost: true,
          canAssignHost: true,
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showRoomOverflowMenu(
                  context: context,
                  data: data,
                  onCopyInvite: () {},
                  onLeave: () {},
                  onEndRoom: () {},
                  onTransportLockChanged: (_) {},
                  onKick: (_) {},
                  onAssignHost: (m) => assignedMember = m,
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      final makeHostBtn = find.byTooltip('Make host');
      expect(makeHostBtn, findsOneWidget);

      await tester.tap(makeHostBtn);
      await tester.pumpAndSettle();

      expect(assignedMember, isNotNull);
      expect(assignedMember?.userId, 'user-member');
      debugDefaultTargetPlatformOverride = null;
    });

    testWidgets('does not display Make host button when self cannot assign host', (tester) async {
      final data = ValueNotifier<RoomMenuData?>(
        RoomMenuData(
          members: [
            RoomMember(
              roomId: 'room-1',
              userId: 'user-1',
              role: 'member',
              joinedAt: DateTime(2026, 1, 1),
            ),
            RoomMember(
              roomId: 'room-1',
              userId: 'user-2',
              role: 'member',
              joinedAt: DateTime(2026, 1, 2),
            ),
          ],
          present: [
            PresentMember(
              userId: 'user-1',
              displayName: 'User 1',
              role: 'member',
              joinedAt: DateTime(2026, 1, 1),
            ),
            PresentMember(
              userId: 'user-2',
              displayName: 'User 2',
              role: 'member',
              joinedAt: DateTime(2026, 1, 2),
            ),
          ],
          media: RoomMedia.none,
          transportLock: false,
          selfId: 'user-1',
          selfIsHost: false,
          canAssignHost: false,
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showRoomOverflowMenu(
                  context: context,
                  data: data,
                  onCopyInvite: () {},
                  onLeave: () {},
                  onEndRoom: () {},
                  onTransportLockChanged: (_) {},
                  onKick: (_) {},
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.byTooltip('Make host'), findsNothing);
    });
  });
}
