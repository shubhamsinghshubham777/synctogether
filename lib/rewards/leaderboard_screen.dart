import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:url_launcher/url_launcher.dart';

import '../analytics.dart';
import '../analytics_consent.dart';
import '../auth/auth_service.dart';
import '../ui/banners.dart';
import '../ui/buttons.dart';
import '../ui/glass.dart';
import '../ui/identity.dart';
import '../ui/loader.dart';
import '../ui/pt_motion.dart';
import '../ui/pt_theme.dart';
import '../ui/responsive.dart';
import '../ui/scroll_fade.dart';
import 'rewards_logic.dart';
import 'rewards_models.dart';
import 'rewards_service.dart';
import 'widgets/badge_shelf.dart';
import 'widgets/season_trophies.dart';

/// Three boards, defaulting to Circle.
///
/// A single global board is demoralising by construction - the top is
/// unreachable and the middle is invisible. Circle is people you have actually
/// shared a room with, which is the board that is winnable, and therefore the
/// one worth telling somebody about.
class LeaderboardScreen extends StatefulWidget {
  const LeaderboardScreen({super.key});

  @override
  State<LeaderboardScreen> createState() => _LeaderboardScreenState();
}

class _LeaderboardScreenState extends State<LeaderboardScreen> {
  LeaderboardScope _scope = .circle;
  LeaderboardPeriod _period = .week;

