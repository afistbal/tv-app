import 'dart:async';
import 'dart:convert';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:yogotv/adjust_tracking.dart';
import 'package:yogotv/api.dart';
import 'package:yogotv/global.dart';
import 'package:yogotv/i18n/strings.g.dart';

class Purchase {
  static const bool debugLogApplePayloadOnly = false;
  static StreamSubscription<List<PurchaseDetails>>? _subscription;
  static dynamic result;
  static void Function()? _loadingCallback;
  static final Map<String, Completer<bool>> _pendingPurchases = {};
  static final Map<String, Map<String, dynamic>> _pendingOrders = {};
  static final Set<String> _attemptedBackgroundTransactions = {};
  static Completer<bool>? _restoreCompleter;

  static Future<void> init() async {
    if (_subscription != null) {
      return;
    }
    _subscription = InAppPurchase.instance.purchaseStream.listen((
      purchaseDetailsList,
    ) async {
      var restoredAndVerified = false;
      try {
        for (var details in purchaseDetailsList) {
          var verification = _PurchaseVerification.retry();
          Global.logger.d(
            'iap_stream status=${details.status} product=${details.productID} purchaseID=${details.purchaseID}',
          );
          Global.payTrace(
            'Apple stream ${jsonEncode({'status': details.status.name, 'productID': details.productID, 'purchaseID': details.purchaseID, 'pendingCompletePurchase': details.pendingCompletePurchase, 'source': details.verificationData.source, 'localVerificationData': _shortText(details.verificationData.localVerificationData), 'serverVerificationData': _shortText(details.verificationData.serverVerificationData), 'error': details.error?.message})}',
          );
          if (details.status == PurchaseStatus.pending) {
            Global.logger.d('pending');
            Global.payTrace('Apple pending ${details.productID}');
          } else {
            if (details.status == PurchaseStatus.error) {
              Global.logger.d('${details.error!}');
              Global.payTrace('Apple error ${details.error?.message ?? ''}');
            } else if (details.status == PurchaseStatus.purchased ||
                details.status == PurchaseStatus.restored) {
              final interactive = _pendingPurchases.containsKey(
                details.productID,
              );
              final transactionKey = _transactionKey(details);
              if (!interactive &&
                  !_attemptedBackgroundTransactions.add(transactionKey)) {
                Global.payTrace(
                  'Apple background transaction already checked this session key=$transactionKey',
                );
                continue;
              }
              Global.payTrace('Apple ${details.status.name}, verify backend');
              final pendingOrder = _pendingOrders[details.productID];
              verification = await _processPurchase(
                details,
                pendingOrder: pendingOrder,
                trackAdjust: details.status == PurchaseStatus.purchased,
                showFailure: interactive,
              );
              if (details.status == PurchaseStatus.restored &&
                  verification.verified) {
                restoredAndVerified = true;
              }
              _completePending(details.productID, verification.verified);
            }
            if (verification.shouldComplete &&
                details.pendingCompletePurchase) {
              Global.payTrace('Apple complete purchase');
              await InAppPurchase.instance.completePurchase(details);
            } else if (details.pendingCompletePurchase) {
              Global.payTrace('Apple purchase not completed: verify failed');
            }
          }
        }
      } on Exception catch (e) {
        Global.logger.d(e);
        Global.payTrace('purchase stream exception $e');
      } finally {
        if (purchaseDetailsList.isEmpty) {
          Global.warning(t.no_order);
        }
        final restoreCompleter = _restoreCompleter;
        if (restoreCompleter != null && !restoreCompleter.isCompleted) {
          restoreCompleter.complete(restoredAndVerified);
        }
        _loadingCallback?.call();
      }
    });
  }

  static dispose() async {
    _loadingCallback?.call();
    await _subscription?.cancel();
    _subscription = null;
  }

  static loading() {
    _loadingCallback = Global.loading();
  }

  static closeLoading() {
    _loadingCallback?.call();
  }

