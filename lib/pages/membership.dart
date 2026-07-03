import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:tiktok_events_sdk/tiktok_events_sdk.dart';
import 'package:yogotv/api.dart';
import 'package:yogotv/app_config.dart';
import 'package:yogotv/components/lazy_image.dart';
import 'package:yogotv/components/loading.dart';
import 'package:yogotv/global.dart';
import 'package:yogotv/i18n/strings.g.dart';
import 'package:yogotv/purchase.dart';
import 'package:yogotv/states/user.dart';

class Membership extends StatefulWidget {
  const Membership({super.key});

  @override
  State<Membership> createState() => _MembershipState();
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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (!kIsWeb && Platform.isIOS) {
      Purchase.canProcess = true;
    }
    Global.blockAd();
    _userStateListener = context.read<UserState>().stream.listen((_) {
      if (mounted) {
        setState(() {});
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

  Future<void> _loadData() async {
    setState(() => _loading = true);

    final vipFuture = api<Map<String, dynamic>>(
      'user/membership',
      method: Method.post,
      loading: false,
    );
    final videosFuture = api<List<dynamic>>(
      'feed/membership',
      method: Method.post,
      loading: false,
    );
    final productsFuture = _loadProducts();

    final vip = await vipFuture;
    final videos = await videosFuture;
    final products = await productsFuture;

    if (!mounted) {
      return;
    }

    final vipPayload = vip.d ?? {};
    final expire = int.tryParse('${vipPayload['vip_expire_at'] ?? 0}') ?? 0;
    final isVip = expire > 0 || context.read<UserState>().isVip;
    final subscriptions = products;

    setState(() {
      _isVip = isVip;
      _vipExpire = _expireText(expire);
      _vipVideos = videos.d ?? [];
      _subscriptions = subscriptions;
      _selectedId = _selectedId ?? _defaultSelectedId(subscriptions);
      _loading = false;
    });
  }

  Future<List<dynamic>> _loadProducts() async {
    final nativeProducts = await api<Map<String, dynamic>>(
      'ggPay/products',
      method: Method.post,
      data: {'type': 10},
      loading: false,
    );
    final nativeRows = _subscriptionRows(nativeProducts.d);
    if (nativeRows.isNotEmpty) {
      return nativeRows;
    }

    final legacyProducts = await api<List<dynamic>>('product', loading: false);
    return _subscriptionRows(legacyProducts.d);
  }

  Future<void> _handleRestore() async {
    setState(() => _loading = true);
    if (!kIsWeb && Platform.isIOS) {
      await Purchase.restore();
    }
    await _refreshUser();
    await _loadData();
  }

  Future<void> _handleSubscribe() async {
    final product = _subscriptions.firstWhere(
      (item) => _productId(item) == _selectedId,
      orElse: () => null,
    );
    if (product == null) {
      Global.warning(t.please_select_a_vip_plan);
      return;
    }

    final price = double.tryParse(_text(product['price'])) ?? 0;
    if (!kIsWeb && Platform.isIOS) {
      await TikTokEventsSdk.logEvent(
        event: TikTokEvent(
          eventName: 'checkout',
          properties: EventProperties(
            description: _storeProductId(product),
            value: price,
            currency: CurrencyCode.USD,
          ),
        ),
      );
      final result = await Purchase.making(product: _storeProductId(product));
      if (result) {
        await TikTokEventsSdk.logEvent(
          event: TikTokEvent(
            eventName: 'subscribe',
            properties: EventProperties(
              description: _storeProductId(product),
              value: price,
              currency: CurrencyCode.USD,
            ),
          ),
        );
        await _refreshUser();
        await _loadData();
      }
      return;
    }

    final result = await api<dynamic>(
      'ggPay/create',
      method: Method.post,
      data: {'product_id': _productId(product), 'isOfferAvailable': false},
      loading: true,
    );
    if (result.c == 0) {
      Global.success(t.success);
      _restore = true;
    }
  }

  Future<void> _refreshUser() async {
    final user = await api<Map<String, dynamic>>(
      'user',
      method: Method.get,
      loading: false,
    );
    final data = user.d;
    if (!mounted || data == null) {
      return;
    }
    context.read<UserState>().set(
      UserStateValue(
        name: data['name'] ?? 'No Name',
        uniqueId: data['unique_id'],
        password: data['password'],
        vip: data['vip'],
        admin: data['admin'],
        anonymous: data['anonymous'],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = context.read<UserState>();

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: Text(''),
        actions: [
          if (!kIsWeb && Platform.isIOS)
            TextButton(
              onPressed: _handleRestore,
              child: Text(
                t.restore,
                style: TextStyle(color: Colors.white, fontSize: 14),
              ),
            ),
        ],
      ),
      body: _loading
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
                                selected: _productId(item) == _selectedId,
                                onTap: () {
                                  setState(() {
                                    _selectedId = _productId(item);
                                  });
                                },
                              ),
                            ),
                          ),
                        ],
                        SizedBox(height: 14),
                        _VipBenefitsPanel(),
                        if (_vipVideos.isNotEmpty) ...[
                          SizedBox(height: 14),
                          _SectionTitle(t.vip_exclusives),
                          SizedBox(height: 14),
                          _VipExclusiveGrid(items: _vipVideos),
                        ],
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
                          padding: EdgeInsets.fromLTRB(15, 12, 15, 0),
                          child: _SubscribeButton(onTap: _handleSubscribe),
                        ),
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
                      ],
                    ),
                  ),
              ],
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
                        fontWeight: FontWeight.w700,
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
          fontWeight: FontWeight.w700,
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
    final basePlan = _planId(item);
    final title = basePlan == 'yearly' ? t.yearly_vip : t.weekly_vip;
    final firstPrice = _text(
      item['first_price'] ?? item['firstPrice'] ?? item['price'],
    );
    final price = _text(item['price']);
    final hasOffer = basePlan == 'weekly' && firstPrice.isNotEmpty;
    final displayPrice = hasOffer ? firstPrice : price;
    final description = basePlan == 'weekly'
        ? (hasOffer
              ? t.first_week_string_then_string_week(
                  firstPrice: _moneyParam(firstPrice),
                  price: _moneyParam(price),
                )
              : t.auto_renewal_cancel_anytime)
        : t.auto_renewal_cancel_anytime;

    final bgGradient = selected
        ? [Color(0xffffecd4), Color(0xfff3cb93)]
        : [Color(0xff3c3427), Color(0xff201816)];
    final textColor = selected ? Color(0xff633e25) : Colors.white;
    final subColor = selected
        ? Color(0xff633e25).withAlpha(190)
        : Colors.white.withAlpha(190);
    final benefitColor = selected ? Color(0xff633e25) : Color(0xfff1da97);

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
                                  fontWeight: FontWeight.w800,
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
                              fontWeight: FontWeight.w800,
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
                          icon: LucideIcons.play,
                          text: t.unlimited_viewing,
                          color: benefitColor,
                        ),
                        _PlanBenefit(
                          icon: LucideIcons.sparkles,
                          text: t.hd_quality,
                          color: benefitColor,
                        ),
                        _PlanBenefit(
                          icon: LucideIcons.badgeX,
                          text: t.ad_free,
                          color: benefitColor,
                        ),
                        _PlanBenefit(
                          icon: LucideIcons.gem,
                          text: t.more_benefits,
                          color: benefitColor,
                        ),
                      ],
                    ),
                  ),
                ],
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
    required this.icon,
    required this.text,
    required this.color,
  });

  final IconData icon;
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: (MediaQuery.of(context).size.width - 30 - 30 - 8) / 2,
      child: Row(
        children: [
          Icon(icon, size: 16, color: color),
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
                  fontWeight: FontWeight.w800,
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
            style: TextStyle(color: Color(0xff633e25), fontSize: 10),
          ),
        ],
      ),
    );
  }
}

