import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:synctogether/auth/auth_service.dart';
import 'package:synctogether/diagnostics.dart';
import 'package:synctogether/profile/entitlement_service.dart';
import 'package:synctogether/profile/profile_models.dart';
import 'package:synctogether/profile/profile_service.dart';
import 'package:synctogether/ui/buttons.dart';
import 'package:synctogether/ui/glass.dart';
import 'package:synctogether/ui/pt_theme.dart';

enum MediaQuotaRejectionReason { singleFileLimitExceeded, weeklyQuotaExceeded, guestBlocked }

class MediaQuotaContext {
  const MediaQuotaContext({
    required this.reason,
    this.fileName,
    this.fileSize,
    this.maxBytes,
    this.remainingBytes,
  });

  final MediaQuotaRejectionReason reason;
  final String? fileName;
  final int? fileSize;
  final int? maxBytes;
  final int? remainingBytes;
}

Future<void> showMediaQuotaDialog(BuildContext context, {MediaQuotaContext? quotaContext}) async {
  await showGlassDialog(
    context: context,
    width: 450,
    scrollable: false,
    padding: const EdgeInsets.symmetric(vertical: 24),
    builder: (dialogContext) => MediaQuotaDialogBody(quotaContext: quotaContext),
  );
}

class MediaQuotaDialogBody extends StatelessWidget {
  const MediaQuotaDialogBody({super.key, this.quotaContext});

  final MediaQuotaContext? quotaContext;

  static const _kGb = 1024 * 1024 * 1024;