  static Future<_PurchaseVerification> _processPurchase(
    PurchaseDetails details, {
    Map<String, dynamic>? pendingOrder,
    required bool trackAdjust,
    required bool showFailure,
  }) async {
    Global.payTrace('call applePay/verify');
    final transaction = _decodeAppleTransaction(
      details.verificationData.localVerificationData,
    );
    final transactionAppAccountToken = _text(transaction['appAccountToken']);
    pendingOrder ??=
        _cachedPendingOrder(details.productID) ??
        _cachedPendingOrderByAccountToken(transactionAppAccountToken);
    final orderNo = _text(pendingOrder?['order_no'] ?? pendingOrder?['pay_no']);
    final appAccountToken = _text(
      pendingOrder?['appAccountToken'] ??
          pendingOrder?['app_account_token'] ??
          transactionAppAccountToken,
    );
    final transactionProductId = _text(transaction['productId']);
    final transactionId = _firstNotEmpty([
      transaction['transactionId'],
      transaction['transactionID'],
      details.purchaseID,
    ]);
    final payload = {
      'appAccountToken': appAccountToken,
      'order_no': orderNo,
      'serverVerificationData': details.verificationData.serverVerificationData,
      'productId': transactionProductId.isNotEmpty
          ? transactionProductId
          : details.productID,
      'purchaseDate': _intOrNull(transaction['purchaseDate']),
      'expiresDate': _intOrNull(transaction['expiresDate']),
      'transactionId': transactionId,
      'originalTransactionId': _text(
        transaction['originalTransactionId'] ??
            transaction['originalTransactionID'],
      ),
      'webOrderLineItemId': _text(transaction['webOrderLineItemId']),
      'restore': details.status == PurchaseStatus.restored,
    };
    Global.payTrace(
      'applePay/verify resolved orderNo=${orderNo.isEmpty ? '(empty)' : orderNo} appAccountToken=${_shortText(appAccountToken)}',
    );
    if (orderNo.isEmpty) {
      Global.payTrace(
        'applePay/verify recovering from Apple receipt without local order',
      );
    }
    final authToken = Global.sp.getString('token') ?? '';
    Global.payTrace(
      'applePay/verify Authorization=${authToken.isEmpty ? '(empty)' : 'present length=${authToken.length}'}',
    );
    Global.payTrace(
      'applePay/verify request ${jsonEncode({...payload, 'serverVerificationData': _shortText(payload['serverVerificationData'])})}',
    );
    Global.payTrace('applePay/verify full request begin');
    Global.payTrace('applePay/verify full request end');
    if (debugLogApplePayloadOnly) {
      Global.payTrace('applePay/verify skipped: debugLogApplePayloadOnly=true');
      return _PurchaseVerification.verified();
    }
    final result = await api(
      'applePay/verify',
      method: Method.post,
      loading: false,
      showError: false,
      data: payload,
    );
    Global.logger.d(
      'applePay_verify result c=${result.c} product=${details.productID} purchaseID=${details.purchaseID}',
    );
    Global.payTrace('applePay/verify result c=${result.c} m=${result.m}');
    Global.payTrace(
      'applePay/verify response ${jsonEncode({'c': result.c, 'm': result.m, 'd': result.d})}',
    );
    if (result.c != 0) {
      closeLoading();
      Global.payTrace(
        'PAYMENT FAILED orderNo=$orderNo verify_c=${result.c} verify_m=${result.m}',
      );
      Global.payTrace('Apple transaction retained for a later verification');
      if (showFailure) {
        Global.error(
          'Order exception，orderNo: ${orderNo.isEmpty ? 'unknown' : orderNo}, please contact us at the feedback center',
        );
      }
      return _PurchaseVerification.retry();
    }
    Global.payTrace(
      'PAYMENT SUCCESS orderNo=$orderNo product=${details.productID}',
    );
    await _clearCachedPendingOrder(
      productId: details.productID,
      appAccountToken: appAccountToken,
    );
    if (trackAdjust && result.c == 0) {
      AdjustTracking.trackPurchase(
        productId: details.productID,
        transactionId: details.purchaseID,
      );
    }
    return _PurchaseVerification.verified();
  }

