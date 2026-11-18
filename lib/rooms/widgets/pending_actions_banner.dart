import 'package:material_ui/material_ui.dart';
import 'package:synctogether/rooms/pending_actions.dart';
import 'package:synctogether/ui/banners.dart';
import 'package:synctogether/ui/booth_icons.g.dart';
import 'package:synctogether/ui/buttons.dart';
import 'package:synctogether/ui/haptics.dart';
import 'package:synctogether/ui/reveal.dart';

/// The single banner for [PendingActions]: "Deleted X · Undo" with the 5 second
/// ring, or - when the call could not finish - what went wrong and Try again.
///
/// Shown by the lobby (the room that started a leave is gone by then), folded
/// in and out so the gap it leaves is zero.
class PendingActionsBanner extends StatelessWidget {
  const PendingActionsBanner({super.key, required this.onUndo});

  /// Called after the action is rolled back, so a leave can walk back into its room.
  final void Function(PendingAction action) onUndo;

  @override
  Widget build(BuildContext context) {
    final pending = PendingActions.instance;
    return ListenableBuilder(
      listenable: pending,
      builder: (context, _) {
        final failure = pending.failure;
        final action = pending.current;
        final Widget? banner = failure != null
            ? PTBanner(
                key: const ValueKey('pending-failure'),
                kind: .error,
                icon: BoothIcons.alert,
                title: failure.title,
                subtitle: failure.message,
                onDismiss: pending.dismissFailure,
                trailing: PTButton(
                  label: 'Try again',
                  variant: .secondary,
                  height: 34,
                  expand: false,
                  onPressed: failure.retry,
                ),
              )
            : action == null
            ? null
            : _banner(pending, action);
        return PTRevealKeep(
          visible: banner != null,
          alignment: Alignment.bottomCenter,
          child: banner ?? const SizedBox(width: double.infinity),
        );
      },
    );
  }

  Widget _banner(PendingActions pending, PendingAction action) {
    final waiting = pending.waitingForNetwork;
    final replaced = pending.replacedTitle;
    return PTBanner(
      // A fresh key restarts the countdown ring for each new action.
      key: ValueKey('pending-${identityHashCode(action)}-$waiting'),
      kind: waiting ? .warning : .info,
      icon: switch (action.kind) {
        .leaveRoom => BoothIcons.leave,
        _ => BoothIcons.delete,
      },
      title: waiting ? '${action.title}, waiting for network' : action.title,
      subtitle: waiting
          ? "We'll finish it when you're back online."
          : replaced != null && action.kind != .leaveRoom
          ? 'Earlier: $replaced is gone for good.'
          : action.subtitle,
      autoDismissAfter: waiting ? null : pending.window,
      onDismiss: waiting ? null : () => pending.commitNow(),
      trailing: PTButton(
        label: 'Undo',
        variant: .secondary,
        height: 34,
        expand: false,
        onPressed: () {
          PTHaptics.tap();
          final undone = pending.undo();
          if (undone != null) onUndo(undone);
        },
      ),
    );
  }
}