  @override
  Widget build(BuildContext context) {
    final profile = ProfileService.instance.profile;
    final limits = EntitlementService.instance.limitsOrFallback;
    final isPrem = EntitlementService.instance.isPremium;
    final isGuest = profile?.isGuest ?? true;

    final weeklyLimit = limits.mediaSharingWeeklyBytes;
    final usedBytes = profile?.r2UploadBytes7d ?? 0;
    final remainingBytes = profile?.remainingWeeklyBytes(weeklyLimit) ?? weeklyLimit;
    final fractionUsed = weeklyLimit > 0 ? (usedBytes / weeklyLimit).clamp(0.0, 1.0) : 0.0;
    final resetDuration = profile?.timeUntilQuotaReset;
    final reason = quotaContext?.reason;
    final blocked = reason != null;

    final title = switch (reason) {
      .singleFileLimitExceeded => 'Too big to share',
      .weeklyQuotaExceeded => 'Not enough allowance left',
      .guestBlocked => 'Sharing needs an account',
      null => isGuest ? 'Sharing needs an account' : 'Sharing allowance',
    };

    void subscribe() {
      Navigator.of(context).pop();
      final source = switch (reason) {
        .singleFileLimitExceeded => 'quota_dialog_single_file',
        .weeklyQuotaExceeded => 'quota_dialog_weekly',
        _ => 'quota_dialog',
      };
      context.push('/lobby/subscribe?source=$source');
    }

    // Tall enough: header and actions stay pinned and only the middle
    // scrolls. Short windows (landscape phones, big text) cannot afford two
    // pinned bands, so the whole body scrolls as one instead.
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxBodyHeight = constraints.maxHeight.clamp(0.0, 720.0);
        final compact = maxBodyHeight < MediaQuery.textScalerOf(context).scale(520);
        Widget middle(Widget child) => compact
            ? Padding(padding: const EdgeInsets.symmetric(horizontal: 20), child: child)
            : Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: child,
                ),
              );
        final body = Column(
          mainAxisSize: .min,
          crossAxisAlignment: .start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: GlassDialogHeader(
                eyebrow: isPrem ? 'Patron · projection' : 'Projection allowance',
                eyebrowColor: blocked && reason != .guestBlocked ? PTColors.danger : null,
                title: title,
                onClose: () => Navigator.of(context).pop(),
              ),
            ),
            const SizedBox(height: 16),
            middle(
              Column(
                mainAxisSize: .min,
                crossAxisAlignment: .stretch,
                spacing: 16,
                children: [
                  if (blocked && reason != .guestBlocked)
                    _BlockedFile(quotaContext: quotaContext!)
                  else if (isPrem)
                    const DialogNote(
                      tone: DialogNoteTone.premium,
                      icon: Symbols.verified_rounded,
                      child: Text('No weekly cap. Share videos up to 10 GB each.'),
                    )
                  else if (!isGuest)
                    _Allowance(
                      remaining: remainingBytes,
                      limit: weeklyLimit,
                      used: usedBytes,
                      fraction: fractionUsed,
                      recharge: resetDuration != null && resetDuration.inHours > 0
                          ? _formatReset(resetDuration)
                          : null,
                    )
                  else
                    Text(
                      'Guest rooms play local files only. Sign in and you get a free '
                      '2.5 GB a week to stream a file to everyone in your room.',
                      style: PTText.body.copyWith(
                        fontSize: 14,
                        height: 1.45,
                        color: PTColors.white(0.8),
                      ),
                    ),
                  if (reason == .singleFileLimitExceeded)
                    Text(
                      isPrem
                          ? 'Patron seats share up to 10 GB a file. It still plays locally.'
                          : 'Free seats share up to 2 GB a file. It still plays locally.',
                      style: PTText.body.copyWith(
                        fontSize: 14,
                        height: 1.45,
                        color: PTColors.white(0.8),
                      ),
                    )
                  else if (reason == .weeklyQuotaExceeded)
                    Text(
                      'Your allowance tops back up as uploads age out of the last 7 days. '
                      'It still plays locally.',
                      style: PTText.body.copyWith(
                        fontSize: 14,
                        height: 1.45,
                        color: PTColors.white(0.8),
                      ),
                    ),
                  if (!blocked)
                    Column(
                      crossAxisAlignment: .start,
                      spacing: 10,
                      children: [
                        _FeatureRow(
                          icon: Symbols.schedule_rounded,
                          title: 'Rolling 7 days',
                          description: 'Uploads free up a week after they finish.',
                        ),
                        _FeatureRow(
                          icon: Symbols.person_rounded,
                          title: 'Free',
                          description: '2.5 GB a week, 2 GB per file.',
                        ),
                        _FeatureRow(
                          icon: Symbols.star_rounded,
                          title: 'Patron',
                          description: 'No weekly cap, 10 GB per file.',
                          highlight: true,
                        ),
                      ],
                    ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: isGuest
                  ? Column(
                      mainAxisSize: .min,
                      crossAxisAlignment: .stretch,
                      spacing: 10,
                      children: [
                        if (AuthService.instance.isAppleSupported)
                          AppleButton(
                            label: 'Sign in with Apple (Free 2.5 GB)',
                            onPressed: () async {
                              Navigator.of(context).pop();
                              try {
                                await AuthService.instance.linkAppleIdentity();
                              } catch (e, s) {
                                reportNonFatal(
                                  e,
                                  s,
                                  during: 'linking Apple identity from media quota dialog',
                                );
                              }
                            },
                          ),
                        GoogleButton(
                          label: 'Sign in with Google (Free 2.5 GB)',
                          onPressed: () async {
                            Navigator.of(context).pop();
                            try {
                              await AuthService.instance.linkGoogleIdentity();
                            } catch (e, s) {
                              reportNonFatal(
                                e,
                                s,
                                during: 'linking Google identity from media quota dialog',
                              );
                            }
                          },
                        ),
                        PTButton(
                          maxLines: 2,
                          label: 'Sign in with Email (Free 2.5 GB)',
                          icon: Symbols.mail_rounded,
                          variant: .secondary,
                          onPressed: () async {
                            Navigator.of(context).pop();
                            try {
                              await AuthService.instance.signOut();
                            } catch (e, s) {
                              reportNonFatal(
                                e,
                                s,
                                during: 'signing out guest for email sign-in from quota dialog',
                              );
                            }
                          },
                        ),
                        DialogTextButton(
                          label: 'Maybe later',
                          onPressed: () => Navigator.of(context).pop(),
                        ),
                      ],
                    )
                  : isPrem
                  ? PTButton(
                      maxLines: 2,
                      label: blocked ? 'Play it locally' : 'Got it',
                      onPressed: () => Navigator.of(context).pop(),
                    )
                  : blocked
                  // A blocked upload still plays locally - sharing only adds
                  // a stream for members without a copy - so that is the lit
                  // action, and the upsell is Brass text beneath it.
                  ? Column(
                      mainAxisSize: .min,
                      crossAxisAlignment: .stretch,
                      spacing: 12,
                      children: [
                        PTButton(
                          maxLines: 2,
                          label: 'Play it locally',
                          onPressed: () => Navigator.of(context).pop(),
                        ),
                        DialogTextButton(
                          label: reason == .singleFileLimitExceeded
                              ? 'Patron seats share up to 10 GB'
                              : 'Patron seats have no weekly cap',
                          color: PTColors.premium,
                          underline: false,
                          onPressed: subscribe,
                        ),
                      ],
                    )
                  : Row(
                      children: [
                        Expanded(
                          child: Align(
                            alignment: .centerLeft,
                            child: DialogTextButton(
                              label: 'Get a Patron seat',
                              color: PTColors.premium,
                              underline: false,
                              textAlign: TextAlign.start,
                              onPressed: subscribe,
                            ),
                          ),
                        ),
                        PTButton(
                          maxLines: 2,
                          label: 'Got it',
                          expand: false,
                          onPressed: () => Navigator.of(context).pop(),
                        ),
                      ],
                    ),
            ),
          ],
        );
        return compact
            ? SingleChildScrollView(child: body)
            : ConstrainedBox(
                constraints: BoxConstraints(maxHeight: maxBodyHeight),
                child: body,
              );
      },
    );
  }

  static String _formatReset(Duration d) {
    if (d.inDays > 0) {
      final days = d.inDays;
      final hours = d.inHours % 24;
      return hours > 0 ? '${days}d ${hours}h' : '${days}d';
    }
    if (d.inHours > 0) {
      return '${d.inHours}h';
    }
    return '${d.inMinutes}m';
  }
}

