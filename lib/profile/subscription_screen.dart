import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:synctogether/analytics.dart';
import 'package:synctogether/diagnostics.dart';
import 'package:synctogether/platform.dart';
import 'package:synctogether/profile/apple_iap_service.dart';
import 'package:synctogether/profile/entitlement_service.dart';
import 'package:synctogether/profile/profile_service.dart';
import 'package:synctogether/ui/banners.dart';
import 'package:synctogether/ui/buttons.dart';
import 'package:synctogether/ui/glass.dart';
import 'package:synctogether/ui/identity.dart';
import 'package:synctogether/ui/loader.dart';
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
  });

  final String? source;
  final bool? desktopOverride;
  final bool? storeBuildOverride;
  final bool? appleStoreBuildOverride;

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

  Widget _layout({required bool compact}) {
    return Column(
      children: [
        Padding(
          padding: EdgeInsets.symmetric(horizontal: compact ? 20 : 48, vertical: compact ? 12 : 28),
          child: _backHeader(compact: compact),
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: EdgeInsets.only(
              left: compact ? 16 : 32,
              right: compact ? 16 : 32,
              top: compact ? 10 : 20,
              bottom: 48,
            ),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 580),
                child: GlassPanel(
                  radius: compact ? 22 : 28,
                  opacity: 0.5,
                  blur: 32,
                  padding: EdgeInsets.all(compact ? 24 : 40),
                  child: _celebrating ? _celebrationBody() : _mainBody(compact: compact),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _backHeader({required bool compact}) {
    return Row(
      spacing: 14,
      children: [
        PTIconButton(
          icon: Symbols.arrow_back_rounded,
          iconSize: compact ? 18 : 20,
          size: compact ? 38 : 42,
          onPressed: () => context.canPop() ? context.pop() : context.go('/lobby'),
        ),
        Text(
          'SyncTogether Premium',
          style: compact ? PTText.cardHeading.copyWith(fontSize: 18) : PTText.cardHeading,
        ),
      ],
    );
  }

  Widget _celebrationBody() {
    return Column(
      mainAxisSize: .min,
      crossAxisAlignment: .center,
      spacing: 20,
      children: [
        Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(
            gradient: PTColors.brandGradient,
            shape: .circle,
            boxShadow: [
              BoxShadow(
                color: PTColors.primary.withValues(alpha: 0.5),
                blurRadius: 28,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: const Icon(Symbols.crown_rounded, size: 36, fill: 1, color: Colors.white),
        ),
        Text('Welcome to Premium! 🎉', style: PTText.screenTitle.copyWith(fontSize: 24)),
        Text(
          'Your account is now upgraded with all premium perks. '
          'Enjoy longer sessions, video facecams, and persistent rooms!',
          textAlign: TextAlign.center,
          style: PTText.body.copyWith(color: PTColors.white(0.7), height: 1.5),
        ),
        const SizedBox(height: 8),
        PTButton(
          label: 'Back to lobby',
          icon: Symbols.home_rounded,
          onPressed: () => context.go('/lobby'),
        ),
      ],
    );
  }

  Widget _mainBody({required bool compact}) {
    final isPrem = EntitlementService.instance.isPremium;

    return Column(
      mainAxisSize: .min,
      crossAxisAlignment: .stretch,
      spacing: 24,
      children: [
        _tierBadgeHeader(isPremium: isPrem),
        _featureList(),
        if (_verifying)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: PTColors.primary.withValues(alpha: 0.12),
              border: Border.all(color: const Color(0xFFA78BFA).withValues(alpha: 0.3)),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              mainAxisAlignment: .center,
              spacing: 12,
              children: [
                const PTLoader(size: 20),
                Text(
                  'Verifying your purchase…',
                  style: PTText.body.copyWith(color: PTColors.textAccent),
                ),
              ],
            ),
          )
        else if (isPrem)
          _premiumStatusActions(compact: compact)
        else
          _purchaseActions(compact: compact),
      ],
    );
  }

  Widget _tierBadgeHeader({required bool isPremium}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        color: isPremium ? PTColors.primary.withValues(alpha: 0.15) : PTColors.white(0.04),
        border: Border.all(
          color: isPremium ? const Color(0xFFA78BFA).withValues(alpha: 0.4) : PTColors.white(0.1),
        ),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        spacing: 14,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              gradient: isPremium ? PTColors.brandGradient : null,
              color: isPremium ? null : PTColors.white(0.08),
              borderRadius: BorderRadius.circular(13),
            ),
            child: Icon(
              isPremium ? Symbols.crown_rounded : Symbols.person_rounded,
              size: 22,
              fill: 1,
              color: Colors.white,
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: .start,
              spacing: 2,
              children: [
                Text(
                  isPremium ? 'Premium Active' : 'Free Plan',
                  style: PTText.cardHeading.copyWith(fontSize: 16),
                ),
                Text(
                  isPremium
                      ? 'All perks unlocked on your account'
                      : 'Upgrade to host larger rooms with video facecams',
                  style: PTText.caption.copyWith(color: PTColors.white(0.55)),
                ),
              ],
            ),
          ),
          if (isPremium) const PremiumBadge(),
        ],
      ),
    );
  }

  Widget _featureList() {
    const perks = [
      ('Up to 20 rooms active at once', Symbols.meeting_room_rounded),
      ('Persistent rooms that stay saved forever', Symbols.save_rounded),
      ('Up to 16 watchers per room', Symbols.groups_rounded),
      ('Video facecams & crystal-clear voice', Symbols.videocam_rounded),
      ('Extended animated emoji reactions', Symbols.add_reaction_rounded),
      ('Watch party sessions up to 24 hours', Symbols.schedule_rounded),
    ];

    return Column(
      crossAxisAlignment: .start,
      spacing: 12,
      children: [
        Text(
          'Premium perks',
          style: PTText.caption.copyWith(fontWeight: .w600, letterSpacing: 0.5),
        ),
        for (final perk in perks)
          Row(
            spacing: 12,
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: PTColors.primary.withValues(alpha: 0.15),
                  shape: .circle,
                ),
                child: Icon(perk.$2, size: 17, fill: 1, color: PTColors.textAccent),
              ),
              Expanded(
                child: Text(
                  perk.$1,
                  style: PTText.body.copyWith(fontSize: 13.5, color: PTColors.white(0.85)),
                ),
              ),
            ],
          ),
      ],
    );
  }

  Widget _purchaseActions({required bool compact}) {
    if (_canShowCheckout) {
      return Column(
        crossAxisAlignment: .stretch,
        spacing: 10,
        children: [
          PTButton(
            label: 'Go Premium',
            icon: Symbols.workspace_premium_rounded,
            height: 48,
            onPressed: _openCheckout,
          ),
          Text(
            "You'll be taken to our website to complete your purchase.",
            textAlign: TextAlign.center,
            style: PTText.finePrint.copyWith(color: PTColors.white(0.4)),
          ),
        ],
      );
    }

    if (_isAppleStore) return _appStorePurchase();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      decoration: BoxDecoration(
        color: PTColors.white(0.04),
        border: Border.all(color: PTColors.white(0.08)),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: .stretch,
        spacing: 12,
        children: [
          Row(
            spacing: 12,
            children: [
              const Icon(Symbols.info_rounded, size: 20, color: PTColors.textAccent),
              Expanded(
                child: Text(
                  'Subscriptions are managed on our website.',
                  style: PTText.body.copyWith(
                    fontSize: 13.5,
                    color: PTColors.white(0.85),
                    fontWeight: .w500,
                  ),
                ),
              ),
            ],
          ),
          Text(
            'Once activated, your account automatically unlocks all features across all your devices.',
            style: PTText.finePrint.copyWith(color: PTColors.white(0.55), height: 1.4),
          ),
          PTButton(
            label: 'Refresh status',
            icon: Symbols.refresh_rounded,
            variant: .secondary,
            height: 40,
            onPressed: _pollForSubscription,
          ),
        ],
      ),
    );
  }

  Widget _premiumStatusActions({required bool compact}) {
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
            icon: Symbols.open_in_new_rounded,
            variant: .secondary,
            height: 48,
            onPressed: _openAccount,
          ),
          Text(
            'Opens account settings in your browser.',
            textAlign: TextAlign.center,
            style: PTText.finePrint.copyWith(color: PTColors.white(0.4)),
          ),
        ],
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      decoration: BoxDecoration(
        color: PTColors.white(0.04),
        border: Border.all(color: PTColors.white(0.08)),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: .stretch,
        spacing: 12,
        children: [
          Text(
            'Your active subscription is managed on our website.',
            textAlign: TextAlign.center,
            style: PTText.body.copyWith(fontSize: 13.5, color: PTColors.white(0.85)),
          ),
          PTButton(
            label: 'Refresh status',
            icon: Symbols.refresh_rounded,
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
        'Sign in with Apple, Google or email to subscribe - Premium belongs to your account, '
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
            icon: Symbols.refresh_rounded,
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
        for (final product in iap.products)
          PTButton(
            label: product.id == kAppleAnnualProductId
                ? 'Annual - ${product.price} / year'
                : 'Monthly - ${product.price} / month',
            icon: Symbols.workspace_premium_rounded,
            variant: product.id == kAppleAnnualProductId ? .secondary : .primary,
            height: 48,
            loading: iap.busy,
            onPressed: iap.busy ? null : () => _buyOnAppStore(product),
          ),
        PTButton(
          label: 'Restore purchases',
          icon: Symbols.restore_rounded,
          variant: .secondary,
          height: 40,
          onPressed: iap.busy ? null : iap.restore,
        ),
        _appStoreFinePrint(),
      ],
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
            icon: Symbols.open_in_new_rounded,
            variant: .secondary,
            height: 48,
            onPressed: () => _openUrl(kAppleManageSubscriptionsUrl),
          )
        else
          _infoCard('Premium is active on your account across all your devices.'),
        PTButton(
          label: 'Refresh status',
          icon: Symbols.refresh_rounded,
          variant: .secondary,
          height: 40,
          onPressed: _pollForSubscription,
        ),
      ],
    );
  }

  Widget _appStoreFinePrint() {
    final style = PTText.finePrint.copyWith(color: PTColors.white(0.45), height: 1.45);
    final link = style.copyWith(color: PTColors.textAccent, decoration: TextDecoration.underline);
    return Column(
      spacing: 8,
      children: [
        Text(
          'Payment is charged to your Apple ID when you confirm. Your subscription renews '
          'automatically at the same price unless cancelled at least 24 hours before the end '
          'of the current period. Manage or cancel any time in your App Store account settings.',
          textAlign: TextAlign.center,
          style: style,
        ),
        Row(
          mainAxisAlignment: .center,
          spacing: 16,
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

  Widget _infoCard(String message) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      decoration: BoxDecoration(
        color: PTColors.white(0.04),
        border: Border.all(color: PTColors.white(0.08)),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Text(
        message,
        textAlign: TextAlign.center,
        style: PTText.body.copyWith(fontSize: 13.5, color: PTColors.white(0.85)),
      ),
    );
  }
}
