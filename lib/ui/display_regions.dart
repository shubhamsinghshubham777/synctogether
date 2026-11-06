import 'dart:io' show Platform;
import 'dart:ui' show DisplayFeature, DisplayFeatureState, DisplayFeatureType;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../diagnostics.dart';
import 'responsive.dart';

/// Turns the iOS reserved regions the runner reports (iPhone Duo, iOS 27.1)
/// into the [DisplayFeature]s Android's embedder gives `MediaQuery`, so
/// `foldOf` and everything built on it works the same on both. Pure, so it is
/// testable as a table.
///
/// - a *division* region is the fold. While it is active the device is
///   partly folded (book or tabletop), which is `postureHalfOpened`; inactive
///   it is flat and divides nothing, so it is reported flat and `foldOf`
///   ignores it, exactly like a flat Android fold;
/// - an *occlusion* region is an area content cannot use. Measured on the
///   simulator, the closed outer display reports the under-display camera and
///   the trailing system block as active occlusions - a cutout, not a hinge, so
///   it becomes `cutout`, which splits nothing. (The iPhone Duo has one
///   continuous inner panel; there is no gap to avoid.)
List<DisplayFeature> featuresFromRegions(List<Map<Object?, Object?>> regions) {
  final out = <DisplayFeature>[];
  for (final r in regions) {
    double n(String k) => (r[k] as num?)?.toDouble() ?? 0;
    final bounds = Rect.fromLTWH(n('left'), n('top'), n('width'), n('height'));
    if (bounds.isEmpty && n('width') == 0 && n('height') == 0) continue;
    final active = r['active'] == true;
    switch (r['kind']) {
      case 'occlusion':
        if (!active) continue;
        out.add(
          DisplayFeature(
            bounds: bounds,
            type: DisplayFeatureType.cutout,
            state: DisplayFeatureState.unknown,
          ),
        );
      case 'division':
        out.add(
          DisplayFeature(
            bounds: bounds,
            type: DisplayFeatureType.fold,
            state: active ? DisplayFeatureState.postureHalfOpened : DisplayFeatureState.postureFlat,
          ),
        );
    }
  }
  return out;
}

/// The fold features iOS reports, as a live value. Empty on every platform
/// that is not iOS 27.1+ on a folding iPhone.
class DisplayRegions {
  DisplayRegions._();
  static final instance = DisplayRegions._();

  static const _channel = MethodChannel('app.synctogether/display_regions');

  /// False off iOS (and under `flutter test`, which is not iOS).
  static bool enabled = !kIsWeb && Platform.isIOS;

  final features = ValueNotifier<List<DisplayFeature>>(const []);
  bool _started = false;

  Future<void> start() async {
    if (!enabled || _started) return;
    _started = true;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'regions') _apply(call.arguments);
    });
    try {
      _apply(await _channel.invokeMethod<Object>('get'));
    } catch (e, s) {
      // Runners older than the bridge, or an OS without the API: no fold.
      reportNonFatal(e, s, during: 'reading the display regions');
    }
  }

  void _apply(Object? raw) {
    final list = [for (final r in (raw as List? ?? const [])) (r as Map).cast<Object?, Object?>()];
    final next = featuresFromRegions(list);
    if (listEquals(next, features.value)) return;
    final before = foldFromFeatures(features.value);
    final after = foldFromFeatures(next);
    features.value = next;
    if (before.axis != after.axis) {
      trace(
        'display fold changed',
        category: 'room',
        data: {'from': before.axis.name, 'to': after.axis.name, 'regions': list.length},
      );
    }
  }
}

/// Merges [DisplayRegions] into the window's `MediaQuery.displayFeatures`, so
/// the rest of the app reads folds from one place. A passthrough off iOS.
class DisplayRegionsHost extends StatefulWidget {
  const DisplayRegionsHost({super.key, required this.child});

  final Widget child;

  @override
  State<DisplayRegionsHost> createState() => _DisplayRegionsHostState();
}

class _DisplayRegionsHostState extends State<DisplayRegionsHost> {
  @override
  void initState() {
    super.initState();
    DisplayRegions.instance.start();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<List<DisplayFeature>>(
      valueListenable: DisplayRegions.instance.features,
      child: widget.child,
      builder: (context, injected, child) {
        // Always wrapped, folded or not: a wrapper that came and went with the
        // fold would remount the whole app under it.
        final mq = MediaQuery.of(context);
        return MediaQuery(
          data: mq.copyWith(displayFeatures: [...mq.displayFeatures, ...injected]),
          child: child!,
        );
      },
    );
  }
}