  static Future<bool> making({
    required dynamic localProductId,
    required String appleProductId,
    required int type,
  }) async {
    loading();
    final completer = Completer<bool>();
    _pendingPurchases[appleProductId] = completer;
    var productIdForPurchase = appleProductId;
    Global.payTrace(
      'start localProductId=$localProductId appleProductId=$appleProductId type=$type',
    );
    Global.logger.d(
      'IAP making localProductId=$localProductId appleProductId=$appleProductId type=$type',
    );
    if (!await _waitForStoreAvailability()) {
      Global.error(t.product_temporarily_unavailable);
      Global.logger.d('IAP unavailable');
      Global.payTrace('IAP unavailable');
      _pendingPurchases.remove(appleProductId);
      _loadingCallback?.call();
      return false;
    }

    try {
      await Global.ensureAnonymousSession();
      Global.payTrace('create Apple preorder');
      final createPayload = {'product_id': localProductId};
      final authToken = Global.sp.getString('token') ?? '';
      Global.payTrace(
        'applePay/create Authorization=${authToken.isEmpty ? '(empty)' : 'Bearer $authToken'}',
      );
      Global.payTrace('applePay/create request ${jsonEncode(createPayload)}');
      var order = await api<Map<String, dynamic>>(
        'applePay/create',
        method: Method.post,
        loading: false,
        data: createPayload,
      );
      if (order.m == 'Authentication Failure.') {
        Global.payTrace(
          'applePay/create auth failed, refresh anonymous session',
        );
        await Global.ensureAnonymousSession(force: true);
        order = await api<Map<String, dynamic>>(
          'applePay/create',
          method: Method.post,
          loading: false,
          data: createPayload,
        );
      }
      Global.payTrace(
        'applePay/create response ${jsonEncode({'c': order.c, 'm': order.m, 'd': order.d})}',
      );
      if (order.c != 0 || order.d == null) {
        Global.payTrace('applePay/create failed c=${order.c} m=${order.m}');
        Global.error(order.m.isEmpty ? 'Purchase Failed' : order.m);
        return false;
      }
      final orderData = order.d!;
      final appAccountToken = _text(
        orderData['appAccountToken'] ?? orderData['app_account_token'],
      );
      final orderAppleProductId = _text(
        orderData['apple_product_id'] ?? orderData['product_id'],
      );
      productIdForPurchase = orderAppleProductId.isNotEmpty
          ? orderAppleProductId
          : appleProductId;
      _pendingPurchases[productIdForPurchase] = completer;
      _pendingOrders[productIdForPurchase] = orderData;
      await _cachePendingOrder(
        productId: productIdForPurchase,
        appAccountToken: appAccountToken,
        order: orderData,
      );
      Global.payTrace(
        'applePay/create selected appleProductId=$productIdForPurchase appAccountToken=${_shortText(appAccountToken)}',
      );

      Global.payTrace('query product');
      final response = await _queryProductDetailsWithRetry({
        productIdForPurchase,
      });
      Global.logger.d(
        'IAP query product=$productIdForPurchase details=${response.productDetails.map((item) => item.id).toList()} notFound=${response.notFoundIDs} error=${response.error}',
      );
      Global.payTrace(
        'query result found=${response.productDetails.length} notFound=${response.notFoundIDs.length}',
      );

      if (response.productDetails.isEmpty) {
        Global.error(t.product_temporarily_unavailable);
        Global.payTrace('no product');
        return false;
      }

      Global.payTrace('open Apple pay sheet');
      final purchaseParam = PurchaseParam(
        productDetails: response.productDetails.first,
        applicationUserName: appAccountToken.isEmpty ? null : appAccountToken,
      );
      Global.payTrace(
        'Apple purchaseParam ${jsonEncode({'localProductId': localProductId, 'appleProductId': productIdForPurchase, 'type': type, 'applicationUserName': appAccountToken, 'method': type == 2 ? 'buyConsumable' : 'buyNonConsumable'})}',
      );
      final result = type == 2
          ? await InAppPurchase.instance.buyConsumable(
              purchaseParam: purchaseParam,
            )
          : await InAppPurchase.instance.buyNonConsumable(
              purchaseParam: purchaseParam,
            );
      Global.payTrace('Apple buy result=$result');
      if (!result) {
        _pendingPurchases.remove(productIdForPurchase);
        _pendingOrders.remove(productIdForPurchase);
        return false;
      }
      final verified = await completer.future.timeout(
        const Duration(seconds: 30),
        onTimeout: () {
          Global.payTrace('purchase verify timeout');
          return false;
        },
      );
      return verified;
    } on Exception catch (error) {
      Global.logger.d('IAP buy failed product=$appleProductId error=$error');
      Global.payTrace('buy failed $error');
      return false;
    } finally {
      _pendingPurchases.remove(appleProductId);
      _pendingPurchases.remove(productIdForPurchase);
      _pendingOrders.remove(appleProductId);
      _pendingOrders.remove(productIdForPurchase);
      closeLoading();
    }
  }

