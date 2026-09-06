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
    padding: const EdgeInsets.symmetric(vertical: 24),
    builder: (dialogContext) => MediaQuotaDialogBody(quotaContext: quotaContext),
  );
}

class MediaQuotaDialogBody extends StatelessWidget {
  const MediaQuotaDialogBody({super.key, this.quotaContext});

  final MediaQuotaContext? quotaContext;

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

    final screenHeight = MediaQuery.sizeOf(context).height;
    final maxBodyHeight = (screenHeight - 88).clamp(280.0, 720.0);

    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxBodyHeight),
      child: Column(
        mainAxisSize: .min,
        crossAxisAlignment: .start,
        children: [
          // Header (pinned)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              spacing: 12,
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: isPrem ? PTColors.primary.withValues(alpha: 0.25) : PTColors.white(0.08),
                    border: Border.all(
                      color: isPrem
                          ? const Color(0xFFA78BFA).withValues(alpha: 0.5)
                          : PTColors.white(0.12),
                    ),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(
                    isPrem ? Symbols.crown_rounded : Symbols.cloud_queue_rounded,
                    size: 24,
                    fill: 1,
                    color: isPrem ? PTColors.textAccent : Colors.white,
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Media Sharing Quota', style: PTText.cardHeading),
                      Text(
                        isPrem
                            ? 'Unlimited with Premium'
                            : isGuest
                            ? 'Sign in to unlock weekly quota'
                            : '${Profile.formatBytes(remainingBytes)} of ${Profile.formatBytes(weeklyLimit)} remaining',
                        style: PTText.caption.copyWith(
                          fontSize: 12,
                          color: isPrem
                              ? PTColors.textAccent
                              : remainingBytes < 1024 * 1024 * 1024 && !isGuest
                              ? PTColors.warning
                              : PTColors.white(0.6),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),

          // Scrollable middle section extending full width with comfortable 20px horizontal padding
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                mainAxisSize: .min,
                crossAxisAlignment: .start,
                spacing: 14,
                children: [
                  // Contextual Blockage Card (shown when an upload was rejected)
                  if (quotaContext != null) _ContextualBlockageCard(quotaContext: quotaContext!),

                  // Live Meter Card
                  if (isPrem)
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            PTColors.primary.withValues(alpha: 0.15),
                            PTColors.gradientEnd.withValues(alpha: 0.08),
                          ],
                        ),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: PTColors.primary.withValues(alpha: 0.3)),
                      ),
                      child: Row(
                        spacing: 10,
                        children: [
                          const Icon(
                            Symbols.verified_rounded,
                            color: PTColors.textAccent,
                            size: 20,
                          ),
                          Expanded(
                            child: Text(
                              'No upload limits! Share videos up to 10.0 GB each with high-speed priority.',
                              style: PTText.body.copyWith(fontSize: 12),
                            ),
                          ),
                        ],
                      ),
                    )
                  else if (!isGuest)
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: PTColors.glass(0.25),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: PTColors.white(0.08)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        spacing: 10,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                '7-Day Rolling Usage',
                                style: PTText.caption.copyWith(fontSize: 12),
                              ),
                              Text(
                                '${Profile.formatBytes(usedBytes)} / ${Profile.formatBytes(weeklyLimit)}',
                                style: PTText.mono.copyWith(
                                  fontSize: 12,
                                  color: PTColors.textAccent,
                                ),
                              ),
                            ],
                          ),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(3),
                            child: LinearProgressIndicator(
                              value: fractionUsed,
                              backgroundColor: PTColors.white(0.1),
                              valueColor: AlwaysStoppedAnimation<Color>(
                                fractionUsed > 0.85 ? PTColors.warning : PTColors.textAccent,
                              ),
                              minHeight: 6,
                            ),
                          ),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                '${Profile.formatBytes(remainingBytes)} available',
                                style: PTText.caption.copyWith(
                                  fontSize: 11,
                                  color: PTColors.online,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              if (resetDuration != null && resetDuration.inHours > 0)
                                Text(
                                  'Recharges in ${_formatReset(resetDuration)}',
                                  style: PTText.caption.copyWith(
                                    fontSize: 11,
                                    color: PTColors.white(0.5),
                                  ),
                                ),
                            ],
                          ),
                        ],
                      ),
                    )
                  else
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: PTColors.glass(0.25),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: PTColors.white(0.08)),
                      ),
                      child: Text(
                        'Sign in to get a free 2.5 GB rolling weekly quota to stream any video file with your room.',
                        style: PTText.body.copyWith(fontSize: 12, color: PTColors.white(0.75)),
                      ),
                    ),

                  // Tier Breakdown / Comparison
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: PTColors.glass(0.15),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: PTColors.white(0.06)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      spacing: 8,
                      children: [
                        Text(
                          'How Quotas Work',
                          style: PTText.caption.copyWith(fontSize: 11, fontWeight: FontWeight.w600),
                        ),
                        _FeatureRow(
                          icon: Symbols.schedule_rounded,
                          title: 'Rolling 7-Day Window',
                          description:
                              'Uploaded bytes automatically clear 7 days after the upload completed.',
                        ),
                        _FeatureRow(
                          icon: Symbols.person_rounded,
                          title: 'Free Plan (\$0/mo)',
                          description:
                              '2.5 GB weekly quota • Up to 2.0 GB single file • Room duration up to 4 hrs.',
                        ),
                        _FeatureRow(
                          icon: Symbols.workspace_premium_rounded,
                          title: 'Premium Plan',
                          description:
                              'Unlimited weekly uploads • Up to 10.0 GB single file • 24h rooms & facecams.',
                          highlight: true,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),

          // Action Buttons (pinned at bottom)
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
                      Row(
                        spacing: 10,
                        children: [
                          Expanded(
                            child: PTButton(
                              label: 'Go Premium (Unlimited)',
                              icon: Symbols.crown_rounded,
                              variant: .secondary,
                              onPressed: () {
                                Navigator.of(context).pop();
                                context.push('/lobby/subscribe?source=quota_dialog');
                              },
                            ),
                          ),
                          PTButton(
                            label: 'Got it',
                            variant: .secondary,
                            expand: false,
                            onPressed: () => Navigator.of(context).pop(),
                          ),
                        ],
                      ),
                    ],
                  )
                : Row(
                    spacing: 10,
                    children: [
                      if (!isPrem) ...[
                        Expanded(
                          child: PTButton(
                            label: quotaContext?.reason == .singleFileLimitExceeded
                                ? 'Upgrade for 10.0 GB Files'
                                : 'Get Unlimited with Premium',
                            icon: Symbols.crown_rounded,
                            onPressed: () {
                              Navigator.of(context).pop();
                              final source = quotaContext?.reason == .singleFileLimitExceeded
                                  ? 'quota_dialog_single_file'
                                  : 'quota_dialog_weekly';
                              context.push('/lobby/subscribe?source=$source');
                            },
                          ),
                        ),
                        PTButton(
                          label: 'Got it',
                          variant: .secondary,
                          expand: false,
                          onPressed: () => Navigator.of(context).pop(),
                        ),
                      ] else
                        Expanded(
                          child: PTButton(
                            label: 'Got it',
                            onPressed: () => Navigator.of(context).pop(),
                          ),
                        ),
                    ],
                  ),
          ),
        ],
      ),
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

