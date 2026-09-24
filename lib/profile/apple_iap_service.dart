import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:synctogether/diagnostics.dart';
import 'package:synctogether/platform.dart';
import 'package:synctogether/profile/entitlement_service.dart';

/// App Store Connect product ids. Permanent once created - Apple never lets an
/// id be reused, so these change only alongside a new product.
const kAppleMonthlyProductId = 'app.synctogether.premium.monthly';
const kAppleAnnualProductId = 'app.synctogether.premium.annual';
const kAppleProductIds = {kAppleMonthlyProductId, kAppleAnnualProductId};

/// Where Apple lets people manage or cancel an App Store subscription. There
/// is no in-app cancel: Apple owns that flow.
const kAppleManageSubscriptionsUrl = 'https://apps.apple.com/account/subscriptions';

enum AppleIapNotice {
  /// The server accepted a purchase or restore; premium is live.
  activated,

  /// Restore found nothing that belongs to this account.
  nothingToRestore,

  /// This Apple ID's subscription is already bound to another SyncTogether
  /// account. One purchase entitles one account - see `apply_apple_transaction`.
  ownedElsewhere,

  /// StoreKit or our server failed; the transaction stays unfinished and is
  /// redelivered on the next launch.
  failed,
}

/// Classifies `/apple-iap/verify`'s answer: whether the transaction may be
/// finished, and what to tell the person. Kept pure so the finish-or-retry
/// decision is testable without StoreKit.
///
/// Finishing tells StoreKit we are done with a transaction for good, so it is
/// only done when retrying cannot change the answer. A network error or a 5xx
/// leaves it unfinished, and StoreKit hands it back on the next launch - and
/// so does a 400: a server that cannot verify a genuine transaction (the Deno
/// X509 bug, the first time this ran) is indistinguishable from a bad one, and
/// a retry per launch costs nothing next to finishing away a paid purchase.
({bool finish, AppleIapNotice notice}) classifyVerifyResponse(int status, String? error) {
  if (status == 200) return (finish: true, notice: .activated);
  if (status == 409 || error == 'owned_elsewhere') return (finish: true, notice: .ownedElsewhere);
  if (status == 403 && error == 'account_mismatch') return (finish: true, notice: .ownedElsewhere);
  return (finish: false, notice: .failed);
}

/// StoreKit 2 purchases for the Apple App Store edition.
///
/// The purchase stream is subscribed at launch, not when the subscription
/// screen opens: renewals, Ask-to-Buy approvals and anything left unfinished
/// by a crash are delivered to whoever is listening when the app starts, and a
/// transaction nobody hears about is never verified.
///
/// Entitlement is never decided here. Every purchased or restored transaction
/// goes to `apple-iap/verify`, which checks Apple's signature and binds it to
/// the account; this class only relays what the server decided, and
/// `EntitlementService` reads the result the same way it reads a Paddle one.
class AppleIapService extends ChangeNotifier {
  AppleIapService._();
  static final instance = AppleIapService._();

  InAppPurchase get _iap => InAppPurchase.instance;
  SupabaseClient get _client => Supabase.instance.client;

  StreamSubscription<List<PurchaseDetails>>? _sub;
  final _notices = StreamController<AppleIapNotice>.broadcast();

  bool _available = false;
  bool _loadingProducts = false;
  bool _busy = false;
  bool _restoring = false;
  final _restoreNotices = <AppleIapNotice>{};
  List<ProductDetails> _products = const [];

  bool get available => _available;
  bool get loadingProducts => _loadingProducts;

  /// A purchase or restore is in flight.
  bool get busy => _busy;

  /// Monthly first, then annual, whatever order StoreKit answered in.
  List<ProductDetails> get products => _products;

  Stream<AppleIapNotice> get notices => _notices.stream;

  bool get enabled => isAppleStoreBuild;

  void start() {
    if (!enabled || _sub != null) return;
    _sub = _iap.purchaseStream.listen(
      _onPurchases,
      onError: (Object e, StackTrace s) =>
          reportNonFatal(e, s, during: 'the StoreKit purchase stream'),
    );
  }

  bool _demoSeeded = false;

  /// Store-screenshot capture only (`DEMO_MODE`): stands in for StoreKit,
  /// which has no products to answer with outside a signed App Store build.
  void seedDemoProducts(List<ProductDetails> products) {
    _demoSeeded = true;
    _products = products;
    notifyListeners();
  }

  Future<void> loadProducts() async {
    if (!enabled || _loadingProducts || _demoSeeded) return;
    _loadingProducts = true;
    notifyListeners();
    try {
      _available = await _iap.isAvailable();
      if (!_available) {
        trace('StoreKit unavailable', category: 'billing');
        return;
      }
      final response = await _iap.queryProductDetails(kAppleProductIds);
      if (response.error != null || response.notFoundIDs.isNotEmpty) {
        // Products missing from App Store Connect (or an unsigned Paid Apps
        // agreement) look exactly like this, and nothing on screen says why.
        trace(
          'StoreKit product query incomplete',
          category: 'billing',
          data: {'notFound': response.notFoundIDs, 'error': response.error?.message},
        );
        reportNonFatal(
          StateError('StoreKit product query incomplete'),
          StackTrace.current,
          during: 'loading App Store products',
        );
      }
      _products = [...response.productDetails]
        ..sort(
          (a, b) => a.id == kAppleMonthlyProductId ? -1 : (b.id == kAppleMonthlyProductId ? 1 : 0),
        );
    } catch (e, s) {
      reportNonFatal(e, s, during: 'loading App Store products');
    } finally {
      _loadingProducts = false;
      notifyListeners();
    }
  }