  static Future<bool> previewCreate({
    required dynamic localProductId,
    required String appleProductId,
    required int type,
  }) async {
    Global.payTrace(
      'web preview start localProductId=$localProductId appleProductId=$appleProductId type=$type',
    );
    final createPayload = {'product_id': localProductId};
    Global.payTrace('applePay/create request ${jsonEncode(createPayload)}');
    final order = await api<Map<String, dynamic>>(
      'applePay/create',
      method: Method.post,
      loading: true,
      data: createPayload,
    );
    Global.payTrace(
      'applePay/create response ${jsonEncode({'c': order.c, 'm': order.m, 'd': order.d})}',
    );
    if (order.c == 0) {
      Global.payTrace(
        'web preview stops before Apple native pay ${jsonEncode({'localProductId': localProductId, 'appleProductId': appleProductId, 'type': type, 'method': type == 2 ? 'buyConsumable' : 'buyNonConsumable'})}',
      );
      Global.payTrace('web preview preorder created');
      return true;
    }
    return false;
  }

  static void _completePending(String productId, bool value) {
    final completer = _pendingPurchases[productId];
    if (completer != null && !completer.isCompleted) {
      completer.complete(value);
    }
  }

  static Future<bool> restore() async {
    _attemptedBackgroundTransactions.clear();
    final completer = Completer<bool>();
    _restoreCompleter = completer;
    try {
      await InAppPurchase.instance.restorePurchases();
      return await completer.future.timeout(
        const Duration(seconds: 15),
        onTimeout: () => false,
      );
    } finally {
      if (identical(_restoreCompleter, completer)) {
        _restoreCompleter = null;
      }
    }
  }

  static Future<void> warmUpProductDetails(Iterable<String> productIds) async {
    try {
      final ids = productIds.where((id) => id.trim().isNotEmpty).toSet();
      if (ids.isEmpty || !await _waitForStoreAvailability()) {
        return;
      }
      final response = await _queryProductDetailsWithRetry(ids);
      Global.payTrace(
        'StoreKit warmup found=${response.productDetails.length} notFound=${response.notFoundIDs}',
      );
    } on Exception catch (error) {
      Global.payTrace('StoreKit warmup failed error=$error');
    }
  }

  static Future<bool> _waitForStoreAvailability() async {
    for (var attempt = 1; attempt <= 4; attempt += 1) {
      try {
        if (await InAppPurchase.instance.isAvailable()) {
          return true;
        }
      } on Exception catch (error) {
        Global.payTrace('StoreKit availability attempt=$attempt error=$error');
      }
      if (attempt < 4) {
        await Future<void>.delayed(Duration(milliseconds: 350 * attempt));
      }
    }
    return false;
  }

  static Future<ProductDetailsResponse> _queryProductDetailsWithRetry(
    Set<String> productIds,
  ) async {
    ProductDetailsResponse? lastResponse;
    for (var attempt = 1; attempt <= 4; attempt += 1) {
      final response = await InAppPurchase.instance.queryProductDetails(
        productIds,
      );
      lastResponse = response;
      final foundIds = response.productDetails.map((item) => item.id).toSet();
      final missingIds = productIds.difference(foundIds);
      Global.payTrace(
        'StoreKit query attempt=$attempt ids=$productIds found=$foundIds missing=$missingIds notFound=${response.notFoundIDs} error=${response.error}',
      );
      if (missingIds.isEmpty) {
        return response;
      }
      if (attempt < 4) {
        await Future<void>.delayed(Duration(milliseconds: 500 * attempt));
      }
    }
    return lastResponse!;
  }
}

String _pendingOrderKey(String productId) {
  return 'apple_pending_order_$productId';
}

