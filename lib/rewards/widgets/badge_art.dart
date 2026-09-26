import 'package:flutter/material.dart';
import '../../ui/booth_icons.g.dart';

import '../../ui/pt_theme.dart';
import '../reward_icons.dart';

/// Achievement ids that ship with artwork in `assets/badges/`.
///
/// An explicit set rather than a try-and-see: `achievements` is a database
/// table, so the catalogue is allowed to run ahead of the client, and a badge
/// added there before its art exists must fall back to its Material Symbol
/// rather than render a broken image.
const kBadgeArt = <String>{
  'century',
  'chatterbox',
  'devoted',
  'double_feature',
  'first_sync',
  'full_house',
  'host_with_most',
  'hype_man',
  'marathon',
  'night_owl',
  'perfect_sync',
  'seven_up',
  'unbroken',
  'week_one',
  'wide_circle',
};

String? badgeArtAsset(String achievementId) =>
    kBadgeArt.contains(achievementId) ? 'assets/badges/$achievementId.png' : null;

/// Season placings are ranks, not ids, and only the podium has art.
String? seasonArtAsset(int rank) =>
    rank >= 1 && rank <= 3 ? 'assets/badges/season_$rank.png' : null;

/// Pulls most of the colour out without going fully grey - a locked badge
/// should still read as the thing you are working toward.
const _kDesaturate = ColorFilter.matrix(<double>[
  0.410,
  0.536,
  0.054,
  0,
  0,
  0.160,
  0.786,
  0.054,
  0,
  0,
  0.160,
  0.536,
  0.304,
  0,
  0,
  0,
  0,
  0,
  1,
  0,
]);

/// A badge's artwork, or its glyph when there is none.
///
/// Locked badges render the art dimmed and drained rather than a padlock: the
/// shape is still recognisable, which is the whole point of showing somebody
/// what they have not earned yet. The progress ring around it already says
/// "not yet", so a padlock on top would be saying it twice.
class BadgeArt extends StatelessWidget {
  const BadgeArt({
    super.key,
    required this.size,
    required this.fallbackIcon,
    this.achievementId,
    this.seasonRank,
    this.locked = false,
    this.fallbackColor,
  });

  final double size;
  final String fallbackIcon;
  final String? achievementId;
  final int? seasonRank;
  final bool locked;
  final Color? fallbackColor;

  String? get _asset => seasonRank != null
      ? seasonArtAsset(seasonRank!)
      : achievementId == null
      ? null
      : badgeArtAsset(achievementId!);

  @override
  Widget build(BuildContext context) {
    final asset = _asset;
    if (asset == null) return _glyph();

    Widget art = Image.asset(
      asset,
      width: size,
      height: size,
      filterQuality: .medium,
      // A missing or unreadable asset must degrade to the glyph, never to a
      // broken-image box in the middle of the shelf.
      errorBuilder: (context, _, _) => _glyph(),
    );
    if (locked) {
      art = Opacity(
        opacity: 0.32,
        child: ColorFiltered(colorFilter: _kDesaturate, child: art),
      );
    }
    return SizedBox.square(dimension: size, child: art);
  }

  Widget _glyph() => Icon(
    locked ? BoothIcons.lock : rewardIcon(fallbackIcon),
    size: size * 0.52,
    fill: locked ? 0 : 1,
    color: fallbackColor ?? PTColors.white(locked ? 0.35 : 0.9),
  );
}