  List<LeaderboardRow> _rows = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    Analytics.instance.track('leaderboard_viewed', {'scope': _scope.wire});
    unawaited(RewardsService.instance.load().then((_) => _trackUpsellShown()));
    unawaited(_reload());
  }

  /// Fired once per visit, and deliberately *not* from `build`.
  ///
  /// The guest upsell here is an inline card rather than a dialog, so there is
  /// no "shown" moment to hang it off - and a `build` call site would report it
  /// on every frame. Without it this surface emitted clicks with no
  /// impressions, which leaves the conversion rate uncomputable and makes the
  /// pair pointless. The visit itself is human-caused; the card is only its
  /// consequence.
  bool _upsellTracked = false;

  void _trackUpsellShown() {
    if (_upsellTracked || !mounted) return;
    if (!RewardsService.instance.state.isGuest) return;
    _upsellTracked = true;
    Analytics.instance.track('upgrade_cta_shown', {'surface': 'leaderboard'});
  }

  Future<void> _reload() async {
    setState(() => _loading = true);
    final rows = await RewardsService.instance.leaderboard(scope: _scope, period: _period);
    if (!mounted) return;
    // The floor can fall back below the threshold between one visit and the
    // next; a selected tab that no longer exists must not strand the screen.
    if (_scope == .global && !RewardsService.instance.state.globalBoard.open) {
      setState(() => _scope = .circle);
      unawaited(_reload());
      return;
    }
    setState(() {
      _rows = rows;
      _loading = false;
    });
  }

  void _setScope(LeaderboardScope scope) {
    if (scope == _scope) return;
    setState(() => _scope = scope);
    Analytics.instance.track('leaderboard_viewed', {'scope': scope.wire});
    unawaited(_reload());
  }

  void _setPeriod(LeaderboardPeriod period) {
    if (period == _period) return;
    setState(() => _period = period);
    unawaited(_reload());
  }

  Future<void> _setPublic(bool value) async {
    Analytics.instance.track('leaderboard_opt_in', {'on': value});
    await RewardsService.instance.setPublicProfile(value);
    if (!mounted) return;
    await _reload();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: AmbientBackground(
        child: ListenableBuilder(
          listenable: Listenable.merge([RewardsService.instance, AnalyticsConsent.instance]),
          builder: (context, _) {
            final state = RewardsService.instance.state;
            return PTResponsive(
              portrait: (_) => _layout(state, compact: true),
              // Phone landscape is 390 tall: the compact header, not the 28 px
              // desktop gutters. Tablets fall back to desktop.
              landscape: (_) => _layout(state, compact: MediaQuery.sizeOf(context).width < 840),
              desktop: (_) => _layout(state, compact: false),
            );
          },
        ),
      ),
    );
  }

  Widget _layout(RewardState state, {required bool compact}) {
    // Edge-to-edge: the list scrolls under the home indicator / nav bar, and
    // the bottom inset pads the content so its last item still clears it.
    return SafeArea(
      bottom: false,
      child: Column(
        children: [
          Padding(
            padding: compact
                ? const EdgeInsets.fromLTRB(20, 10, 20, 0)
                : const EdgeInsets.symmetric(horizontal: 48, vertical: 28),
            child: Row(
              spacing: 14,
              children: [
                PTIconButton(
                  icon: Symbols.arrow_back_rounded,
                  iconSize: 20,
                  size: compact ? 44 : 42,
                  onPressed: () => context.go('/lobby'),
                ),
                Flexible(
                  child: Text(
                    'Leaderboard',
                    maxLines: 1,
                    overflow: .ellipsis,
                    style: compact ? PTText.cardHeading.copyWith(fontSize: 18) : PTText.cardHeading,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: ScrollFadeEdge(
              child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(
                  compact ? 20 : 48,
                  20,
                  compact ? 20 : 48,
                  40 + MediaQuery.paddingOf(context).bottom,
                ),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 620),
                    child: Column(
                      crossAxisAlignment: .stretch,
                      children: [
                        _summary(state),
                        const SizedBox(height: 18),
                        _scopeTabs(state),
                        const SizedBox(height: 12),
                        _periodTabs(),
                        const SizedBox(height: 16),
                        if (AnalyticsConsent.instance.optedOut) ...[
                          _pausedCard(),
                          const SizedBox(height: 16),
                        ] else if (!state.publicProfile) ...[
                          _consentCard(state),
                          const SizedBox(height: 16),
                        ],
                        _board(state),
                        const SizedBox(height: 20),
                        _scoringCard(state),
                        const SizedBox(height: 20),
                        _badgeCard(state, compact: compact),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _summary(RewardState state) {
    final rank = _scope == .circle ? state.circleRank : state.weekRank;
    return GlassPanel(
      radius: 22,
      opacity: 0.5,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
      child: Row(
        children: [
          Expanded(
            child: _Tile(
              label: 'Streak',
              value: '${state.streak.current}',
              suffix: state.streak.current == 1 ? 'day' : 'days',
              icon: Symbols.local_fire_department_rounded,
              tint: PTColors.streak,
            ),
          ),
          _divider(),
          Expanded(
            child: _Tile(
              label: 'This week',
              value: formatPoints(state.points.week),
              suffix: 'pts',
              icon: Symbols.bolt_rounded,
              tint: PTColors.textAccent,
            ),
          ),
          _divider(),
          Expanded(
            child: _Tile(
              label: 'Rank',
              value: rankOrdinal(rank),
              suffix: _scope.title.toLowerCase().replaceFirst('your ', ''),
              icon: Symbols.trophy_rounded,
              tint: PTColors.premium,
            ),
          ),
        ],
      ),
    );
  }

  Widget _divider() => Container(width: 1, height: 38, color: PTColors.white(0.08));

  /// The global tab is absent, not empty, until the board is real.
  ///
  /// A tab that always says "warming up" is a dead tab, and with a young product
  /// it would say that for months. This keeps the promise visible as one line of
  /// copy instead, which ages better than a permanently broken-looking control.
  Widget _scopeTabs(RewardState state) {
    final open = state.globalBoard.open;
    final scopes = open ? LeaderboardScope.values : const [LeaderboardScope.circle];
    return Column(
      crossAxisAlignment: .stretch,
      spacing: 8,
      children: [
        Row(
          spacing: 10,
          children: [
            for (final scope in scopes)
              Expanded(
                child: _Tab(
                  label: scope.title,
                  selected: _scope == scope,
                  onTap: () => _setScope(scope),
                ),
              ),
          ],
        ),
        if (!open)
          Text(
            'A board for everyone opens once enough people are playing. '
            'Until then this one is yours and the people you watch with.',
            textAlign: .center,
            style: PTText.finePrint.copyWith(fontSize: 11.5),
          ),
      ],
    );
  }

  Widget _periodTabs() {
    // Wrap: three chips at 2.0x text do not fit a 320 phone on one line.
    return Wrap(
      alignment: .center,
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final period in LeaderboardPeriod.values)
          _Chip(label: period.title, selected: _period == period, onTap: () => _setPeriod(period)),
      ],
    );
  }

  /// Consent is asked here, in context, the first time somebody opens the board -
  /// not buried in settings, and never assumed. The copy states exactly what
  /// becomes public, because a leaderboard is a change to a product that
  /// advertises itself as having no tracking.
  Widget _consentCard(RewardState state) {
    if (state.isGuest) {
      return GlassPanel(
        radius: 20,
        opacity: 0.5,
        borderColor: PTColors.primary.withValues(alpha: 0.3),
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
        child: Column(
          crossAxisAlignment: .start,
          spacing: 12,
          children: [
            Text('Streaks need an account', style: PTText.cardHeading.copyWith(fontSize: 16)),
            Text(
              'Guest sessions are wiped after a few days, so a streak held on one '
              'would not survive the week. Sign in and it starts counting - same '
              'session, same rooms, nothing to move.',
              style: PTText.caption,
            ),
            GoogleButton(
              label: 'Sign in with Google',
              onPressed: () {
                Analytics.instance.track('upgrade_cta_clicked', {
                  'surface': 'leaderboard',
                  'action': 'sign_in',
                });
                unawaited(AuthService.instance.linkGoogleIdentity());
              },
            ),
          ],
        ),
      );
    }
    return GlassPanel(
      radius: 20,
      opacity: 0.5,
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
      child: Column(
        crossAxisAlignment: .start,
        spacing: 12,
        children: [
          Row(
            spacing: 10,
            children: [
              const Icon(Symbols.visibility_rounded, size: 18, color: PTColors.textAccent),
              Expanded(
                child: Text('Join the board', style: PTText.cardHeading.copyWith(fontSize: 16)),
              ),
            ],
          ),
          Text(
            'Turning this on shows your name, avatar, streak and rank to people '
            'you watch with, and on the public board. What you watch, who you '
            'watch it with and anything you type stays private either way.',
            style: PTText.caption,
          ),
          PTButton(
            label: 'Show me on the board',
            icon: Symbols.trophy_rounded,
            onPressed: () => unawaited(_setPublic(true)),
          ),
        ],
      ),
    );
  }

  /// Shown when usage data is off. The alternative - a board silently frozen at
  /// whatever it last said - is how a product teaches people that its switches
  /// do nothing.
  Widget _pausedCard() {
    return GlassPanel(
      radius: 20,
      opacity: 0.5,
      borderColor: PTColors.warningBorder.withValues(alpha: 0.28),
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
      child: Column(
        crossAxisAlignment: .start,
        spacing: 10,
        children: [
          Row(
            spacing: 10,
            children: [
              const Icon(Symbols.pause_circle_rounded, size: 18, color: PTColors.warning),
              Expanded(
                child: Text('Streaks are paused', style: PTText.cardHeading.copyWith(fontSize: 16)),
              ),
            ],
          ),
          Text(
            'You turned off usage data, and streaks are built from the same records - '
            'so nothing is being counted. Your streak is held where it was, not lost. '
            'Turn sharing back on in your profile and it picks up from the next session.',
            style: PTText.caption,
          ),
          PTButton(
            label: 'Open profile settings',
            variant: .secondary,
            icon: Symbols.settings_rounded,
            onPressed: () => context.go('/lobby/profile'),
          ),
        ],
      ),
    );
  }

  Widget _board(RewardState state) {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 48),
        child: Center(child: PTLoader(size: 28)),
      );
    }

    if (_rows.isEmpty) {
      return GlassPanel(
        radius: 20,
        opacity: 0.4,
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 28),
        child: Column(
          spacing: 8,
          children: [
            Icon(Symbols.groups_rounded, size: 28, color: PTColors.white(0.35)),
            Text(
              switch (_scope) {
                .circle => 'Nobody in your circle is on the board yet',
                .global =>
                  state.globalBoard.open
                      ? 'Nothing here yet this week'
                      : 'The global board is still warming up',
              },
              textAlign: .center,
              style: PTText.body.copyWith(fontSize: 15),
            ),
            Text(
              switch (_scope) {
                .circle =>
                  'Watch something with someone, and whoever turns their profile '
                      'on will show up here.',
                .global =>
                  state.globalBoard.open
                      ? 'Watch 20 minutes with someone and you are on it.'
                      : 'It opens once enough people are playing. A board with a '
                            'handful of names on it is worse than no board.',
              },
              textAlign: .center,
              style: PTText.finePrint.copyWith(fontSize: 12),
            ),
          ],
        ),
      );
    }

    return GlassPanel(
      radius: 20,
      opacity: 0.45,
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(children: [for (final row in _rows) _BoardRow(row: row)]),
    );
  }

  Widget _scoringCard(RewardState state) {
    final band = nextStreakBand(state.streak.current);
    return GlassPanel(
      radius: 18,
      opacity: 0.35,
      shadow: false,
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      child: Column(
        crossAxisAlignment: .start,
        spacing: 8,
        children: [
          Text('How points work', style: PTText.panelHeading),
          Text(
            'One point a minute watched together, up to 240 a day. '
            '15 more for each different person you watch with, up to five. '
            '25 if a room hits four people. '
            'Then your streak multiplies the lot - '
            '${streakMultiplier(state.streak.current).toStringAsFixed(2)}x right now.',
            style: PTText.caption.copyWith(fontSize: 12.5),
          ),
          if (band != null)
            Text(
              '${band.days} more day${band.days == 1 ? '' : 's'} in a row takes you '
              'to ${band.multiplier.toStringAsFixed(2)}x.',
              style: PTText.finePrint.copyWith(fontSize: 12, color: PTColors.textAccent),
            ),
          Text(
            'Watching alone earns nothing, and neither does a room left open - '
            "this counts time you actually spent with someone.",
            style: PTText.finePrint.copyWith(fontSize: 11.5),
          ),
        ],
      ),
    );
  }

  Widget _badgeCard(RewardState state, {required bool compact}) {
    final next = nextAchievement(state.achievements, state.metrics);
    return GlassPanel(
      radius: 20,
      opacity: 0.45,
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
      child: Column(
        crossAxisAlignment: .stretch,
        spacing: 14,
        children: [
          Row(
            children: [
              Expanded(child: Text('Badges', style: PTText.panelHeading)),
              Text(
                '${state.unlocked.length} earned',
                style: PTText.finePrint.copyWith(fontSize: 12),
              ),
            ],
          ),
          if (next != null)
            Text(
              'Closest: ${next.title} - ${next.description}',
              style: PTText.finePrint.copyWith(fontSize: 12, color: PTColors.textAccent),
            ),
          if (state.seasons.isNotEmpty) SeasonTrophies(seasons: state.seasons),
          BadgeShelf(state: state, crossAxisCount: compact ? 3 : 5),
          if (state.publicProfile) _profileLink(state),
        ],
      ),
    );
  }

  Widget _profileLink(RewardState state) {
    final handle = state.handle;
    if (handle == null) {
      return Text(
        state.isPremium
            ? 'Pick a handle in your profile and your badges get a page you can link to.'
            : 'Premium gets you a handle, and a page of badges you can link to. '
                  'Your rank here works either way.',
        style: PTText.finePrint.copyWith(fontSize: 11.5),
      );
    }
    final url = profileUrl(handle);
    return PTButton(
      label: 'Share my profile',
      icon: Symbols.ios_share_rounded,
      variant: .secondary,
      onPressed: () async {
        Analytics.instance.track('profile_shared', {'surface': 'leaderboard'});
        await Clipboard.setData(ClipboardData(text: url));
        if (mounted) showPTSnack(context, 'Link copied.', kind: .success);
        await launchUrl(Uri.parse(url), mode: .externalApplication);
      },
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({
    required this.label,
    required this.value,
    required this.suffix,
    required this.icon,
    required this.tint,
  });

  final String label;
  final String value;
  final String suffix;
  final IconData icon;
  final Color tint;

  @override
  Widget build(BuildContext context) {
    return Column(
      spacing: 3,
      children: [
        Icon(icon, size: 17, fill: 1, color: tint),
        FittedBox(
          fit: .scaleDown,
          child: Text(value, style: PTText.cardHeading.copyWith(fontSize: 19)),
        ),
        Text(
          '$label · $suffix',
          maxLines: 1,
          overflow: .ellipsis,
          style: PTText.finePrint.copyWith(fontSize: 10.5),
        ),
      ],
    );
  }
}

class _Tab extends StatelessWidget {
  const _Tab({required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return PTPressable(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 11),
        alignment: .center,
        decoration: BoxDecoration(
          color: selected ? PTColors.primary.withValues(alpha: 0.18) : PTColors.white(0.04),
          border: Border.all(
            color: selected ? PTColors.primary.withValues(alpha: 0.5) : PTColors.white(0.08),
          ),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Text(
          label,
          maxLines: 1,
          overflow: .ellipsis,
          style: PTText.body.copyWith(
            fontSize: 14,
            fontWeight: .w600,
            color: selected ? PTColors.textAccent : PTColors.white(0.6),
          ),
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return PTPressable(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? PTColors.white(0.1) : Colors.transparent,
          border: Border.all(color: PTColors.white(selected ? 0.18 : 0.07)),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          label,
          style: PTText.finePrint.copyWith(
            fontSize: 12,
            fontWeight: .w600,
            color: PTColors.white(selected ? 0.9 : 0.5),
          ),
        ),
      ),
    );
  }
}

class _BoardRow extends StatelessWidget {
  const _BoardRow({required this.row});

  final LeaderboardRow row;

  @override
  Widget build(BuildContext context) {
    final medal = switch (row.rank) {
      1 => PTColors.premium,
      2 => PTColors.silver,
      3 => PTColors.bronze,
      _ => null,
    };
    // Below ~360 logical px (before text scaling) the streak column starves
    // the name to a few letters, so it folds into the subtitle line instead.
    return LayoutBuilder(
      builder: (context, box) {
        final compact = box.maxWidth < MediaQuery.textScalerOf(context).scale(360);
        return _build(medal, compact);
      },
    );
  }

  Widget _streak() => Row(
    mainAxisSize: .min,
    spacing: 3,
    children: [
      const Icon(Symbols.local_fire_department_rounded, size: 14, fill: 1, color: PTColors.streak),
      Text(
        '${row.streak}',
        style: PTText.finePrint.copyWith(fontSize: 12, color: PTColors.white(0.7)),
      ),
    ],
  );

  Widget _build(Color? medal, bool compact) {
    final watched = Text(
      '${formatWatchHours(row.watched)} watched',
      maxLines: 1,
      overflow: .ellipsis,
      style: PTText.finePrint.copyWith(fontSize: 11),
    );
    return Container(
      padding: EdgeInsets.symmetric(horizontal: compact ? 12 : 16, vertical: 10),
      decoration: BoxDecoration(
        color: row.isMe ? PTColors.primary.withValues(alpha: 0.12) : Colors.transparent,
        border: row.isMe
            ? Border(left: BorderSide(color: PTColors.primary.withValues(alpha: 0.8), width: 3))
            : null,
      ),
      child: Row(
        spacing: compact ? 10 : 12,
        children: [
          SizedBox(
            width: compact ? 20 : 26,
            child: FittedBox(
              fit: .scaleDown,
              child: Text(
                '${row.rank}',
                textAlign: .center,
                style: PTText.body.copyWith(
                  fontFamily: PTFonts.mono,
                  fontSize: 13,
                  fontWeight: .w600,
                  color: medal ?? PTColors.white(0.45),
                ),
              ),
            ),
          ),
          PTAvatar(
            userId: row.userId,
            displayName: row.displayName,
            avatarUrl: row.avatarUrl,
            premium: row.isPremium,
            frame: row.frame,
            size: 34,
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: .start,
              children: [
                Text(
                  row.isMe ? '${row.displayName} (you)' : row.displayName,
                  maxLines: 1,
                  overflow: .ellipsis,
                  style: PTText.body.copyWith(fontSize: 14, fontWeight: .w600),
                ),
                if (compact && row.streak > 0)
                  Row(
                    spacing: 8,
                    children: [
                      _streak(),
                      Flexible(child: watched),
                    ],
                  )
                else
                  watched,
              ],
            ),
          ),
          if (!compact && row.streak > 0) _streak(),
          SizedBox(
            width: compact ? 48 : 56,
            child: FittedBox(
              fit: .scaleDown,
              alignment: .centerRight,
              child: Text(
                formatPoints(row.points),
                textAlign: .right,
                style: PTText.body.copyWith(
                  fontFamily: PTFonts.mono,
                  fontSize: 13,
                  fontWeight: .w600,
                  color: PTColors.textAccent,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
