import 'dart:async';
import 'dart:io';

import 'package:fast_file_picker/fast_file_picker.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:synctogether/app_version.dart';
import 'package:synctogether/analytics.dart';
import 'package:synctogether/analytics_consent.dart';
import 'package:synctogether/analytics_disclosure_dialog.dart';
import 'package:synctogether/auth/auth_service.dart';
import 'package:synctogether/rewards/rewards_logic.dart';
import 'package:synctogether/rewards/rewards_models.dart';
import 'package:synctogether/rewards/rewards_service.dart';
import 'package:synctogether/rewards/unlock_log.dart';
import 'package:synctogether/rewards/widgets/badge_shelf.dart';
import 'package:synctogether/rewards/widgets/season_trophies.dart';
import 'package:synctogether/rewards/widgets/shared_recaps_dialog.dart';
import 'package:synctogether/av/av_settings_dialog.dart';
import 'package:synctogether/diagnostics.dart';
import 'package:synctogether/platform.dart';
import 'package:synctogether/profile/camera_capture_dialog.dart';
import 'package:synctogether/profile/entitlement_service.dart';
import 'package:synctogether/profile/media_quota_dialog.dart';
import 'package:synctogether/profile/profile_models.dart';
import 'package:synctogether/profile/profile_service.dart';
import 'package:synctogether/rooms/moderation_service.dart';
import 'package:synctogether/ui/banners.dart';
import 'package:synctogether/ui/buttons.dart';
import 'package:synctogether/ui/glass.dart';
import 'package:synctogether/ui/identity.dart';
import 'package:synctogether/ui/inputs.dart';
import 'package:synctogether/ui/loader.dart';
import 'package:synctogether/ui/pt_motion.dart';
import 'package:synctogether/ui/pt_theme.dart';
import 'package:synctogether/ui/responsive.dart';
import 'package:synctogether/updates/update_service.dart';
import 'package:url_launcher/url_launcher.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  bool _uploadingAvatar = false;
  bool? _mediaSharingRememberedChoice;

  @override
  void initState() {
    super.initState();
    if (ProfileService.instance.profile == null) {
      ProfileService.instance.load();
    }
    if (EntitlementService.instance.limits == null) {
      EntitlementService.instance.load();
    }
    _loadMediaSharingPreference();
    unawaited(RewardsService.instance.load().then((_) => _trackHandleUpsellShown()));
    unawaited(RewardsService.instance.loadReferrals());
  }

  /// Once per visit, and never from `build`: the handle field is inline, so
  /// rendering it is not an event and a `build` call site would fire on every
  /// frame. Without it the `handle` surface reported clicks with no
  /// impressions, and a conversion rate needs both halves.
  bool _handleUpsellTracked = false;

  void _trackHandleUpsellShown() {
    if (_handleUpsellTracked || !mounted) return;
    final state = RewardsService.instance.state;
    if (state.isPremium || state.handle != null) return;
    _handleUpsellTracked = true;
    Analytics.instance.track('upgrade_cta_shown', {'surface': 'handle'});
  }

  Future<void> _loadMediaSharingPreference() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _mediaSharingRememberedChoice = prefs.getBool('pt.media_sharing.remember_choice');
    });
  }

  Future<void> _setMediaSharingPreference(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('pt.media_sharing.remember_choice', value);
    if (!mounted) return;
    setState(() => _mediaSharingRememberedChoice = value);
  }

  Future<void> _resetMediaSharingPreference() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('pt.media_sharing.remember_choice');
    if (!mounted) return;
    setState(() => _mediaSharingRememberedChoice = null);
  }

  Future<void> _showAvatarOptions() async {
    final choice = await showGlassDialog<String>(
      context: context,
      width: 320,
      padding: const EdgeInsets.all(20),
      builder: (dialogContext) => Column(
        mainAxisSize: .min,
        crossAxisAlignment: .stretch,
        children: [
          Row(
            mainAxisAlignment: .spaceBetween,
            children: [
              Text('Profile Photo', style: PTText.cardHeading.copyWith(fontSize: 16)),
              PTIconButton(
                icon: Symbols.close_rounded,
                size: 28,
                iconSize: 16,
                onPressed: () => Navigator.of(dialogContext).pop(),
              ),
            ],
          ),
          const SizedBox(height: 16),
          PTButton(
            label: 'Take photo with camera',
            icon: Symbols.photo_camera_rounded,
            variant: .primary,
            height: 42,
            onPressed: () => Navigator.of(dialogContext).pop('camera'),
          ),
          const SizedBox(height: 10),
          PTButton(
            label: 'Choose image file',
            icon: Symbols.folder_open_rounded,
            variant: .secondary,
            height: 42,
            onPressed: () => Navigator.of(dialogContext).pop('file'),
          ),
        ],
      ),
    );

    if (choice == 'camera') {
      if (!mounted) return;
      final bytes = await showCameraCaptureDialog(context);
      if (bytes != null && mounted) {
        setState(() => _uploadingAvatar = true);
        try {
          await ProfileService.instance.uploadAvatar(bytes);
          if (mounted) _snack('Profile photo updated!', kind: .success);
        } catch (e, s) {
          reportNonFatal(e, s, during: 'uploading camera avatar');
          if (mounted) _snack("Couldn't update your photo. Try a different image.");
        } finally {
          if (mounted) setState(() => _uploadingAvatar = false);
        }
      }
    } else if (choice == 'file') {
      await _pickAvatar();
    }
  }

  Future<void> _pickAvatar() async {
    const imageTypes = XTypeGroup(label: 'Images', extensions: ['jpg', 'jpeg', 'png', 'webp']);
    final picked = await FastFilePicker.pickFile(acceptedTypeGroups: [imageTypes]);
    final path = picked?.path;
    if (path == null) return;
    setState(() => _uploadingAvatar = true);
    try {
      await ProfileService.instance.uploadAvatar(await File(path).readAsBytes());
    } catch (e, s) {
      // "Try a different image" is a guess. Storage quota, a bucket policy or a
      // dead connection all land here, and only the log can tell them apart.
      reportNonFatal(e, s, during: 'uploading an avatar');
      if (mounted) _snack("Couldn't update your photo. Try a different image.");
    } finally {
      if (mounted) setState(() => _uploadingAvatar = false);
    }
  }

  Future<void> _editDisplayName(Profile profile) async {
    final controller = TextEditingController(text: profile.displayName);
    final saved = await showGlassDialog<bool>(
      context: context,
      width: 400,
      builder: (dialogContext) => Column(
        mainAxisSize: .min,
        crossAxisAlignment: .start,
        spacing: 16,
        children: [
          Text('Pick a display name', style: PTText.cardHeading),
          PTTextField(
            controller: controller,
            hint: 'Your name',
            autofocus: true,
            maxLength: 40,
            onSubmitted: (_) => Navigator.of(dialogContext).pop(true),
          ),
          Row(
            mainAxisAlignment: .end,
            spacing: 11,
            children: [
              PTButton(
                label: 'Cancel',
                variant: .secondary,
                height: 46,
                expand: false,
                onPressed: () => Navigator.of(dialogContext).pop(false),
              ),
              PTButton(
                label: 'Save',
                height: 46,
                expand: false,
                onPressed: () => Navigator.of(dialogContext).pop(true),
              ),
            ],
          ),
        ],
      ),
    );
    final name = controller.text.trim();
    if (saved == true && name.isNotEmpty && name != profile.displayName) {
      try {
        await ProfileService.instance.updateDisplayName(name);
      } catch (e, s) {
        reportNonFatal(e, s, during: 'saving the display name');
        if (mounted) _snack("Couldn't save that name. Give it another try.");
      }
    }
  }

  Future<void> _confirmDeleteAccount() async {
    final confirmed = await showGlassDialog<bool>(
      context: context,
      width: 400,
      builder: (dialogContext) => Column(
        mainAxisSize: .min,
        crossAxisAlignment: .start,
        spacing: 14,
        children: [
          Text('Delete your account?', style: PTText.cardHeading),
          Text(
            'This wipes your profile, room memberships and chat for good. '
            'There is no undo.',
            style: PTText.body.copyWith(fontSize: 14, color: PTColors.white(0.6), height: 1.5),
          ),
          // Deleting the account cannot end an App Store subscription - only
          // Apple can - so without this Apple would keep billing for an
          // account that no longer exists (guideline 5.1.1(v)).
          if (EntitlementService.instance.premiumSources.contains('apple'))
            Text(
              'Your App Store subscription keeps renewing until you cancel it. '
              'Cancel it in your App Store account settings first. Deleting your '
              "account here doesn't stop Apple billing you.",
              style: PTText.body.copyWith(fontSize: 14, color: PTColors.warning, height: 1.5),
            ),
          Row(
            mainAxisAlignment: .end,
            spacing: 11,
            children: [
              PTButton(
                label: 'Keep account',
                variant: .secondary,
                height: 46,
                expand: false,
                onPressed: () => Navigator.of(dialogContext).pop(false),
              ),
              PTButton(
                label: 'Delete forever',
                variant: .destructive,
                icon: Symbols.delete_rounded,
                height: 46,
                expand: false,
                onPressed: () => Navigator.of(dialogContext).pop(true),
              ),
            ],
          ),
        ],
      ),
    );
    if (confirmed == true) {
      try {
        // The badge log is device-local, so it has to be cleared here: a second
        // account on this machine must not inherit the first one's
        // announcements and silently lose its own `achievement_unlocked`.
        await UnlockLog.instance.clear();
        await AuthService.instance.deleteAccount();
      } catch (e, s) {
        // Account deletion has known server-side failure modes (a hosted room
        // still referencing the user), so the cause is worth keeping.
        reportNonFatal(e, s, during: 'deleting the account');
        if (mounted) _snack("Couldn't delete the account right now. Try again in a bit.");
      }
    }
  }

  void _snack(String message, {PTSnackKind kind = PTSnackKind.error}) =>
      showPTSnack(context, message, kind: kind);

  /// Width at which the page splits into an identity column and a settings
  /// column. Below it everything runs in one editorial column.
  static const double _splitWidth = 1000;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: AmbientBackground(
        child: ListenableBuilder(
          listenable: Listenable.merge([
            ProfileService.instance,
            EntitlementService.instance,
            RewardsService.instance,
          ]),
          builder: (context, _) {
            final profile = ProfileService.instance.profile;
            if (profile == null) {
              return const Center(child: PTLoader(size: 32));
            }
            return PTResponsive(
              desktop: (_) => _desktop(profile),
              portrait: (_) => _portrait(profile),
              landscape: (_) => _landscape(profile),
            );
          },
        ),
      ),
    );
  }

  /// Desktop and tablet (via the `tablet → desktop` fallback). Two columns
  /// from [_splitWidth] up; a single centred column below it, which is what a
  /// portrait iPad or a narrow desktop window wants.
  /// Set while building the wide desktop split, where every settings section
  /// is a Seat card in a grid instead of a ruled section in a column.
  bool _cards = false;

  Widget _desktop(Profile profile) {
    return SafeArea(
      child: LayoutBuilder(
        builder: (context, box) {
          final split = box.maxWidth >= _splitWidth;
          final gutter = box.maxWidth >= 720 ? 48.0 : 24.0;
          if (split) return _wideSplit(profile);
          _cards = false;
          return Column(
            children: [
              Padding(
                padding: EdgeInsets.fromLTRB(gutter, 24, gutter, 0),
                child: _centred(640, _backHeader(size: 42)),
              ),
              Expanded(
                child: SingleChildScrollView(
                  padding: EdgeInsets.fromLTRB(gutter, 32, gutter, 56),
                  child: _centred(640, _oneColumn(profile, nameSize: 44)),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  /// The Profile, desktop board: a full-height identity column behind a
  /// hairline, and the settings as Seat cards - Membership across the top,
  /// then two columns once there is room for them.
  Widget _wideSplit(Profile profile) {
    final guest = profile.isGuest;
    final version = AppVersion.current;
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.fromLTRB(40, 16, 40, 16),
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: PTColors.aisle)),
          ),
          child: Row(
            children: [
              Expanded(child: _backHeader(size: 40)),
              if (version != null)
                Text(version, style: PTText.mono.copyWith(fontSize: 11, color: PTColors.away)),
            ],
          ),
        ),
        Expanded(
          child: Row(
            crossAxisAlignment: .stretch,
            children: [
              Container(
                width: 400,
                decoration: const BoxDecoration(
                  border: Border(right: BorderSide(color: PTColors.aisle)),
                ),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(56, 44, 40, 48),
                  child: Builder(
                    builder: (context) {
                      _cards = false;
                      return Column(
                        crossAxisAlignment: .stretch,
                        children: [
                          _identityColumn(profile, nameSize: 48),
                          const SizedBox(height: 32),
                          _blockedSection(),
                          _exitSection(guest),
                        ],
                      );
                    },
                  ),
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(40, 36, 56, 48),
                  child: LayoutBuilder(
                    builder: (context, box) {
                      _cards = true;
                      final left = <Widget>[
                        _accountSection(profile),
                        _mediaQuotaSection(),
                        _audioVideoSection(),
                        if (supportsSelfUpdate) _updatesSection(),
                      ];
                      final right = <Widget>[if (!guest) _boardsSection(), _privacySection()];
                      final twoUp = box.maxWidth >= 760;
                      final cards = Column(
                        crossAxisAlignment: .stretch,
                        children: [
                          _enter(1, _seatSection()),
                          if (twoUp)
                            Row(
                              crossAxisAlignment: .start,
                              spacing: 20,
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: .stretch,
                                    children: [for (final (i, w) in left.indexed) _enter(i + 2, w)],
                                  ),
                                ),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: .stretch,
                                    children: [
                                      for (final (i, w) in right.indexed) _enter(i + 2, w),
                                    ],
                                  ),
                                ),
                              ],
                            )
                          else
                            for (final (i, w) in [...left, ...right].indexed) _enter(i + 2, w),
                        ],
                      );
                      _cards = false;
                      return cards;
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _portrait(Profile profile) {
    // Edge-to-edge: the list scrolls under the home indicator / nav bar, and
    // the bottom inset pads the content so its last item still clears it.
    return SafeArea(
      bottom: false,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
            child: _backHeader(titleSize: 18),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(22, 24, 22, 40 + MediaQuery.paddingOf(context).bottom),
              child: profile.isGuest ? _oneColumn(profile, nameSize: 34) : _phoneColumn(profile),
            ),
          ),
        ],
      ),
    );
  }

  /// Phone landscape: height is the scarce thing, so the identity column and
  /// the settings scroll independently side by side.
  Widget _landscape(Profile profile) {
    return SafeArea(
      minimum: const EdgeInsets.symmetric(horizontal: 44),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: _backHeader(iconSize: 19, size: 38, titleSize: 17),
          ),
          Expanded(
            child: _twoColumns(
              profile,
              // An SE (667 wide, less the notch gutters) needs the settings
              // column more than a normal phone does.
              identityWidth: MediaQuery.sizeOf(context).width < 720 ? 200 : 250,
              gap: 32,
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 22),
              nameSize: 26,
            ),
          ),
        ],
      ),
    );
  }

  Widget _centred(double maxWidth, Widget child) => Center(
    child: ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: child,
    ),
  );

  Widget _twoColumns(
    Profile profile, {
    required double identityWidth,
    required double gap,
    required EdgeInsets padding,
    double maxWidth = double.infinity,
    double nameSize = 48,
  }) {
    final scrollPadding = EdgeInsets.only(top: padding.top, bottom: padding.bottom);
    return Padding(
      padding: EdgeInsets.only(left: padding.left, right: padding.right),
      child: _centred(
        maxWidth,
        Row(
          crossAxisAlignment: .start,
          children: [
            SizedBox(
              width: identityWidth,
              child: SingleChildScrollView(
                padding: scrollPadding,
                child: _identityColumn(profile, nameSize: nameSize),
              ),
            ),
            SizedBox(width: gap),
            Expanded(
              child: SingleChildScrollView(padding: scrollPadding, child: _settingsColumn(profile)),
            ),
          ],
        ),
      ),
    );
  }

  /// Phone portrait for an account: the identity collapses to one row, the
  /// stats sit straight under it and membership is a card with a full-width
  /// call to action - the page's one lit button - before the settings.
  Widget _phoneColumn(Profile profile) {
    final rewards = RewardsService.instance.state;
    final isPrem = EntitlementService.instance.isPremium;
    final streak = rewards.streak.current;
    final badges = rewards.unlocked.length;
    final since = profile.createdAt;
    return Column(
      crossAxisAlignment: .stretch,
      children: [
        _enter(
          0,
          Row(
            spacing: 14,
            children: [
              _avatar(profile, size: 64),
              Expanded(
                child: Column(
                  crossAxisAlignment: .start,
                  spacing: 8,
                  children: [
                    MouseRegion(
                      cursor: SystemMouseCursors.click,
                      child: GestureDetector(
                        behavior: .opaque,
                        onTap: () => _editDisplayName(profile),
                        child: Row(
                          spacing: 8,
                          children: [
                            Flexible(
                              child: Text(
                                profile.displayName,
                                maxLines: 2,
                                overflow: .ellipsis,
                                textScaler: _displayScaler(context),
                                style: PTText.display.copyWith(fontSize: 28, height: 1.02),
                              ),
                            ),
                            Icon(Symbols.edit_rounded, size: 17, color: PTColors.white(0.55)),
                          ],
                        ),
                      ),
                    ),
                    Row(
                      spacing: 10,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            border: Border.all(
                              color: isPrem ? PTColors.premiumBorder : PTColors.rail,
                            ),
                            borderRadius: BorderRadius.circular(2),
                          ),
                          child: Text(
                            isPrem ? 'PATRON SEAT' : 'FREE SEAT',
                            style: PTText.label.copyWith(
                              fontSize: 10,
                              color: isPrem ? PTColors.premium : PTColors.fg,
                            ),
                          ),
                        ),
                        if (since != null)
                          Flexible(
                            child: Text(
                              'since ${_monthName(since.month)} ${since.year}',
                              maxLines: 1,
                              overflow: .ellipsis,
                              style: PTText.caption.copyWith(fontWeight: .w400),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 22),
        _enter(
          1,
          Row(
            children: [
              Expanded(
                child: Text(
                  'WATCHING · $badges ${badges == 1 ? 'BADGE' : 'BADGES'}',
                  style: PTText.label,
                ),
              ),
              PTPressable(
                onTap: () => context.go('/lobby/leaderboard'),
                // 44pt tall: this is a touch layout.
                child: Container(
                  height: 44,
                  color: Colors.transparent,
                  child: Row(
                    mainAxisSize: .min,
                    spacing: 6,
                    children: [
                      const Icon(Symbols.trophy_rounded, size: 16, color: PTColors.fg),
                      Text('Leaderboard', style: PTText.body.copyWith(fontWeight: .w600)),
                      Icon(Symbols.chevron_right_rounded, size: 18, color: PTColors.white(0.6)),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        _enter(
          2,
          Row(
            crossAxisAlignment: .start,
            spacing: 16,
            children: [
              Expanded(
                child: _numeral(
                  '$streak',
                  'day streak',
                  color: streak > 0 ? PTColors.ember : PTColors.fg,
                ),
              ),
              Expanded(child: _numeral(formatWatchHours(rewards.totals.watched), 'watched')),
              Expanded(child: _numeral('${rewards.totals.coWatchers}', 'watched with')),
            ],
          ),
        ),
        const SizedBox(height: 20),
        _enter(3, _membershipCard(isPrem)),
        const SizedBox(height: 12),
        _settingsColumn(profile, withSeat: false),
      ],
    );
  }

  Widget _membershipCard(bool isPrem) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: PTColors.glassBase,
        borderRadius: BorderRadius.circular(PTRadius.panel),
        border: Border.all(color: PTColors.aisle),
      ),
      child: Column(
        crossAxisAlignment: .stretch,
        spacing: 12,
        children: [
          Text('MEMBERSHIP', style: PTText.label),
          Row(
            crossAxisAlignment: .end,
            spacing: 10,
            children: [
              Expanded(
                child: Text(
                  isPrem ? 'Patron seat' : 'Free seat',
                  style: PTText.cardHeading.copyWith(
                    fontSize: 20,
                    color: isPrem ? PTColors.premium : null,
                  ),
                ),
              ),
              Text(
                isPrem ? '16 seats · video · 24h' : '8 seats · voice · 4h',
                style: PTText.caption.copyWith(fontWeight: .w400),
              ),
            ],
          ),
          PTButton(
            label: isPrem ? 'Manage' : 'Get a Patron seat',
            variant: isPrem ? .secondary : .primary,
            icon: isPrem ? Symbols.arrow_forward_rounded : Symbols.crown_rounded,
            height: 48,
            onPressed: () => context.go('/lobby/subscribe?source=profile'),
          ),
        ],
      ),
    );
  }

  Widget _oneColumn(Profile profile, {required double nameSize}) {
    return Column(
      crossAxisAlignment: .stretch,
      children: [
        _identityColumn(profile, nameSize: nameSize),
        const SizedBox(height: 36),
        _settingsColumn(profile),
      ],
    );
  }

  /// One-shot stagger. Capped so the last section never waits noticeably.
  Widget _enter(int index, Widget child) => PTEntrance(
    delay: Duration(milliseconds: 45 * index.clamp(0, 7)),
    offset: 10,
    child: child,
  );

  // ─── Identity column ────────────────────────────────────────────────────

  Widget _identityColumn(Profile profile, {required double nameSize}) {
    final guest = profile.isGuest;
    return Column(
      crossAxisAlignment: .start,
      children: [
        _enter(0, Text(guest ? 'GUEST SEAT' : 'YOUR SEAT', style: PTText.label)),
        const SizedBox(height: 18),
        _enter(1, guest ? _guestAvatar() : _avatar(profile)),
        const SizedBox(height: 22),
        _enter(2, _nameBlock(profile, nameSize)),
        const SizedBox(height: 32),
        if (guest) _enter(3, _keepIdentity()) else _enter(3, _watchingBlock()),
      ],
    );
  }

  Widget _guestAvatar() {
    return Container(
      width: 112,
      height: 112,
      decoration: BoxDecoration(
        color: PTColors.aisle,
        shape: .circle,
        border: Border.all(color: PTColors.rail, width: 2),
      ),
      child: Icon(Symbols.person_rounded, size: 48, fill: 1, color: PTColors.white(0.4)),
    );
  }

  Widget _avatar(Profile profile, {double size = 112}) {
    final rewards = RewardsService.instance.state;
    final button = size < 80 ? 28.0 : 36.0;
    return SizedBox(
      width: size + 4,
      height: size + 4,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // A fresh photo scale-pulses itself in - confirmation the user is
          // already looking at, so no snackbar is needed for the happy path.
          PTEntrance(
            key: ValueKey(profile.avatarUrl),
            offset: 0,
            scaleFrom: 0.9,
            fade: false,
            duration: PTMotion.state,
            child: PTAvatar(
              userId: profile.id,
              displayName: profile.displayName,
              avatarUrl: profile.avatarUrl,
              frame: rewards.equippedFrame,
              premium: EntitlementService.instance.isPremium,
              size: size,
              ringColor: PTColors.rail,
            ),
          ),
          Positioned.fill(
            child: IgnorePointer(
              child: AnimatedOpacity(
                opacity: _uploadingAvatar ? 1 : 0,
                duration: PTMotion.functional(context, PTMotion.state),
                child: const DecoratedBox(
                  decoration: BoxDecoration(color: PTColors.canvasScrim, shape: .circle),
                ),
              ),
            ),
          ),
          Positioned(
            bottom: 0,
            right: 0,
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              child: PTPressable(
                onTap: _uploadingAvatar ? null : _showAvatarOptions,
                child: Container(
                  width: button,
                  height: button,
                  decoration: BoxDecoration(
                    color: PTColors.aisle,
                    borderRadius: BorderRadius.circular(PTRadius.control),
                    border: Border.all(color: PTColors.rail),
                  ),
                  child: AnimatedSwitcher(
                    duration: PTMotion.functional(context, PTMotion.state),
                    switchInCurve: PTMotion.enter,
                    switchOutCurve: PTMotion.exit,
                    child: _uploadingAvatar
                        ? PTLoader(key: const ValueKey('uploading'), size: button / 2)
                        : Icon(
                            Symbols.photo_camera_rounded,
                            key: const ValueKey('idle'),
                            size: button / 2,
                            fill: 1,
                            color: PTColors.fg.withValues(alpha: 0.85),
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

  Widget _nameBlock(Profile profile, double nameSize) {
    final isPrem = EntitlementService.instance.isPremium;
    final since = profile.createdAt;
    final sinceLabel = since != null
        ? 'Watching together since ${_monthName(since.month)} ${since.year}'
        : 'Watching together';
    return Column(
      crossAxisAlignment: .start,
      spacing: 10,
      children: [
        AnimatedSwitcher(
          duration: PTMotion.functional(context, PTMotion.state),
          switchInCurve: PTMotion.enter,
          switchOutCurve: PTMotion.exit,
          layoutBuilder: (current, previous) =>
              Stack(alignment: .topLeft, children: [...previous, ?current]),
          child: Text(
            profile.displayName,
            key: ValueKey(profile.displayName),
            maxLines: 3,
            overflow: .ellipsis,
            // Display type is already large; letting it grow at the body rate
            // turns a long name into three clipped fragments at 2x.
            textScaler: _displayScaler(context),
            style: PTText.display.copyWith(fontSize: nameSize, height: 1.02),
          ),
        ),
        if (profile.isGuest)
          const GuestBadge()
        else
          Row(
            spacing: 8,
            children: [
              if (isPrem)
                const Icon(Symbols.crown_rounded, size: 15, fill: 1, color: PTColors.premium),
              Flexible(
                child: Text(
                  isPrem ? 'PATRON SEAT' : 'FREE SEAT',
                  style: PTText.label.copyWith(
                    color: isPrem ? PTColors.premium : PTColors.white(0.7),
                  ),
                ),
              ),
            ],
          ),
        if (!profile.isGuest) Text(sinceLabel, style: PTText.caption.copyWith(fontWeight: .w400)),
      ],
    );
  }

  /// The guest's one real move: keep this seat by signing in. No box - a Beam
  /// rule down the side marks it as the thing on this page worth doing.
  Widget _keepIdentity() {
    return Container(
      padding: const EdgeInsets.only(left: 18),
      decoration: const BoxDecoration(
        border: Border(left: BorderSide(color: PTColors.primary, width: 2)),
      ),
      child: Column(
        crossAxisAlignment: .stretch,
        spacing: 14,
        children: [
          Text('Keep your identity', style: PTText.cardHeading),
          Text(
            'Sign in to pick a name and photo, and keep them across '
            'devices. Your current session carries over.',
            style: PTText.body.copyWith(fontSize: 14, color: PTColors.white(0.65), height: 1.5),
          ),
          if (AuthService.instance.isAppleSupported)
            AppleButton(
              label: 'Sign in with Apple',
              onPressed: () async {
                try {
                  await AuthService.instance.linkAppleIdentity();
                } catch (e, s) {
                  reportNonFatal(e, s, during: 'linking an Apple identity to a guest');
                  if (mounted) _snack("Couldn't start Apple sign-in. Try again.");
                }
              },
            ),
          GoogleButton(
            label: 'Sign in with Google',
            onPressed: () async {
              try {
                await AuthService.instance.linkGoogleIdentity();
              } catch (e, s) {
                reportNonFatal(e, s, during: 'linking a Google identity to a guest');
                if (mounted) _snack("Couldn't start Google sign-in. Try again.");
              }
            },
          ),
        ],
      ),
    );
  }

  Widget _watchingBlock() {
    final rewards = RewardsService.instance;
    final state = rewards.state;
    final streak = state.streak.current;
    return Column(
      crossAxisAlignment: .stretch,
      spacing: 18,
      children: [
        const _Rule(),
        _ActionRow(
          minRowWidth: 200,
          children: [
            Expanded(child: Text('WATCHING', style: PTText.label)),
            PTButton(
              label: 'Leaderboard',
              variant: .secondary,
              icon: Symbols.trophy_rounded,
              height: 34,
              expand: false,
              onPressed: () => context.go('/lobby/leaderboard'),
            ),
          ],
        ),
        Row(
          crossAxisAlignment: .start,
          spacing: 16,
          children: [
            Expanded(
              child: _numeral(
                '$streak',
                'day streak',
                color: streak > 0 ? PTColors.ember : PTColors.fg,
              ),
            ),
            Expanded(child: _numeral(formatWatchHours(state.totals.watched), 'watched')),
            Expanded(child: _numeral('${state.totals.coWatchers}', 'watched with')),
          ],
        ),
        if (rewards.referrals > 0)
          Text(
            '${rewards.referrals} ${rewards.referrals == 1 ? 'person' : 'people'} '
            'joined SyncTogether through one of your rooms.',
            style: PTText.finePrint.copyWith(fontSize: 12, color: PTColors.textAccent),
          ),
        if (state.seasons.isNotEmpty) SeasonTrophies(seasons: state.seasons),
        BadgeShelf(state: state, crossAxisCount: 4),
      ],
    );
  }

  TextScaler _displayScaler(BuildContext context) =>
      MediaQuery.textScalerOf(context).clamp(maxScaleFactor: 1.25);

  /// A stat set as type, not a tile: the numeral carries it.
  Widget _numeral(String value, String label, {Color color = PTColors.fg}) {
    return Column(
      crossAxisAlignment: .start,
      spacing: 4,
      children: [
        FittedBox(
          fit: .scaleDown,
          alignment: .centerLeft,
          child: Text(
            value,
            maxLines: 1,
            textScaler: _displayScaler(context),
            style: PTText.display.copyWith(fontSize: 38, color: color),
          ),
        ),
        Text(
          label.toUpperCase(),
          maxLines: 2,
          overflow: .ellipsis,
          style: PTText.label.copyWith(fontSize: 10),
        ),
      ],
    );
  }

  // ─── Settings column ────────────────────────────────────────────────────

  Widget _settingsColumn(Profile profile, {bool withSeat = true}) {
    final guest = profile.isGuest;
    final sections = <Widget>[
      if (withSeat) _seatSection(),
      _accountSection(profile),
      if (!guest) _boardsSection(),
      _mediaQuotaSection(),
      _audioVideoSection(),
      if (supportsSelfUpdate) _updatesSection(),
      _blockedSection(),
      _privacySection(),
      _exitSection(guest),
    ];
    return Column(
      crossAxisAlignment: .stretch,
      children: [for (var i = 0; i < sections.length; i++) _enter(i + 1, sections[i])],
    );
  }

  Widget _seatSection() {
    final isPrem = EntitlementService.instance.isPremium;
    return _Section(
      card: _cards,
      kicker: 'Membership',
      children: [
        _settingRow(
          title: isPrem
              ? 'Patron seat'
              : (ProfileService.instance.profile?.isGuest ?? false)
              ? 'Guest seat'
              : 'Free seat',
          subtitle: isPrem
              ? '16-seat rooms with video facecams, 24-hour rooms and up to 20 saved.'
              : (ProfileService.instance.profile?.isGuest ?? false)
              ? 'Rooms of 4 for an hour. Sign in for free rooms of 8 and four-hour sessions.'
              : 'Rooms of 8 with voice, 4 hours a session. A Patron seat brings 16-seat '
                    'rooms, video facecams, 24-hour and saved rooms.',
          titleColor: isPrem ? PTColors.premium : null,
          minRowWidth: 420,
          trailing: PTButton(
            label: isPrem ? 'Manage' : 'Get a Patron seat',
            variant: isPrem ? .secondary : .primary,
            icon: isPrem ? Symbols.arrow_forward_rounded : Symbols.crown_rounded,
            height: 38,
            expand: false,
            onPressed: () => context.go('/lobby/subscribe?source=profile'),
          ),
        ),
      ],
    );
  }

  Widget _accountSection(Profile profile) {
    if (profile.isGuest) {
      return _Section(
        card: _cards,
        kicker: 'Account',
        children: [
          Opacity(
            opacity: 0.5,
            child: _settingRow(
              title: 'Display name',
              subtitle: profile.displayName,
              trailing: Icon(Symbols.lock_rounded, size: 17, fill: 1, color: PTColors.white(0.6)),
            ),
          ),
        ],
      );
    }
    return _Section(
      card: _cards,
      kicker: 'Account',
      children: [
        MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            behavior: .opaque,
            onTap: () => _editDisplayName(profile),
            child: _settingRow(
              key: ValueKey('name-${profile.displayName}'),
              title: 'Display name',
              subtitle: profile.displayName,
              subtitleStrong: true,
              trailing: Icon(Symbols.edit_rounded, size: 18, color: PTColors.white(0.45)),
            ),
          ),
        ),
        const _Rule(faint: true),
        _settingRow(
          title: 'Email',
          subtitle: profile.email ?? '-',
          subtitleStrong: true,
          trailing: Icon(Symbols.lock_rounded, size: 17, fill: 1, color: PTColors.white(0.35)),
        ),
        Text(
          "Linked to your Google account, so it can't be changed.",
          style: PTText.finePrint.copyWith(color: PTColors.white(0.35)),
        ),
        ..._passwordRows(profile),
      ],
    );
  }

  /// Lets an account set a password, so email sign-in is not code-only.
  ///
  /// There is deliberately no "you already have one" state: Supabase exposes
  /// no flag for it, and inferring it from the identity list would be wrong
  /// for anyone who signed up with a one-time code. Setting a password is
  /// idempotent, so the control reads the same either way.
  List<Widget> _passwordRows(Profile profile) {
    if (profile.isGuest || (profile.email ?? '').isEmpty) return const [];
    return [
      const _Rule(faint: true),
      _settingRow(
        title: 'Password',
        subtitle: 'Sign in with a password instead of a code',
        minRowWidth: 380,
        trailing: PTButton(
          label: 'Set password',
          variant: .secondary,
          height: 34,
          expand: false,
          onPressed: () => unawaited(_setPassword()),
        ),
      ),
      Text(
        'Optional. A 6-digit code always works, so forgetting this can never lock you out.',
        style: PTText.finePrint.copyWith(color: PTColors.white(0.35)),
      ),
    ];
  }

  Widget _boardsSection() {
    final state = RewardsService.instance.state;
    return _Section(
      card: _cards,
      kicker: 'On the boards',
      children: [
        PTToggleRow(
          title: 'Show me on leaderboards',
          subtitle:
              'Your name, avatar, streak and rank become visible to people you '
              'watch with and on the public board. What you watch, who with, and '
              'anything you type stays private either way.',
          value: state.publicProfile,
          onChanged: (value) {
            Analytics.instance.track('leaderboard_opt_in', {'on': value});
            unawaited(RewardsService.instance.setPublicProfile(value));
          },
        ),
        if (state.publicProfile) ...[const _Rule(faint: true), _handleRow(state)],
        if (state.availableFrames.isNotEmpty) ...[const _Rule(faint: true), _framePicker(state)],
        _link('Manage shared recaps', () => showSharedRecapsDialog(context)),
      ],
    );
  }

  Widget _handleRow(RewardState state) {
    final handle = state.handle;
    // A handle is permanent, globally unique and first-come, which makes it the
    // one thing here worth squatting - so it is the Premium perk. Being *on*
    // the board is free; having a page of your own is not.
    if (!state.isPremium && handle == null) {
      return MouseRegion(
        cursor: SystemMouseCursors.click,
        child: PTPressable(
          onTap: () {
            Analytics.instance.track('upgrade_cta_clicked', {
              'surface': 'handle',
              'action': 'notify',
            });
            context.go('/lobby/subscribe?source=handle');
          },
          child: _settingRow(
            title: 'Public handle',
            titleTag: const DialogTag('Patron', tone: DialogTagTone.premium),
            subtitle:
                'Patron seats get a page at synctogether.app/u/you, with your streak and '
                'badges on it.',
            minRowWidth: 360,
            trailing: IgnorePointer(
              child: PTButton(
                label: 'Get a handle',
                variant: .secondary,
                icon: Symbols.crown_rounded,
                height: 36,
                expand: false,
                onPressed: () {},
              ),
            ),
          ),
        ),
      );
    }
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: PTPressable(
        onTap: () => unawaited(_editHandle(state)),
        child: _settingRow(
          key: ValueKey('handle-$handle'),
          title: 'Public handle',
          subtitle: handle == null ? 'Pick one to get a shareable page' : '@$handle',
          subtitleStrong: handle != null,
          trailing: Icon(Symbols.edit_rounded, size: 18, color: PTColors.white(0.45)),
        ),
      ),
    );
  }

  Widget _framePicker(RewardState state) {
    final profile = ProfileService.instance.profile;
    final frames = state.availableFrames.toList()..sort((a, b) => a.index.compareTo(b.index));
    return Column(
      crossAxisAlignment: .start,
      spacing: 12,
      children: [
        Text('Avatar frame', style: PTText.body.copyWith(fontSize: 14, fontWeight: .w600)),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            for (final frame in [null, ...frames])
              PTPressable(
                onTap: () => unawaited(_equip(frame)),
                child: AnimatedOpacity(
                  opacity: state.equippedFrame == frame ? 1 : 0.45,
                  duration: PTMotion.functional(context, PTMotion.state),
                  child: PTAvatar(
                    userId: profile?.id ?? '',
                    displayName: profile?.displayName ?? '?',
                    avatarUrl: profile?.avatarUrl,
                    frame: frame,
                    size: 40,
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }

  Widget _mediaQuotaSection() {
    final profile = ProfileService.instance.profile;
    final limits = EntitlementService.instance.limitsOrFallback;
    final isPrem = EntitlementService.instance.isPremium;
    final isGuest = profile?.isGuest ?? true;

    final weeklyLimit = limits.mediaSharingWeeklyBytes;
    final usedBytes = profile?.r2UploadBytes7d ?? 0;
    final remainingBytes = profile?.remainingWeeklyBytes(weeklyLimit) ?? weeklyLimit;
    final fractionUsed = weeklyLimit > 0 ? (usedBytes / weeklyLimit).clamp(0.0, 1.0) : 0.0;

    return _Section(
      card: _cards,
      kicker: 'Media sharing',
      trailing: _link('Details', () => showMediaQuotaDialog(context)),
      children: [
        Text(
          'Media Sharing Bandwidth',
          style: PTText.body.copyWith(fontSize: 14, fontWeight: .w600),
        ),
        if (isPrem)
          Text(
            'Unlimited weekly uploads active with your Premium subscription.',
            style: PTText.finePrint.copyWith(color: PTColors.white(0.6)),
          )
        else if (!isGuest) ...[
          Row(
            children: [
              Expanded(
                child: Text(
                  '${Profile.formatBytes(remainingBytes)} available of ${Profile.formatBytes(weeklyLimit)}',
                  style: PTText.finePrint.copyWith(color: PTColors.white(0.6)),
                  overflow: .ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '${Profile.formatBytes(usedBytes)} used',
                style: PTText.mono.copyWith(color: PTColors.textAccent, fontSize: 11),
              ),
            ],
          ),
          ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: LinearProgressIndicator(
              value: fractionUsed,
              backgroundColor: PTColors.aisle,
              valueColor: AlwaysStoppedAnimation<Color>(
                fractionUsed > 0.85 ? PTColors.warning : PTColors.textAccent,
              ),
              minHeight: 3,
            ),
          ),
        ] else
          Text(
            'Sign in for a free 2.5 GB weekly streaming quota.',
            style: PTText.finePrint.copyWith(color: PTColors.white(0.5)),
          ),
        if (limits.canShareMedia) ...[
          const _Rule(faint: true),
          PTToggleRow(
            title: 'Auto-share local videos with room',
            subtitle: _mediaSharingRememberedChoice == null
                ? 'Currently asks every time you pick a local video. Toggle on to always upload and share, or off to always play locally.'
                : (_mediaSharingRememberedChoice!
                      ? 'Always uploads and shares local videos with room members.'
                      : 'Always plays local videos locally without uploading.'),
            value: _mediaSharingRememberedChoice ?? false,
            onChanged: (enabled) => _setMediaSharingPreference(enabled),
          ),
          if (_mediaSharingRememberedChoice != null)
            _link('Reset to ask every time', _resetMediaSharingPreference),
        ],
      ],
    );
  }

  Widget _audioVideoSection() {
    return _Section(
      card: _cards,
      kicker: 'Sound & picture',
      children: [
        _settingRow(
          title: 'Audio & Video',
          subtitle: 'Microphone, camera, and speaker defaults',
          minRowWidth: 380,
          trailing: PTButton(
            label: 'Configure',
            variant: .secondary,
            icon: Symbols.arrow_forward_rounded,
            height: 38,
            expand: false,
            onPressed: () => showAvSettingsDialog(context),
          ),
        ),
      ],
    );
  }

  Widget _updatesSection() {
    if (!supportsSelfUpdate) return const SizedBox.shrink();
    return _Section(
      card: _cards,
      kicker: 'Updates',
      children: [
        ListenableBuilder(
          listenable: UpdateService.instance,
          builder: (context, _) => PTToggleRow(
            title: 'Automatically download updates',
            subtitle:
                'Download updates silently in the background so you can restart immediately when ready.',
            value: UpdateService.instance.autoDownload,
            onChanged: (enabled) => UpdateService.instance.setAutoDownload(enabled),
          ),
        ),
      ],
    );
  }

  /// The list of people this account has blocked, with a way back.
  ///
  /// A block the user cannot see is a block the user cannot undo. It renders
  /// nothing when the list is empty rather than an empty state: this sits in
  /// a settings screen most people will never need, and a bare "Blocked
  /// people" heading only invites the question.
  Widget _blockedSection() {
    return ListenableBuilder(
      listenable: ModerationService.instance,
      builder: (context, _) {
        final blocked = ModerationService.instance.blockedUsers;
        if (blocked.isEmpty) return const SizedBox.shrink();
        return _Section(
          card: _cards,
          kicker: 'Blocked people',
          children: [
            Text(
              'You will not see their messages or cameras in any room.',
              style: PTText.finePrint.copyWith(color: PTColors.white(0.55)),
            ),
            for (final user in blocked)
              Row(
                spacing: 12,
                children: [
                  PTAvatar(
                    userId: user.userId,
                    displayName: user.displayName,
                    avatarUrl: user.avatarUrl,
                    size: 32,
                  ),
                  Expanded(
                    child: Text(
                      user.displayName,
                      overflow: .ellipsis,
                      style: PTText.body.copyWith(fontSize: 14, fontWeight: .w500),
                    ),
                  ),
                  PTButton(
                    label: 'Unblock',
                    variant: .secondary,
                    height: 34,
                    expand: false,
                    onPressed: () => unawaited(_unblock(user)),
                  ),
                ],
              ),
          ],
        );
      },
    );
  }

  Widget _privacySection() {
    return _Section(
      card: _cards,
      kicker: 'Privacy',
      children: [
        ListenableBuilder(
          listenable: AnalyticsConsent.instance,
          builder: (context, _) {
            final sharing = !AnalyticsConsent.instance.optedOut;
            return Column(
              crossAxisAlignment: .stretch,
              spacing: 12,
              children: [
                PTToggleRow(
                  title: 'Share usage data',
                  subtitle:
                      'Counts of things like rooms created and features used, so we know what '
                      'to build next. Never your chats, file names or links. Turning this off '
                      'also pauses streaks, badges and leaderboards, since they are built from the '
                      'same records, and a switch that leaves some of it running would not be '
                      'much of a switch.',
                  value: sharing,
                  onChanged: (shareData) => AnalyticsConsent.instance.setOptedOut(!shareData),
                ),
                _link('See exactly what we collect', () => showAnalyticsDisclosure(context)),
                AnimatedSize(
                  duration: PTMotion.functional(context, PTMotion.state),
                  curve: PTMotion.enter,
                  alignment: .topLeft,
                  child: sharing
                      ? const SizedBox(width: double.infinity)
                      : Container(
                          width: double.infinity,
                          padding: const EdgeInsets.only(left: 14),
                          decoration: const BoxDecoration(
                            border: Border(left: BorderSide(color: PTColors.rail, width: 2)),
                          ),
                          child: Text(
                            'Nothing is being collected. Your streak is paused where it was, not '
                            'lost. Turn this back on and it picks up from the next session.',
                            style: PTText.finePrint.copyWith(fontSize: 12, height: 1.45),
                          ),
                        ),
                ),
              ],
            );
          },
        ),
        PTButtonBar(
          buttons: [
            PTButton(
              label: 'Privacy policy',
              variant: .secondary,
              icon: Symbols.open_in_new_rounded,
              height: 36,
              onPressed: () => launchUrl(
                Uri.parse('https://synctogether.app/privacy'),
                mode: LaunchMode.externalApplication,
              ),
            ),
            PTButton(
              label: 'Terms of service',
              variant: .secondary,
              icon: Symbols.open_in_new_rounded,
              height: 36,
              onPressed: () => launchUrl(
                Uri.parse('https://synctogether.app/terms'),
                mode: LaunchMode.externalApplication,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _exitSection(bool guest) {
    if (guest) {
      return _Section(
        card: _cards,
        kicker: 'Leave',
        children: [
          PTButton(
            label: 'End guest session',
            icon: Symbols.logout_rounded,
            variant: .secondary,
            onPressed: AuthService.instance.signOut,
          ),
        ],
      );
    }
    return _Section(
      card: _cards,
      kicker: 'Leave',
      children: [
        PTButtonBar(
          buttons: [
            PTButton(
              label: 'Log out',
              icon: Symbols.logout_rounded,
              variant: .secondary,
              onPressed: () {
                unawaited(UnlockLog.instance.clear());
                AuthService.instance.signOut();
              },
            ),
            PTButton(
              label: 'Delete account',
              icon: Symbols.delete_rounded,
              variant: .destructive,
              onPressed: _confirmDeleteAccount,
            ),
          ],
        ),
      ],
    );
  }

  /// A settings row: title over a quieter line, trailing control at the end.
  /// Drops the control beneath the text when the row cannot hold both.
  Widget _settingRow({
    Key? key,
    required String title,
    required String subtitle,
    required Widget trailing,
    bool subtitleStrong = false,
    Color? titleColor,
    Widget? titleTag,
    double minRowWidth = 300,
  }) {
    return _ActionRow(
      key: key,
      minRowWidth: minRowWidth,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: .start,
            spacing: 3,
            children: [
              Row(
                spacing: 8,
                children: [
                  Flexible(
                    child: Text(
                      title,
                      style: PTText.body.copyWith(
                        fontSize: 14,
                        fontWeight: .w600,
                        color: titleColor,
                      ),
                    ),
                  ),
                  ?titleTag,
                ],
              ),
              Text(
                subtitle,
                overflow: .ellipsis,
                maxLines: 3,
                style: subtitleStrong
                    ? PTText.body.copyWith(fontSize: 14, color: PTColors.white(0.7))
                    : PTText.body.copyWith(
                        fontSize: 12.5,
                        color: PTColors.white(0.5),
                        height: 1.45,
                      ),
              ),
            ],
          ),
        ),
        trailing,
      ],
    );
  }

  Widget _link(String label, VoidCallback onTap) {
    return Row(
      mainAxisSize: .min,
      children: [
        // Flexible, not a bare child: a longer translation at phone width
        // would otherwise overflow outright.
        Flexible(
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            child: PTPressable(
              onTap: onTap,
              child: Text(
                label,
                style: PTText.caption.copyWith(
                  color: PTColors.link,
                  decoration: TextDecoration.underline,
                  decorationColor: PTColors.link.withValues(alpha: 0.5),
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _backHeader({double iconSize = 20, double size = 44, double? titleSize}) {
    return Row(
      spacing: 14,
      children: [
        PTIconButton(
          icon: Symbols.arrow_back_rounded,
          iconSize: iconSize,
          size: size,
          onPressed: () => context.go('/lobby'),
        ),
        Flexible(
          child: Text(
            'Profile',
            maxLines: 1,
            overflow: .ellipsis,
            style: titleSize == null
                ? PTText.cardHeading
                : PTText.cardHeading.copyWith(fontSize: titleSize),
          ),
        ),
      ],
    );
  }

  Future<void> _editHandle(RewardState state) async {
    final controller = TextEditingController(text: state.handle ?? '');
    final value = await showGlassDialog<String>(
      context: context,
      width: 400,
      builder: (dialogContext) => Column(
        mainAxisSize: .min,
        crossAxisAlignment: .start,
        spacing: 16,
        children: [
          Text('Pick a handle', style: PTText.cardHeading),
          Text(
            'This becomes synctogether.app/u/yourhandle, a page with your streak '
            'and badges on it that you can link to.',
            style: PTText.caption,
          ),
          PTTextField(
            controller: controller,
            hint: 'yourhandle',
            autofocus: true,
            maxLength: 20,
            onSubmitted: (v) => Navigator.of(dialogContext).pop(v),
          ),
          Row(
            mainAxisAlignment: .end,
            spacing: 11,
            children: [
              PTButton(
                label: 'Cancel',
                variant: .secondary,
                height: 46,
                expand: false,
                onPressed: () => Navigator.of(dialogContext).pop(),
              ),
              PTButton(
                label: 'Save',
                height: 46,
                expand: false,
                onPressed: () => Navigator.of(dialogContext).pop(controller.text),
              ),
            ],
          ),
        ],
      ),
    );
    controller.dispose();
    if (value == null || value.trim().isEmpty) return;
    try {
      await RewardsService.instance.claimHandle(value);
      // The one thing Premium actually buys in this whole feature. Whether
      // anybody claims one is the question that decides if handles - and the
      // public pages built on them - were worth shipping. The handle itself is
      // deliberately not a property: it is a name somebody chose, and it tells
      // the funnel nothing that the event alone does not.
      Analytics.instance.track('handle_claimed');
      if (mounted) _snack('Handle claimed.', kind: .success);
    } on RewardsFailure catch (failure) {
      if (mounted) _snack(failure.message);
    }
  }

  Future<void> _equip(AvatarFrame? frame) async {
    try {
      await RewardsService.instance.equipFrame(frame);
      Analytics.instance.track('frame_equipped', {'frame': frame?.name ?? 'none'});
    } on RewardsFailure catch (failure) {
      if (mounted) _snack(failure.message);
    }
  }

  Future<void> _unblock(BlockedUser user) async {
    try {
      await ModerationService.instance.unblock(user.userId);
      if (mounted) _snack('${user.displayName} is unblocked.', kind: .success);
    } catch (_) {
      if (mounted) _snack("Couldn't unblock them. Try again.");
    }
  }

  Future<void> _setPassword() async {
    final password = await showGlassDialog<String>(
      context: context,
      width: 420,
      builder: (_) => const _SetPasswordDialog(),
    );
    if (password == null || !mounted) return;
    try {
      await AuthService.instance.setPassword(password);
      if (mounted) _snack('Password saved. You can sign in with it next time.', kind: .success);
    } catch (e, s) {
      reportNonFatal(e, s, during: 'setting an account password');
      if (mounted) _snack("Couldn't save that password. Try again.");
    }
  }

  String _monthName(int month) => const [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ][month - 1];
}

/// A ruled settings section: a Rail hairline, a mono uppercase kicker, then
/// rows. No box - the rule and the kicker do the grouping.
class _Section extends StatelessWidget {
  const _Section({required this.kicker, required this.children, this.trailing, this.card = false});

  final String kicker;
  final List<Widget> children;
  final Widget? trailing;

  /// A Seat card (the wide desktop grid) rather than a ruled section.
  final bool card;

  @override
  Widget build(BuildContext context) {
    if (card) {
      return Container(
        margin: const EdgeInsets.only(bottom: 20),
        padding: const EdgeInsets.fromLTRB(22, 20, 22, 22),
        decoration: BoxDecoration(
          color: PTColors.glassBase,
          border: Border.all(color: PTColors.aisle),
          borderRadius: BorderRadius.circular(PTRadius.panel),
        ),
        child: Column(
          crossAxisAlignment: .stretch,
          spacing: 16,
          children: [
            Row(
              spacing: 12,
              children: [
                Expanded(child: Text(kicker.toUpperCase(), style: PTText.label)),
                ?trailing,
              ],
            ),
            ...children,
          ],
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 30),
      child: Column(
        crossAxisAlignment: .stretch,
        spacing: 16,
        children: [
          const _Rule(),
          Row(
            spacing: 12,
            children: [
              Expanded(child: Text(kicker.toUpperCase(), style: PTText.label)),
              ?trailing,
            ],
          ),
          ...children,
        ],
      ),
    );
  }
}

/// A one-pixel hairline. [faint] separates rows inside a section.
class _Rule extends StatelessWidget {
  const _Rule({this.faint = false});

  final bool faint;

  @override
  Widget build(BuildContext context) =>
      SizedBox(height: 1, child: ColoredBox(color: faint ? PTColors.aisle : PTColors.rail));
}

/// Collects a new account password. Pops the password, or null if cancelled.
class _SetPasswordDialog extends StatefulWidget {
  const _SetPasswordDialog();

  @override
  State<_SetPasswordDialog> createState() => _SetPasswordDialogState();
}

class _SetPasswordDialogState extends State<_SetPasswordDialog> {
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _obscure = true;
  String? _error;

  /// The server enforces its own floor; this is the friendlier one, checked
  /// here so the failure arrives before the round trip rather than after it.
  static const _minLength = 8;

  @override
  void dispose() {
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  void _submit() {
    final password = _password.text;
    if (password.length < _minLength) {
      setState(() => _error = 'Use at least $_minLength characters.');
      return;
    }
    if (password != _confirm.text) {
      setState(() => _error = "Those two don't match.");
      return;
    }
    Navigator.of(context).pop(password);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: .min,
      crossAxisAlignment: .stretch,
      children: [
        Row(
          spacing: 10,
          children: [
            const Icon(Symbols.lock_rounded, size: 22, color: PTColors.textAccent),
            Expanded(
              child: Text('Set a password', style: PTText.screenTitle.copyWith(fontSize: 18)),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          'You can then sign in with your email and this password. A 6-digit '
          'code still works, so forgetting it is never a lockout.',
          style: PTText.body.copyWith(color: PTColors.white(0.7), height: 1.45),
        ),
        const SizedBox(height: 16),
        PTTextField(
          controller: _password,
          label: 'New password',
          hint: 'At least $_minLength characters',
          obscureText: _obscure,
          autofocus: true,
          onChanged: (_) => setState(() => _error = null),
          suffixIcon: IconButton(
            icon: Icon(
              _obscure ? Symbols.visibility_rounded : Symbols.visibility_off_rounded,
              size: 18,
              color: PTColors.white(0.5),
            ),
            tooltip: _obscure ? 'Show password' : 'Hide password',
            onPressed: () => setState(() => _obscure = !_obscure),
          ),
        ),
        const SizedBox(height: 12),
        PTTextField(
          controller: _confirm,
          label: 'Confirm password',
          obscureText: _obscure,
          errorText: _error,
          onChanged: (_) => setState(() => _error = null),
          onSubmitted: (_) => _submit(),
        ),
        const SizedBox(height: 18),
        Row(
          spacing: 12,
          children: [
            Expanded(
              child: PTButton(
                label: 'Cancel',
                variant: .secondary,
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),
            Expanded(
              child: PTButton(label: 'Save', onPressed: _submit),
            ),
          ],
        ),
      ],
    );
  }
}

/// A settings row of `[leading..., Expanded(text), trailing button]`. The
/// button has a fixed intrinsic width, so on a 320 phone or at 2.0x text the
/// row cannot fit; below that point the last child drops under the rest,
/// right-aligned, instead of overflowing.
class _ActionRow extends StatelessWidget {
  const _ActionRow({super.key, required this.children, this.minRowWidth = 360});

  final List<Widget> children;

  /// Width (before text scaling) below which the trailing action drops
  /// beneath the rest. A heading with one short button needs far less room
  /// than a card with an icon, two lines of copy and a CTA.
  final double minRowWidth;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) {
        final needed = MediaQuery.textScalerOf(context).scale(minRowWidth);
        if (box.maxWidth >= needed) {
          return Row(spacing: 12, children: children);
        }
        return Column(
          crossAxisAlignment: .end,
          spacing: 10,
          children: [
            Row(spacing: 12, children: children.sublist(0, children.length - 1)),
            children.last,
          ],
        );
      },
    );
  }
}
