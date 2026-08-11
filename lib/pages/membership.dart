import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:tiktok_events_sdk/tiktok_events_sdk.dart';
import 'package:yogotv/adjust_tracking.dart';
import 'package:yogotv/api.dart';
import 'package:yogotv/components/android_toolbar.dart';
import 'package:yogotv/components/lazy_image.dart';
import 'package:yogotv/components/loading.dart';
import 'package:yogotv/global.dart';
import 'package:yogotv/i18n/strings.g.dart';
import 'package:yogotv/movie_cover.dart';
import 'package:yogotv/payment_diagnostics.dart';
import 'package:yogotv/purchase.dart';
import 'package:yogotv/states/user.dart';

class Membership extends StatefulWidget {
  const Membership({super.key});

  @override
  State<Membership> createState() => _MembershipState();
}

enum VipPayResult { vip, coins }

Future<VipPayResult?> showVipPayBottomSheet(
  BuildContext context, {
  String episodeCoins = '0',
}) {
  return showModalBottomSheet<VipPayResult>(
    context: context,
    isScrollControlled: true,
    isDismissible: true,
    enableDrag: false,
    backgroundColor: Colors.transparent,
    builder: (sheetContext) => FractionallySizedBox(
      heightFactor: 0.8,
      alignment: Alignment.bottomCenter,
      child: _VipPaySheet(episodeCoins: episodeCoins),
    ),
  );
}

class TopUpPage extends StatelessWidget {
  const TopUpPage({super.key, this.episodeCoins = '0'});

  final String episodeCoins;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xff151515),
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            AndroidToolbar(
              title: t.top_up,
              onBack: context.pop,
              trailing: _paymentDiagnosticsButton(context),
            ),
            Expanded(
              child: _VipPaySheet(episodeCoins: episodeCoins, fullPage: true),
            ),
          ],
        ),
      ),
    );
  }
}

class _MembershipState extends State<Membership> with WidgetsBindingObserver {
  late final StreamSubscription<UserStateValue?> _userStateListener;

  bool _loading = true;
  bool _restore = false;
  bool _isVip = false;
  String _vipExpire = '';
  String? _selectedId;
  List<dynamic> _subscriptions = [];
  List<dynamic> _vipVideos = [];
  bool _viewContentTracked = false;
  int _eligibilityRequest = 0;

