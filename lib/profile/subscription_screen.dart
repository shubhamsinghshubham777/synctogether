import 'dart:async';
import '../ui/booth_icons.g.dart';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:synctogether/analytics.dart';
import 'package:synctogether/diagnostics.dart';
import 'package:synctogether/platform.dart';
import 'package:synctogether/profile/apple_iap_service.dart';
import 'package:synctogether/profile/entitlement_service.dart';
import 'package:synctogether/profile/profile_service.dart';
import 'package:synctogether/ui/banners.dart';
import 'package:synctogether/ui/buttons.dart';
import 'package:synctogether/ui/glass.dart';
import 'package:synctogether/ui/booth.dart';
import 'package:synctogether/ui/loader.dart';
import 'package:synctogether/ui/pt_motion.dart';
import 'package:synctogether/ui/pt_theme.dart';
import 'package:synctogether/ui/responsive.dart';
import 'package:url_launcher/url_launcher.dart';

String get checkoutUrl =>
    kDebugMode ? 'http://localhost:3000/premium' : 'https://synctogether.app/premium';

String get accountUrl =>
    kDebugMode ? 'http://localhost:3000/account' : 'https://synctogether.app/account';

// Guideline 3.1.2 requires both beside an auto-renewing subscription offer.
const _termsUrl = 'https://synctogether.app/terms';
const _privacyUrl = 'https://synctogether.app/privacy';

class SubscriptionScreen extends StatefulWidget {
  const SubscriptionScreen({
    super.key,
    this.source,
    this.desktopOverride,
    this.storeBuildOverride,
    this.appleStoreBuildOverride,
    this.demoState,
  });

  final String? source;
  final bool? desktopOverride;
  final bool? storeBuildOverride;
  final bool? appleStoreBuildOverride;

  /// Demo builds only (`?state=` on the route, see app_router.dart): opens
  /// straight into `verifying` or `activated`, which otherwise need a real
  /// checkout round-trip. Null in every release build.
  final String? demoState;

  @override
  State<SubscriptionScreen> createState() => _SubscriptionScreenState();
}

class _SubscriptionScreenState extends State<SubscriptionScreen> with WidgetsBindingObserver {
  bool _awaitingCheckout = false;
  bool _verifying = false;
  bool _celebrating = false;
  StreamSubscription<AppleIapNotice>? _iapNotices;

