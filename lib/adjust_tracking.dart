import 'dart:convert';
import 'dart:async';
import 'dart:io';

import 'package:adjust_sdk/adjust.dart';
import 'package:adjust_sdk/adjust_attribution.dart';
import 'package:adjust_sdk/adjust_config.dart';
import 'package:adjust_sdk/adjust_deeplink.dart';
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
  static const String _deepLinkInfoKey = 'adjustDeepLinkInfo';
  static const String _tokenSyncedAdidKey = 'adjustTokenSyncedAdid';
  static final Map<String, _PendingCheckout> _pendingCheckouts = {};
  static final Completer<String> _adidReady = Completer<String>();
  static final Completer<void> _attributionReady = Completer<void>();
  static final StreamController<void> _attributionUpdates =
      StreamController<void>.broadcast();
  static final StreamController<String> _deepLinkUpdates =
      StreamController<String>.broadcast();
  static String _pendingDeepLink = '';
  static bool _initialized = false;

  static Stream<void> get attributionUpdates => _attributionUpdates.stream;
  static Stream<String> get deepLinkUpdates => _deepLinkUpdates.stream;

  static String takePendingDeepLink() {
    final link = _pendingDeepLink;
    _pendingDeepLink = '';
    return link;
  }

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
    config.directDeeplinkCallback = _handleDirectDeeplink;
    config.deferredDeeplinkCallback = _handleDeferredDeeplink;
    config.isDeferredDeeplinkOpeningEnabled = false;
    Adjust.initSdk(config);
    _initialized = true;

    try {
      await refreshAttribution();
      _completeAttributionReady();
      final adid = await Adjust.getAdidWithTimeout(3000);
      await _saveAdid(adid);
    } on Exception catch (error) {
      Global.logger.d('adjust init ids failed: $error');
      _completeAttributionReady();
    }
  }

  static String get adid => Global.sp.getString(_adidKey) ?? '';

  static String get attributionInfo {
    final attribution = _jsonMap(Global.sp.getString(_attributionKey));
    return attribution.isEmpty ? '' : jsonEncode(attribution);
  }

  static bool get attributionNeedsRefresh {
    final attribution = _jsonMap(Global.sp.getString(_attributionKey));
    final trackerToken = attribution['trackerToken']?.toString().trim() ?? '';
    return attribution.isEmpty ||
        trackerToken.isEmpty ||
        trackerToken == 'unattr';
  }

  static Future<bool> refreshAttribution() async {
    if (!_initialized || kIsWeb || !Platform.isIOS || Global.webPreview) {
      return false;
    }
    final previous = attributionInfo;
    try {
      final attribution = await Adjust.getAttributionWithTimeout(3000);
      if (attribution != null) {
        await _saveAttribution(attribution);
      }
    } on Exception catch (error) {
      Global.logger.d('adjust attribution refresh failed: $error');
    }
    return previous != attributionInfo;
  }

  static Map<String, dynamic> commonParams() {
    return {'ad_id': adid};
  }

  static Map<String, dynamic> loginParams() {
    return {...commonParams(), 'ad_attr_info': attributionInfo};
  }

  static bool get shouldRefreshTokenForCurrentAdid {
    final current = _tokenSyncValue();
    if (current.isEmpty) {
      return false;
    }
    return (Global.sp.getString(_tokenSyncedAdidKey) ?? '') != current;
  }

  static Future<void> markTokenAdidSynced({
    required Map<String, dynamic> submittedParams,
  }) async {
    final current = _tokenSyncValue(
      adidValue: submittedParams['ad_id']?.toString(),
      attributionValue: submittedParams['ad_attr_info']?.toString(),
    );
    if (current.isEmpty) {
      return;
    }
    await Global.sp.setString(_tokenSyncedAdidKey, current);
  }

  static Future<bool> waitForAdid({Duration? timeout}) {
    if (adid.isNotEmpty) {
      return Future.value(true);
    }
    if (kIsWeb || !Platform.isIOS || Global.webPreview) {
      return Future.value(false);
    }
    final future = _adidReady.future.then((_) => true);
    if (timeout == null) {
      return future;
    }
    return future.timeout(timeout, onTimeout: () => false);
  }

  static Future<bool> waitForAttribution({Duration? timeout}) {
    if (attributionInfo.isNotEmpty) {
      return Future.value(true);
    }
    if (kIsWeb || !Platform.isIOS || Global.webPreview) {
      return Future.value(false);
    }
    final future = _attributionReady.future.then(
      (_) => attributionInfo.isNotEmpty,
    );
    if (timeout == null) {
      return future;
    }
    return future.timeout(timeout, onTimeout: () => attributionInfo.isNotEmpty);
  }

  static Future<void> recordDeepLink(String? rawLink) async {
    final link = rawLink?.trim() ?? '';
    if (link.isEmpty) {
      return;
    }
    final uri = Uri.tryParse(link);
    if (uri == null) {
      return;
    }
    await Global.cacheFromSourceCandidate(
      uri.queryParameters['from_source'],
      origin: 'adjust deep link',
    );
    final previous = _jsonMap(Global.sp.getString(_deepLinkInfoKey));
    if (previous['url'] == link) {
      return;
    }
    final data = <String, dynamic>{
      'url': link,
      'receivedAt': DateTime.now().toIso8601String(),
    };
    for (final key in _deepLinkParamKeys) {
      final value = uri.queryParameters[key]?.trim();
      if (value != null && value.isNotEmpty) {
        data[key] = value;
      }
    }
    final encoded = jsonEncode(data);
    await Global.sp.setString(_deepLinkInfoKey, encoded);
    Global.logger.d('adjust deep link info saved: $encoded');
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

    final encoded = jsonEncode(data);
    final previous = Global.sp.getString(_attributionKey) ?? '';
    await Global.sp.setString(_attributionKey, encoded);
    _completeAttributionReady();
    if (previous != encoded) {
      Global.logger.d('adjust attribution saved: $encoded');
      _emitAttributionUpdate();
    }
    try {
      final adid = await Adjust.getAdidWithTimeout(1000);
      await _saveAdid(adid);
    } on Exception catch (error) {
      Global.logger.d('adjust adid failed: $error');
    }
  }

  static Future<void> _saveAdid(String? adid) async {
    final value = adid ?? '';
    if (value.isEmpty) {
      return;
    }
    final previous = Global.sp.getString(_adidKey) ?? '';
    await Global.sp.setString(_adidKey, value);
    if (!_adidReady.isCompleted) {
      _adidReady.complete(value);
    }
    if (previous != value) {
      _emitAttributionUpdate();
    }
  }

  static void _handleDirectDeeplink(String? deeplink) {
    unawaited(_processDirectDeeplink(deeplink));
  }

  static Future<void> _processDirectDeeplink(String? deeplink) async {
    final link = deeplink?.trim() ?? '';
    if (link.isEmpty) {
      return;
    }
    Global.logger.d('adjust direct deeplink=$link');
    try {
      final resolved = await Adjust.processAndResolveDeeplink(
        AdjustDeeplink(link),
      );
      final routedLink = resolved?.trim().isNotEmpty == true
          ? resolved!.trim()
          : link;
      await _deliverDeepLink(routedLink);
    } on Exception catch (error) {
      Global.logger.d('adjust resolve deeplink failed: $error');
      await _deliverDeepLink(link);
    }
  }

  static void _handleDeferredDeeplink(String? deeplink) {
    final link = deeplink?.trim() ?? '';
    if (link.isEmpty) {
      return;
    }
    Global.logger.d('adjust deferred deeplink=$link');
    unawaited(_deliverDeepLink(link));
  }

  static Future<void> _deliverDeepLink(String link) async {
    _pendingDeepLink = link;
    await recordDeepLink(link);
    if (!_deepLinkUpdates.isClosed) {
      _deepLinkUpdates.add(link);
    }
  }

  static void _completeAttributionReady() {
    if (!_attributionReady.isCompleted) {
      _attributionReady.complete();
    }
  }

  static void _emitAttributionUpdate() {
    if (!_attributionUpdates.isClosed) {
      _attributionUpdates.add(null);
    }
  }

  static String _tokenSyncValue({String? adidValue, String? attributionValue}) {
    final currentAdid = (adidValue ?? adid).trim();
    if (currentAdid.isEmpty) {
      return '';
    }
    final currentAttribution = attributionValue ?? attributionInfo;
    return jsonEncode({
      'adid': currentAdid,
      'ad_attr_info': currentAttribution,
    });
  }

  static Map<String, dynamic> _jsonMap(String? value) {
    final raw = value?.trim() ?? '';
    if (raw.isEmpty) {
      return {};
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        return Map<String, dynamic>.from(decoded);
      }
      if (decoded is Map) {
        return Map<String, dynamic>.from(decoded);
      }
    } on FormatException {
      return {};
    }
    return {};
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

const List<String> _deepLinkParamKeys = [
  'movieId',
  'movie_id',
  'id',
  'episodeNum',
  'episode',
  'episode_no',
  'ep',
  'v',
  'fbclid',
  'fbc',
  'fbp',
  'gclid',
  'ttclid',
  'utm_source',
  'utm_medium',
  'utm_campaign',
  'utm_content',
  'utm_term',
  'utm_id',
  'campaign',
  'adgroup',
  'creative',
  'from_source',
  'adj_t',
  'adjust_t',
  'adj_sub1',
  'adj_sub2',
  'adj_sub3',
  'adj_sub4',
  'adj_sub5',
];

class _PendingCheckout {
  const _PendingCheckout(this.orderId, this.amount);

  final String orderId;
  final num amount;
}