/// What is left this week, set big, with a thin Cue bar of what is used.
class _Allowance extends StatelessWidget {
  const _Allowance({
    required this.remaining,
    required this.limit,
    required this.used,
    required this.fraction,
    this.recharge,
  });

  final int remaining;
  final int limit;
  final int used;
  final double fraction;
  final String? recharge;

  @override
  Widget build(BuildContext context) {
    final low = remaining < MediaQuotaDialogBody._kGb;
    return Column(
      crossAxisAlignment: .stretch,
      spacing: 10,
      children: [
        Row(
          crossAxisAlignment: .baseline,
          textBaseline: .alphabetic,
          children: [
            Expanded(
              child: Text(
                Profile.formatBytes(remaining),
                style: PTText.display.copyWith(
                  fontSize: 30,
                  letterSpacing: -0.8,
                  color: low ? PTColors.warning : PTColors.fg,
                ),
              ),
            ),
            Text('LEFT OF ${Profile.formatBytes(limit)}'.toUpperCase(), style: PTText.label),
          ],
        ),
        ClipRRect(
          borderRadius: BorderRadius.circular(2),
          child: SizedBox(
            height: 4,
            child: Stack(
              fit: .expand,
              children: [
                const ColoredBox(color: PTColors.rail),
                FractionallySizedBox(
                  alignment: .centerLeft,
                  widthFactor: fraction,
                  child: ColoredBox(color: fraction > 0.85 ? PTColors.warning : PTColors.online),
                ),
              ],
            ),
          ),
        ),
        Text(
          [
            '${Profile.formatBytes(used)} used this week',
            if (recharge != null) 'tops up in $recharge',
          ].join(' · ').toUpperCase(),
          style: PTText.label.copyWith(fontSize: 10),
        ),
      ],
    );
  }
}

/// The file that could not be shared, and by how much: one Signal box.
class _BlockedFile extends StatelessWidget {
  const _BlockedFile({required this.quotaContext});

  final MediaQuotaContext quotaContext;

  @override
  Widget build(BuildContext context) {
    final c = quotaContext;
    final isPrem = EntitlementService.instance.isPremium;
    final single = c.reason == .singleFileLimitExceeded;
    final cap = single ? c.maxBytes : c.remainingBytes;
    final over = c.fileSize != null && cap != null && cap >= 0
        ? (c.fileSize! - cap).clamp(0, 100 * MediaQuotaDialogBody._kGb)
        : null;
    Widget metric(String label, String value, {Color? color}) => Expanded(
      child: Column(
        crossAxisAlignment: .start,
        spacing: 2,
        children: [
          Text(label, style: PTText.label.copyWith(fontSize: 10)),
          Text(
            value,
            style: PTText.mono.copyWith(
              fontSize: 15,
              fontWeight: .w600,
              color: color ?? PTColors.fg,
            ),
          ),
        ],
      ),
    );
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(PTRadius.control),
        border: Border.all(color: PTColors.dangerBorder),
      ),
      child: Column(
        crossAxisAlignment: .start,
        spacing: 12,
        children: [
          if (c.fileName != null && c.fileName!.isNotEmpty)
            Row(
              spacing: 8,
              children: [
                Icon(Symbols.draft_rounded, size: 16, color: PTColors.white(0.6)),
                Expanded(
                  child: Text(
                    c.fileName!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: PTText.mono.copyWith(fontSize: 12.5, color: PTColors.fg),
                  ),
                ),
              ],
            ),
          if (c.fileSize != null)
            Row(
              children: [
                metric('FILE', Profile.formatBytes(c.fileSize!)),
                if (cap != null && cap >= 0)
                  metric(
                    single ? (isPrem ? 'PATRON CAP' : 'FREE CAP') : 'LEFT',
                    Profile.formatBytes(cap),
                  ),
                if (over != null)
                  metric(
                    single ? 'OVER BY' : 'SHORT BY',
                    Profile.formatBytes(over),
                    color: PTColors.danger,
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

class _FeatureRow extends StatelessWidget {
  const _FeatureRow({
    required this.icon,
    required this.title,
    required this.description,
    this.highlight = false,
  });

  final IconData icon;
  final String title;
  final String description;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: .start,
      spacing: 8,
      children: [
        Icon(icon, size: 16, color: highlight ? PTColors.premium : PTColors.white(0.5)),
        Expanded(
          child: RichText(
            text: TextSpan(
              style: PTText.caption.copyWith(fontSize: 12, color: PTColors.white(0.7)),
              children: [
                TextSpan(
                  text: '$title: ',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: highlight ? PTColors.premium : PTColors.fg,
                  ),
                ),
                TextSpan(text: description),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