  bool get _isDesktop => widget.desktopOverride ?? isDesktop;
  bool get _isStore => widget.storeBuildOverride ?? isStoreBuild;
  bool get _isAppleStore => widget.appleStoreBuildOverride ?? isAppleStoreBuild;
  bool get _canShowCheckout => _isDesktop && !_isStore;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    Analytics.instance.track('subscription_screen_viewed', {'source': widget.source ?? 'direct'});
    _verifying = widget.demoState == 'verifying';
    _celebrating = widget.demoState == 'activated';
    if (_isAppleStore) {
      _iapNotices = AppleIapService.instance.notices.listen(_onIapNotice);
      AppleIapService.instance.loadProducts();
    }
  }

  @override
  void dispose() {
    _iapNotices?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _awaitingCheckout && !_verifying && !_celebrating) {
      _pollForSubscription();
    }
  }

  Future<void> _openCheckout() async {
    Analytics.instance.track('checkout_opened', {'source': widget.source ?? 'direct'});
    setState(() => _awaitingCheckout = true);
    final uri = Uri.parse(checkoutUrl);
    try {
      final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!launched && mounted) {
        showPTSnack(context, "Couldn't open browser. Please visit synctogether.app/premium");
      }
    } catch (e, s) {
      reportNonFatal(e, s, during: 'launching checkout url');
      if (mounted) {
        showPTSnack(context, "Couldn't open browser. Please visit synctogether.app/premium");
      }
    }
  }

  void _onIapNotice(AppleIapNotice notice) {
    if (!mounted) return;
    switch (notice) {
      case .activated:
        if (_celebrating) return;
        setState(() => _celebrating = true);
        Analytics.instance.track('purchase_confirmed');
      case .nothingToRestore:
        showPTSnack(context, 'No App Store subscription found for this Apple ID.');
      case .ownedElsewhere:
        showPTSnack(
          context,
          "This Apple ID's subscription is already linked to a different SyncTogether account.",
        );
      case .failed:
        showPTSnack(context, "Hmm, the App Store purchase didn't go through. Please try again.");
    }
  }

  void _buyOnAppStore(ProductDetails product) {
    Analytics.instance.track('app_store_purchase_started', {
      'source': widget.source ?? 'direct',
      'plan': product.id == kAppleAnnualProductId ? 'annual' : 'monthly',
    });
    AppleIapService.instance.buy(product);
  }

  Future<void> _openUrl(String url) async {
    try {
      final launched = await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
      if (!launched && mounted) showPTSnack(context, "Couldn't open that link. Please try again.");
    } catch (e, s) {
      reportNonFatal(e, s, during: 'launching $url');
      if (mounted) showPTSnack(context, "Couldn't open that link. Please try again.");
    }
  }

  Future<void> _openAccount() async {
    final uri = Uri.parse(accountUrl);
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (e, s) {
      reportNonFatal(e, s, during: 'launching account url');
      if (mounted) {
        showPTSnack(context, "Couldn't open browser. Please visit synctogether.app/account");
      }
    }
  }

  Future<void> _pollForSubscription() async {
    setState(() => _verifying = true);
    for (var attempt = 1; attempt <= 3; attempt++) {
      if (!mounted) return;
      try {
        final updated = await EntitlementService.instance.refresh();
        if (updated?.isPremium == true) {
          if (mounted) {
            setState(() {
              _verifying = false;
              _awaitingCheckout = false;
              _celebrating = true;
            });
            Analytics.instance.track('purchase_confirmed');
          }
          return;
        }
      } catch (e, s) {
        reportNonFatal(e, s, during: 'polling subscription status');
      }
      if (attempt < 3) {
        await Future<void>.delayed(const Duration(seconds: 3));
      }
    }
    if (mounted) {
      setState(() {
        _verifying = false;
        _awaitingCheckout = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: AmbientBackground(
        child: ListenableBuilder(
          listenable: Listenable.merge([
            ProfileService.instance,
            EntitlementService.instance,
            AppleIapService.instance,
          ]),
          builder: (context, _) {
            return PTResponsive(
              desktop: (_) => _layout(compact: false),
              portrait: (_) => _layout(compact: true),
              landscape: (_) => _layout(compact: true),
            );
          },
        ),
      ),
    );
  }

  /// An editorial page rather than a card: the pitch on the left, the offer
  /// (a paper ticket and the one lit button) on the right, folding to one
  /// column below [_twoColumnMin]. Everything scrolls, so the App Store legal
  /// copy (3.1.2) can never be clipped - only pushed below the fold.
  static const _twoColumnMin = 860.0;

  /// Phones keep the web checkout in reach: the button docks to the bottom
  /// edge with the legal links, instead of sitting below a long table.
  bool _stickyCta(bool compact) =>
      compact &&
      _canShowCheckout &&
      !EntitlementService.instance.isPremium &&
      !_celebrating &&
      !_verifying;

  Widget _layout({required bool compact}) {
    final gutter = compact ? 16.0 : 48.0;
    final sticky = _stickyCta(compact);
    // Edge-to-edge: the page scrolls under the home indicator / nav bar, and
    // the bottom inset pads the content so its last item still clears it.
    return SafeArea(
      bottom: false,
      child: Column(
        crossAxisAlignment: .stretch,
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(gutter, compact ? 10 : 24, gutter, 0),
            child: _backHeader(compact: compact),
          ),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final wide = constraints.maxWidth >= _twoColumnMin;
                return SingleChildScrollView(
                  padding: EdgeInsets.fromLTRB(
                    gutter,
                    compact ? 20 : 40,
                    gutter,
                    sticky ? 24 : 48 + MediaQuery.paddingOf(context).bottom,
                  ),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: BoxConstraints(maxWidth: wide ? 1120 : 560),
                      child: _celebrating
                          ? _celebrationBody(compact: compact)
                          : wide
                          ? Row(
                              crossAxisAlignment: .start,
                              spacing: 72,
                              children: [
                                Expanded(child: _pitch(compact: false)),
                                SizedBox(width: 380, child: _offer()),
                              ],
                            )
                          : compact
                          // Phones lead with the ticket - it is the thing
                          // being sold - then the perks, as the board does.
                          ? Column(
                              crossAxisAlignment: .stretch,
                              spacing: 24,
                              children: [
                                _pitch(compact: true, withComparison: false),
                                _ticket(isPremium: EntitlementService.instance.isPremium),
                                if (EntitlementService.instance.isPremium)
                                  _heldChecks()
                                else
                                  _comparison(compact: true),
                                _offer(sticky: sticky, withTicket: false),
                              ],
                            )
                          : Column(
                              crossAxisAlignment: .stretch,
                              spacing: 36,
                              children: [
                                _pitch(compact: compact),
                                _offer(sticky: sticky),
                              ],
                            ),
                    ),
                  ),
                );
              },
            ),
          ),
          if (sticky) _stickyBar(gutter),
        ],
      ),
    );
  }

  Widget _backHeader({required bool compact}) {
    return Row(
      spacing: 14,
      children: [
        PTIconButton(
          icon: BoothIcons.arrowBack,
          iconSize: compact ? 18 : 20,
          size: compact ? 38 : 42,
          onPressed: () => context.canPop() ? context.pop() : context.go('/lobby'),
        ),
        Flexible(
          child: Text(
            'Patron seats',
            maxLines: 1,
            overflow: .ellipsis,
            style: PTText.panelHeading.copyWith(fontSize: compact ? 15 : 16),
          ),
        ),
      ],
    );
  }

  /// Display type grows with the reader's text size, but only so far - at
  /// 2x a 64px headline would break inside "Patron".
  TextScaler _displayScaler() => MediaQuery.textScalerOf(context).clamp(maxScaleFactor: 1.3);

  Widget _headline(String lead, {required bool compact}) {
    final size = compact ? 40.0 : 64.0;
    return Text.rich(
      TextSpan(
        text: lead,
        children: const [
          TextSpan(
            text: '.',
            style: TextStyle(color: PTColors.premium),
          ),
        ],
      ),
      textScaler: _displayScaler(),
      style: PTText.display.copyWith(fontSize: size, letterSpacing: -size * 0.035, height: 0.98),
    );
  }

  Widget _pitch({required bool compact, bool withComparison = true}) {
    final isPrem = EntitlementService.instance.isPremium;
    return Column(
      crossAxisAlignment: .start,
      children: [
        Text(
          isPrem ? 'YOUR SEAT IS HELD' : 'SYNCTOGETHER PREMIUM',
          style: PTText.label.copyWith(color: PTColors.premium),
        ),
        const SizedBox(height: 14),
        _headline(isPrem ? "You're a Patron" : 'Get a Patron seat', compact: compact),
        const SizedBox(height: 16),
        Text(
          isPrem
              ? 'Every perk is live on your account, on every device you sign in to.'
              : 'Bigger rooms, faces on screen and rooms that wait for you, '
                    'for everyone who comes to your room.',
          style: PTText.body.copyWith(
            fontSize: compact ? 15 : 17,
            height: 1.45,
            color: PTColors.white(0.7),
          ),
        ),
        if (withComparison) ...[
          SizedBox(height: compact ? 24 : 36),
          if (isPrem) _heldChecks() else _comparison(compact: compact),
        ],
      ],
    );
  }

  /// Free against Patron, one ruled row per perk. The numbers mirror
  /// `tier_limits` and the media-sharing caps (see the quota notes in
  /// CLAUDE.md for every place these are copied); the room carries the host's
  /// tier, so each one reaches the whole room.
  static const _perks = [
    (BoothIcons.group, '16-seat rooms', 'Free rooms hold 8.', '8', '16'),
    (BoothIcons.videocam, 'Video facecams', 'Free rooms get voice only.', 'Voice', 'Video'),
    (BoothIcons.moon, '24-hour rooms', 'Pick your own session length.', '4 h', '24 h'),
    (BoothIcons.film, 'Rooms that stay saved', 'Up to 20, waiting in your lobby.', '-', '20'),
    (
      BoothIcons.star,
      'Every reaction',
      'The full animated set, not just the first eight.',
      '8',
      'All',
    ),
    (BoothIcons.upload, '10 GB shared uploads', 'Per file, with no weekly limit.', '2 GB', '10 GB'),
  ];

  Widget _comparison({required bool compact}) {
    final rule = BorderSide(color: PTColors.rail);
    final col = compact ? 52.0 : 88.0;
    final head = PTText.label.copyWith(fontSize: 10);
    // Phones drop the header and the Free column: each row's caption already
    // says what Free gets, and the narrow table reads as one list of perks.
    return Column(
      crossAxisAlignment: .stretch,
      children: [
        if (!compact)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
              children: [
                Expanded(child: Text('WHAT CHANGES', style: head)),
                SizedBox(
                  width: col,
                  child: Text('FREE', textAlign: .end, style: head),
                ),
                SizedBox(
                  width: col,
                  child: Text(
                    'PATRON',
                    textAlign: .end,
                    style: head.copyWith(color: PTColors.premium),
                  ),
                ),
              ],
            ),
          ),
        // Rows deal in one after another - the table is the pitch, so it
        // gets a little choreography. One-shot; nothing runs after.
        for (final (i, perk) in _perks.indexed)
          PTEntrance(
            delay: Duration(milliseconds: 45 * i),
            duration: PTMotion.state,
            offset: 8,
            child: Container(
              padding: EdgeInsets.symmetric(vertical: compact ? 12 : 16),
              decoration: BoxDecoration(
                border: Border(
                  top: compact && i == 0 ? .none : rule,
                  bottom: !compact && i == _perks.length - 1 ? rule : .none,
                ),
              ),
              child: Row(
                spacing: compact ? 10 : 16,
                children: [
                  if (!compact)
                    Text(
                      (i + 1).toString().padLeft(2, '0'),
                      softWrap: false,
                      style: PTText.label.copyWith(color: PTColors.premiumBorder),
                    ),
                  Icon(perk.$1, size: compact ? 18 : 20, color: PTColors.premium),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: .start,
                      spacing: 2,
                      children: [
                        Text(
                          perk.$2,
                          textScaler: compact ? null : _displayScaler(),
                          style: compact
                              ? PTText.body.copyWith(fontSize: 15, fontWeight: .w600)
                              : PTText.screenTitle.copyWith(fontSize: 24, height: 1.1),
                        ),
                        Text(perk.$3, style: PTText.caption.copyWith(color: PTColors.white(0.5))),
                      ],
                    ),
                  ),
                  if (!compact)
                    SizedBox(
                      width: col,
                      child: Text(
                        perk.$4,
                        textAlign: .end,
                        style: PTText.mono.copyWith(fontSize: 13, color: PTColors.white(0.55)),
                      ),
                    ),
                  SizedBox(
                    width: col,
                    child: Text(
                      perk.$5,
                      textAlign: .end,
                      style: PTText.mono.copyWith(
                        fontSize: 13,
                        fontWeight: .w600,
                        color: PTColors.premium,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  /// What a Patron already has, as three plain lines - the table is a pitch,
  /// and there is nothing left to sell.
  Widget _heldChecks() {
    const lines = [
      '16-seat rooms with video facecams',
      '24-hour rooms, up to 20 saved',
      'Every reaction · 10 GB shared uploads',
    ];
    return Column(
      crossAxisAlignment: .start,
      spacing: 12,
      children: [
        for (final line in lines)
          Row(
            spacing: 12,
            children: [
              const Icon(BoothIcons.check, size: 18, color: PTColors.premium),
              Flexible(child: Text(line, style: PTText.body.copyWith(fontSize: 15))),
            ],
          ),
      ],
    );
  }

  /// Three reassurances under the offer - true on both billing rails.
  Widget _reassurances() {
    const lines = [
      'Unlocks on every device you sign in to, the moment payment clears.',
      "Your room carries the perks, so guests don't need a seat of their own.",
      'Cancel any time; you keep it to the end of the paid period.',
    ];
    return _panel(
      Column(
        crossAxisAlignment: .start,
        spacing: 10,
        children: [
          for (final line in lines)
            Row(
              crossAxisAlignment: .start,
              spacing: 10,
              children: [
                const Padding(
                  padding: EdgeInsets.only(top: 2),
                  child: Icon(BoothIcons.check, size: 16, color: PTColors.online),
                ),
                Expanded(
                  child: Text(
                    line,
                    style: PTText.body.copyWith(
                      fontSize: 13.5,
                      height: 1.4,
                      color: PTColors.white(0.8),
                    ),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _legalLinks() {
    final link = PTText.finePrint.copyWith(
      color: PTColors.white(0.6),
      decoration: TextDecoration.underline,
      decorationColor: PTColors.white(0.35),
    );
    // Wrap so both links stay on screen at 320 wide / 2.0x text.
    return Wrap(
      alignment: .center,
      spacing: 16,
      runSpacing: 6,
      children: [
        GestureDetector(
          onTap: () => _openUrl(_termsUrl),
          child: Text('Terms of Use', style: link),
        ),
        GestureDetector(
          onTap: () => _openUrl(_privacyUrl),
          child: Text('Privacy Policy', style: link),
        ),
      ],
    );
  }

  /// The right-hand column: the ticket, then whatever this build and this
  /// account can actually do about it.
  Widget _offer({bool sticky = false, bool withTicket = true}) {
    final isPrem = EntitlementService.instance.isPremium;
    return Column(
      crossAxisAlignment: .stretch,
      spacing: 20,
      children: [
        if (withTicket) _ticket(isPremium: isPrem),
        if (_verifying)
          _panel(
            Row(
              mainAxisAlignment: .center,
              spacing: 12,
              children: [
                const PTLoader(size: 20),
                Flexible(
                  child: Text(
                    'Verifying your purchase…',
                    style: PTText.body.copyWith(color: PTColors.textAccent),
                  ),
                ),
              ],
            ),
          )
        else if (isPrem)
          _premiumStatusActions()
        else ...[
          if (!sticky) _purchaseActions(),
          _reassurances(),
          // The App Store offer carries its own links beside the price
          // (3.1.2), and the sticky bar carries them on phones.
          if (!_isAppleStore && !sticky) _legalLinks(),
        ],
      ],
    );
  }

  Widget _ticket({required bool isPremium}) {
    final ink = PTColors.canvas;
    final soft = PTColors.canvas.withValues(alpha: 0.55);
    final ticket = PTTicket(
      paper: true,
      stubWidth: 84,
      semanticLabel: isPremium ? 'Patron ticket, admitted' : 'Admit one Patron',
      body: Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 16, 18),
        child: Column(
          crossAxisAlignment: .start,
          mainAxisSize: .min,
          spacing: 6,
          children: [
            Text(
              isPremium ? 'PATRON · ADMITTED' : 'ADMIT ONE PATRON',
              style: PTText.label.copyWith(color: PTColors.liveInk),
            ),
            Text(
              'Patron',
              textScaler: _displayScaler(),
              style: PTText.display.copyWith(fontSize: 38, color: ink, letterSpacing: -1.2),
            ),
            Text(
              'SyncTogether Premium',
              style: PTText.caption.copyWith(color: soft, fontWeight: .w600),
            ),
            const SizedBox(height: 4),
            Text(
              isPremium
                  ? (premiumTermLabel(EntitlementService.instance.premiumTerm) ??
                        'ALL PERKS UNLOCKED')
                  : 'MONTHLY OR ANNUAL',
              style: PTText.label.copyWith(color: soft, fontSize: 10),
            ),
          ],
        ),
      ),
      // Scaled down rather than wrapped: a torn stub reads as one block.
      stub: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: FittedBox(
          fit: .scaleDown,
          child: Column(
            mainAxisAlignment: .center,
            spacing: 2,
            children: [
              Text('ROW', style: PTText.label.copyWith(color: soft, fontSize: 10)),
              Text(
                'P',
                textScaler: _displayScaler(),
                style: PTText.display.copyWith(fontSize: 40, color: PTColors.premiumBorder),
              ),
              Text('SEAT 16', style: PTText.label.copyWith(color: soft, fontSize: 10)),
            ],
          ),
        ),
      ),
    );
    if (!isPremium) return ticket;
    // Already a Patron: the ticket has been through the door. The stamp sits
    // beside the tear line, where it covers no lettering.
    return LayoutBuilder(
      builder: (context, box) => Stack(
        clipBehavior: .none,
        children: [
          ticket,
          Positioned(
            // Inside the body's empty right side, just short of the tear:
            // clear of the stub's lettering and of the title.
            left: box.maxWidth - 84 - 88 - 6,
            top: 0,
            bottom: 0,
            child: Center(
              child: PTStamp(
                color: PTColors.premiumBorder,
                size: 88,
                angle: -0.14,
                child: Column(
                  mainAxisSize: .min,
                  spacing: 2,
                  children: [
                    Text('PATRON', style: _stampInk(9)),
                    Text(
                      'ADMITTED',
                      style: PTText.display.copyWith(
                        fontSize: 15,
                        letterSpacing: 0,
                        color: PTColors.premiumBorder,
                      ),
                    ),
                    Text('SEAT 16', style: _stampInk(9)),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _stickyBar(double gutter) {
    return Container(
      padding: EdgeInsets.fromLTRB(gutter, 12, gutter, 12 + MediaQuery.paddingOf(context).bottom),
      decoration: const BoxDecoration(
        color: PTColors.canvas,
        border: Border(top: BorderSide(color: PTColors.aisle)),
      ),
      child: Column(
        mainAxisSize: .min,
        crossAxisAlignment: .stretch,
        spacing: 10,
        children: [_purchaseActions(), _legalLinks()],
      ),
    );
  }

  /// Stamp lettering. The label style carries its own light colour, which
  /// would print Screen ink on paper - the stamp's ink has to win.
  TextStyle _stampInk(double size) =>
      PTText.label.copyWith(fontSize: size, letterSpacing: 1.4, color: PTColors.premiumBorder);

  Widget _celebrationBody({required bool compact}) {
    final body = Column(
      mainAxisSize: .min,
      crossAxisAlignment: .center,
      children: [
        SizedBox(height: compact ? 40 : 96),
        PTStamp(
          color: PTColors.premium,
          size: compact ? 124 : 144,
          angle: -0.16,
          child: Column(
            mainAxisSize: .min,
            spacing: 2,
            children: [
              Text('PATRON', style: _stampInk(10).copyWith(color: PTColors.premium)),
              Text(
                'ADMITTED',
                style: PTText.display.copyWith(
                  fontSize: compact ? 20 : 24,
                  letterSpacing: 0,
                  color: PTColors.premium,
                ),
              ),
              Text('ALL PERKS LIVE', style: _stampInk(9).copyWith(color: PTColors.premium)),
            ],
          ),
        ),
        const SizedBox(height: 32),
        _headline('Welcome, Patron', compact: compact),
        const SizedBox(height: 16),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: Text(
            'Bigger rooms, video facecams and 24-hour rooms are live on your account now, '
            'on every device.',
            textAlign: TextAlign.center,
            style: PTText.body.copyWith(color: PTColors.white(0.7), height: 1.5),
          ),
        ),
        const SizedBox(height: 32),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: PTButton(label: 'Back to lobby', onPressed: () => context.go('/lobby')),
        ),
      ],
    );
    // The confetti is thrown once, behind the stamp, and paints nothing after.
    return Stack(
      alignment: .topCenter,
      children: [
        Positioned.fill(child: PTConfetti(origin: Alignment(0, compact ? -0.55 : -0.6))),
        body,
      ],
    );
  }

  Widget _finePrint(String text) => Text(
    text,
    textAlign: TextAlign.center,
    style: PTText.finePrint.copyWith(color: PTColors.white(0.45), height: 1.45),
  );

  Widget _purchaseActions() {
    if (_canShowCheckout) {
      return Column(
        crossAxisAlignment: .stretch,
        spacing: 10,
        children: [
          PTButton(
            label: 'Take a Patron seat',
            icon: BoothIcons.crown,
            height: 50,
            onPressed: _openCheckout,
          ),
          Row(
            mainAxisAlignment: .center,
            spacing: 6,
            children: [
              Icon(BoothIcons.openInNew, size: 14, color: PTColors.white(0.45)),
              Flexible(child: _finePrint('Checkout opens on synctogether.app in your browser.')),
            ],
          ),
        ],
      );
    }

    if (_isAppleStore) return _appStorePurchase();

    return _panel(
      Column(
        crossAxisAlignment: .stretch,
        spacing: 12,
        children: [
          Text(
            'Subscriptions are managed on our website.',
            style: PTText.body.copyWith(fontWeight: .w600, color: PTColors.fg),
          ),
          Text(
            'Once activated, your account automatically unlocks all features across all your devices.',
            style: PTText.finePrint.copyWith(color: PTColors.white(0.55), height: 1.4),
          ),
          PTButton(
            label: 'Refresh status',
            icon: BoothIcons.restore,
            variant: .secondary,
            height: 40,
            onPressed: _pollForSubscription,
          ),
        ],
      ),
    );
  }

  Widget _premiumStatusActions() {
    // An App Store subscription is only ever managed by Apple, whichever
    // build is showing it; a web account page cannot cancel it.
    final sources = EntitlementService.instance.premiumSources;
    if (_isAppleStore || (sources.contains('apple') && !sources.contains('paddle'))) {
      return _appStoreManage(sources);
    }

    if (_canShowCheckout) {
      return Column(
        crossAxisAlignment: .stretch,
        spacing: 10,
        children: [
          PTButton(
            label: 'Manage subscription',
            icon: BoothIcons.openInNew,
            variant: .secondary,
            height: 48,
            onPressed: _openAccount,
          ),
          _finePrint('Opens account settings in your browser.'),
        ],
      );
    }

    return _panel(
      Column(
        crossAxisAlignment: .stretch,
        spacing: 12,
        children: [
          Text(
            'Your active subscription is managed on our website.',
            style: PTText.body.copyWith(fontSize: 14, color: PTColors.white(0.85)),
          ),
          PTButton(
            label: 'Refresh status',
            icon: BoothIcons.restore,
            variant: .secondary,
            height: 40,
            onPressed: _pollForSubscription,
          ),
        ],
      ),
    );
  }

  Widget _appStorePurchase() {
    final iap = AppleIapService.instance;
    if (EntitlementService.instance.limitsOrFallback.isGuest) {
      return _infoCard(
        'Sign in with Apple, Google or email to subscribe. Premium belongs to your account, '
        'so it follows you to every device.',
      );
    }
    if (iap.loadingProducts && iap.products.isEmpty) {
      return const Center(child: PTLoader(size: 22));
    }
    if (iap.products.isEmpty) {
      return Column(
        crossAxisAlignment: .stretch,
        spacing: 12,
        children: [
          _infoCard("Couldn't reach the App Store right now."),
          PTButton(
            label: 'Try again',
            icon: BoothIcons.restore,
            variant: .secondary,
            height: 40,
            onPressed: iap.loadProducts,
          ),
        ],
      );
    }
    return Column(
      crossAxisAlignment: .stretch,
      spacing: 10,
      children: [
        for (final product in iap.products) _storeOption(product, iap),
        Center(
          child: TextButton.icon(
            onPressed: iap.busy ? null : iap.restore,
            icon: const Icon(BoothIcons.restore, size: 16),
            label: const Text('Restore purchases'),
            style: TextButton.styleFrom(
              foregroundColor: PTColors.fg,
              textStyle: PTText.body.copyWith(
                fontSize: 14,
                fontWeight: .w600,
                decoration: TextDecoration.underline,
              ),
            ),
          ),
        ),
        _appStoreFinePrint(),
      ],
    );
  }

  /// One App Store plan as a row: monthly lit, annual outlined, each with
  /// StoreKit's own localized price - never a hard-coded one.
  Widget _storeOption(ProductDetails product, AppleIapService iap) {
    final annual = product.id == kAppleAnnualProductId;
    final ink = annual ? PTColors.fg : PTColors.onAccent;
    return Semantics(
      button: true,
      label: annual ? 'Annual, ${product.price} a year' : 'Monthly, ${product.price} a month',
      child: MouseRegion(
        cursor: iap.busy ? MouseCursor.defer : SystemMouseCursors.click,
        child: PTPressable(
          enabled: !iap.busy,
          onTap: () => _buyOnAppStore(product),
          child: AnimatedOpacity(
            duration: PTMotion.functional(context, PTMotion.hover),
            opacity: iap.busy ? 0.5 : 1,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
              decoration: BoxDecoration(
                color: annual ? Colors.transparent : PTColors.primary,
                border: Border.all(color: annual ? PTColors.rail : PTColors.primary),
                borderRadius: BorderRadius.circular(PTRadius.control),
                boxShadow: annual ? const [] : PTColors.beamSpill,
              ),
              child: Row(
                spacing: 12,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: .start,
                      spacing: 2,
                      children: [
                        Text(
                          annual ? 'Annual' : 'Monthly',
                          style: PTText.buttonLabel.copyWith(color: ink, fontSize: 16),
                        ),
                        Text(
                          annual ? 'Billed yearly' : 'Renews every month',
                          style: PTText.caption.copyWith(
                            color: ink.withValues(alpha: 0.7),
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    annual ? '${product.price} / year' : '${product.price} / month',
                    style: PTText.mono.copyWith(color: ink, fontSize: 15, fontWeight: .w600),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _appStoreManage(Set<String> sources) {
    return Column(
      crossAxisAlignment: .stretch,
      spacing: 10,
      children: [
        if (sources.contains('apple'))
          PTButton(
            label: 'Manage in App Store',
            icon: BoothIcons.openInNew,
            variant: .secondary,
            height: 48,
            onPressed: () => _openUrl(kAppleManageSubscriptionsUrl),
          )
        else
          _infoCard('Premium is active on your account across all your devices.'),
        PTButton(
          label: 'Refresh status',
          icon: BoothIcons.restore,
          variant: .secondary,
          height: 40,
          onPressed: _pollForSubscription,
        ),
      ],
    );
  }

  Widget _appStoreFinePrint() {
    final style = PTText.finePrint.copyWith(color: PTColors.white(0.45), height: 1.45);
    final link = style.copyWith(color: PTColors.link, decoration: TextDecoration.underline);
    return Column(
      spacing: 8,
      children: [
        const SizedBox(height: 4),
        Text(
          'Payment is charged to your Apple ID when you confirm. Your subscription renews '
          'automatically at the same price unless cancelled at least 24 hours before the end '
          'of the current period. Manage or cancel any time in your App Store account settings.',
          textAlign: TextAlign.center,
          style: style,
        ),
        // Wrap so both links stay on screen at 320 wide / 2.0x text.
        Wrap(
          alignment: .center,
          spacing: 16,
          runSpacing: 6,
          children: [
            GestureDetector(
              onTap: () => _openUrl(_termsUrl),
              child: Text('Terms of Use', style: link),
            ),
            GestureDetector(
              onTap: () => _openUrl(_privacyUrl),
              child: Text('Privacy Policy', style: link),
            ),
          ],
        ),
      ],
    );
  }

  /// A Seat surface with a Rail hairline - the page's one kind of box.
  Widget _panel(Widget child) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      decoration: BoxDecoration(
        color: PTColors.glassBase,
        border: Border.all(color: PTColors.rail),
        borderRadius: BorderRadius.circular(PTRadius.panel),
      ),
      child: child,
    );
  }

  Widget _infoCard(String message) {
    return _panel(
      Text(
        message,
        textAlign: TextAlign.center,
        style: PTText.body.copyWith(fontSize: 14, color: PTColors.white(0.85)),
      ),
    );
  }
}

const _kMonths = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

/// The ticket's date line. Only says "renews" when the data proves it -
/// a Paddle cancellation never reaches the local row, so Paddle is "paid
/// through"; a manual grant simply ends.
@visibleForTesting
String? premiumTermLabel(PremiumTerm? term) {
  if (term == null) return null;
  final d = term.until.toLocal();
  final date = '${d.day} ${_kMonths[d.month - 1]} ${d.year}';
  final verb = switch (term) {
    PremiumTerm(source: 'apple', renews: true) => 'Renews',
    PremiumTerm(source: 'apple') => 'Ends',
    PremiumTerm(source: 'paddle') => 'Paid through',
    _ => 'Patron until',
  };
  return '$verb $date'.toUpperCase();
}