  @override
  void initState() {
    super.initState();
    Global.payTrace('VIP page entered build=verify-order-cache-v2');
    WidgetsBinding.instance.addObserver(this);
    Global.blockAd();
    _userStateListener = context.read<UserState>().stream.listen((value) {
      if (mounted) {
        final becameVip = (value?.vip ?? 0) > 0 && !_isVip;
        setState(() {
          _isVip = _isVip || (value?.vip ?? 0) > 0;
        });
        if (becameVip) {
          unawaited(_loadData(showLoading: false));
        }
      }
    });
    _loadData();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    Global.allowAd();
    _userStateListener.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed && _restore) {
      _restore = false;
      _handleRestore();
    }
  }

  Future<void> _loadData({bool showLoading = true}) async {
    if (showLoading && mounted) {
      setState(() => _loading = true);
    }

    final vipFuture = api<Map<String, dynamic>>(
      'user/membership',
      method: Method.post,
      loading: false,
    );
    final videosFuture = api<dynamic>(
      'feed/membership?page=1',
      method: Method.post,
      loading: false,
    );
    final productsFuture = _loadProducts();

    Result<Map<String, dynamic>>? vip;
    Result<dynamic>? videos;
    List<dynamic> products = _subscriptions;
    try {
      vip = await vipFuture;
      videos = await videosFuture;
      products = await productsFuture;
    } on Exception catch (error) {
      Global.logger.d('membership_load_failed $error');
      Global.payTrace('membership reload failed');
    }

    if (!mounted) {
      return;
    }

    final vipPayload = vip?.d ?? {};
    final expire = _membershipExpire(vipPayload);
    final isVip =
        _membershipIsActive(vipPayload) || context.read<UserState>().isVip;
    final subscriptions = _withCachedAppleIntroductoryEligibility(products);
    final vipVideos = videos?.c == 0
        ? _membershipRows(videos?.d).take(6).toList()
        : _vipVideos;

    setState(() {
      _isVip = isVip;
      _vipExpire = _expireText(expire);
      _vipVideos = vipVideos;
      _subscriptions = subscriptions;
      _selectedId = _selectedId ?? _defaultSelectedId(subscriptions);
      _loading = false;
    });
    if (_applePayMode) {
      _refreshAppleIntroductoryEligibility(subscriptions);
      unawaited(
        Purchase.warmUpProductDetails(subscriptions.map(_storeProductId)),
      );
    }
    if (!_viewContentTracked) {
      _viewContentTracked = true;
      AdjustTracking.trackViewContent();
    }
  }

  Future<List<dynamic>> _loadProducts() async {
    final path = _applePayMode ? 'applePay/products' : 'product';
    if (_applePayMode) {
      await Global.ensureAnonymousSession();
    }
    Global.payTrace('products request path=$path');
    var products = await api<dynamic>(
      path,
      method: Method.post,
      data: _applePayMode ? {} : {'type': 10},
      loading: false,
    );
    if (_applePayMode && products.m == 'Authentication Failure.') {
      Global.payTrace('products auth failed, refresh anonymous session');
      await Global.ensureAnonymousSession(force: true);
      products = await api<dynamic>(
        path,
        method: Method.post,
        data: {},
        loading: false,
      );
    }
    Global.payTrace('products response c=${products.c} m=${products.m}');
    return _subscriptionRows(products.d);
  }

  void _refreshAppleIntroductoryEligibility(List<dynamic> subscriptions) {
    final request = ++_eligibilityRequest;
    unawaited(() async {
      final updated = await _withAppleIntroductoryEligibility(subscriptions);
      if (!mounted || request != _eligibilityRequest) {
        return;
      }
      setState(() => _subscriptions = updated);
    }());
  }

  Future<void> _handleRestore() async {
    setState(() => _loading = true);
    final isIosRestore = !kIsWeb && Platform.isIOS;
    var restored = false;
    if (isIosRestore) {
      restored = await Purchase.restore();
    }
    await _refreshMembership();
    await _loadData();
    if (isIosRestore &&
        !restored &&
        mounted &&
        !context.read<UserState>().isVip) {
      Global.warning(t.no_order);
    }
  }

  Future<void> _handleSubscribe() async {
    final product = _selectedSubscription();
    if (product == null) {
      Global.warning(t.please_select_a_vip_plan);
      return;
    }

    final price = double.tryParse(_text(product['price'])) ?? 0;
    if (_applePayMode) {
      final storeProductId = _storeProductId(product);
      final priceType = await Purchase.introductoryPriceType(storeProductId);
      await _trackCheckout(storeProductId: storeProductId, price: price);
      Global.payTrace('membership subscribe call IAP');
      if (Global.webPreview) {
        final result = await Purchase.previewCreate(
          localProductId: _productId(product),
          appleProductId: storeProductId,
          type: 1,
          priceType: priceType,
        );
        Global.payTrace('membership preview create returned=$result');
        if (mounted) {
          setState(() => _loading = false);
        }
        return;
      }
      final result = await Purchase.making(
        localProductId: _productId(product),
        appleProductId: storeProductId,
        type: 1,
        priceType: priceType,
      );
      Global.payTrace('membership IAP returned=$result');
      if (!result) {
        if (!mounted) {
          return;
        }
        await _showPurchaseDiagnostics(context, success: false);
        return;
      }
      if (result) {
        await TikTokEventsSdk.logEvent(
          event: TikTokEvent(
            eventName: 'subscribe',
            properties: EventProperties(
              description: storeProductId,
              value: price,
              currency: CurrencyCode.USD,
            ),
          ),
        );
        Global.payTrace('membership refresh vip');
        await _refreshMembership();
        if (!mounted) {
          return;
        }
        Global.payTrace('membership reload products');
        final userVip = context.read<UserState>().isVip;
        setState(() {
          _isVip = userVip || _isVip;
          _loading = false;
        });
        await _loadData(showLoading: false);
        if (mounted) {
          await _showPurchaseDiagnostics(context, success: true);
        }
      }
      return;
    }

    final result = await api<dynamic>(
      'pay/create',
      method: Method.post,
      data: {'payment': 1, 'product_id': _productId(product)},
      loading: true,
    );
    if (result.c == 0) {
      _restore = true;
      Global.success(t.success);
    }
  }

  Future<void> _handleSubscriptionTap(dynamic product) async {
    final productId = _productId(product);
    if (productId.isEmpty) {
      return;
    }
    setState(() => _selectedId = productId);
    await _handleSubscribe();
  }

  dynamic _selectedSubscription() {
    for (final item in _subscriptions) {
      if (_productId(item) == _selectedId) {
        return item;
      }
    }
    Global.payTrace('membership selected product missing id=$_selectedId');
    return null;
  }

  Future<void> _refreshMembership() async {
    final user = await api<Map<String, dynamic>>(
      'user/membership',
      method: Method.post,
      loading: false,
    );
    final data = user.d;
    if (!mounted || data == null) {
      Global.payTrace('membership user refresh empty c=${user.c}');
      return;
    }
    Global.logger.d(
      'membership_refresh vip_expire_at=${data['vip_expire_at']}',
    );
    Global.payTrace(
      'membership response vip_expire_at=${data['vip_expire_at']}',
    );
    final expireMillis = int.tryParse('${data['vip_expire_at'] ?? 0}') ?? 0;
    final isVip = expireMillis > 0;
    final userState = context.read<UserState>();
    if (userState.isVip != isVip) {
      userState.setVip(isVip ? 1 : 0);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = context.read<UserState>();

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            AndroidToolbar(
              title: t.membership,
              onBack: context.pop,
              trailing: _paymentDiagnosticsButton(context),
            ),
            Expanded(
              child: _loading
                  ? Loading()
                  : Column(
                      children: [
                        Expanded(
                          child: RefreshIndicator(
                            color: Colors.white,
                            backgroundColor: Color(0xffff3d5d),
                            onRefresh: _loadData,
                            child: ListView(
                              physics: AlwaysScrollableScrollPhysics(),
                              padding: EdgeInsets.fromLTRB(15, 8, 15, 15),
                              children: [
                                _UserHeader(
                                  name: _userName(user),
                                  isVip: _isVip,
                                  vipExpire: _vipExpire,
                                ),
                                if (!_isVip) ...[
                                  SizedBox(height: 14),
                                  _SectionTitle(t.choose_vip_plan),
                                  SizedBox(height: 2),
                                  ..._subscriptions.map(
                                    (item) => Padding(
                                      padding: EdgeInsets.only(bottom: 12),
                                      child: _VipPlanCard(
                                        item: item,
                                        selected:
                                            _productId(item) == _selectedId,
                                        onTap: () => unawaited(
                                          _handleSubscriptionTap(item),
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                                if (_isVip) ...[
                                  SizedBox(height: 14),
                                  _VipBenefitsPanel(),
                                ],
                                SizedBox(height: 14),
                                _SectionTitle(t.vip_exclusives),
                                _VipExclusiveGrid(
                                  items: _vipVideos,
                                  minimumSlots: 6,
                                ),
                                SizedBox(height: 14),
                                _RechargeTips(),
                              ],
                            ),
                          ),
                        ),
                        if (!_isVip)
                          SafeArea(
                            top: false,
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Padding(
                                  padding: EdgeInsets.symmetric(
                                    horizontal: 15,
                                    vertical: 8,
                                  ),
                                  child: Text(
                                    t.cancel_auto_renewal_anytime,
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      color: Color(0xff999999),
                                      fontSize: 14,
                                      height: 1.2,
                                    ),
                                  ),
                                ),
                                if (!kIsWeb && Platform.isIOS)
                                  TextButton(
                                    onPressed: _handleRestore,
                                    child: Text(
                                      t.restore_purchases,
                                      style: TextStyle(
                                        color: Color(0xff999999),
                                        fontSize: 14,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _VipPaySheet extends StatefulWidget {
  const _VipPaySheet({required this.episodeCoins, this.fullPage = false});

  final String episodeCoins;
  final bool fullPage;

  @override
  State<_VipPaySheet> createState() => _VipPaySheetState();
}

class _VipPaySheetState extends State<_VipPaySheet> {
  bool _loading = true;
  String _balance = '0';
  String? _selectedId;
  List<dynamic> _subscriptions = [];
  List<dynamic> _coins = [];
  int _eligibilityRequest = 0;

  @override
  void initState() {
    super.initState();
    Global.payTrace('VIP sheet entered build=verify-order-cache-v2');
    _loadData();
    AdjustTracking.trackViewContent();
  }

  Future<void> _loadData() async {
    final productPath = _applePayMode ? 'applePay/products' : 'product';
    if (_applePayMode) {
      await Global.ensureAnonymousSession();
    }
    Global.payTrace('products request path=$productPath');
    final productsFuture = api<dynamic>(
      productPath,
      method: Method.post,
      data: _applePayMode ? {} : {'type': 10},
      loading: false,
    );
    final balanceFuture = api<dynamic>(
      'user/balance',
      method: Method.post,
      loading: false,
    );
    final vipFuture = api<Map<String, dynamic>>(
      'user/membership',
      method: Method.post,
      loading: false,
    );

    var products = await productsFuture;
    final balance = await balanceFuture;
    final vip = await vipFuture;
    if (_applePayMode && products.m == 'Authentication Failure.') {
      Global.payTrace('products auth failed, refresh anonymous session');
      await Global.ensureAnonymousSession(force: true);
      products = await api<dynamic>(
        productPath,
        method: Method.post,
        data: {},
        loading: false,
      );
    }
    Global.payTrace('products response c=${products.c} m=${products.m}');
    if (!mounted) {
      return;
    }
    if (vip.c == 0 && vip.d != null) {
      final expireMillis = int.tryParse('${vip.d!['vip_expire_at'] ?? 0}') ?? 0;
      context.read<UserState>().setVip(expireMillis > 0 ? 1 : 0);
    }
    final subscriptions = _withCachedAppleIntroductoryEligibility(
      _subscriptionRows(products.d),
    );
    final coins = _purchaseRows(products.d);
    if (!mounted) {
      return;
    }
    setState(() {
      _subscriptions = subscriptions;
      _coins = coins;
      _balance = _cleanNumber(balance.d);
      _selectedId =
          _selectedId ??
          _defaultSelectedId(subscriptions) ??
          (coins.isEmpty ? null : _productId(coins.first));
      _loading = false;
    });
    if (_applePayMode) {
      _refreshAppleIntroductoryEligibility(subscriptions);
      unawaited(Purchase.warmUpProductDetails(coins.map(_storeProductId)));
    }
  }

  void _refreshAppleIntroductoryEligibility(List<dynamic> subscriptions) {
    final request = ++_eligibilityRequest;
    unawaited(() async {
      final updated = await _withAppleIntroductoryEligibility(subscriptions);
      if (!mounted || request != _eligibilityRequest) {
        return;
      }
      setState(() => _subscriptions = updated);
    }());
  }

  Future<void> _pay(dynamic product) async {
    setState(() => _selectedId = _productId(product));
    final price = double.tryParse(_text(product['price'])) ?? 0;
    final storeProductId = _storeProductId(product);
    if (_applePayMode) {
      final payResult = _payResultFor(product);
      final type = payResult == VipPayResult.coins ? 2 : 1;
      final priceType = type == 1
          ? await Purchase.introductoryPriceType(storeProductId)
          : 0;
      await _trackCheckout(storeProductId: storeProductId, price: price);
      Global.payTrace('sheet pay call IAP result=$payResult');
      if (Global.webPreview) {
        final result = await Purchase.previewCreate(
          localProductId: _productId(product),
          appleProductId: storeProductId,
          type: type,
          priceType: priceType,
        );
        Global.payTrace('sheet preview create returned=$result');
        return;
      }
      final result = await Purchase.making(
        localProductId: _productId(product),
        appleProductId: storeProductId,
        type: type,
        priceType: priceType,
      );
      Global.payTrace('sheet IAP returned=$result');
      if (!result) {
        if (!mounted) {
          return;
        }
        await _showPurchaseDiagnostics(context, success: false);
        return;
      }
      if (result) {
        await TikTokEventsSdk.logEvent(
          event: TikTokEvent(
            eventName: 'subscribe',
            properties: EventProperties(
              description: storeProductId,
              value: price,
              currency: CurrencyCode.USD,
            ),
          ),
        );
        Global.payTrace(
          payResult == VipPayResult.coins
              ? 'sheet refresh balance'
              : 'sheet refresh vip',
        );
        if (payResult == VipPayResult.coins) {
          await _refreshBalance();
        } else {
          await _refreshMembership();
        }
        if (!mounted) {
          return;
        }
        await _showPurchaseDiagnostics(context, success: true);
        if (!mounted) {
          return;
        }
        Global.payTrace('sheet close with ${_payResultFor(product)}');
        Navigator.of(context).pop(_payResultFor(product));
      }
      return;
    }

    final result = await api<dynamic>(
      'pay/create',
      method: Method.post,
      data: {'payment': 1, 'product_id': _productId(product)},
      loading: true,
    );
    if (result.c == 0) {
      final productId = int.tryParse(_productId(product));
      if (productId == null) {
        Global.error(t.failed);
        return;
      }
      if (!mounted) {
        return;
      }
      context.push('/airwallex', extra: {'product': productId});
    }
  }

  VipPayResult _payResultFor(dynamic product) {
    final productId = _productId(product);
    final coinProduct = _coins.any((item) => _productId(item) == productId);
    return coinProduct ? VipPayResult.coins : VipPayResult.vip;
  }

  Future<void> _refreshMembership() async {
    final user = await api<Map<String, dynamic>>(
      'user/membership',
      method: Method.post,
      loading: false,
    );
    final data = user.d;
    if (!mounted || data == null) {
      Global.payTrace('sheet user refresh empty c=${user.c}');
      return;
    }
    Global.logger.d('vip_sheet_refresh vip_expire_at=${data['vip_expire_at']}');
    Global.payTrace(
      'sheet membership response vip_expire_at=${data['vip_expire_at']}',
    );
    final expireMillis = int.tryParse('${data['vip_expire_at'] ?? 0}') ?? 0;
    final isVip = expireMillis > 0;
    final userState = context.read<UserState>();
    if (userState.isVip != isVip) {
      userState.setVip(isVip ? 1 : 0);
    }
  }

  Future<void> _refreshBalance() async {
    final previousBalance = _balance;
    PaymentDiagnostics.stage(
      'balance_refresh_started',
      details: 'before=$previousBalance',
    );
    try {
      final balance = await api<dynamic>(
        'user/balance',
        method: Method.post,
        loading: false,
        showError: false,
      );
      Global.payTrace(
        'sheet balance refresh c=${balance.c} value=${balance.d}',
      );
      if (balance.c != 0) {
        PaymentDiagnostics.warning(
          'balance_refresh_rejected',
          'serverCode=${balance.c} serverMessage=${balance.m}',
        );
        return;
      }
      final nextBalance = _cleanNumber(balance.d);
      PaymentDiagnostics.stage(
        'balance_refresh_ok',
        details: 'before=$previousBalance after=$nextBalance',
      );
      if (mounted) {
        setState(() => _balance = nextBalance);
      }
    } on Exception catch (error) {
      PaymentDiagnostics.warning('balance_refresh_failed', '$error');
    }
  }

  @override
  Widget build(BuildContext context) {
    final isVip = context.watch<UserState>().isVip;
    return ClipRRect(
      borderRadius: widget.fullPage
          ? BorderRadius.zero
          : BorderRadius.vertical(top: Radius.circular(12)),
      child: Material(
        color: Color(0xff151515),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 15),
            child: Column(
              children: [
                if (!widget.fullPage)
                  _VipPayBalanceRow(
                    episodeCoins: widget.episodeCoins,
                    balance: _balance,
                    onClose: () => Navigator.pop(context),
                  ),
                Expanded(
                  child: _loading
                      ? Loading()
                      : SingleChildScrollView(
                          physics: AlwaysScrollableScrollPhysics(),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (!isVip && _subscriptions.isNotEmpty) ...[
                                Text(
                                  t.membership,
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 18,
                                  ),
                                ),
                                SizedBox(height: 12),
                                ..._subscriptions.map(
                                  (item) => Padding(
                                    padding: EdgeInsets.only(bottom: 12),
                                    child: _VipPlanCard(
                                      item: item,
                                      selected: _productId(item) == _selectedId,
                                      onTap: () => _pay(item),
                                    ),
                                  ),
                                ),
                              ],
                              if (_coins.isNotEmpty) ...[
                                if (!isVip && _subscriptions.isNotEmpty)
                                  SizedBox(height: 5),
                                if (widget.fullPage) ...[
                                  Text(
                                    t.coins,
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 18,
                                    ),
                                  ),
                                  SizedBox(height: 12),
                                ],
                                GridView.builder(
                                  shrinkWrap: true,
                                  physics: NeverScrollableScrollPhysics(),
                                  itemCount: _coins.length,
                                  gridDelegate:
                                      SliverGridDelegateWithFixedCrossAxisCount(
                                        crossAxisCount: 2,
                                        crossAxisSpacing: 14,
                                        mainAxisSpacing: 12,
                                        childAspectRatio: 1.92,
                                      ),
                                  itemBuilder: (context, index) {
                                    final item = _coins[index];
                                    return _CoinPlanCard(
                                      item: item,
                                      selected: _productId(item) == _selectedId,
                                      onTap: () => _pay(item),
                                    );
                                  },
                                ),
                              ],
                              SizedBox(height: 15),
                              _RechargeTips(),
                              SizedBox(height: 15),
                            ],
                          ),
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _VipPayBalanceRow extends StatelessWidget {
  const _VipPayBalanceRow({
    required this.episodeCoins,
    required this.balance,
    required this.onClose,
  });

  final String episodeCoins;
  final String balance;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 60,
      child: Row(
        children: [
          Text(
            t.this_episode,
            style: TextStyle(color: Color(0xff999999), fontSize: 14),
          ),
          SizedBox(width: 4),
          Image.asset('assets/images/android/ic_coin.png', width: 14),
          SizedBox(width: 4),
          Expanded(
            child: Text(
              episodeCoins,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: Colors.white, fontSize: 14),
            ),
          ),
          SizedBox(width: 12),
          Text(
            t.balance,
            style: TextStyle(color: Color(0xff999999), fontSize: 14),
          ),
          SizedBox(width: 4),
          Image.asset('assets/images/android/ic_coin.png', width: 14),
          SizedBox(width: 4),
          Expanded(
            child: Text(
              balance,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: Colors.white, fontSize: 14),
            ),
          ),
          InkWell(
            onTap: onClose,
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: EdgeInsets.all(2),
              child: SvgPicture.asset(
                'assets/images/android/ic_close.svg',
                width: 24,
                height: 24,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CoinPlanCard extends StatelessWidget {
  const _CoinPlanCard({
    required this.item,
    required this.selected,
    required this.onTap,
  });

  final dynamic item;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final coin = _coinAmount(item);
    final price = _text(item['price']);
    final bonusValue = _bonusValue(item);
    final bonusCoins = _bonusCoins(item);
    final bonus = bonusCoins == 0 ? '' : '+${_cleanNumber(bonusCoins)}';
    final bg = selected
        ? [Color(0xffffecd4), Color(0xfff3cb93)]
        : [Color(0xff332f2a), Color(0xff332f2a)];
    final textColor = selected ? Color(0xff633e25) : Colors.white;
    final priceBg = selected
        ? [Color(0xffc17846), Color(0xff603c24)]
        : [Color(0x594e4e4e), Color(0x594e4e4e)];

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Ink(
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: bg),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Stack(
          children: [
            if (bonusValue > 0)
              PositionedDirectional(
                top: 0,
                end: 0,
                child: Container(
                  padding: EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: selected
                          ? [Color(0xffea6f3c), Color(0xffeba341)]
                          : [Color(0xff46372c), Color(0xff46372c)],
                    ),
                    borderRadius: BorderRadiusDirectional.only(
                      topEnd: Radius.circular(12),
                      bottomStart: Radius.circular(12),
                    ),
                  ),
                  child: Text(
                    '+${(bonusValue * 100).toInt()}%',
                    style: TextStyle(color: Colors.white, fontSize: 12),
                  ),
                ),
              ),
            Column(
              children: [
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Image.asset(
                            'assets/images/android/ic_coin.png',
                            width: 20,
                            height: 20,
                          ),
                          SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              coin,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(color: textColor, fontSize: 18),
                            ),
                          ),
                        ],
                      ),
                      if (bonus.isNotEmpty) ...[
                        SizedBox(height: 4),
                        Text(
                          bonus,
                          style: TextStyle(
                            color: textColor.withAlpha(191),
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                Container(
                  width: double.infinity,
                  padding: EdgeInsets.symmetric(vertical: 6),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(colors: priceBg),
                    borderRadius: BorderRadius.vertical(
                      bottom: Radius.circular(12),
                    ),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    '\$${_moneyValue(price)}',
                    style: TextStyle(
                      color: selected ? Colors.white : Color(0xfff1da97),
                      fontSize: 14,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _UserHeader extends StatelessWidget {
  const _UserHeader({
    required this.name,
    required this.isVip,
    required this.vipExpire,
  });

  final String name;
  final bool isVip;
  final String vipExpire;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        ClipOval(
          child: Image.asset(
            'assets/images/android/ic_avatar_guest.png',
            width: 44,
            height: 44,
            fit: BoxFit.cover,
          ),
        ),
        SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Flexible(
                    child: Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                  ),
                  if (isVip) ...[
                    SizedBox(width: 4),
                    Image.asset(
                      'assets/images/android/ic_me_tag_vip.png',
                      width: 42,
                      height: 20,
                      fit: BoxFit.contain,
                    ),
                  ],
                ],
              ),
              SizedBox(height: 2),
              Text(
                isVip && vipExpire.isNotEmpty
                    ? '${t.valid_until} $vipExpire'
                    : t.not_a_vip_yet,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: Color(0xff999999), fontSize: 14),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 10),
      child: Text(
        text,
        style: TextStyle(
          color: Colors.white,
          fontSize: 16,
          fontWeight: FontWeight.w400,
        ),
      ),
    );
  }
}

class _VipPlanCard extends StatelessWidget {
  const _VipPlanCard({
    required this.item,
    required this.selected,
    required this.onTap,
  });

  final dynamic item;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final title = _productTitle(item);
    final basePlan = _planId(item);
    final price = _text(item['price']);
    final firstPrice = _text(item['first_price'] ?? item['firstPrice']);
    final appleEligibility = item['_apple_intro_eligible'];
    final isOfferEligible = appleEligibility == true;
    final hasOffer =
        (basePlan == 'weekly' || basePlan == 'yearly') &&
        isOfferEligible &&
        firstPrice.isNotEmpty &&
        price.isNotEmpty &&
        _moneyNumber(firstPrice) < _moneyNumber(price);
    final displayPrice = hasOffer ? firstPrice : price;
    final bonusValue = _bonusValue(item);
    final showTimedOffer = hasOffer && basePlan == 'weekly';
    final discountPercent = showTimedOffer
        ? _discountPercent(firstPrice, price)
        : 0;
    final badgeText = !hasOffer && bonusValue > 0
        ? '+${(bonusValue * 100).toInt()}%'
        : '';
    final description = showTimedOffer
        ? t.first_week_string_then_string_week(
            s: _moneyParam(firstPrice),
            s2: _moneyParam(price),
          )
        : t.auto_renewal_cancel_anytime;

    final bgGradient = selected
        ? [Color(0xffffecd4), Color(0xfff3cb93)]
        : [Color(0xff3c3427), Color(0xff201816)];
    final textColor = selected ? Color(0xff633e25) : Colors.white;
    final subColor = selected
        ? Color(0xff633e25).withAlpha(190)
        : Colors.white.withAlpha(190);
    final benefitColor = selected ? Color(0xff633e25) : Color(0xfff1da97);
    final benefitSuffix = selected ? '0' : '1';

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Ink(
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: bgGradient),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Stack(
            children: [
              PositionedDirectional(
                top: 0,
                end: 0,
                child: Opacity(
                  opacity: selected ? 1 : 0.1,
                  child: Image.asset(
                    'assets/images/android/img_weekly_price_right.png',
                    width: 200,
                    fit: BoxFit.contain,
                  ),
                ),
              ),
              Column(
                children: [
                  Padding(
                    padding: EdgeInsets.fromLTRB(15, 22, 15, 22),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: textColor,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              SizedBox(height: 8),
                              Text(
                                description,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: subColor,
                                  fontSize: 12,
                                  height: 1.2,
                                ),
                              ),
                            ],
                          ),
                        ),
                        SizedBox(width: 12),
                        Container(
                          padding: EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            gradient: selected
                                ? LinearGradient(
                                    colors: [
                                      Color(0xffc17846),
                                      Color(0xff603c24),
                                    ],
                                  )
                                : null,
                            color: selected ? null : Color(0xff3a342f),
                            borderRadius: BorderRadius.circular(30),
                          ),
                          child: Text(
                            '\$$displayPrice',
                            style: TextStyle(
                              color: selected
                                  ? Colors.white
                                  : Color(0xfff1da97),
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    width: double.infinity,
                    padding: EdgeInsets.symmetric(horizontal: 15, vertical: 10),
                    decoration: BoxDecoration(
                      color: selected ? Color(0x29fff4e5) : Color(0x594e4e4e),
                      borderRadius: BorderRadius.vertical(
                        bottom: Radius.circular(12),
                      ),
                    ),
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 10,
                      children: [
                        _PlanBenefit(
                          asset: 'ic_benefit_short_$benefitSuffix.svg',
                          text: t.unlimited_viewing,
                          color: benefitColor,
                        ),
                        _PlanBenefit(
                          asset: 'ic_benefit_hd_$benefitSuffix.svg',
                          text: t.hd_quality,
                          color: benefitColor,
                        ),
                        _PlanBenefit(
                          asset: 'ic_benefit_ad_$benefitSuffix.svg',
                          text: t.ad_free,
                          color: benefitColor,
                        ),
                        _PlanBenefit(
                          asset: 'ic_benefit_benefit_$benefitSuffix.svg',
                          text: t.more_benefits,
                          color: benefitColor,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              if (discountPercent > 0 || badgeText.isNotEmpty)
                PositionedDirectional(
                  top: 0,
                  end: 0,
                  child: hasOffer
                      ? _OfferCountdownBadge()
                      : Container(
                          padding: EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: selected
                                  ? [Color(0xffea6f3c), Color(0xffeba341)]
                                  : [Color(0xff46372c), Color(0xff46372c)],
                            ),
                            borderRadius: BorderRadiusDirectional.only(
                              topEnd: Radius.circular(12),
                              bottomStart: Radius.circular(12),
                            ),
                          ),
                          child: Text(
                            badgeText,
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PlanBenefit extends StatelessWidget {
  const _PlanBenefit({
    required this.asset,
    required this.text,
    required this.color,
  });

  final String asset;
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: (MediaQuery.of(context).size.width - 30 - 30 - 8) / 2,
      child: Row(
        children: [
          SvgPicture.asset(
            'assets/images/android/$asset',
            width: 16,
            height: 16,
          ),
          SizedBox(width: 4),
          Expanded(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: color, fontSize: 10),
            ),
          ),
        ],
      ),
    );
  }
}

class _OfferCountdownBadge extends StatefulWidget {
  @override
  State<_OfferCountdownBadge> createState() => _OfferCountdownBadgeState();
}

class _OfferCountdownBadgeState extends State<_OfferCountdownBadge> {
  static const _offerDuration = Duration(minutes: 30);
  static const _deadlineKey = 'membership-offer-countdown-deadline';
  late int _deadlineMs;
  late final Timer _timer;

  @override
  void initState() {
    super.initState();
    _deadlineMs = _resolveDeadline();
    _timer = Timer.periodic(Duration(seconds: 1), (_) {
      if (mounted) {
        if (DateTime.now().millisecondsSinceEpoch >= _deadlineMs) {
          _deadlineMs = _resolveDeadline();
        }
        setState(() {});
      }
    });
  }

  static int _resolveDeadline() {
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final savedDeadline = Global.sp.getInt(_deadlineKey) ?? 0;
    if (savedDeadline > nowMs) {
      return savedDeadline;
    }

    final nextDeadline = nowMs + _offerDuration.inMilliseconds;
    unawaited(Global.sp.setInt(_deadlineKey, nextDeadline));
    return nextDeadline;
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final remainingMs = _deadlineMs - DateTime.now().millisecondsSinceEpoch;
    final remainingSeconds = remainingMs <= 0
        ? 0
        : (remainingMs / Duration.millisecondsPerSecond).ceil();
    final minutes = (remainingSeconds ~/ Duration.secondsPerMinute)
        .remainder(60)
        .toString()
        .padLeft(2, '0');
    final seconds = remainingSeconds
        .remainder(Duration.secondsPerMinute)
        .toString()
        .padLeft(2, '0');

    return Container(
      padding: EdgeInsetsDirectional.only(start: 11, end: 9, top: 3, bottom: 3),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xfffd36bc), Color(0xfffd3a5a)],
        ),
        borderRadius: BorderRadiusDirectional.only(
          topEnd: Radius.circular(12),
          bottomStart: Radius.circular(12),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SvgPicture.string(
            '''
<svg width="16" height="16" viewBox="0 0 16 16" fill="none" xmlns="http://www.w3.org/2000/svg">
  <path d="M7.93 0.991C11.762 0.991 14.868 4.098 14.868 7.93C14.868 11.762 11.762 14.868 7.93 14.868C4.098 14.868 0.991 11.762 0.991 7.93C0.991 4.098 4.098 0.991 7.93 0.991ZM10.257 2.48C7.242 1.207 3.767 2.618 2.493 5.633C1.22 8.648 2.632 12.124 5.646 13.398C8.661 14.67 12.137 13.259 13.41 10.244C13.562 9.885 13.677 9.511 13.756 9.129C14.323 6.362 12.859 3.579 10.257 2.48ZM7.92 3.472C8.193 3.472 8.415 3.693 8.415 3.967V7.723L11.245 10.554C11.438 10.747 11.438 11.061 11.245 11.254C11.052 11.447 10.738 11.447 10.545 11.254L7.425 8.133V3.967C7.425 3.693 7.646 3.472 7.92 3.472Z" fill="white"/>
</svg>
''',
            width: 16,
            height: 16,
          ),
          SizedBox(width: 4),
          Text(
            '$minutes:$seconds',
            style: TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _VipBenefitsPanel extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 15, vertical: 16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xffffecd4), Color(0xfff3cb93)],
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(child: _GoldLine(reverse: false)),
              SizedBox(width: 12),
              Text(
                t.vip_benefits,
                style: TextStyle(
                  color: Color(0xff633e25),
                  fontWeight: FontWeight.w600,
                ),
              ),
              SizedBox(width: 12),
              Expanded(child: _GoldLine(reverse: true)),
            ],
          ),
          SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _VipBenefitAsset(
                image: 'ic_vip_short.png',
                text: t.unlimited_viewing,
              ),
              _VipBenefitAsset(image: 'ic_vip_ad.png', text: t.ad_free),
              _VipBenefitAsset(image: 'ic_vip_hd.png', text: t.hd_quality),
              _VipBenefitAsset(
                image: 'ic_vip_benefit.png',
                text: t.more_benefits,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _GoldLine extends StatelessWidget {
  const _GoldLine({required this.reverse});

  final bool reverse;

  @override
  Widget build(BuildContext context) {
    final colors = [Colors.transparent, Color(0xff633e25)];
    return Container(
      height: 4,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: reverse ? colors.reversed.toList() : colors,
        ),
        borderRadius: BorderRadius.circular(12),
      ),
    );
  }
}

class _VipBenefitAsset extends StatelessWidget {
  const _VipBenefitAsset({required this.image, required this.text});

  final String image;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Image.asset(
            'assets/images/android/$image',
            width: 40,
            height: 40,
            fit: BoxFit.contain,
          ),
          SizedBox(height: 6),
          Text(
            text,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Color(0xff633e25),
              fontSize: 12,
              height: 1.2,
            ),
          ),
        ],
      ),
    );
  }
}

class _VipExclusiveGrid extends StatelessWidget {
  const _VipExclusiveGrid({required this.items, this.minimumSlots = 0});

  final List<dynamic> items;
  final int minimumSlots;

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      shrinkWrap: true,
      physics: NeverScrollableScrollPhysics(),
      itemCount: items.length < minimumSlots ? minimumSlots : items.length,
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 10,
        mainAxisSpacing: 12,
        childAspectRatio: items.isEmpty ? 3 / 4 : 0.57,
      ),
      itemBuilder: (context, index) {
        if (index >= items.length) {
          return const _VipExclusivePlaceholder();
        }
        final item = items[index];
        final image = _posterUrl(item);
        final ratio = MediaQuery.of(context).devicePixelRatio.clamp(1.0, 3.0);
        return InkWell(
          onTap: () => _openPlay(context, item),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AspectRatio(
                aspectRatio: 3 / 4,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: SizedBox.expand(
                    child: image.isEmpty
                        ? const _VipPosterPlaceholder()
                        : LazyImage(
                            url: image,
                            width: double.infinity,
                            height: double.infinity,
                            fit: BoxFit.cover,
                            cacheWidth: (120 * ratio).round(),
                          ),
                  ),
                ),
              ),
              SizedBox(height: 8),
              Text(
                _titleText(item),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  height: 1.16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _VipExclusivePlaceholder extends StatelessWidget {
  const _VipExclusivePlaceholder();

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topCenter,
      child: AspectRatio(
        aspectRatio: 3 / 4,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: const _VipPosterPlaceholder(),
        ),
      ),
    );
  }
}

class _VipPosterPlaceholder extends StatelessWidget {
  const _VipPosterPlaceholder();

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Color(0xff212121),
      child: Center(
        child: SvgPicture.asset(
          'assets/images/android/ic_logo_loading.svg',
          width: 32,
          height: 32,
        ),
      ),
    );
  }
}

class _RechargeTips extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Text(
      _rechargeTips(),
      style: TextStyle(color: Color(0xff999999), fontSize: 14, height: 1.3),
    );
  }
}

String _userName(UserState user) {
  if (user.state == null || user.state!.anonymous == 1) {
    return t.guest;
  }
  return user.state!.name;
}

bool get _applePayMode => Global.webPreview || (!kIsWeb && Platform.isIOS);

Future<void> _trackCheckout({
  required String storeProductId,
  required double price,
}) async {
  if (Global.webPreview) {
    Global.payTrace('web preview skip checkout tracking');
    return;
  }
  AdjustTracking.trackInitiateCheckout(
    productId: storeProductId,
    amount: price,
  );
  try {
    await TikTokEventsSdk.logEvent(
      event: TikTokEvent(
        eventName: 'checkout',
        properties: EventProperties(
          description: storeProductId,
          value: price,
          currency: CurrencyCode.USD,
        ),
      ),
    );
  } on Object catch (error) {
    Global.logger.d('checkout tracking failed: $error');
    Global.payTrace('checkout tracking failed $error');
  }
}

List<dynamic> _subscriptionRows(dynamic payload) {
  final fromGroupedPayload = payload is Map;
  final rows = fromGroupedPayload ? payload['subscription'] : payload;
  final list = rows is List ? rows : <dynamic>[];
  if (fromGroupedPayload) {
    return list.whereType<Map>().where((item) {
      return _storeProductId(item).isNotEmpty;
    }).toList();
  }
  return list.where((item) {
    if (item is! Map) {
      return false;
    }
    if (!fromGroupedPayload &&
        _productType(item) != 0 &&
        _productType(item) != 1) {
      return false;
    }
    final plan = _planId(item);
    return plan.isNotEmpty;
  }).toList();
}

Future<List<dynamic>> _withAppleIntroductoryEligibility(
  List<dynamic> subscriptions,
) async {
  if (kIsWeb || !Platform.isIOS || subscriptions.isEmpty) {
    return subscriptions;
  }
  final eligibility = await Purchase.introductoryOfferEligibility(
    subscriptions.map(_storeProductId),
  );
  if (eligibility.isEmpty) {
    return subscriptions;
  }
  return _applyAppleIntroductoryEligibility(subscriptions, eligibility);
}

List<dynamic> _withCachedAppleIntroductoryEligibility(
  List<dynamic> subscriptions,
) {
  if (kIsWeb || !Platform.isIOS || subscriptions.isEmpty) {
    return subscriptions;
  }
  final eligibility = Purchase.cachedIntroductoryOfferEligibility(
    subscriptions.map(_storeProductId),
  );
  if (eligibility.isEmpty) {
    return subscriptions;
  }
  return _applyAppleIntroductoryEligibility(subscriptions, eligibility);
}

List<dynamic> _applyAppleIntroductoryEligibility(
  List<dynamic> subscriptions,
  Map<String, bool> eligibility,
) {
  return subscriptions.map((item) {
    if (item is! Map) {
      return item;
    }
    final productId = _storeProductId(item);
    if (!eligibility.containsKey(productId)) {
      return item;
    }
    return <String, dynamic>{
      ...Map<String, dynamic>.from(item),
      '_apple_intro_eligible': eligibility[productId],
    };
  }).toList();
}

List<dynamic> _purchaseRows(dynamic payload) {
  final fromGroupedPayload = payload is Map;
  final rows = fromGroupedPayload ? payload['purchase'] : payload;
  final list = rows is List ? rows : <dynamic>[];
  if (fromGroupedPayload) {
    return list.whereType<Map>().where((item) {
      return _storeProductId(item).isNotEmpty;
    }).toList();
  }
  return list.whereType<Map>().where((item) {
    if (!fromGroupedPayload && _productType(item) != 2) {
      return false;
    }
    final coin = double.tryParse(_coinAmount(item)) ?? 0;
    return coin > 0 || _productType(item) == 2;
  }).toList();
}

List<dynamic> _membershipRows(dynamic payload) {
  dynamic current = payload;
  for (var depth = 0; depth < 3; depth += 1) {
    if (current is List) {
      return current.whereType<Map>().toList();
    }
    if (current is! Map) {
      return const [];
    }
    current =
        current['data'] ??
        current['list'] ??
        current['items'] ??
        current['videos'];
  }
  return current is List ? current.whereType<Map>().toList() : const [];
}

int _membershipExpire(Map<String, dynamic> payload) {
  final raw = int.tryParse(
    _text(
      payload['vip_expire_at'] ??
          payload['expire_at'] ??
          payload['expire_time'] ??
          payload['expire'],
    ),
  );
  if (raw == null || raw <= 0) {
    return 0;
  }
  return raw > 100000000000 ? raw ~/ 1000 : raw;
}

bool _membershipIsActive(Map<String, dynamic> payload) {
  final value = payload['is_vip'] ?? payload['isVip'] ?? payload['vip'];
  return value == true ||
      value == 1 ||
      _text(value) == '1' ||
      _membershipExpire(payload) > 0;
}

String? _defaultSelectedId(List<dynamic> subscriptions) {
  for (final item in subscriptions) {
    if (_planId(item) == 'weekly') {
      return _productId(item);
    }
  }
  return subscriptions.isEmpty ? null : _productId(subscriptions.first);
}

String _planId(dynamic item) {
  if (item is! Map) {
    return '';
  }
  return _text(item['product_id']).toLowerCase();
}

String _productTitle(dynamic item) {
  if (item is! Map) {
    return '';
  }
  return _text(
    item['display_name'] ??
        item['displayName'] ??
        item['title'] ??
        item['name'] ??
        item['base_plan_id'] ??
        item['basePlanId'],
  );
}

String _productId(dynamic item) {
  if (item is! Map) {
    return '';
  }
  return _text(item['id']);
}

String _coinAmount(dynamic item) {
  if (item is! Map) {
    return '';
  }
  return _text(item['coin'] ?? item['coins'] ?? item['amount']);
}

double _bonusValue(dynamic item) {
  if (item is! Map) {
    return 0;
  }
  return double.tryParse(_text(item['bonus'] ?? item['bouns'])) ?? 0;
}

int _bonusCoins(dynamic item) {
  final coin = double.tryParse(_coinAmount(item)) ?? 0;
  final bonus = _bonusValue(item);
  if (coin <= 0 || bonus <= 0) {
    return 0;
  }
  return (coin * bonus).round();
}

int _productType(dynamic item) {
  if (item is! Map) {
    return 0;
  }
  return int.tryParse(_text(item['type'] ?? item['product_type'])) ?? 0;
}

String _storeProductId(dynamic item) {
  if (item is! Map) {
    return '';
  }
  return _text(
    item['product_id'] ??
        item['apple_product_id'] ??
        item['ios_product_id'] ??
        item['name'] ??
        item['google_product_id'] ??
        item['googleProductId'],
  );
}

String _moneyParam(String value) {
  if (value.isEmpty || value.startsWith(r'$')) {
    return value;
  }
  return '\$$value';
}

String _moneyValue(String value) {
  if (value.startsWith(r'$')) {
    return value.substring(1);
  }
  return value;
}

double _moneyNumber(String value) {
  return double.tryParse(value.replaceAll(RegExp(r'[^0-9.]'), '')) ?? 0;
}

int _discountPercent(String price, String renewalPrice) {
  final p = _moneyNumber(price);
  final r = _moneyNumber(renewalPrice);
  if (p <= 0 || r <= 0 || p >= r) {
    return 0;
  }
  return (100 - (p / r * 100).floor()).clamp(0, 99).toInt();
}

String _cleanNumber(dynamic value) {
  final number = double.tryParse(_text(value));
  if (number == null) {
    return _text(value);
  }
  if (number == number.roundToDouble()) {
    return number.toInt().toString();
  }
  return number.toString();
}

String _expireText(int seconds) {
  if (seconds <= 0) {
    return '';
  }
  final date = DateTime.fromMillisecondsSinceEpoch(seconds * 1000);
  final month = date.month.toString().padLeft(2, '0');
  final day = date.day.toString().padLeft(2, '0');
  return '${date.year}-$month-$day';
}

String _posterUrl(dynamic item) {
  final image = movieCoverPath(item);
  return image.isEmpty ? '' : Global.static(image);
}

String _titleText(dynamic item) {
  if (item is! Map) {
    return t.untitled;
  }
  final title = _text(item['title']);
  return title.isEmpty ? t.untitled : title;
}

void _openPlay(BuildContext context, dynamic item) {
  if (item is! Map) {
    return;
  }
  final id = item['id'] ?? item['movie_id'];
  if (id != null) {
    context.push('/play', extra: {'id': id});
  }
}

String _text(dynamic value) {
  if (value == null) {
    return '';
  }
  return value.toString().trim();
}

Widget? _paymentDiagnosticsButton(BuildContext context) {
  if (!PaymentDiagnostics.enabled) {
    return null;
  }
  return SizedBox(
    width: 40,
    height: 40,
    child: IconButton(
      tooltip: 'Payment logs',
      padding: EdgeInsets.zero,
      onPressed: () {
        unawaited(
          showPaymentDiagnosticsDialog(
            context,
            title: 'Payment diagnostics',
            summary: 'Manual log view',
          ),
        );
      },
      icon: const Icon(LucideIcons.bug, size: 20, color: Colors.white),
    ),
  );
}

Future<void> _showPurchaseDiagnostics(
  BuildContext context, {
  required bool success,
}) async {
  if (!PaymentDiagnostics.enabled ||
      !context.mounted ||
      (!success && PaymentDiagnostics.lastFailureCanceled)) {
    return;
  }
  final failure = PaymentDiagnostics.lastFailure;
  await showPaymentDiagnosticsDialog(
    context,
    title: success ? 'Purchase completed' : 'Purchase stopped',
    summary: success
        ? 'Backend verification and Apple transaction completion succeeded.'
        : (failure.isEmpty ? 'The purchase did not complete.' : failure),
  );
}

String _rechargeTips() {
  return t.recharge_tips.join('\n\n');
}
