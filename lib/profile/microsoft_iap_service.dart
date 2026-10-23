import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:synctogether/diagnostics.dart';
import 'package:synctogether/platform.dart';
import 'package:synctogether/profile/entitlement_service.dart';

/// Where Microsoft lets people manage or cancel a Store subscription.
const kMicrosoftManageSubscriptionsUrl = 'https://account.microsoft.com/services';

enum MicrosoftIapNotice {
  /// The server accepted the Store's answer; premium is live.
  activated,

  /// Restore found no subscription on this Microsoft account.
  nothingToRestore,

  /// This Microsoft account's subscription is bound to another SyncTogether
  /// account. One purchase entitles one account - see `apply_microsoft_subscription`.
  ownedElsewhere,

  /// The Store or our server failed; nothing was lost, a retry (or the next
  /// launch) asks the Store again.
  failed,
}

/// One purchasable subscription as the Store lists it.
@immutable
class MicrosoftProduct {
  const MicrosoftProduct({
    required this.storeId,
    required this.title,
    required this.price,
    required this.period,
  });

  final String storeId;
  final String title;

  /// Localised by the Store, never hard-coded.
  final String price;

  /// `month`, `year` or `other`.
  final String period;

  bool get annual => period == 'year';

  static MicrosoftProduct? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['storeId'];
    if (id is! String || id.isEmpty) return null;
    return MicrosoftProduct(
      storeId: id,
      title: '${raw['title'] ?? ''}',
      price: '${raw['price'] ?? ''}',
      period: '${raw['period'] ?? 'other'}',
    );
  }
}

/// Classifies `ms-iap/verify`'s answer. Pure, so the decision is testable
/// without the Store. [active] is the server's "live right now"; a 200 for a
/// subscription that is cancelled or lapsed is a recorded fact, not an
/// activation. Null (a server that predates the field) keeps the old reading.
MicrosoftIapNotice classifyMicrosoftVerify(int status, String? error, {bool? active}) {
  if (status == 200) return active == false ? .nothingToRestore : .activated;
  if (status == 404 || error == 'nothing_to_restore') return .nothingToRestore;
  if (status == 409 || error == 'owned_elsewhere' || error == 'account_mismatch') {
    return .ownedElsewhere;
  }
  return .failed;
}

/// The native half: `windows/runner/store_purchase.cpp`.
abstract interface class StorePurchaseChannel {
  Future<List<MicrosoftProduct>> products();

  /// `succeeded`, `alreadyPurchased`, `notPurchased`, `networkError`, `serverError`.
  Future<String> purchase(String storeId);

  Future<String> idKey({required String serviceTicket, required String userId});
}

/// The native plugin answers from a worker thread; if that answer is lost the
/// future would never complete and the screen would spin for good.
const _kNativeTimeout = Duration(seconds: 30);

class _NativeStorePurchase implements StorePurchaseChannel {
  static const _channel = MethodChannel('app.synctogether/store_purchase');

  @override
  Future<List<MicrosoftProduct>> products() async {
    final raw = await _channel
        .invokeListMethod<Object?>('products')
        .timeout(_kNativeTimeout, onTimeout: () => throw TimeoutException('Store products'));
    final parsed = [for (final r in raw ?? const <Object?>[]) ?MicrosoftProduct.tryParse(r)];
    if (parsed.length != (raw?.length ?? 0)) {
      trace(
        'Store product rows dropped as malformed',
        category: 'billing',
        data: {'rows': raw?.length ?? 0, 'kept': parsed.length},
      );
    }
    return parsed;
  }

  @override
  Future<String> purchase(String storeId) async =>
      await _channel.invokeMethod<String>('purchase', {'storeId': storeId}) ?? 'serverError';

  @override
  Future<String> idKey({required String serviceTicket, required String userId}) async =>
      await _channel
          .invokeMethod<String>('idKey', {'serviceTicket': serviceTicket, 'userId': userId})
          .timeout(_kNativeTimeout, onTimeout: () => throw TimeoutException('Store ID key')) ??
      '';
}

/// Microsoft Store subscriptions for the Windows Store build.
///
/// Mirrors [AppleIapService]: entitlement is never decided here. The app asks
/// the Store for an ID key bound to this account, `ms-iap/verify` checks it
/// against Microsoft and records the result, and `EntitlementService` reads
/// it back like any other rail. The Store sends no renewal notifications, so
/// the app re-checks once per launch (and on sign-in) and an unrefreshed row
/// simply expires.
class MicrosoftIapService extends ChangeNotifier {
  MicrosoftIapService._();
  static final instance = MicrosoftIapService._();

  @visibleForTesting
  MicrosoftIapService.forTesting({
    required StorePurchaseChannel channel,
    required Future<({int status, String? error, Object? data})> Function(
      String path,
      Map<String, dynamic>? body,
    )
    invoke,
    required String? Function() userId,
  }) : _channelOverride = channel,
       _invokeOverride = invoke,
       _userIdOverride = userId;

  StorePurchaseChannel? _channelOverride;
  Future<({int status, String? error, Object? data})> Function(String, Map<String, dynamic>?)?
  _invokeOverride;
  String? Function()? _userIdOverride;

  StorePurchaseChannel get _store => _channelOverride ??= _NativeStorePurchase();
  SupabaseClient get _client => Supabase.instance.client;
  String? get _userId => (_userIdOverride ?? () => _client.auth.currentUser?.id)();

  final _notices = StreamController<MicrosoftIapNotice>.broadcast();
  StreamSubscription<AuthState>? _authSub;
  bool _started = false;
  bool _loadingProducts = false;
  bool _busy = false;
  List<MicrosoftProduct> _products = const [];
  String? _lastError;

  bool get enabled => isMicrosoftStoreBuild;
  bool get loadingProducts => _loadingProducts;
  bool get busy => _busy;

