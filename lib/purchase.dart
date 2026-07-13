import 'dart:async';
import 'dart:convert';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:yogotv/adjust_tracking.dart';
import 'package:yogotv/api.dart';
import 'package:yogotv/global.dart';
import 'package:yogotv/i18n/strings.g.dart';

class Purchase {
  static const bool debugLogApplePayloadOnly = false;
  static late final StreamSubscription<List<PurchaseDetails>> subscription;
  static dynamic result;
  static bool canProcess = false;
  static void Function()? _loadingCallback;
  static final Map<String, Completer<bool>> _pendingPurchases = {};
  static final Map<String, Map<String, dynamic>> _pendingOrders = {};

  static init() {
    subscription = InAppPurchase.instance.purchaseStream.listen((
      purchaseDetailsList,
    ) async {
      if (!canProcess) {
        return;
      }
      try {
        for (var details in purchaseDetailsList) {
          var verified = false;
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
              Global.payTrace('Apple ${details.status.name}, verify backend');
              final pendingOrder = _pendingOrders[details.productID];
              verified = await _processPurchase(
                details,
                pendingOrder: pendingOrder,
                trackAdjust: details.status == PurchaseStatus.purchased,
              );
              _completePending(details.productID, verified);
            }
            if (verified && details.pendingCompletePurchase) {
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
        _loadingCallback?.call();
      }
    });
  }

  static dispose() async {
    _loadingCallback?.call();
    await subscription.cancel();
  }

  static loading() {
    _loadingCallback = Global.loading();
  }

  static closeLoading() {
    _loadingCallback?.call();
  }

  static Future<bool> _processPurchase(
    PurchaseDetails details, {
    Map<String, dynamic>? pendingOrder,
    required bool trackAdjust,
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
    final payload = {
      'appAccountToken': appAccountToken,
      'order_no': orderNo,
      'serverVerificationData': details.verificationData.serverVerificationData,
      'productId': transactionProductId.isNotEmpty
          ? transactionProductId
          : details.productID,
      'purchaseDate': _intOrNull(transaction['purchaseDate']),
      'expiresDate': _intOrNull(transaction['expiresDate']),
    };
    Global.payTrace(
      'applePay/verify resolved orderNo=${orderNo.isEmpty ? '(empty)' : orderNo} appAccountToken=${_shortText(appAccountToken)}',
    );
    if (orderNo.isEmpty) {
      closeLoading();
      Global.payTrace('applePay/verify skipped: missing order_no');
      Global.payTrace('PAYMENT FAILED orderNo=unknown reason=missing_order_no');
      Global.error(
        'Order exception，orderNo: unknown, please contact us at the feedback center',
      );
      return false;
    }
    final authToken = Global.sp.getString('token') ?? '';
    Global.payTrace(
      'applePay/verify Authorization=${authToken.isEmpty ? '(empty)' : 'Bearer $authToken'}',
    );
    Global.payTrace(
      'applePay/verify request ${jsonEncode({...payload, 'serverVerificationData': _shortText(payload['serverVerificationData'])})}',
    );
    Global.payTrace('applePay/verify full request begin');
    _printPayPayload('applePay/verify full request ${jsonEncode(payload)}');
    Global.payTrace('applePay/verify full request end');
    if (debugLogApplePayloadOnly) {
      Global.payTrace('applePay/verify skipped: debugLogApplePayloadOnly=true');
      return true;
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
      Global.error(
        'Order exception，orderNo: ${orderNo.isEmpty ? 'unknown' : orderNo}, please contact us at the feedback center',
      );
      return false;
    }
    Global.payTrace('PAYMENT SUCCESS orderNo=$orderNo product=${details.productID}');
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
    return result.c == 0;
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
    if (!await InAppPurchase.instance.isAvailable()) {
      Global.error('Purchase Failed');
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
      final response = await InAppPurchase.instance.queryProductDetails({
        productIdForPurchase,
      });
      Global.logger.d(
        'IAP query product=$productIdForPurchase details=${response.productDetails.map((item) => item.id).toList()} notFound=${response.notFoundIDs} error=${response.error}',
      );
      Global.payTrace(
        'query result found=${response.productDetails.length} notFound=${response.notFoundIDs.length}',
      );

      if (response.productDetails.isEmpty) {
        Global.error('No Product');
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

  static Future<void> restore() async {
    await InAppPurchase.instance.restorePurchases();
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

void _printPayPayload(String value) {
  const chunkSize = 900;
  for (var start = 0; start < value.length; start += chunkSize) {
    final end = (start + chunkSize) > value.length
        ? value.length
        : start + chunkSize;
    // Keep the full payload visible in Xcode without relying on one very long line.
    // ignore: avoid_print
    print('[PAY_FULL] ${value.substring(start, end)}');
  }
}
