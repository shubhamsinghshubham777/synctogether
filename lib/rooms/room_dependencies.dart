import 'package:flutter/widgets.dart';
import 'package:media_kit/media_kit.dart';

/// The one seam [RoomScreen] needs to be pumped in a widget test, in the
/// style of `SyncBackend`: pure delegation, defaulted to the real thing, and
/// no behaviour change in production.
///
/// Everything else the room reaches for is already swappable - the `Player`
/// is passed in by `MainApp`, the service singletons have settable
/// `instance`s (which is how `installMockDependencies` works), sync goes
/// through `SyncService.defaultBackendOverride`, and AV through
/// `LiveKitService.isConfiguredOverride`. What is left is media_kit's video
/// surface: a `VideoController` needs the native libmpv that `flutter test`
/// does not load, so it cannot be constructed at all there.
class RoomDependencies {
  const RoomDependencies({this.videoView});

  /// Replaces media_kit's `Video` widget. When set, the room never constructs
  /// a `VideoController` (it is created lazily, only by the default view).
  final Widget Function(BuildContext context, Player player)? videoView;

  static const real = RoomDependencies();
}
