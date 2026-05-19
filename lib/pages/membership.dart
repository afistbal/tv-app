import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:url_launcher/url_launcher_string.dart';
import 'package:yogotv/api.dart';
import 'package:yogotv/components/loading.dart';
import 'package:yogotv/global.dart';
import 'package:yogotv/i18n/strings.g.dart';
import 'package:yogotv/purchase.dart';
import 'package:yogotv/states/user.dart';
import 'package:tiktok_events_sdk/tiktok_events_sdk.dart';

class Membership extends StatefulWidget {
  const Membership({super.key});

  @override
  State<StatefulWidget> createState() {
    return _Membership();
  }
}

class _Membership extends State<Membership> with WidgetsBindingObserver {
  late final StreamSubscription<UserStateValue?> _userStateListener;
  int _selected = 0;
  List<dynamic> _product = [];
  String _amount = '';
  String _billingAt = '';
  int _status = 1;
  bool _loading = true;
  bool _restore = false;

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addObserver(this);

    if (Platform.isIOS) {
      Purchase.canProcess = true;
    }

    Global.blockAd();
    _userStateListener = context.read<UserState>().stream.listen((state) {
      setState(() {});
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

  _loadData() async {
    if (context.read<UserState>().isVip) {
      api('user/membership').then((res) {
        setState(() {
          _amount = res.d['amount'];
          _billingAt = res.d['renewal_at'];
          _status = res.d['status'];
          _loading = false;
        });
      });
    } else {
      api('product').then((res) {
        setState(() {
          _product = res.d.map((e) {
            switch (e['name']) {
              case 'weekly':
                e['name2'] = t['${e['name']}_vip'];
                e['type'] = t.week;
                break;
              case 'monthly':
                e['name2'] = t['${e['name']}_vip'];
                e['type'] = t.month;
                break;
              case 'yearly':
                e['name2'] = t['${e['name']}_vip'];
                e['type'] = t.year;
                break;
              case 'daily':
                e['name2'] = t['${e['name']}_vip'];
                e['type'] = t.day;
                break;
            }
            return e;
          }).toList();
          _selected = _product[0]['id'];
          _loading = false;
        });
      });
    }
  }

  _handleRestore() async {
    setState(() {
      _loading = true;
    });
    if (Platform.isIOS) {
      await Purchase.restore();
    }
    final user = await api('user');
    if (mounted) {
      context.read<UserState>().set(
        UserStateValue(
          name: user.d['name'] ?? 'No Name',
          uniqueId: user.d['unique_id'],
          password: user.d['password'],
          vip: user.d['vip'],
          admin: user.d['admin'],
          anonymous: user.d['anonymous'],
        ),
      );
      _loadData();
    }
  }

  _handleSubmit() async {
    if (Platform.isIOS) {
      final product = _product.firstWhere((e) => e['id'] == _selected);
      await TikTokEventsSdk.logEvent(
        event: TikTokEvent(
          eventName: 'checkout',
          properties: EventProperties(
            description: product['name'],
            value: double.parse(product['price']),
            currency: CurrencyCode.USD,
          ),
        ),
      );
      final result = await Purchase.making(product: product['name']);
      if (result) {
        TikTokEventsSdk.logEvent(
          event: TikTokEvent(
            eventName: 'subscribe',
            properties: EventProperties(
              description: product['name'],
              value: double.parse(product['price']),
              currency: CurrencyCode.USD,
            ),
          ),
        );
      }
    } else {
      final cancel = Global.loading();
      final url = kDebugMode
          ? 'http://192.168.1.30:5173'
          : 'https://app.yogotv.com';
      final result = await api(
        'pay/create',
        method: Method.post,
        loading: false,
        data: {'payment': 1, 'product_id': _selected},
      );

      if (result.c != 0) {
        cancel();
        Global.error(t.failed);
        return;
      }
      await launchUrlString(
        '$url/airwallex.html?env=${kDebugMode ? 'demo' : 'prod'}&pi=${result.d['pi']}&customer_id=${result.d['customer_id']}&client_secret=${result.d['client_secret']}&currency=${result.d['currency']}&success_url=${Uri.encodeComponent('$url/airwallex.html?action=success&message=${t.success}')}&fail_url=${Uri.encodeComponent('$url/airwallex.html?action=failed&message=${t.failed}')}',
      );
      _restore = true;
      cancel();
    }
  }

  _handleCancel() async {
    if (Platform.isAndroid) {
      final result = await context.push<bool>(
        '/alert',
        extra: {'title': t.unsubscribe, 'content': t.alert_unsubscribe},
      );
      if (result == true) {
        api<bool>(
          'subscription/cancel',
          method: Method.post,
          loading: true,
        ).then((res) {
          if (res.d == true) {
            setState(() {
              _loading = true;
              _loadData();
            });
          }
        });
      }
    } else {
      context.push(
        '/alert',
        extra: {'title': t.unsubscribe, 'content': t.alert_unsubscribe2},
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(t.membership),
        actionsPadding: EdgeInsets.only(right: 8),
        actions: [
          if (Platform.isIOS)
            IconButton(
              onPressed: _handleRestore,
              padding: EdgeInsets.symmetric(horizontal: 16),
              icon: Text(t.restore, style: TextStyle(fontSize: 16)),
            ),
        ],
      ),
      body: _loading
          ? Loading()
          : context.read<UserState>().isVip
          ? Padding(
              padding: EdgeInsets.all(16),
              child: Column(
                spacing: 16,
                children: [
                  SizedBox(height: 48),
                  Icon(LucideIcons.gem, color: Colors.amber, size: 64),
                  Text(
                    t.member_description,
                    style: TextStyle(fontSize: 18, color: Colors.amber),
                  ),
                  SizedBox(height: 32),
                  Ink(
                    decoration: BoxDecoration(
                      color: Colors.white10,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Wrap(
                      children: [
                        ListTile(
                          title: Text(t.renewal_amount),
                          trailing: Text(
                            '\$$_amount',
                            style: TextStyle(fontSize: 16),
                          ),
                        ),
                        Divider(height: 1),
                        ListTile(
                          title: Text(t.renewal_time),
                          trailing: Text(
                            DateFormat.yMMMEd().format(
                              DateTime.parse(_billingAt),
                            ),
                            style: TextStyle(fontSize: 16),
                          ),
                        ),
                        Divider(height: 1),
                        ListTile(
                          title: Text(t.renewal_status),
                          trailing: Text(
                            _status == 1 ? t.enable : t.cancelled,
                            style: TextStyle(fontSize: 16),
                          ),
                        ),
                        ...(_status == 1
                            ? [
                                Divider(height: 1),
                                ListTile(
                                  onTap: _handleCancel,
                                  title: Text(t.unsubscribe),
                                  trailing: Icon(
                                    Icons.arrow_forward_ios,
                                    size: 20,
                                  ),
                                ),
                              ]
                            : []),
                      ],
                    ),
                  ),
                  Text(
                    t.member_support,
                    style: TextStyle(color: Colors.white54),
                  ),
                ],
              ),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      spacing: 16,
                      children: [
                        SizedBox(height: 0),
                        ..._product.map(
                          (e) => Stack(
                            children: [
                              Padding(
                                padding: EdgeInsets.only(left: 16, right: 16),
                                child: InkWell(
                                  onTap: () {
                                    setState(() {
                                      _selected = e['id'];
                                    });
                                  },
                                  child: Ink(
                                    padding: EdgeInsets.symmetric(
                                      vertical: 24,
                                      horizontal: 16,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Color(0x10ffffff),
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(
                                        color: _selected == e['id']
                                            ? Colors.amber.shade400
                                            : Color(0x10ffffff),
                                        width: 2,
                                      ),
                                    ),
                                    child: Row(
                                      spacing: 8,
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      children: [
                                        Expanded(
                                          child: Text(
                                            e['name2'],
                                            style: TextStyle(
                                              fontSize: 28,
                                              height: 1,
                                              color: Colors.amber.shade100,
                                            ),
                                          ),
                                        ),
                                        Column(
                                          spacing: 4,
                                          children: [
                                            Row(
                                              children: [
                                                Text(
                                                  '\$${e['price']}',
                                                  style: TextStyle(
                                                    fontSize: 20,
                                                    height: 1,
                                                  ),
                                                ),
                                                Text(
                                                  ' / ${e['type']}',
                                                  style: TextStyle(
                                                    fontSize: 14,
                                                    height: 1,
                                                  ),
                                                ),
                                              ],
                                            ),
                                            Text(
                                              t.renew_price(
                                                price:
                                                    '\$${e['renewal_price']}',
                                              ),
                                              style: TextStyle(
                                                fontSize: 14,
                                                height: 1,
                                                color: Colors.white54,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                              if (e['price'] != e['renewal_price'])
                                Positioned(
                                  top: 0,
                                  left: 16,
                                  child: Ink(
                                    padding: EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 4,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.red,
                                      borderRadius: BorderRadius.only(
                                        topLeft: Radius.circular(6),
                                        bottomRight: Radius.circular(6),
                                      ),
                                    ),
                                    child: Text(
                                      t.discount,
                                      style: TextStyle(
                                        color: Colors.white,
                                        height: 1,
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                        Padding(
                          padding: EdgeInsets.only(left: 16, right: 16),
                          child: Ink(
                            width: double.infinity,
                            padding: EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: Color(0x05ffffff),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              spacing: 4,
                              children: [
                                Text(
                                  t.join_membership,
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: Colors.amber.withAlpha(200),
                                  ),
                                ),
                                SizedBox(height: 4),
                                Text(t.join_1, style: TextStyle(fontSize: 16)),
                                Text(t.join_2, style: TextStyle(fontSize: 16)),
                                Text(t.join_3, style: TextStyle(fontSize: 16)),
                                Text(
                                  '4.${t.join_cancel}',
                                  style: TextStyle(fontSize: 16),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                SafeArea(
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: Column(
                      spacing: 8,
                      children: [
                        InkWell(
                          onTap: _handleSubmit,
                          child: Ink(
                            height: 54,
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [Colors.amber, Colors.deepOrangeAccent],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Center(
                              child: Text(
                                t.subscribe_now,
                                style: TextStyle(fontSize: 18, height: 1),
                              ),
                            ),
                          ),
                        ),
                        SizedBox(height: 0),
                        Column(
                          spacing: 8,
                          children: [
                            Text(
                              t.payment_agreement,
                              style: TextStyle(color: Colors.white60),
                            ),
                            GestureDetector(
                              onTap: () {
                                launchUrlString(
                                  'https://ddkk.hk/membership-terms.html',
                                );
                              },
                              child: Text(
                                '[ ${t.membership_terms_of_service} ]',
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}
