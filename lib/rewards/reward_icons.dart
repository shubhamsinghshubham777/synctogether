import 'package:flutter/widgets.dart';
import '../ui/booth_icons.g.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'rewards_logic.dart';

/// The achievement catalogue lives in a database table so that adding a badge is
/// an `insert` rather than a release - and a table cannot hold an [IconData].
/// It stores the Material Symbols *name*, and this map turns it back into a
/// glyph.
///
/// Deliberately an explicit map rather than `SymbolsGet.get`: that extension
/// resolves by name at runtime and therefore requires `--no-tree-shake-icons`,
/// which would pull the entire Material Symbols font into every installer.
const _kRewardIcons = <String, IconData>{
  'handshake': Symbols.handshake_rounded,
  'local_fire_department': BoothIcons.fire,
  'whatshot': BoothIcons.fire,
  'bolt': Symbols.bolt_rounded,
  'theaters': BoothIcons.film,
  'groups': BoothIcons.group,
  'timer': BoothIcons.schedule,
  'bedtime': BoothIcons.moon,
  'diversity_3': BoothIcons.group,
  'military_tech': Symbols.military_tech_rounded,
  'celebration': Symbols.celebration_rounded,
  'stadia_controller': Symbols.stadia_controller_rounded,
  'target': Symbols.target_rounded,
  'forum': BoothIcons.chat,
  'event_available': Symbols.event_available_rounded,
  'pause_circle': Symbols.pause_circle_rounded,
  'videocam': BoothIcons.videocam,
  'favorite': BoothIcons.react,
  'verified': Symbols.verified_rounded,
  'flag': BoothIcons.flag,
  'workspace_premium': BoothIcons.crown,
  'emoji_events': BoothIcons.trophy,
  'leaderboard': BoothIcons.trophy,
};

/// A name the catalogue knows, or the generic trophy. A badge added to the table
/// before its glyph is added here renders as a trophy rather than a crash - the
/// catalogue is allowed to run ahead of the client, and older clients will keep
/// running against a newer table.
IconData rewardIcon(String name) => _kRewardIcons[name] ?? BoothIcons.trophy;

IconData superlativeIcon(SuperlativeKey key) => rewardIcon(key.icon);