  /// Monthly first, then annual.
  List<MicrosoftProduct> get products => _products;

  /// Why the last product load came back empty, for the screen to show: whoever
  /// hits this is on a machine nobody is watching a dashboard for.
  String? get lastError => _lastError;
  Stream<MicrosoftIapNotice> get notices => _notices.stream;

  void start() {
    if (!enabled || _started) return;
    _started = true;
    _authSub = _client.auth.onAuthStateChange.listen(
      (state) {
        if (state.event == AuthChangeEvent.initialSession ||
            state.event == AuthChangeEvent.signedIn) {
          unawaited(sync(silent: true));
        }
      },
      onError: (Object e) {
        trace('Auth stream error', category: 'billing', data: {'error': '$e'});
      },
    );
  }

  Future<void> loadProducts() async {
    if (_loadingProducts) return;
    _loadingProducts = true;
    notifyListeners();
    _lastError = null;
    try {
      final list = await _store.products();
      _products = [...list]..sort((a, b) => a.annual == b.annual ? 0 : (a.annual ? 1 : -1));
      trace('Store products loaded', category: 'billing', data: {'count': list.length});
      if (list.isEmpty) {
        // A packaged, associated build with published add-ons always has some;
        // none means a wrong association or add-ons that are not live yet.
        _lastError = 'The Store returned no subscriptions for this app.';
        reportNonFatal(StateError(_lastError!), null, during: 'loading Microsoft Store products');
      }
    } catch (e, s) {
      // Not packaged, not associated with the Store, or offline: the screen
      // shows "couldn't reach the Store" and Try again.
      _lastError = '$e';
      reportNonFatal(e, s, during: 'loading Microsoft Store products');
    } finally {
      _loadingProducts = false;
      notifyListeners();
    }
  }

  Future<void> buy(MicrosoftProduct product) async {
    if (_userId == null || _busy) return;
    _setBusy(true);
    trace('Store purchase started', category: 'billing', data: {'product': product.storeId});
    try {
      final status = await _store.purchase(product.storeId);
      trace('Store purchase finished', category: 'billing', data: {'status': status});
      switch (status) {
        case 'succeeded' || 'alreadyPurchased':
          _notices.add(await sync());
        case 'notPurchased':
          break; // The person closed the dialog.
        case 'networkError':
          _notices.add(.failed); // Transient; the trace above records it.
        default:
          reportNonFatal(
            StateError('Store purchase ended with status $status'),
            null,
            during: 'starting a Microsoft Store purchase',
          );
          _notices.add(.failed);
      }
    } catch (e, s) {
      reportNonFatal(e, s, during: 'starting a Microsoft Store purchase');
      _notices.add(.failed);
    } finally {
      _setBusy(false);
    }
  }

  Future<void> restore() async {
    if (_userId == null || _busy) return;
    _setBusy(true);
    try {
      _notices.add(await sync());
    } finally {
      _setBusy(false);
    }
  }

  /// Asks the Store what this Microsoft account owns and has the server
  /// record it. [silent] is the launch check: no notice, and a person who has
  /// bought nothing is not an event.
  Future<MicrosoftIapNotice> sync({bool silent = false}) async {
    final userId = _userId;
    if (userId == null) return .failed;
    // A failure at any stage is a trace; a person who just pressed Buy (not
    // [silent]) also gets it reported, since they are watching it not work.
    MicrosoftIapNotice fail(String stage, [Object? detail]) {
      trace('Store sync failed', category: 'billing', data: {'stage': stage, 'detail': '$detail'});
      if (!silent) {
        reportNonFatal(
          StateError('Microsoft Store sync failed at $stage: $detail'),
          null,
          during: 'syncing Microsoft Store purchases',
        );
      }
      return .failed;
    }

    try {
      final ticket = await _invoke('ms-iap/ticket', null);
      if (ticket.status != 200) return fail('ticket', '${ticket.status} ${ticket.error}');
      final data = ticket.data;
      final serviceTicket = data is Map ? '${data['service_ticket'] ?? ''}' : '';
      if (serviceTicket.isEmpty) return fail('ticket', 'empty service ticket');
      final key = await _store.idKey(serviceTicket: serviceTicket, userId: userId);
      if (key.isEmpty) return fail('idKey', 'the Store returned an empty key');
      final verdict = await _invoke('ms-iap/verify', {'store_id_key': key});
      final answer = verdict.data;
      final active = answer is Map && answer['active'] is bool ? answer['active'] as bool : null;
      final notice = classifyMicrosoftVerify(verdict.status, verdict.error, active: active);
      if (notice == .failed) return fail('verify', '${verdict.status} ${verdict.error}');
      // Any 200 changed what we hold, a revocation included, so re-read it.
      if (verdict.status == 200) await EntitlementService.instance.refresh();
      return notice;
    } catch (e, s) {
      trace('Store sync threw', category: 'billing', data: {'error': '$e'});
      if (!silent) reportNonFatal(e, s, during: 'syncing Microsoft Store purchases');
      return .failed;
    }
  }

  Future<({int status, String? error, Object? data})> _invoke(
    String path,
    Map<String, dynamic>? body,
  ) async {
    final override = _invokeOverride;
    if (override != null) return override(path, body);
    try {
      final response = await _client.functions.invoke(path, body: body);
      return (status: response.status, error: null, data: response.data);
    } on FunctionException catch (e) {
      final details = e.details;
      return (
        status: e.status,
        error: details is Map ? details['error'] as String? : null,
        data: null,
      );
    }
  }

  void _setBusy(bool value) {
    if (_busy == value) return;
    _busy = value;
    notifyListeners();
  }

  @override
  void dispose() {
    _authSub?.cancel();
    super.dispose();
  }
}
