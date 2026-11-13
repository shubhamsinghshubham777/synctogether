import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter/widgets.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:synctogether/diagnostics.dart';
import 'package:synctogether/env.dart';
import 'package:synctogether/profile/entitlement_service.dart';
import 'package:synctogether/rooms/room_service.dart';

import '../contract.dart';
import 'breadcrumb_log.dart';
import 'device_model.dart';
import 'os_label.dart';
import 'probes.dart';
import 'redact.dart';

/// Best-effort route of the screen the user is on, `/lobby` if unknown.
String currentRoute(BuildContext ctx) {
  try {
    return GoRouter.of(ctx).routeInformationProvider.value.uri.toString();
  } catch (_) {
    return '/lobby';
  }
}

/// Fills in everything slower than the screenshot. Every section is
/// independent: one failing never costs the others, and nothing here reads chat
/// text, member names, file contents or full paths.
Future<BugCapture> gatherCapture(BugCapture c) async {
  final summary = <String, String>{...c.summary};
  final context = <String, Object?>{...c.context};

  Future<void> section(String name, FutureOr<void> Function() body) async {
    try {
      await body();
    } catch (e, s) {
      reportNonFatal(e, s, during: 'gathering bug report section $name');
    }
  }

  await section('app', () async {
    final info = await PackageInfo.fromPlatform();
    // "1.16.1", not "1.16.1 (1.16.1)" when the build number is the version.
    final build = info.buildNumber;
    summary['app'] = build.isEmpty || build == info.version
        ? info.version
        : '${info.version} ($build)';
    context['app'] = {
      'version': info.version,
      'build': info.buildNumber,
      'mode': kReleaseMode ? 'release' : 'debug',
      'local_stack': Env.usingLocalStack,
    };
  });

  await section('device', () async {
    final model = await DeviceModel.read();
    final rawOs = Platform.operatingSystemVersion.split('\n').first;
    final os = await OsLabel.read(Platform.operatingSystem, rawOs);
    summary['device'] = [
      ?model,
      os.label,
      '${Platform.numberOfProcessors} cores',
      Platform.localeName,
    ].join(' · ');
    context['device'] = {
      'model': ?model,
      'os': Platform.operatingSystem,
      'os_label': os.label,
      'os_build': ?os.build,
      'os_version': rawOs,
      'cores': Platform.numberOfProcessors,
      'locale': Platform.localeName,
    };
  });

  await section('screen', () {
    summary['screen'] = redactText(c.screenRoute);
    context['route'] = c.screenRoute;
  });

  await section('account', () {
    final uid = Supabase.instance.client.auth.currentUser?.id;
    context['user_id'] = uid;
    context['tier'] = EntitlementService.instance.tier;
    summary['account'] =
        'tier ${EntitlementService.instance.tier}${uid == null ? ' · signed out' : ''}';
  });

  await section('room', () {
    final room = RoomService.instance.currentRoom;
    if (room == null) return;
    final uid = Supabase.instance.client.auth.currentUser?.id;
    summary['room'] =
        '${room.code} · ${room.createdBy == uid ? 'host' : 'guest'} · ${room.mediaKind.name}';
    context['room'] = {
      'id': room.id,
      'code': room.code,
      'is_host': room.createdBy == uid,
      'media_kind': room.mediaKind.name,
      'max_members': room.maxMembers,
      'persistent': room.persistent,
      'transport_lock': room.transportLock,
    };
  });

  for (final e in FeedbackProbes.snapshot().entries) {
    final lines = {for (final l in e.value.entries) l.key: redactText(l.value)};
    summary[e.key] = lines.entries.map((l) => '${l.key} ${l.value}').join(' · ');
    context[e.key] = lines;
  }

  await section('net', () async {
    final host = Uri.tryParse(Env.supabaseUrl)?.host;
    if (host == null || host.isEmpty) return;
    final sw = Stopwatch()..start();
    try {
      await InternetAddress.lookup(host).timeout(const Duration(seconds: 2));
      summary['net'] = 'dns ok · ${sw.elapsedMilliseconds} ms';
      context['net'] = {'dns_ms': sw.elapsedMilliseconds, 'ok': true};
    } catch (_) {
      summary['net'] = 'backend unreachable';
      context['net'] = {'ok': false};
    }
  });

  final last = BreadcrumbLog.lastLabels(3);
  if (last.isNotEmpty) summary['last'] = last.join(' · ');
  return c.copyWith(summary: summary, context: context, logsText: BreadcrumbLog.render());
}