String _pendingOrderTokenKey(String appAccountToken) {
  return 'apple_pending_order_token_$appAccountToken';
}

Future<void> _cachePendingOrder({
  required String productId,
  required String appAccountToken,
  required Map<String, dynamic> order,
}) async {
  final value = jsonEncode(order);
  if (productId.isEmpty) {
    return;
  }
  await Global.sp.setString(_pendingOrderKey(productId), value);
  if (appAccountToken.isNotEmpty) {
    await Global.sp.setString(_pendingOrderTokenKey(appAccountToken), value);
  }
}

Map<String, dynamic>? _cachedPendingOrder(String productId) {
  if (productId.isEmpty) {
    return null;
  }
  final value = Global.sp.getString(_pendingOrderKey(productId)) ?? '';
  if (value.isEmpty) {
    return null;
  }
  try {
    final decoded = jsonDecode(value);
    if (decoded is Map<String, dynamic>) {
      Global.payTrace('use cached pending order product=$productId');
      return decoded;
    }
    if (decoded is Map) {
      Global.payTrace('use cached pending order product=$productId');
      return decoded.map((key, value) => MapEntry('$key', value));
    }
  } on Exception catch (error) {
    Global.payTrace('cached pending order decode failed $error');
  }
  return null;
}

Map<String, dynamic>? _cachedPendingOrderByAccountToken(
  String appAccountToken,
) {
  if (appAccountToken.isEmpty) {
    return null;
  }
  final value =
      Global.sp.getString(_pendingOrderTokenKey(appAccountToken)) ?? '';
  if (value.isEmpty) {
    return null;
  }
  try {
    final decoded = jsonDecode(value);
    if (decoded is Map<String, dynamic>) {
      Global.payTrace('use cached pending order appAccountToken');
      return decoded;
    }
    if (decoded is Map) {
      Global.payTrace('use cached pending order appAccountToken');
      return decoded.map((key, value) => MapEntry('$key', value));
    }
  } on Exception catch (error) {
    Global.payTrace('cached pending order token decode failed $error');
  }
  return null;
}

Future<void> _clearCachedPendingOrder({
  required String productId,
  required String appAccountToken,
}) async {
  if (productId.isEmpty && appAccountToken.isEmpty) {
    return;
  }
  if (productId.isNotEmpty) {
    await Global.sp.remove(_pendingOrderKey(productId));
  }
  if (appAccountToken.isNotEmpty) {
    await Global.sp.remove(_pendingOrderTokenKey(appAccountToken));
  }
}

String _text(dynamic value) {
  if (value == null) {
    return '';
  }
  return '$value';
}

String _shortText(dynamic value) {
  final text = _text(value);
  if (text.length <= 180) {
    return text;
  }
  return '${text.substring(0, 180)}...(${text.length})';
}

Map<String, dynamic> _decodeAppleTransaction(String value) {
  try {
    final decoded = jsonDecode(value);
    if (decoded is Map<String, dynamic>) {
      return decoded;
    }
    if (decoded is Map) {
      return decoded.map((key, value) => MapEntry('$key', value));
    }
  } on Exception catch (error) {
    Global.payTrace('Apple transaction decode failed $error');
  }
  return {};
}

int? _intOrNull(dynamic value) {
  if (value == null) {
    return null;
  }
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.toInt();
  }
  return int.tryParse('$value');
}

String _transactionKey(PurchaseDetails details) {
  return _firstNotEmpty([
    details.purchaseID,
    '${details.productID}:${details.transactionDate ?? ''}:${details.verificationData.serverVerificationData.hashCode}',
  ]);
}

String _firstNotEmpty(Iterable<dynamic> values) {
  for (final value in values) {
    final text = _text(value).trim();
    if (text.isNotEmpty) {
      return text;
    }
  }
  return '';
}

class _PurchaseVerification {
  const _PurchaseVerification._({
    required this.verified,
    required this.shouldComplete,
  });

  const _PurchaseVerification.verified()
    : this._(verified: true, shouldComplete: true);

  const _PurchaseVerification.retry()
    : this._(verified: false, shouldComplete: false);

  final bool verified;
  final bool shouldComplete;
}