  Future<void> buy(ProductDetails product) async {
    final userId = _client.auth.currentUser?.id;
    if (!enabled || userId == null || _busy) return;
    _setBusy(true);
    trace('StoreKit purchase started', category: 'billing', data: {'product': product.id});
    try {
      // `applicationUserName` becomes the transaction's appAccountToken, which
      // must be a UUID - the Supabase user id is one. The server refuses any
      // transaction whose token is not the caller.
      final started = await _iap.buyNonConsumable(
        purchaseParam: PurchaseParam(productDetails: product, applicationUserName: userId),
      );
      if (!started) _setBusy(false);
    } catch (e, s) {
      reportNonFatal(e, s, during: 'starting an App Store purchase');
      _setBusy(false);
      _notices.add(.failed);
    }
  }

  Future<void> restore() async {
    final userId = _client.auth.currentUser?.id;
    if (!enabled || userId == null || _busy) return;
    _setBusy(true);
    _restoring = true;
    _restoreNotices.clear();
    trace('StoreKit restore started', category: 'billing');
    try {
      await _iap.restorePurchases(applicationUserName: userId);
      // StoreKit 2 delivers restored transactions through the stream before
      // this completes; give the verify round trips a moment to land.
      await Future<void>.delayed(const Duration(seconds: 2));
      // A restore replays every past transaction, so it reports one outcome
      // for the lot rather than one per transaction.
      _notices.add(switch (_restoreNotices) {
        final n when n.contains(AppleIapNotice.activated) => .activated,
        final n when n.contains(AppleIapNotice.ownedElsewhere) => .ownedElsewhere,
        final n when n.contains(AppleIapNotice.failed) => .failed,
        _ => .nothingToRestore,
      });
    } catch (e, s) {
      reportNonFatal(e, s, during: 'restoring App Store purchases');
      _notices.add(.failed);
    } finally {
      _restoring = false;
      _setBusy(false);
    }
  }

  Future<void> _onPurchases(List<PurchaseDetails> purchases) async {
    for (final purchase in purchases) {
      switch (purchase.status) {
        case .pending:
          continue;
        case .canceled:
          _setBusy(false);
        case .error:
          trace(
            'StoreKit purchase failed',
            category: 'billing',
            data: {'product': purchase.productID, 'code': purchase.error?.code},
          );
          _setBusy(false);
          _notices.add(.failed);
        case .purchased || .restored:
          await _deliver(purchase);
      }
      if (purchase.pendingCompletePurchase &&
          purchase.status != .purchased &&
          purchase.status != .restored) {
        await _finish(purchase);
      }
    }
  }

  Future<void> _deliver(PurchaseDetails purchase) async {
    final jws = purchase.verificationData.serverVerificationData;
    if (_client.auth.currentUser == null || jws.isEmpty) {
      // Left unfinished: StoreKit redelivers it once someone is signed in.
      _setBusy(false);
      return;
    }
    ({bool finish, AppleIapNotice notice}) verdict;
    try {
      final response = await _client.functions.invoke(
        'apple-iap/verify',
        body: {'signed_transaction': jws},
      );
      verdict = classifyVerifyResponse(response.status, null);
    } on FunctionException catch (e) {
      final details = e.details;
      verdict = classifyVerifyResponse(
        e.status,
        details is Map ? details['error'] as String? : null,
      );
      if (!verdict.finish || verdict.notice == .failed) {
        reportNonFatal(e, StackTrace.current, during: 'verifying an App Store transaction');
      }
    } catch (e, s) {
      reportNonFatal(e, s, during: 'verifying an App Store transaction');
      verdict = (finish: false, notice: .failed);
    }
    trace(
      'StoreKit transaction verified',
      category: 'billing',
      data: {
        'product': purchase.productID,
        'status': purchase.status.name,
        'notice': verdict.notice.name,
      },
    );

    if (verdict.finish) await _finish(purchase);
    if (verdict.notice == .activated) await EntitlementService.instance.refresh();
    if (_restoring) {
      _restoreNotices.add(verdict.notice);
    } else {
      _notices.add(verdict.notice);
      _setBusy(false);
    }
  }

  Future<void> _finish(PurchaseDetails purchase) async {
    try {
      await _iap.completePurchase(purchase);
    } catch (e, s) {
      reportNonFatal(e, s, during: 'finishing an App Store transaction');
    }
  }

  void _setBusy(bool value) {
    if (_busy == value) return;
    _busy = value;
    notifyListeners();
  }
}