class _VipExclusiveGrid extends StatelessWidget {
  const _VipExclusiveGrid({required this.items});

  final List<dynamic> items;

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      shrinkWrap: true,
      physics: NeverScrollableScrollPhysics(),
      itemCount: items.length,
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 10,
        mainAxisSpacing: 12,
        childAspectRatio: 0.58,
      ),
      itemBuilder: (context, index) {
        final item = items[index];
        final image = _posterUrl(item);
        final ratio = MediaQuery.of(context).devicePixelRatio.clamp(1.0, 3.0);
        return InkWell(
          onTap: () => _openPlay(context, item),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: image.isEmpty
                      ? Container(color: Color(0xff212121))
                      : LazyImage(
                          url: image,
                          width: double.infinity,
                          height: double.infinity,
                          fit: BoxFit.cover,
                          cacheWidth: (120 * ratio).round(),
                          cacheHeight: (160 * ratio).round(),
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
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        );
      },
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

class _SubscribeButton extends StatelessWidget {
  const _SubscribeButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Ink(
          height: 44,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xffffecd4), Color(0xfff3cb93)],
            ),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Center(
            child: Text(
              t.subscribe,
              style: TextStyle(
                color: Color(0xff633e25),
                fontSize: 17,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

String _userName(UserState user) {
  if (user.state == null || user.state!.anonymous == 1) {
    return t.guest;
  }
  return user.state!.name;
}

List<dynamic> _subscriptionRows(dynamic payload) {
  final rows = payload is Map ? payload['subscription'] : payload;
  final list = rows is List ? rows : <dynamic>[];
  return list.where((item) {
    if (item is! Map) {
      return false;
    }
    final plan = _planId(item);
    return plan == 'weekly' || plan == 'yearly';
  }).toList();
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
  return _text(item['base_plan_id'] ?? item['basePlanId'] ?? item['name']);
}

String _productId(dynamic item) {
  if (item is! Map) {
    return '';
  }
  return _text(item['id']);
}

String _storeProductId(dynamic item) {
  if (item is! Map) {
    return '';
  }
  return _text(
    item['apple_product_id'] ??
        item['ios_product_id'] ??
        item['product_id'] ??
        item['google_product_id'] ??
        item['googleProductId'] ??
        item['name'],
  );
}

String _moneyParam(String value) {
  if (value.isEmpty || value.startsWith(r'$')) {
    return value;
  }
  return '\$$value';
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
  if (item is! Map) {
    return '';
  }
  final image = _text(item['image']);
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

String _rechargeTips() {
  final appName = AppConfig.current.brandDisplayName;
  if (LocaleSettings.currentLocale == AppLocale.zhHant) {
    return [
      '儲值說明',
      '1. $appName 提供免費與付費內容',
      '2. 付費內容可使用金幣與獎勵金幣解鎖，或購買會員後觀看',
      '3. 訂閱期間內，你可以不受限制地觀看 App 內所有內容',
      '4. 訂閱成功完成後，訂閱福利將依你的訂單狀態於 24 小時內生效。',
      '5. 目前訂閱期間結束前 24 小時內，系統會依所選方案價格從你的帳戶扣除續訂費用。續訂付款成功處理後，你的訂閱期間將自動延長。',
      '6. 如需取消續訂，請至少在目前訂閱期間結束前 24 小時前往 App Store 取消訂閱。',
      '7. 如果你已成功儲值且款項已扣除，但餘額未變更，請點擊「還原」嘗試重新整理。',
      '8. 如有其他問題，請透過意見回饋聯絡我們。繼續即表示你同意我們的會員協議、付款協議與隱私權政策',
    ].join('\n\n');
  }
  return [
    'Recharge Instructions',
    '1. $appName offers both free and paid content',
    '2. Paid content can be unlocked using coins and reward coins, or by purchasing a membership to watch',
    '3. During the subscription period, you can watch all content in the app without restrictions',
    '4. Subscription benefits will take effect within 24 hours after the subscription is successfully completed, depending on the status of your order.',
    '5. Within 24 hours before the current subscription period ends, the system will deduct the renewal fee from your account based on the price of the selected plan. After the renewal payment is successfully processed, your subscription period will be automatically extended.',
    '6. If you need to cancel the renewal, please go to App Store to cancel the subscription at least 24 hours before the current subscription period ends.',
    '7. If you have successfully recharged and the payment has been deducted, but the balance has not changed, please click "Restore" to try refreshing.',
    '8. For other issues, please contact us through feedback. Continuing means you agree to our Membership Agreement, Payment Agreement and Privacy Policy',
  ].join('\n\n');
}
