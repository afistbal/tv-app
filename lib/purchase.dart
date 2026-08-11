import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_storekit/in_app_purchase_storekit.dart';
import 'package:in_app_purchase_storekit/store_kit_2_wrappers.dart';
import 'package:in_app_purchase_storekit/store_kit_wrappers.dart';
import 'package:yogotv/adjust_tracking.dart';
import 'package:yogotv/api.dart';
import 'package:yogotv/global.dart';
import 'package:yogotv/i18n/strings.g.dart';
import 'package:yogotv/payment_diagnostics.dart';

class Purchase {
  static const bool debugLogApplePayloadOnly = false;
  static StreamSubscription<List<PurchaseDetails>>? _subscription;
  static dynamic result;
  static void Function()? _loadingCallback;
  static final Map<String, Completer<bool>> _pendingPurchases = {};
  static final Map<String, int> _pendingPurchaseTypes = {};
  static final Map<String, Map<String, dynamic>> _pendingOrders = {};
  static final Set<String> _attemptedBackgroundTransactions = {};
  static final Set<String> _finishedTransactions = {};
  static final Map<String, Future<_PurchaseResult>> _transactionTasks = {};
  static final Map<String, bool> _introEligibilityCache = {};
  static Future<bool>? _backgroundRecovery;
  static final Map<String, Future<void>> _introEligibilityPreloads = {};
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
        for (final details in purchaseDetailsList) {
          Global.logger.d(
            'iap_stream status=${details.status} product=${details.productID} purchaseID=${details.purchaseID}',
          );
          Global.payTrace(
            'Apple stream ${jsonEncode({'status': details.status.name, 'productID': details.productID, 'purchaseID': details.purchaseID, 'pendingCompletePurchase': details.pendingCompletePurchase, 'source': details.verificationData.source, 'localVerificationDataLength': details.verificationData.localVerificationData.length, 'serverVerificationDataLength': details.verificationData.serverVerificationData.length, 'errorCode': details.error?.code, 'errorMessage': details.error?.message})}',
          );

          if (details.status == PurchaseStatus.pending) {
            PaymentDiagnostics.stage(
              'apple_pending',
              details: 'product=${details.productID}',
            );
            continue;
          }

          if (details.status == PurchaseStatus.canceled) {
            PaymentDiagnostics.failure(
              'apple_canceled',
              details.error?.message ?? 'User canceled the Apple purchase',
              code: details.error?.code ?? '',
              canceled: true,
            );
            _completePending(details.productID, false);
            continue;
          }

          if (details.status == PurchaseStatus.error) {
            final message = details.error?.message ?? 'Apple purchase failed';
            Global.logger.d('${details.error}');
            PaymentDiagnostics.failure(
              'apple_transaction_error',
              message,
              code: details.error?.code ?? '',
            );
            _completePending(details.productID, false);
            continue;
          }

          if (details.status != PurchaseStatus.purchased &&
              details.status != PurchaseStatus.restored) {
            PaymentDiagnostics.warning(
              'apple_unknown_status',
              'status=${details.status.name} product=${details.productID}',
            );
            continue;
          }

          final interactive = _pendingPurchases.containsKey(details.productID);
          final transactionKey = _transactionKey(details);
          if (_finishedTransactions.contains(transactionKey)) {
            Global.payTrace(
              'Apple transaction already finished this session key=$transactionKey',
            );
            continue;
          }
          if (!interactive &&
              !_attemptedBackgroundTransactions.add(transactionKey)) {
            Global.payTrace(
              'Apple background transaction already checked this session key=$transactionKey',
            );
            continue;
          }

          final purchaseResult = await _verifyAndFinish(
            details,
            trackAdjust: details.status == PurchaseStatus.purchased,
            showFailure: interactive,
            allowProductOrderFallback: interactive,
          );
          if (details.status == PurchaseStatus.restored &&
              purchaseResult.success) {
            restoredAndVerified = true;
          }
          _completePending(details.productID, purchaseResult.success);
        }
      } on Exception catch (e) {
        Global.logger.d(e);
        PaymentDiagnostics.failure('purchase_stream', '$e');
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

    if (!kIsWeb && Platform.isIOS) {
      final recovery = _recoverUnfinishedTransactions();
      _backgroundRecovery = recovery;
      unawaited(
        recovery.whenComplete(() {
          if (identical(_backgroundRecovery, recovery)) {
            _backgroundRecovery = null;
          }
        }),
      );
    }
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

  static Future<_PurchaseResult> _verifyAndFinish(
    PurchaseDetails details, {
    required bool trackAdjust,
    required bool showFailure,
    required bool allowProductOrderFallback,
  }) {
    final transactionKey = _transactionKey(details);
    final existing = _transactionTasks[transactionKey];
    if (existing != null) {
      Global.payTrace(
        'Apple transaction processing already in progress key=$transactionKey',
      );
      return existing;
    }

    final task = () async {
      try {
        return await _verifyAndFinishInternal(
          details,
          trackAdjust: trackAdjust,
          showFailure: showFailure,
          allowProductOrderFallback: allowProductOrderFallback,
        );
      } on Exception catch (error) {
        PaymentDiagnostics.failure(
          'transaction_processing',
          'product=${details.productID} error=$error',
        );
        return const _PurchaseResult.retry();
      }
    }();
    _transactionTasks[transactionKey] = task;
    unawaited(
      task.whenComplete(() {
        if (identical(_transactionTasks[transactionKey], task)) {
          _transactionTasks.remove(transactionKey);
        }
      }),
    );
    return task;
  }

  static Future<_PurchaseResult> _verifyAndFinishInternal(
    PurchaseDetails details, {
    required bool trackAdjust,
    required bool showFailure,
    required bool allowProductOrderFallback,
  }) async {
    final transactionKey = _transactionKey(details);
    final transaction = _decodeAppleTransaction(
      details.verificationData.localVerificationData,
    );
    final signedTransaction = _decodeAppleJwsPayload(
      details.verificationData.serverVerificationData,
    );
    final signedAppAccountToken = _text(signedTransaction['appAccountToken']);
    final localAppAccountToken = _firstNotEmpty([
      transaction['appAccountToken'],
      details is SK2PurchaseDetails ? details.appAccountToken : null,
    ]);
    if (signedAppAccountToken.isNotEmpty &&
        localAppAccountToken.isNotEmpty &&
        signedAppAccountToken != localAppAccountToken) {
      PaymentDiagnostics.add(
        'Apple transaction field mismatch field=appAccountToken '
        'signed=${_shortText(signedAppAccountToken)} '
        'local=${_shortText(localAppAccountToken)}',
      );
    }
    final transactionAppAccountToken = _firstNotEmpty([
      signedAppAccountToken,
      localAppAccountToken,
    ]);
    final pendingOrder = _pendingOrderForTransaction(
      productId: details.productID,
      appAccountToken: transactionAppAccountToken,
      allowProductFallback: allowProductOrderFallback,
    );
    final orderNo = _text(pendingOrder?['order_no'] ?? pendingOrder?['pay_no']);
    final appAccountToken = _text(
      pendingOrder?['appAccountToken'] ??
          pendingOrder?['app_account_token'] ??
          transactionAppAccountToken,
    );
    final transactionProductId = _firstNotEmpty([
      signedTransaction['productId'],
      transaction['productId'],
    ]);
    final transactionId = _firstNotEmpty([
      signedTransaction['transactionId'],
      transaction['transactionId'],
      transaction['transactionID'],
      details.purchaseID,
    ]);
    PaymentDiagnostics.stage(
      'transaction_received',
      details:
          'status=${details.status.name} product=${details.productID} '
          'transactionId=${transactionId.isEmpty ? '(empty)' : transactionId} '
          'pendingComplete=${details.pendingCompletePurchase}',
    );
    final payload = {
      'appAccountToken': appAccountToken,
      'order_no': orderNo,
      'serverVerificationData': details.verificationData.serverVerificationData,
      'productId': transactionProductId.isNotEmpty
          ? transactionProductId
          : details.productID,
      'purchaseDate': _intOrNull(
        signedTransaction['purchaseDate'] ?? transaction['purchaseDate'],
      ),
      'expiresDate': _intOrNull(
        signedTransaction['expiresDate'] ?? transaction['expiresDate'],
      ),
      'transactionId': transactionId,
      'originalTransactionId': _text(
        signedTransaction['originalTransactionId'] ??
            transaction['originalTransactionId'] ??
            transaction['originalTransactionID'],
      ),
      'webOrderLineItemId': _text(
        signedTransaction['webOrderLineItemId'] ??
            transaction['webOrderLineItemId'],
      ),
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
      'applePay/verify request ${jsonEncode({...payload, 'serverVerificationData': '<redacted length=${details.verificationData.serverVerificationData.length}>'})}',
    );
    PaymentDiagnostics.stage(
      'verify_started',
      details:
          'orderNo=${orderNo.isEmpty ? '(empty)' : orderNo} '
          'transactionId=${transactionId.isEmpty ? '(empty)' : transactionId}',
    );
    if (debugLogApplePayloadOnly) {
      PaymentDiagnostics.failure(
        'verify_skipped',
        'debugLogApplePayloadOnly=true',
      );
      return _PurchaseResult.retry(
        orderNo: orderNo,
        appAccountToken: appAccountToken,
        transactionId: transactionId,
      );
    }
    late final dynamic result;
    try {
      result = await api(
        'applePay/verify',
        method: Method.post,
        loading: false,
        showError: false,
        data: payload,
      );
    } on Exception catch (error) {
      PaymentDiagnostics.failure('verify_request_failed', '$error');
      if (showFailure && !PaymentDiagnostics.enabled) {
        Global.error('Purchase verification failed. Please try again later.');
      }
      return _PurchaseResult.retry(
        orderNo: orderNo,
        appAccountToken: appAccountToken,
        transactionId: transactionId,
      );
    }
    Global.logger.d(
      'applePay_verify result c=${result.c} product=${details.productID} purchaseID=${details.purchaseID}',
    );
    Global.payTrace('applePay/verify result c=${result.c} m=${result.m}');
    if (result.c != 0) {
      closeLoading();
      PaymentDiagnostics.failure(
        'verify_rejected',
        'orderNo=${orderNo.isEmpty ? '(empty)' : orderNo} '
            'transactionId=${transactionId.isEmpty ? '(empty)' : transactionId} '
            'serverCode=${result.c} serverMessage=${result.m}',
        code: '${result.c}',
      );
      Global.payTrace('Apple transaction retained for a later verification');
      if (showFailure && !PaymentDiagnostics.enabled) {
        Global.error(
          'Order exception，orderNo: ${orderNo.isEmpty ? 'unknown' : orderNo}, please contact us at the feedback center',
        );
      }
      return _PurchaseResult.retry(
        orderNo: orderNo,
        appAccountToken: appAccountToken,
        transactionId: transactionId,
      );
    }
    PaymentDiagnostics.stage(
      'verify_ok',
      details:
          'orderNo=${orderNo.isEmpty ? '(empty)' : orderNo} '
          'transactionId=${transactionId.isEmpty ? '(empty)' : transactionId}',
    );

    if (_pendingPurchaseTypes[details.productID] == 2) {
      PaymentDiagnostics.stage(
        'consumable_verified',
        details:
            'product=${details.productID} '
            'transactionId=${transactionId.isEmpty ? '(empty)' : transactionId}',
      );
      _completePending(details.productID, true);
    }

    var storeKitFinished = true;
    if (details.pendingCompletePurchase) {
      PaymentDiagnostics.stage(
        'client_finish_started',
        details:
            'product=${details.productID} '
            'transactionId=${transactionId.isEmpty ? '(empty)' : transactionId}',
      );
      await InAppPurchase.instance.completePurchase(details);
      storeKitFinished = await _confirmStoreKitTransactionFinished(
        productId: details.productID,
        transactionId: transactionId,
      );
      PaymentDiagnostics.stage(
        'client_finish_ok',
        details:
            'product=${details.productID} '
            'transactionId=${transactionId.isEmpty ? '(empty)' : transactionId} '
            'removedFromQueue=$storeKitFinished',
      );
    }

    if (storeKitFinished) {
      await _clearCachedPendingOrder(
        productId: details.productID,
        appAccountToken: appAccountToken,
        orderNo: orderNo,
      );
      _finishedTransactions.add(transactionKey);
    } else {
      PaymentDiagnostics.warning(
        'client_finish_pending',
        'product=${details.productID} transactionId=$transactionId',
      );
      Global.payTrace(
        'StoreKit transaction still pending after finish; retain local order '
        'product=${details.productID} transactionId=$transactionId',
      );
    }
    if (trackAdjust) {
      AdjustTracking.trackPurchase(
        productId: details.productID,
        transactionId: details.purchaseID,
      );
    }
    PaymentDiagnostics.stage(
      'purchase_complete',
      details:
          'orderNo=${orderNo.isEmpty ? '(empty)' : orderNo} '
          'transactionId=${transactionId.isEmpty ? '(empty)' : transactionId}',
    );
    return _PurchaseResult.verified(
      orderNo: orderNo,
      appAccountToken: appAccountToken,
      transactionId: transactionId,
    );
  }

  static Future<bool> _confirmStoreKitTransactionFinished({
    required String productId,
    required String transactionId,
  }) async {
    if (kIsWeb ||
        !Platform.isIOS ||
        transactionId.isEmpty ||
        !await SKRequestMaker.supportsStoreKit2()) {
      return true;
    }

    for (var attempt = 1; attempt <= 8; attempt += 1) {
      try {
        final unfinished = await SK2Transaction.unfinishedTransactions();
        final transaction = unfinished
            .where(
              (item) => item.id == transactionId && item.productId == productId,
            )
            .firstOrNull;
        if (transaction == null) {
          return true;
        }

        if (attempt == 4) {
          final numericId = int.tryParse(transaction.id);
          if (numericId != null) {
            await SK2Transaction.finish(numericId);
            Global.payTrace(
              'StoreKit direct finish retried '
              'product=$productId transactionId=$transactionId',
            );
          }
        }
      } on Exception catch (error) {
        Global.payTrace(
          'StoreKit finish confirmation failed '
          'product=$productId transactionId=$transactionId error=$error',
        );
        return false;
      }
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
    return false;
  }

  static Future<bool> making({
    required dynamic localProductId,
    required String appleProductId,
    required int type,
    int priceType = 0,
  }) async {
    PaymentDiagnostics.beginAttempt(
      localProductId: '$localProductId',
      appleProductId: appleProductId,
      type: type,
    );
    loading();
    final completer = Completer<bool>();
    var productIdForPurchase = appleProductId;
    Global.payTrace(
      'start localProductId=$localProductId appleProductId=$appleProductId type=$type',
    );
    Global.logger.d(
      'IAP making localProductId=$localProductId appleProductId=$appleProductId type=$type',
    );
    PaymentDiagnostics.stage('store_availability');
    if (!await _waitForStoreAvailability()) {
      Global.error(t.product_temporarily_unavailable);
      Global.logger.d('IAP unavailable');
      PaymentDiagnostics.failure(
        'store_unavailable',
        'Apple in-app purchase is unavailable',
      );
      _loadingCallback?.call();
      return false;
    }

    try {
      final backgroundRecovery = _backgroundRecovery;
      if (backgroundRecovery != null) {
        PaymentDiagnostics.stage('unfinished_wait');
        await backgroundRecovery;
      }
      PaymentDiagnostics.stage(
        'unfinished_check',
        details: 'product=$appleProductId',
      );
      final recovered = await _recoverUnfinishedTransactions(
        productId: appleProductId,
        interactive: true,
      );
      if (!recovered) {
        if (!PaymentDiagnostics.enabled) {
          Global.error(
            'A previous purchase is still being processed. Please try again later.',
          );
        }
        return false;
      }
      PaymentDiagnostics.stage('unfinished_clear');

      await Global.ensureAnonymousSession();
      PaymentDiagnostics.stage('create_started');
      final createPayload = {
        'product_id': localProductId,
        'price_type': priceType,
      };
      final authToken = Global.sp.getString('token') ?? '';
      Global.payTrace(
        'applePay/create Authorization=${authToken.isEmpty ? '(empty)' : 'present length=${authToken.length}'}',
      );
      Global.payTrace('applePay/create request ${jsonEncode(createPayload)}');
      var order = await api<Map<String, dynamic>>(
        'applePay/create',
        method: Method.post,
        loading: false,
        showError: false,
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
          showError: false,
          data: createPayload,
        );
      }
      Global.payTrace('applePay/create response c=${order.c} m=${order.m}');
      if (order.c != 0 || order.d == null) {
        PaymentDiagnostics.failure(
          'create_rejected',
          'serverCode=${order.c} serverMessage=${order.m}',
          code: '${order.c}',
        );
        if (!PaymentDiagnostics.enabled) {
          Global.error(order.m.isEmpty ? 'Purchase Failed' : order.m);
        }
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
      await _cachePendingOrder(
        productId: productIdForPurchase,
        appAccountToken: appAccountToken,
        order: orderData,
      );
      final orderNo = _text(orderData['order_no'] ?? orderData['pay_no']);
      PaymentDiagnostics.stage(
        'create_ok',
        details:
            'orderNo=${orderNo.isEmpty ? '(empty)' : orderNo} '
            'appleProductId=$productIdForPurchase '
            'appAccountToken=${_shortText(appAccountToken)}',
      );

      PaymentDiagnostics.stage(
        'product_query',
        details: 'product=$productIdForPurchase',
      );
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
        PaymentDiagnostics.failure(
          'product_not_found',
          'product=$productIdForPurchase notFound=${response.notFoundIDs}',
        );
        return false;
      }

      _pendingPurchases[productIdForPurchase] = completer;
      _pendingPurchaseTypes[productIdForPurchase] = type;
      _pendingOrders[productIdForPurchase] = orderData;
      final purchaseParam = PurchaseParam(
        productDetails: response.productDetails.first,
        applicationUserName: appAccountToken.isEmpty ? null : appAccountToken,
      );
      PaymentDiagnostics.stage(
        'apple_sheet_requested',
        details:
            'orderNo=${orderNo.isEmpty ? '(empty)' : orderNo} '
            'product=$productIdForPurchase '
            'method=${type == 2 ? 'buyConsumable' : 'buyNonConsumable'}',
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
        PaymentDiagnostics.failure(
          'apple_purchase_not_started',
          'Apple purchase API returned false',
        );
        return false;
      }
      if (!completer.isCompleted) {
        PaymentDiagnostics.stage(
          'waiting_transaction',
          details: 'product=$productIdForPurchase',
        );
      }
      final verified = await completer.future.timeout(
        const Duration(seconds: 30),
        onTimeout: () {
          PaymentDiagnostics.failure(
            'transaction_timeout',
            'No completed transaction within 30 seconds after Apple returned',
          );
          return false;
        },
      );
      return verified;
    } on PlatformException catch (error) {
      final message = error.message ?? '$error';
      PaymentDiagnostics.failure(
        'apple_purchase_request_failed',
        message,
        code: error.code,
      );
      Global.logger.d(
        'IAP platform failure product=$appleProductId '
        'code=${error.code} message=$message details=${error.details}',
      );
      if (!PaymentDiagnostics.enabled) {
        Global.error(
          error.code == 'storekit_duplicate_product_object'
              ? 'A previous purchase is still being processed. Please try again later.'
              : message,
        );
      }
      return false;
    } on Exception catch (error) {
      Global.logger.d('IAP buy failed product=$appleProductId error=$error');
      PaymentDiagnostics.failure(PaymentDiagnostics.currentStage, '$error');
      return false;
    } finally {
      _pendingPurchases.remove(appleProductId);
      _pendingPurchases.remove(productIdForPurchase);
      _pendingPurchaseTypes.remove(appleProductId);
      _pendingPurchaseTypes.remove(productIdForPurchase);
      _pendingOrders.remove(appleProductId);
      _pendingOrders.remove(productIdForPurchase);
      closeLoading();
    }
  }

  static Future<bool> _recoverUnfinishedTransactions({
    String? productId,
    bool interactive = false,
  }) async {
    if (kIsWeb || !Platform.isIOS) {
      return true;
    }

    try {
      if (!await SKRequestMaker.supportsStoreKit2()) {
        Global.payTrace('StoreKit unfinished query skipped: StoreKit 1 device');
        return true;
      }
      final transactions = await SK2Transaction.unfinishedTransactions();
      final matching = transactions
          .where(
            (transaction) =>
                productId == null || transaction.productId == productId,
          )
          .toList();
      Global.payTrace(
        'StoreKit unfinished query product=${productId ?? '(all)'} '
        'count=${matching.length} '
        'transactions=${matching.map((item) => '${item.productId}:${item.id}').toList()}',
      );
      if (matching.isEmpty) {
        return true;
      }

      var recovered = true;
      for (final transaction in matching) {
        final transactionKey = transaction.id.isNotEmpty
            ? transaction.id
            : '${transaction.productId}:${transaction.purchaseDate}';
        if (_finishedTransactions.contains(transactionKey)) {
          continue;
        }
        PaymentDiagnostics.stage(
          'unfinished_found',
          details:
              'product=${transaction.productId} '
              'transactionId=${transaction.id} '
              'appAccountToken=${_shortText(transaction.appAccountToken)}',
        );
        final details = SK2PurchaseDetails(
          productID: transaction.productId,
          purchaseID: transaction.id,
          verificationData: PurchaseVerificationData(
            localVerificationData: transaction.jsonRepresentation ?? '',
            serverVerificationData: transaction.receiptData ?? '',
            source: 'app_store',
          ),
          transactionDate: transaction.purchaseDate,
          status: PurchaseStatus.purchased,
          appAccountToken: transaction.appAccountToken,
        );
        final result = await _verifyAndFinish(
          details,
          trackAdjust: false,
          showFailure: interactive,
          allowProductOrderFallback: false,
        );
        recovered = recovered && result.success;
      }
      return recovered;
    } on PlatformException catch (error) {
      PaymentDiagnostics.warning(
        'unfinished_query_failed',
        'code=${error.code} message=${error.message ?? error}',
      );
      return true;
    } on Exception catch (error) {
      PaymentDiagnostics.warning('unfinished_query_failed', '$error');
      return true;
    }
  }

  static Map<String, dynamic>? _pendingOrderForTransaction({
    required String productId,
    required String appAccountToken,
    required bool allowProductFallback,
  }) {
    if (appAccountToken.isNotEmpty) {
      final tokenOrder = _cachedPendingOrderByAccountToken(appAccountToken);
      if (tokenOrder != null) {
        return tokenOrder;
      }

      final candidates = [
        _pendingOrders[productId],
        _cachedPendingOrder(productId),
      ];
      for (final candidate in candidates) {
        if (candidate != null &&
            _orderAppAccountToken(candidate) == appAccountToken) {
          return candidate;
        }
      }
      Global.payTrace(
        'no matching local order for Apple appAccountToken '
        'product=$productId token=${_shortText(appAccountToken)}',
      );
      return null;
    }

    if (!allowProductFallback) {
      Global.payTrace(
        'no Apple appAccountToken; product-only order fallback disabled '
        'product=$productId',
      );
      return null;
    }
    return _pendingOrders[productId] ?? _cachedPendingOrder(productId);
  }

  static Future<bool> previewCreate({
    required dynamic localProductId,
    required String appleProductId,
    required int type,
    int priceType = 0,
  }) async {
    Global.payTrace(
      'web preview start localProductId=$localProductId appleProductId=$appleProductId type=$type',
    );
    final createPayload = {
      'product_id': localProductId,
      'price_type': priceType,
    };
    Global.payTrace('applePay/create request ${jsonEncode(createPayload)}');
    final order = await api<Map<String, dynamic>>(
      'applePay/create',
      method: Method.post,
      loading: true,
      data: createPayload,
    );
    Global.payTrace('applePay/create response c=${order.c} m=${order.m}');
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

  static Map<String, bool> cachedIntroductoryOfferEligibility(
    Iterable<String> productIds,
  ) {
    final ids = productIds.where((id) => id.trim().isNotEmpty).toSet();
    if (ids.isEmpty || _introEligibilityCache.isEmpty) {
      return const {};
    }
    final result = <String, bool>{};
    for (final id in ids) {
      final value = _introEligibilityCache[id];
      if (value != null) {
        result[id] = value;
      }
    }
    return result;
  }

  static Future<void> preloadMembershipIntroductoryOfferEligibility() {
    return _preloadIntroductoryOfferEligibility(
      key: 'membership',
      requestData: const {},
    );
  }

  static Future<void> preloadRetentionIntroductoryOfferEligibility() {
    return _preloadIntroductoryOfferEligibility(
      key: 'retention',
      requestData: const {'price_type': 1},
    );
  }

  static Future<void> _preloadIntroductoryOfferEligibility({
    required String key,
    required Map<String, dynamic> requestData,
  }) {
    if (kIsWeb || !Platform.isIOS) {
      return Future.value();
    }
    final current = _introEligibilityPreloads[key];
    if (current != null) {
      return current;
    }
    final task = _preloadIntroductoryOfferEligibilityProducts(
      key: key,
      requestData: requestData,
    );
    _introEligibilityPreloads[key] = task;
    return task.whenComplete(() {
      if (identical(_introEligibilityPreloads[key], task)) {
        _introEligibilityPreloads.remove(key);
      }
    });
  }

  static Future<void> _preloadIntroductoryOfferEligibilityProducts({
    required String key,
    required Map<String, dynamic> requestData,
  }) async {
    try {
      await Global.ensureAnonymousSession();
      var products = await api<dynamic>(
        'applePay/products',
        method: Method.post,
        data: requestData,
        loading: false,
        showError: false,
      );
      if (products.m == 'Authentication Failure.') {
        await Global.ensureAnonymousSession(force: true);
        products = await api<dynamic>(
          'applePay/products',
          method: Method.post,
          data: requestData,
          loading: false,
          showError: false,
        );
      }
      if (products.c != 0) {
        Global.payTrace(
          'StoreKit intro preload products rejected c=${products.c} m=${products.m}',
        );
        return;
      }
      final ids = _appleSubscriptionProductIds(products.d).toSet();
      if (ids.isEmpty) {
        return;
      }
      Global.payTrace('StoreKit intro preload key=$key ids=$ids');
      await warmUpProductDetails(ids);
      final eligibility = await introductoryOfferEligibility(ids);
      Global.payTrace('StoreKit intro preload key=$key result=$eligibility');
    } on Exception catch (error) {
      Global.payTrace('StoreKit intro preload key=$key failed error=$error');
    }
  }

  static Future<Map<String, bool>> introductoryOfferEligibility(
    Iterable<String> productIds,
  ) async {
    if (kIsWeb || !Platform.isIOS) {
      return const {};
    }
    final ids = productIds.where((id) => id.trim().isNotEmpty).toSet();
    if (ids.isEmpty || !await SKRequestMaker.supportsStoreKit2()) {
      return const {};
    }

    try {
      final products = await SK2Product.products(ids.toList());
      final eligibility = <String, bool>{};
      for (final product in products) {
        final hasIntroductoryOffer =
            product.subscription?.promotionalOffers.any(
              (offer) => offer.type == SK2SubscriptionOfferType.introductory,
            ) ??
            false;
        if (!hasIntroductoryOffer) {
          eligibility[product.id] = false;
          continue;
        }
        try {
          eligibility[product.id] =
              await SK2Product.isIntroductoryOfferEligible(product.id);
        } on Exception catch (error) {
          Global.payTrace(
            'StoreKit introductory eligibility failed '
            'product=${product.id} error=$error',
          );
        }
      }
      Global.payTrace('StoreKit introductory eligibility $eligibility');
      if (eligibility.isNotEmpty) {
        _introEligibilityCache.addAll(eligibility);
      }
      return eligibility;
    } on Exception catch (error) {
      Global.payTrace('StoreKit introductory offers query failed error=$error');
      return const {};
    }
  }

  static Future<int> introductoryPriceType(String productId) async {
    final eligibility = await introductoryOfferEligibility([productId]);
    return eligibility[productId] == true ? 1 : 0;
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
  required String orderNo,
}) async {
  if (productId.isEmpty && appAccountToken.isEmpty) {
    return;
  }
  if (productId.isNotEmpty) {
    final productOrder = _cachedPendingOrder(productId);
    if (productOrder == null ||
        _sameOrder(
          productOrder,
          appAccountToken: appAccountToken,
          orderNo: orderNo,
        )) {
      await Global.sp.remove(_pendingOrderKey(productId));
    } else {
      Global.payTrace(
        'retain product pending order because it belongs to another purchase '
        'product=$productId',
      );
    }
  }
  if (appAccountToken.isNotEmpty) {
    await Global.sp.remove(_pendingOrderTokenKey(appAccountToken));
  }
}

String _orderAppAccountToken(Map<String, dynamic> order) {
  return _text(order['appAccountToken'] ?? order['app_account_token']);
}

String _orderNo(Map<String, dynamic> order) {
  return _text(order['order_no'] ?? order['pay_no']);
}

bool _sameOrder(
  Map<String, dynamic> order, {
  required String appAccountToken,
  required String orderNo,
}) {
  final candidateToken = _orderAppAccountToken(order);
  if (appAccountToken.isNotEmpty && candidateToken.isNotEmpty) {
    return appAccountToken == candidateToken;
  }
  final candidateOrderNo = _orderNo(order);
  if (orderNo.isNotEmpty && candidateOrderNo.isNotEmpty) {
    return orderNo == candidateOrderNo;
  }
  return false;
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

Map<String, dynamic> _decodeAppleJwsPayload(String value) {
  try {
    final parts = value.split('.');
    if (parts.length != 3) {
      return {};
    }
    final payload = utf8.decode(
      base64Url.decode(base64Url.normalize(parts[1])),
    );
    final decoded = jsonDecode(payload);
    if (decoded is Map<String, dynamic>) {
      return decoded;
    }
    if (decoded is Map) {
      return decoded.map((key, value) => MapEntry('$key', value));
    }
  } on Exception catch (error) {
    Global.payTrace('Apple signed transaction decode failed $error');
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

Iterable<String> _appleSubscriptionProductIds(dynamic payload) sync* {
  final rows = _appleSubscriptionRows(payload);
  for (final item in rows) {
    if (item is! Map) {
      continue;
    }
    final id = _firstNotEmpty([
      item['apple_product_id'],
      item['product_id'],
      item['ios_product_id'],
      item['store_product_id'],
      item['google_product_id'],
      item['googleProductId'],
    ]);
    if (id.isNotEmpty) {
      yield id;
    }
  }
}

List<dynamic> _appleSubscriptionRows(dynamic payload) {
  if (payload is List) {
    return payload;
  }
  if (payload is! Map) {
    return const [];
  }
  final subscription = payload['subscription'];
  if (subscription is List) {
    return subscription;
  }
  final products = payload['products'] ?? payload['list'] ?? payload['items'];
  return products is List ? products : const [];
}

class _PurchaseResult {
  const _PurchaseResult._({
    required this.success,
    required this.orderNo,
    required this.appAccountToken,
    required this.transactionId,
  });

  const _PurchaseResult.verified({
    String orderNo = '',
    String appAccountToken = '',
    String transactionId = '',
  }) : this._(
         success: true,
         orderNo: orderNo,
         appAccountToken: appAccountToken,
         transactionId: transactionId,
       );

  const _PurchaseResult.retry({
    String orderNo = '',
    String appAccountToken = '',
    String transactionId = '',
  }) : this._(
         success: false,
         orderNo: orderNo,
         appAccountToken: appAccountToken,
         transactionId: transactionId,
       );

  final bool success;
  final String orderNo;
  final String appAccountToken;
  final String transactionId;
}