class _ContextualBlockageCard extends StatelessWidget {
  const _ContextualBlockageCard({required this.quotaContext});

  final MediaQuotaContext quotaContext;

  @override
  Widget build(BuildContext context) {
    final reason = quotaContext.reason;
    final fileName = quotaContext.fileName;
    final fileSize = quotaContext.fileSize;
    final maxBytes = quotaContext.maxBytes;
    final remainingBytes = quotaContext.remainingBytes;

    final String badgeText;
    final String titleText;
    final String bodyText;
    final IconData badgeIcon;

    switch (reason) {
      case .singleFileLimitExceeded:
        badgeText = 'SINGLE-FILE LIMIT EXCEEDED';
        badgeIcon = Symbols.warning_amber_rounded;
        titleText = 'Video Exceeds Free File Limit';
        bodyText =
            'Free accounts can upload videos up to 2.0 GB per file. Upgrade to SyncTogether Premium for files up to 10.0 GB with zero weekly caps.';
      case .weeklyQuotaExceeded:
        badgeText = 'WEEKLY QUOTA EXCEEDED';
        badgeIcon = Symbols.speed_rounded;
        titleText = 'Insufficient Weekly Quota';
        bodyText =
            'This video requires more quota than your remaining 7-day balance. Upgrade to SyncTogether Premium for unlimited sharing, or wait for your rolling quota to recharge.';
      case .guestBlocked:
        badgeText = 'SIGN-IN REQUIRED';
        badgeIcon = Symbols.lock_person_rounded;
        titleText = 'Media Sharing Requires an Account';
        bodyText =
            'Guest accounts cannot upload or share media. Sign up or log in using Email OTP, Apple, or Google to unlock a free 2.5 GB rolling weekly quota.';
    }

    final int? deltaBytes;
    final String? deltaLabel;
    if (fileSize != null && reason == .singleFileLimitExceeded && maxBytes != null) {
      deltaBytes = (fileSize - maxBytes).clamp(0, 100 * 1024 * 1024 * 1024);
      deltaLabel = 'Over limit by';
    } else if (fileSize != null && reason == .weeklyQuotaExceeded && remainingBytes != null) {
      deltaBytes = (fileSize - remainingBytes).clamp(0, 100 * 1024 * 1024 * 1024);
      deltaLabel = 'Quota shortfall';
    } else {
      deltaBytes = null;
      deltaLabel = null;
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: PTColors.warning.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: PTColors.warning.withValues(alpha: 0.45)),
      ),
      child: Column(
        crossAxisAlignment: .start,
        spacing: 10,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: PTColors.warning.withValues(alpha: 0.22),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: PTColors.warning.withValues(alpha: 0.5)),
            ),
            child: Row(
              mainAxisSize: .min,
              spacing: 5,
              children: [
                Icon(badgeIcon, size: 14, color: PTColors.warning),
                Text(
                  badgeText,
                  style: PTText.mono.copyWith(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: PTColors.warning,
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
          ),
          Text(titleText, style: PTText.cardHeading.copyWith(fontSize: 15, color: Colors.white)),
          Text(
            bodyText,
            style: PTText.body.copyWith(fontSize: 12, color: PTColors.white(0.82), height: 1.35),
          ),
          if (fileSize != null || (fileName != null && fileName.isNotEmpty))
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: PTColors.glass(0.3),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: PTColors.white(0.08)),
              ),
              child: Column(
                crossAxisAlignment: .start,
                spacing: 10,
                children: [
                  if (fileName != null && fileName.isNotEmpty)
                    Row(
                      spacing: 8,
                      children: [
                        const Icon(Symbols.movie_rounded, size: 16, color: PTColors.textAccent),
                        Expanded(
                          child: Text(
                            fileName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: PTText.mono.copyWith(
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              color: PTColors.white(0.9),
                            ),
                          ),
                        ),
                      ],
                    ),
                  if (fileSize != null) ...[
                    if (fileName != null && fileName.isNotEmpty)
                      Divider(height: 1, thickness: 1, color: PTColors.white(0.08)),
                    Row(
                      children: [
                        Expanded(
                          child: _MetricBadge(
                            label: 'Selected Video',
                            value: Profile.formatBytes(fileSize),
                            highlightColor: Colors.white,
                          ),
                        ),
                        Container(width: 1, height: 28, color: PTColors.white(0.12)),
                        if (reason == .singleFileLimitExceeded && maxBytes != null) ...[
                          Expanded(
                            child: _MetricBadge(
                              label: 'Free Plan Cap',
                              value: Profile.formatBytes(maxBytes),
                              highlightColor: PTColors.white(0.75),
                            ),
                          ),
                          if (deltaBytes != null) ...[
                            Container(width: 1, height: 28, color: PTColors.white(0.12)),
                            Expanded(
                              child: _MetricBadge(
                                label: deltaLabel!,
                                value: '+${Profile.formatBytes(deltaBytes)}',
                                highlightColor: const Color(0xFFF87171),
                              ),
                            ),
                          ],
                        ] else if (reason == .weeklyQuotaExceeded && remainingBytes != null) ...[
                          Expanded(
                            child: _MetricBadge(
                              label: 'Remaining',
                              value: Profile.formatBytes(remainingBytes),
                              highlightColor: PTColors.white(0.75),
                            ),
                          ),
                          if (deltaBytes != null) ...[
                            Container(width: 1, height: 28, color: PTColors.white(0.12)),
                            Expanded(
                              child: _MetricBadge(
                                label: deltaLabel!,
                                value: '-${Profile.formatBytes(deltaBytes)}',
                                highlightColor: const Color(0xFFF87171),
                              ),
                            ),
                          ],
                        ],
                      ],
                    ),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _MetricBadge extends StatelessWidget {
  const _MetricBadge({required this.label, required this.value, required this.highlightColor});

  final String label;
  final String value;
  final Color highlightColor;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: .min,
      children: [
        Text(
          label,
          style: PTText.caption.copyWith(fontSize: 10, color: PTColors.white(0.55)),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: PTText.mono.copyWith(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: highlightColor,
          ),
          textAlign: TextAlign.center,
        ),
      ],
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
        Icon(icon, size: 16, color: highlight ? PTColors.textAccent : PTColors.white(0.5)),
        Expanded(
          child: RichText(
            text: TextSpan(
              style: PTText.caption.copyWith(fontSize: 11, color: PTColors.white(0.7)),
              children: [
                TextSpan(
                  text: '$title: ',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: highlight ? PTColors.textAccent : Colors.white,
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
