import 'package:flutter/widgets.dart';
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
  'local_fire_department': Symbols.local_fire_department_rounded,
  'whatshot': Symbols.whatshot_rounded,
  'bolt': Symbols.bolt_rounded,
  'theaters': Symbols.theaters_rounded,
  'groups': Symbols.groups_rounded,
  'timer': Symbols.timer_rounded,
  'bedtime': Symbols.bedtime_rounded,
  'diversity_3': Symbols.diversity_3_rounded,
  'military_tech': Symbols.military_tech_rounded,
  'celebration': Symbols.celebration_rounded,
  'stadia_controller': Symbols.stadia_controller_rounded,
  'target': Symbols.target_rounded,
  'forum': Symbols.forum_rounded,
  'event_available': Symbols.event_available_rounded,
  'pause_circle': Symbols.pause_circle_rounded,
  'videocam': Symbols.videocam_rounded,
  'favorite': Symbols.favorite_rounded,
  'verified': Symbols.verified_rounded,
  'flag': Symbols.flag_rounded,
  'workspace_premium': Symbols.workspace_premium_rounded,
  'emoji_events': Symbols.emoji_events_rounded,
  'leaderboard': Symbols.leaderboard_rounded,
};

/// A name the catalogue knows, or the generic trophy. A badge added to the table
/// before its glyph is added here renders as a trophy rather than a crash - the
/// catalogue is allowed to run ahead of the client, and older clients will keep
/// running against a newer table.
IconData rewardIcon(String name) => _kRewardIcons[name] ?? Symbols.emoji_events_rounded;

IconData superlativeIcon(SuperlativeKey key) => rewardIcon(key.icon);
