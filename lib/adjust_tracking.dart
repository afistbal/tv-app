import 'dart:convert';
import 'dart:io';

import 'package:adjust_sdk/adjust.dart';
import 'package:adjust_sdk/adjust_attribution.dart';
import 'package:adjust_sdk/adjust_config.dart';
import 'package:adjust_sdk/adjust_event.dart';
import 'package:flutter/foundation.dart';
import 'package:yogotv/global.dart';

class AdjustTracking {
  static const String appToken = '5szgwldoexkw';
  static const String _registerToken = 'ls72bp';
  static const String _checkoutToken = 'tpalge';
  static const String _loginToken = 'a9lqbp';
  static const String _purchaseToken = '9xlojg';
  static const String _viewContentToken = '8sgoaw';

  static const String _adidKey = 'adjustId';
  static const String _attributionKey = 'adjustAttrInfo';
  static final Map<String, _PendingCheckout> _pendingCheckouts = {};
  static bool _initialized = false;

  static Future<void> init() async {
    if (_initialized || kIsWeb || !Platform.isIOS || Global.webPreview) {
      return;
    }

    const useSandbox = bool.fromEnvironment(
      'ADJUST_SANDBOX',
      defaultValue: kDebugMode,
    );
    final config = AdjustConfig(
      appToken,
      useSandbox ? AdjustEnvironment.sandbox : AdjustEnvironment.production,
    );
    config.logLevel = kReleaseMode
        ? AdjustLogLevel.suppress
        : AdjustLogLevel.verbose;
    config.isCostDataInAttributionEnabled = true;
    config.isAdServicesEnabled = true;
    config.isAppTrackingTransparencyUsageEnabled = true;
    config.attributionCallback = _saveAttribution;
    Adjust.initSdk(config);
    _initialized = true;

    try {
      final attribution = await Adjust.getAttributionWithTimeout(1500);
      if (attribution != null) {
        _saveAttribution(attribution);
      }
      final adid = await Adjust.getAdidWithTimeout(1500);
      if (adid != null && adid.isNotEmpty) {
        await Global.sp.setString(_adidKey, adid);
      }
    } on Exception catch (error) {
      Global.logger.d('adjust init ids failed: $error');
    }
  }

  static String get adid => Global.sp.getString(_adidKey) ?? '';

  static String get attributionInfo =>
      Global.sp.getString(_attributionKey) ?? '';

  static Map<String, dynamic> commonParams() {
    return {'ad_id': adid};
  }

  static Map<String, dynamic> loginParams() {
    return {...commonParams(), 'ad_attr_info': attributionInfo};
  }

  static void trackRegister() {
    _trackSimple(_registerToken, 'register');
  }

  static void trackLogin() {
    _trackSimple(_loginToken, 'login');
  }

  static void trackViewContent() {
    _trackSimple(_viewContentToken, 'view content');
  }

  static void trackInitiateCheckout({
    required String productId,
    required num amount,
  }) {
    if (!_initialized) {
      Global.logger.d('adjust skip initiate checkout: not initialized');
      return;
    }
    final orderId =
        'checkout-$productId-${DateTime.now().millisecondsSinceEpoch}';
    _pendingCheckouts[productId] = _PendingCheckout(orderId, amount);
    final event = AdjustEvent(_checkoutToken)
      ..deduplicationId = orderId
      ..productId = productId
      ..callbackId = orderId;
    if (amount > 0) {
      event.setRevenue(amount, 'USD');
    }
    event.addCallbackParameter('product_id', productId);
    Adjust.trackEvent(event);
    Global.logger.d(
      'adjust initiate checkout product=$productId amount=$amount',
    );
  }

  static void trackPurchase({
    required String productId,
    String? transactionId,
  }) {
    if (!_initialized) {
      Global.logger.d('adjust skip purchase: not initialized');
      return;
    }
    final checkout = _pendingCheckouts.remove(productId);
    final orderId = _firstNotEmpty([
      transactionId,
      checkout?.orderId,
      'purchase-$productId-${DateTime.now().millisecondsSinceEpoch}',
    ]);
    final event = AdjustEvent(_purchaseToken)
      ..deduplicationId = orderId
      ..transactionId = transactionId
      ..productId = productId
      ..callbackId = orderId;
    final amount = checkout?.amount ?? 0;
    if (amount > 0) {
      event.setRevenue(amount, 'USD');
    }
    event.addCallbackParameter('product_id', productId);
    Adjust.trackEvent(event);
    Global.logger.d(
      'adjust purchase product=$productId transaction=$transactionId amount=$amount',
    );
  }

  static void _trackSimple(String token, String name) {
    if (!_initialized) {
      Global.logger.d('adjust skip $name: not initialized');
      return;
    }
    Adjust.trackEvent(AdjustEvent(token));
    Global.logger.d('adjust $name');
  }

  static Future<void> _saveAttribution(AdjustAttribution attribution) async {
    final data = {
      'trackerToken': attribution.trackerToken,
      'trackerName': attribution.trackerName,
      'network': attribution.network,
      'campaign': attribution.campaign,
      'adgroup': attribution.adgroup,
      'creative': attribution.creative,
      'clickLabel': attribution.clickLabel,
      'costType': attribution.costType,
      'costAmount': attribution.costAmount.toString(),
      'costCurrency': attribution.costCurrency,
      'fbInstallReferrer': attribution.fbInstallReferrer,
    };

    await Global.sp.setString(_attributionKey, jsonEncode(data));
    try {
      final adid = await Adjust.getAdidWithTimeout(1000);
      if (adid != null && adid.isNotEmpty) {
        await Global.sp.setString(_adidKey, adid);
      }
    } on Exception catch (error) {
      Global.logger.d('adjust adid failed: $error');
    }
  }

  static String _firstNotEmpty(List<String?> values) {
    for (final value in values) {
      if (value != null && value.isNotEmpty) {
        return value;
      }
    }
    return DateTime.now().millisecondsSinceEpoch.toString();
  }
}

class _PendingCheckout {
  const _PendingCheckout(this.orderId, this.amount);

  final String orderId;
  final num amount;
}
