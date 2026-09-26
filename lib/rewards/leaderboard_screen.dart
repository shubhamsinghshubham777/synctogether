import 'dart:async';
import '../ui/booth_icons.g.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:url_launcher/url_launcher.dart';

import '../analytics.dart';
import '../analytics_consent.dart';
import '../auth/auth_service.dart';
import '../ui/banners.dart';
import '../ui/booth.dart';
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
    final state = RewardsService.instance.state;
    // Either prompt counts: the guest sign-in note or the Patron card.
    if (!state.isGuest && !_showPatronCard(state)) return;
    _upsellTracked = true;
    Analytics.instance.track('upgrade_cta_shown', {'surface': 'leaderboard'});
  }

  /// How far behind the top of the shown board you are, and who is there -
  /// null when you lead it, are not on it, or it has not loaded.
  (int, String)? get _gapToFirst {
    if (_rows.length < 2) return null;
    final me = _rows.where((r) => r.isMe).firstOrNull;
    if (me == null || me.rank == 1) return null;
    final first = _rows.first;
    return (first.points - me.points, first.displayName.split(' ').first);
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

  /// The rows deal in once per visit. A tab or period change swaps the board
  /// in place - replaying the stagger on every switch would make the board
  /// feel slower each time it is used.
  bool _boardDealt = false;

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
              // Phone landscape is 390 tall: the compact header, not the 48 px
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
    final gutter = compact ? 20.0 : 48.0;
    // Edge-to-edge: the page scrolls under the home indicator / nav bar, and
    // the bottom inset pads the content so its last item still clears it.
    return SafeArea(
      bottom: false,
      child: Column(
        children: [
          Padding(
            padding: compact
                ? const EdgeInsets.fromLTRB(20, 10, 20, 0)
                : const EdgeInsets.fromLTRB(48, 28, 48, 0),
            child: Row(
              spacing: 14,
              children: [
                PTIconButton(
                  icon: BoothIcons.arrowBack,
                  iconSize: 20,
                  size: compact ? 44 : 42,
                  onPressed: () => context.go('/lobby'),
                ),
                Expanded(
                  child: Text('LEADERBOARD', maxLines: 1, overflow: .ellipsis, style: PTText.label),
                ),
                // Consent, handle and frame all live in the profile.
                TextButton(
                  onPressed: () => context.go('/lobby/profile'),
                  style: TextButton.styleFrom(
                    foregroundColor: PTColors.white(0.7),
                    textStyle: PTText.caption.copyWith(decoration: TextDecoration.underline),
                  ),
                  child: Text(compact ? 'Settings' : 'Leaderboard settings'),
                ),
              ],
            ),
          ),
          Expanded(
            child: ScrollFadeEdge(
              child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(
                  gutter,
                  compact ? 18 : 28,
                  gutter,
                  48 + MediaQuery.paddingOf(context).bottom,
                ),
                child: LayoutBuilder(
                  builder: (context, box) {
                    // Two columns only where the aside can be a real column
                    // beside a board that still reads as a list.
                    final wide = !compact && box.maxWidth >= 900;
                    return Center(
                      child: ConstrainedBox(
                        constraints: BoxConstraints(maxWidth: wide ? 1080 : 620),
                        child: wide ? _wide(state) : _single(state, compact: compact),
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _lead(RewardState state, {required bool compact}) => [
    _masthead(state, compact: compact),
    SizedBox(height: compact ? 22 : 32),
    _standing(state, compact: compact),
    SizedBox(height: compact ? 26 : 36),
  ];

  List<Widget> _boardColumn(RewardState state) => [
    _controls(state),
    const SizedBox(height: 18),
    if (AnalyticsConsent.instance.optedOut) ...[
      _pausedNote(),
      const SizedBox(height: 22),
    ] else if (!state.publicProfile) ...[
      _consentNote(state),
      const SizedBox(height: 22),
    ],
    _board(state),
  ];

  Widget _single(RewardState state, {required bool compact}) {
    return Column(
      crossAxisAlignment: .stretch,
      children: [
        ..._lead(state, compact: compact),
        ..._boardColumn(state),
        const SizedBox(height: 40),
        _scoring(state),
        const SizedBox(height: 40),
        _badges(state),
      ],
    );
  }

  Widget _wide(RewardState state) {
    return Column(
      crossAxisAlignment: .stretch,
      children: [
        ..._lead(state, compact: false),
        Row(
          crossAxisAlignment: .start,
          children: [
            Expanded(
              child: Column(crossAxisAlignment: .stretch, children: _boardColumn(state)),
            ),
            const SizedBox(width: 56),
            // The aside: typeset alongside the board, separated by a rule
            // rather than boxed.
            Container(
              width: MediaQuery.textScalerOf(context).scale(320).clamp(320, 440),
              padding: const EdgeInsets.only(left: 28),
              decoration: const BoxDecoration(
                border: Border(left: BorderSide(color: PTColors.aisle)),
              ),
              child: Column(
                crossAxisAlignment: .stretch,
                children: [_scoring(state), const SizedBox(height: 40), _badges(state)],
              ),
            ),
          ],
        ),
      ],
    );
  }

  /// The headline names the board. When the global board is closed the scope
  /// control is absent altogether and this line carries the promise instead.
  Widget _masthead(RewardState state, {required bool compact}) {
    final open = state.globalBoard.open;
    return Column(
      crossAxisAlignment: .start,
      spacing: 10,
      children: [
        MediaQuery.withClampedTextScaling(
          maxScaleFactor: 1.4,
          child: Text(
            _scope == .circle ? 'Your circle.' : 'The board.',
            style: PTText.display.copyWith(
              fontSize: compact ? 40 : 64,
              letterSpacing: compact ? -1.2 : -2.2,
              height: 0.95,
            ),
          ),
        ),
        Text(
          state.isGuest
              ? 'Take a seat with an account and your streak starts counting.'
              : open
              ? 'Ranked by points: the people you watch with, or everyone playing.'
              : 'A board for everyone opens once enough people are playing. '
                    'Until then this one is yours and the people you watch with.',
          style: PTText.caption.copyWith(fontSize: compact ? 13 : 14),
        ),
      ],
    );
  }

  /// Your own standing, set as figures rather than tiles. A guest cannot hold
  /// a streak, so theirs renders dimmed rather than missing - the same rule as
  /// the lobby's streak chip.
  Widget _standing(RewardState state, {required bool compact}) {
    final rank = _scope == .circle ? state.circleRank : state.weekRank;
    final days = state.streak.current;
    final lit = !state.isGuest && days > 0;
    final toFirst = compact ? null : _gapToFirst;
    final figure = PTText.display.copyWith(fontSize: compact ? 44 : 64, letterSpacing: -2);
    Widget block(String label, Widget value) => Column(
      crossAxisAlignment: .start,
      mainAxisSize: .min,
      spacing: 6,
      children: [
        Text(label, maxLines: 1, overflow: .ellipsis, style: PTText.label),
        MediaQuery.withClampedTextScaling(
          maxScaleFactor: 1.3,
          child: FittedBox(fit: .scaleDown, alignment: .centerLeft, child: value),
        ),
      ],
    );
    final stampSize = compact ? 76.0 : 96.0;
    return Opacity(
      opacity: state.isGuest ? 0.45 : 1,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 18),
        decoration: const BoxDecoration(
          border: Border.symmetric(horizontal: BorderSide(color: PTColors.aisle)),
        ),
        child: Row(
          crossAxisAlignment: .center,
          spacing: compact ? 16 : 36,
          children: [
            PTStamp(
              size: stampSize,
              color: lit ? PTColors.streak : PTColors.rail,
              animate: lit,
              child: Padding(
                padding: EdgeInsets.all(stampSize * 0.14),
                child: MediaQuery.withClampedTextScaling(
                  maxScaleFactor: 1,
                  child: FittedBox(
                    child: Column(
                      mainAxisSize: .min,
                      children: [
                        Text(
                          '$days',
                          style: PTText.display.copyWith(
                            fontSize: 30,
                            color: lit ? PTColors.streak : PTColors.away,
                          ),
                        ),
                        Text(
                          days == 1 ? 'DAY' : 'DAYS',
                          style: PTText.label.copyWith(
                            fontSize: 9,
                            color: lit ? PTColors.streak : PTColors.away,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            Expanded(
              child: block(
                compact ? 'RANK' : 'RANK · ${_scope == .circle ? 'CIRCLE' : 'EVERYONE'}',
                Text(rankOrdinal(rank), style: figure),
              ),
            ),
            Expanded(
              child: block(
                compact ? 'WEEK' : 'THIS WEEK',
                Row(
                  mainAxisSize: .min,
                  crossAxisAlignment: .baseline,
                  textBaseline: .alphabetic,
                  spacing: 6,
                  children: [
                    Text(formatPoints(state.points.week), style: figure),
                    Text('pts', style: PTText.mono.copyWith(fontSize: compact ? 13 : 15)),
                  ],
                ),
              ),
            ),
            if (toFirst != null)
              Expanded(
                child: block(
                  'TO FIRST',
                  Row(
                    mainAxisSize: .min,
                    crossAxisAlignment: .baseline,
                    textBaseline: .alphabetic,
                    spacing: 8,
                    children: [
                      Text(
                        formatPoints(toFirst.$1),
                        style: figure.copyWith(color: PTColors.white(0.7)),
                      ),
                      Text('pts behind ${toFirst.$2}', style: PTText.mono.copyWith(fontSize: 15)),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// Flat, underlined text controls - pills are for people. The scope row is
  /// absent, not empty, until the global board is real: a tab that always says
  /// "warming up" is a dead tab, and with a young product it would say that
  /// for months.
  Widget _controls(RewardState state) {
    final open = state.globalBoard.open;
    return Container(
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: PTColors.aisle)),
      ),
      child: Row(
        crossAxisAlignment: .end,
        children: [
          if (open)
            Flexible(
              child: Row(
                mainAxisSize: .min,
                spacing: 20,
                children: [
                  for (final scope in LeaderboardScope.values)
                    Flexible(
                      child: _UnderlineTab(
                        label: scope.title,
                        selected: _scope == scope,
                        onTap: () => _setScope(scope),
                      ),
                    ),
                ],
              ),
            ),
          if (open) const Spacer(),
          Flexible(
            child: Row(
              mainAxisSize: .min,
              spacing: 20,
              children: [
                for (final period in LeaderboardPeriod.values)
                  Flexible(
                    child: _UnderlineTab(
                      label: switch (period) {
                        .week => 'WEEK',
                        .month => 'MONTH',
                        .all => 'ALL TIME',
                      },
                      mono: true,
                      selected: _period == period,
                      onTap: () => _setPeriod(period),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Consent is asked here, in context, the first time somebody opens the board -
  /// not buried in settings, and never assumed. The copy states exactly what
  /// becomes public, because a leaderboard is a change to a product that
  /// advertises itself as ad-free with no ad trackers, and analytics you can switch off.
  Widget _consentNote(RewardState state) {
    if (state.isGuest) {
      return _Note(
        rule: PTColors.primary,
        title: 'Streaks need an account',
        body:
            'Guest sessions are wiped after a few days, so a streak held on one '
            'would not survive the week. Sign in and it starts counting, same '
            'session, same rooms, nothing to move.',
        action: GoogleButton(
          label: 'Sign in with Google',
          onPressed: () {
            Analytics.instance.track('upgrade_cta_clicked', {
              'surface': 'leaderboard',
              'action': 'sign_in',
            });
            unawaited(AuthService.instance.linkGoogleIdentity());
          },
        ),
      );
    }
    return _Note(
      rule: PTColors.primary,
      title: 'Join the board',
      body:
          'Turning this on shows your name, avatar, streak and rank to people '
          'you watch with, and on the public board. What you watch, who you '
          'watch it with and anything you type stays private either way.',
      action: PTButton(
        label: 'Show me on the board',
        icon: BoothIcons.trophy,
        expand: false,
        onPressed: () => unawaited(_setPublic(true)),
      ),
    );
  }

  /// Shown when usage data is off. The alternative - a board silently frozen at
  /// whatever it last said - is how a product teaches people that its switches
  /// do nothing.
  Widget _pausedNote() {
    return _Note(
      rule: PTColors.warning,
      title: 'Streaks are paused',
      body:
          'You turned off usage data, and streaks are built from the same records, '
          'so nothing is being counted. Your streak is held where it was, not lost. '
          'Turn sharing back on in your profile and it picks up from the next session.',
      action: PTButton(
        label: 'Open profile settings',
        variant: .secondary,
        icon: Symbols.settings_rounded,
        expand: false,
        onPressed: () => context.go('/lobby/profile'),
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
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 32),
        child: Column(
          crossAxisAlignment: .start,
          spacing: 8,
          children: [
            Text(switch (_scope) {
              .circle => 'Nobody in your circle is on the board yet',
              .global =>
                state.globalBoard.open
                    ? 'Nothing here yet this week'
                    : 'The global board is still warming up',
            }, style: PTText.cardHeading.copyWith(fontSize: 18)),
            Text(switch (_scope) {
              .circle =>
                'Watch something with someone, and whoever turns their profile '
                    'on will show up here.',
              .global =>
                state.globalBoard.open
                    ? 'Watch 20 minutes with someone and you are on it.'
                    : 'It opens once enough people are playing. A board with a '
                          'handful of names on it is worse than no board.',
            }, style: PTText.caption),
          ],
        ),
      );
    }

    final deal = !_boardDealt;
    if (deal) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _boardDealt = true);
    }
    // Rows deal in top-down, capped so a long board still lands quickly.
    final head = PTText.label.copyWith(fontSize: 10);
    return Column(
      crossAxisAlignment: .stretch,
      children: [
        LayoutBuilder(
          builder: (context, box) {
            // Same breakpoint as the rows: below it the streak folds into the
            // subtitle and there is no column to head.
            if (box.maxWidth < MediaQuery.textScalerOf(context).scale(360)) {
              return const SizedBox.shrink();
            }
            return Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 12, 8),
              child: Row(
                spacing: 14,
                children: [
                  SizedBox(width: 36, child: Text('#', style: head)),
                  Expanded(child: Text('WATCHER', style: head)),
                  SizedBox(
                    width: 64,
                    child: Text('STREAK', textAlign: .end, style: head),
                  ),
                  SizedBox(
                    width: 72,
                    child: Text('POINTS', textAlign: .end, style: head),
                  ),
                ],
              ),
            );
          },
        ),
        for (final (i, row) in _rows.indexed)
          PTEntrance(
            key: ValueKey(row.userId),
            enabled: deal,
            delay: Duration(milliseconds: 30 * (i < 10 ? i : 10)),
            duration: PTMotion.state,
            offset: 6,
            child: _BoardRow(row: row),
          ),
        Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Text(switch (_period) {
            // reward_period_start truncates to the ISO week, in UTC.
            .week => 'Resets Monday (UTC). Only people who turned their profile on appear here.',
            .month =>
              'Resets on the 1st (UTC). Only people who turned their profile on appear here.',
            .all => 'Only people who turned their profile on appear here.',
          }, style: PTText.finePrint.copyWith(fontSize: 12)),
        ),
        if (_showPatronCard(state)) ...[const SizedBox(height: 20), _patronCard()],
      ],
    );
  }

  /// Free, on the board, no handle: the one thing a Patron seat adds here.
  bool _showPatronCard(RewardState state) =>
      !state.isGuest && !state.isPremium && state.publicProfile && state.handle == null;

  Widget _patronCard() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        border: Border.all(color: PTColors.premiumBorder),
        borderRadius: BorderRadius.circular(PTRadius.panel),
      ),
      child: Column(
        crossAxisAlignment: .stretch,
        spacing: 10,
        children: [
          Row(
            spacing: 8,
            children: [
              const Icon(BoothIcons.crown, size: 14, color: PTColors.premium),
              Text('PATRON', style: PTText.label.copyWith(color: PTColors.premium)),
            ],
          ),
          Text(
            'Patrons get a handle, and a page of badges you can link to. '
            'Your rank here works either way.',
            style: PTText.body.copyWith(fontSize: 14, height: 1.45),
          ),
          PTButton(
            label: 'Get a Patron seat',
            variant: .secondary,
            height: 40,
            onPressed: () {
              Analytics.instance.track('upgrade_cta_clicked', {
                'surface': 'leaderboard',
                'action': 'subscribe',
              });
              context.go('/lobby/subscribe?source=leaderboard');
            },
          ),
        ],
      ),
    );
  }

  /// The formula is published on the board itself, so it is typeset as a
  /// ledger: every term and every cap on its own line.
  Widget _scoring(RewardState state) {
    final band = nextStreakBand(state.streak.current);
    final multiplier = streakMultiplier(state.streak.current).toStringAsFixed(2);
    return Column(
      crossAxisAlignment: .stretch,
      spacing: 10,
      children: [
        Text('HOW POINTS WORK', style: PTText.label),
        const SizedBox(height: 2),
        const _Term(figure: '1', text: 'point a minute watched together, up to 240 a day.'),
        const _Term(figure: '+15', text: 'for each different person you watch with, up to five.'),
        const _Term(figure: '+25', text: 'if a room hits four people.'),
        _Term(
          figure: '${multiplier}x',
          text: 'then your streak multiplies the lot. That is you, right now.',
          color: PTColors.streak,
        ),
        if (band != null)
          Text(
            '${band.days} more day${band.days == 1 ? '' : 's'} in a row takes you '
            'to ${band.multiplier.toStringAsFixed(2)}x.',
            style: PTText.caption.copyWith(fontSize: 12.5, color: PTColors.fg),
          ),
        Text(
          'Watching alone earns nothing, and neither does a room left open. '
          "This counts time you actually spent with someone.",
          style: PTText.finePrint.copyWith(fontSize: 11.5),
        ),
      ],
    );
  }

  Widget _badges(RewardState state) {
    final next = nextAchievement(state.achievements, state.metrics);
    return Column(
      crossAxisAlignment: .stretch,
      spacing: 14,
      children: [
        Row(
          children: [
            Expanded(child: Text('BADGES', style: PTText.label)),
            Text('${state.unlocked.length} earned', style: PTText.mono.copyWith(fontSize: 12)),
          ],
        ),
        if (next != null)
          Text(
            'Closest: ${next.title} · ${next.description}',
            style: PTText.caption.copyWith(fontSize: 12.5),
          ),
        if (state.seasons.isNotEmpty) SeasonTrophies(seasons: state.seasons),
        BadgeShelf(state: state, showLabels: false),
        if (state.publicProfile) _profileLink(state),
      ],
    );
  }

  Widget _profileLink(RewardState state) {
    final handle = state.handle;
    if (handle == null) {
      // The free-tier version of this line is the Patron card under the board.
      if (!state.isPremium) return const SizedBox.shrink();
      return Text(
        'Pick a handle in your profile and your badges get a page you can link to.',
        style: PTText.finePrint.copyWith(fontSize: 11.5),
      );
    }
    final url = profileUrl(handle);
    return PTButton(
      label: 'Share my profile',
      icon: BoothIcons.share,
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

/// A notice set as a ruled paragraph rather than a boxed card.
class _Note extends StatelessWidget {
  const _Note({required this.rule, required this.title, required this.body, required this.action});

  final Color rule;
  final String title;
  final String body;
  final Widget action;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.only(left: 16, top: 2, bottom: 2),
      decoration: BoxDecoration(
        border: Border(left: BorderSide(color: rule, width: 2)),
      ),
      child: Column(
        crossAxisAlignment: .start,
        spacing: 10,
        children: [
          Text(title, style: PTText.cardHeading.copyWith(fontSize: 17)),
          Text(body, style: PTText.caption),
          const SizedBox(height: 2),
          action,
        ],
      ),
    );
  }
}

/// One line of the points ledger: the figure in mono, the rule beside it.
class _Term extends StatelessWidget {
  const _Term({required this.figure, required this.text, this.color = PTColors.fg});

  final String figure;
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: .baseline,
      textBaseline: .alphabetic,
      spacing: 12,
      children: [
        SizedBox(
          width: MediaQuery.textScalerOf(context).scale(44).clamp(44, 64),
          child: Text(
            figure,
            textAlign: .right,
            style: PTText.mono.copyWith(fontSize: 14, fontWeight: .w600, color: color),
          ),
        ),
        Expanded(child: Text(text, style: PTText.caption.copyWith(fontSize: 13))),
      ],
    );
  }
}

class _UnderlineTab extends StatelessWidget {
  const _UnderlineTab({
    required this.label,
    required this.selected,
    required this.onTap,
    this.mono = false,
  });

  final String label;
  final bool selected;
  final bool mono;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final style = mono
        ? PTText.label.copyWith(color: selected ? PTColors.fg : PTColors.white(0.45))
        : PTText.body.copyWith(
            fontSize: 15,
            fontWeight: .w600,
            color: selected ? PTColors.fg : PTColors.white(0.5),
          );
    return Semantics(
      selected: selected,
      button: true,
      child: PTPressable(
        onTap: onTap,
        child: AnimatedContainer(
          duration: PTMotion.hover,
          padding: const EdgeInsets.only(top: 12, bottom: 10),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: selected ? PTColors.fg : PTColors.fg.withValues(alpha: 0),
                width: 2,
              ),
            ),
          ),
          child: Text(label, maxLines: 1, overflow: .ellipsis, style: style),
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
    // Below ~360 logical px (before text scaling) the streak column starves
    // the name to a few letters, so it folds into the subtitle line instead.
    return LayoutBuilder(
      builder: (context, box) {
        final compact = box.maxWidth < MediaQuery.textScalerOf(context).scale(360);
        return _build(compact);
      },
    );
  }

  Widget _streak() => Row(
    mainAxisSize: .min,
    spacing: 3,
    children: [
      const Icon(BoothIcons.fire, size: 14, fill: 1, color: PTColors.streak),
      Text('${row.streak}', style: PTText.mono.copyWith(fontSize: 12)),
    ],
  );

  Widget _build(bool compact) {
    // The podium: the top three set their rank as a display numeral in the
    // medal's colour, a touch more air, a bigger seat. Everyone else is mono.
    final medal = switch (row.rank) {
      1 => PTColors.premium,
      2 => PTColors.silver,
      3 => PTColors.bronze,
      _ => null,
    };
    final podium = medal != null;
    final watched = Text(
      '${formatWatchHours(row.watched)} watched',
      maxLines: 1,
      overflow: .ellipsis,
      style: PTText.finePrint.copyWith(fontSize: 11.5),
    );
    return Container(
      padding: EdgeInsets.fromLTRB(
        compact ? 8 : 12,
        podium ? 14 : 10,
        compact ? 8 : 12,
        podium ? 14 : 10,
      ),
      decoration: BoxDecoration(
        color: row.isMe ? PTColors.glassBase : null,
        border: Border(
          left: BorderSide(
            color: row.isMe ? PTColors.primary : PTColors.primary.withValues(alpha: 0),
            width: 2,
          ),
          bottom: const BorderSide(color: PTColors.aisle),
        ),
      ),
      child: Row(
        spacing: compact ? 10 : 14,
        children: [
          SizedBox(
            width: compact ? 26 : 36,
            child: FittedBox(
              fit: .scaleDown,
              alignment: .centerLeft,
              child: Text(
                podium ? '${row.rank}' : row.rank.toString().padLeft(2, '0'),
                style: podium
                    ? PTText.display.copyWith(fontSize: 28, letterSpacing: -1, color: medal)
                    : PTText.mono.copyWith(fontSize: 13, color: PTColors.white(0.45)),
              ),
            ),
          ),
          // A fixed seat keeps every name on one column whatever the size.
          SizedBox(
            width: 40,
            child: Center(
              child: PTAvatar(
                userId: row.userId,
                displayName: row.displayName,
                avatarUrl: row.avatarUrl,
                premium: row.isPremium,
                frame: row.frame,
                size: podium ? 40 : 32,
              ),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: .start,
              spacing: 1,
              children: [
                Text(
                  row.isMe ? '${row.displayName} (you)' : row.displayName,
                  maxLines: 1,
                  overflow: .ellipsis,
                  style: PTText.body.copyWith(
                    fontSize: podium ? 15.5 : 14.5,
                    fontWeight: .w600,
                    color: PTColors.fg,
                  ),
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
          if (!compact)
            SizedBox(
              width: 64,
              child: Align(
                alignment: .centerRight,
                child: row.streak > 0 ? _streak() : const SizedBox.shrink(),
              ),
            ),
          SizedBox(
            width: compact ? 52 : 72,
            child: FittedBox(
              fit: .scaleDown,
              alignment: .centerRight,
              child: Text(
                formatPoints(row.points),
                textAlign: .right,
                style: PTText.mono.copyWith(
                  fontSize: podium ? 15 : 13,
                  fontWeight: .w600,
                  color: PTColors.fg,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
