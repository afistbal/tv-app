import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:yogotv/api.dart';
import 'package:yogotv/app_config.dart';
import 'package:yogotv/global.dart';
import 'package:yogotv/i18n/strings.g.dart';
import 'package:yogotv/states/main.dart';
import 'package:yogotv/states/user.dart';

class Profile extends StatefulWidget {
  const Profile({super.key});

  @override
  State<Profile> createState() => _Profile();
}

class _Profile extends State<Profile> {
  late final StreamSubscription<UserStateValue?> _userListener;

  bool _loading = false;
  bool _isVip = false;
  String _vipExpire = '';
  String _coins = '0';

  @override
  void initState() {
    super.initState();
    _userListener = context.read<UserState>().stream.listen((_) {
      if (mounted) {
        _loadData(silent: true);
      }
    });
    _loadData();
  }

  @override
  void dispose() {
    _userListener.cancel();
    super.dispose();
  }

  Future<void> _loadData({bool silent = false}) async {
    if (!silent && mounted) {
      setState(() => _loading = true);
    }

    final userFuture = _loadUserInfo();
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

    await userFuture;
    final balance = await balanceFuture;
    final vip = await vipFuture;

    if (!mounted) {
      return;
    }

    final vipPayload = vip.d ?? {};
    final expire = int.tryParse('${vipPayload['vip_expire_at'] ?? 0}') ?? 0;
    final userState = context.read<UserState>();
    final isVip = expire > 0 || userState.isVip;
    if (isVip && !userState.isVip) {
      userState.setVip(1);
    }

    setState(() {
      _coins = _cleanNumber(balance.d);
      _isVip = isVip;
      _vipExpire = _expireText(expire);
      _loading = false;
    });
  }

  Future<void> _loadUserInfo() async {
    final token = Global.sp.getString('token') ?? '';
    if (token.isEmpty) {
      return;
    }

    final deviceUuid = Global.sp.getString('device_uuid') ?? '';
    final result = await api<Map<String, dynamic>>(
      'login/token',
      method: Method.post,
      data: {
        'token': token,
        if (deviceUuid.isNotEmpty) 'device_uuid': deviceUuid,
      },
      loading: false,
    );
    final payload = result.d;
    final nestedInfo = payload?['info'];
    final info = nestedInfo is Map ? nestedInfo : payload;
    if (!mounted || result.c != 0 || info == null) {
      return;
    }

    final value = UserStateValue(
      name: _text(info['name']).isEmpty ? 'No Name' : _text(info['name']),
      uniqueId: _text(info['uid'] ?? info['unique_id'] ?? info['id']),
      password: _text(info['password']),
      vip: _intValue(info['vip']),
      admin: _intValue(info['admin']),
      anonymous: _intValue(info['anonymous']),
    );
    final current = context.read<UserState>().state;
    if (current == null ||
        current.name != value.name ||
        current.uniqueId != value.uniqueId ||
        current.password != value.password ||
        current.vip != value.vip ||
        current.admin != value.admin ||
        current.anonymous != value.anonymous) {
      context.read<UserState>().set(value);
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<UserState, UserStateValue?>(
      builder: (context, user) {
        return RefreshIndicator(
          onRefresh: _loadData,
          color: Colors.white,
          backgroundColor: Color(0xff222222),
          child: CustomScrollView(
            physics: AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: 15),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SafeArea(
                        bottom: false,
                        child: SizedBox(
                          height: 34,
                          child: Align(
                            alignment: Alignment.centerRight,
                            child: _SettingsButton(
                              onTap: () => context.push('/about'),
                            ),
                          ),
                        ),
                      ),
                      SizedBox(height: 18),
                      _UserHeader(user: user),
                      SizedBox(height: 20),
                      _isVip
                          ? _VipUnlockedCard(expireText: _vipExpire)
                          : _VipLockedCard(
                              onSubscribe: () => _openMembership(context),
                            ),
                      SizedBox(height: _isVip ? 16 : 16),
                      _AccountCard(
                        coins: _coins,
                        loading: _loading,
                        onDetails: () => context.push('/earn/detail'),
                        onTopUp: () => _openMembership(context),
                      ),
                      SizedBox(height: 12),
                      _MineMenuItem(
                        icon: LucideIcons.history,
                        label: t.history,
                        onTap: () {
                          context.read<MainState>().setIndex(2);
                        },
                      ),
                      _MineMenuItem(
                        icon: LucideIcons.languages,
                        label: t.language,
                        onTap: () => context.push('/language'),
                      ),
                      _MineMenuItem(
                        icon: LucideIcons.circleQuestionMark,
                        label: t.feedback_help,
                        onTap: () => context.push('/help'),
                      ),
                      if (context.read<UserState>().isAdmin)
                        _MineMenuItem(
                          icon: LucideIcons.userCog,
                          label: t.admin,
                          onTap: () => context.push('/admin'),
                        ),
                      SizedBox(height: 10),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _SettingsButton extends StatelessWidget {
  const _SettingsButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: SizedBox(
        width: 36,
        height: 36,
        child: Icon(LucideIcons.settings, color: Colors.white, size: 24),
      ),
    );
  }
}

class _UserHeader extends StatelessWidget {
  const _UserHeader({required this.user});

  final UserStateValue? user;

  @override
  Widget build(BuildContext context) {
    final isAnonymous = user == null || user!.anonymous == 1;
    final name = isAnonymous ? t.log_in : user!.name;
    final uid = user?.uniqueId ?? Global.sp.getString('uid') ?? '';

    return InkWell(
      onTap: isAnonymous ? () => context.push('/login') : null,
      borderRadius: BorderRadius.circular(8),
      child: Row(
        children: [
          ClipOval(
            child: Image.asset(
              'assets/images/android/ic_avatar_guest.png',
              width: 48,
              height: 48,
              fit: BoxFit.cover,
            ),
          ),
          SizedBox(width: 15),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          height: 1.2,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    if (isAnonymous) ...[
                      SizedBox(width: 4),
                      Icon(
                        LucideIcons.chevronRight,
                        color: Colors.white,
                        size: 16,
                      ),
                    ],
                  ],
                ),
                SizedBox(height: 5),
                Text(
                  uid.isEmpty
                      ? _formatNative(t.uid_s, '--')
                      : _formatNative(t.uid_s, uid),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Color(0xff999999),
                    fontSize: 14,
                    height: 1.2,
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

class _VipLockedCard extends StatelessWidget {
  const _VipLockedCard({required this.onSubscribe});

  final VoidCallback onSubscribe;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onSubscribe,
      child: Container(
        padding: EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xffffecd4), Color(0xfff3cb93)],
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
          ),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            Text(
              t.upgrade_vip_unlock_all_benefits,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Color(0xff633e25),
                fontSize: 16,
                height: 1.2,
                fontWeight: FontWeight.w800,
              ),
            ),
            SizedBox(height: 14),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _VipBenefit(
                  image: 'assets/images/android/ic_vip_short.png',
                  label: t.unlimited_viewing,
                ),
                _VipBenefit(
                  image: 'assets/images/android/ic_vip_hd.png',
                  label: t.hd_quality,
                ),
                _VipBenefit(
                  image: 'assets/images/android/ic_vip_benefit.png',
                  label: t.more_benefits,
                ),
              ],
            ),
            SizedBox(height: 14),
            Container(
              height: 40,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xffc17846), Color(0xff603c24)],
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                ),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                t.subscribe,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 17,
                  height: 1,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _VipBenefit extends StatelessWidget {
  const _VipBenefit({required this.image, required this.label});

  final String image;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Image.asset(image, width: 40, height: 40, fit: BoxFit.contain),
          SizedBox(height: 6),
          Text(
            label,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: Color(0xff633e25),
              fontSize: 10,
              height: 1.1,
            ),
          ),
        ],
      ),
    );
  }
}

class _VipUnlockedCard extends StatelessWidget {
  const _VipUnlockedCard({required this.expireText});

  final String expireText;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => context.push('/membership'),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        height: 88,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xffffecd4), Color(0xfff3cb93)],
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
          ),
          borderRadius: BorderRadius.circular(12),
        ),
        clipBehavior: Clip.hardEdge,
        child: Stack(
          children: [
            Positioned.fill(
              right: 0,
              child: Align(
                alignment: Alignment.centerRight,
                child: Image.asset(
                  'assets/images/android/bg_vip_mine.png',
                  height: 88,
                  fit: BoxFit.fitHeight,
                ),
              ),
            ),
            Padding(
              padding: EdgeInsets.only(left: 16, right: 16),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              LucideIcons.crown,
                              color: Color(0xff633e25),
                              size: 20,
                            ),
                            SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                _formatNative(
                                  t.app_name_vip,
                                  AppConfig.current.brandDisplayName,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: Color(0xff321c0d),
                                  fontSize: 16,
                                  height: 1.2,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                          ],
                        ),
                        SizedBox(height: 6),
                        Text(
                          expireText.isEmpty
                              ? ''
                              : _formatNative(t.valid_until_s, expireText),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Color(0xff96542a),
                            fontSize: 14,
                            height: 1.1,
                          ),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(width: 10),
                  Container(
                    padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: Color(0xffe6bd8b),
                      borderRadius: BorderRadius.circular(22),
                    ),
                    child: Text(
                      t.subscribed,
                      style: TextStyle(
                        color: Color(0xd9633e25),
                        fontSize: 14,
                        height: 1,
                        fontWeight: FontWeight.w600,
                      ),
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

class _AccountCard extends StatelessWidget {
  const _AccountCard({
    required this.coins,
    required this.loading,
    required this.onDetails,
    required this.onTopUp,
  });

  final String coins;
  final bool loading;
  final VoidCallback onDetails;
  final VoidCallback onTopUp;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: Color(0xff151515),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          SizedBox(
            height: 48,
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    t.my_account,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      height: 1.2,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                InkWell(
                  onTap: onDetails,
                  borderRadius: BorderRadius.circular(12),
                  child: Row(
                    children: [
                      Text(
                        t.details,
                        style: TextStyle(
                          color: Color(0xff999999),
                          fontSize: 14,
                        ),
                      ),
                      Icon(
                        LucideIcons.chevronRight,
                        color: Color(0xff999999),
                        size: 14,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: Colors.white.withAlpha(26)),
          SizedBox(
            height: 68,
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        t.coins,
                        style: TextStyle(
                          color: Color(0xff999999),
                          fontSize: 12,
                          height: 1.2,
                        ),
                      ),
                      SizedBox(height: 8),
                      Row(
                        children: [
                          Image.asset(
                            'assets/images/android/ic_coin.png',
                            width: 16,
                            height: 16,
                          ),
                          SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              loading ? '0' : coins,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                height: 1,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                InkWell(
                  onTap: onTopUp,
                  borderRadius: BorderRadius.circular(22),
                  child: Container(
                    padding: EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                    decoration: BoxDecoration(
                      color: Color(0xffff3d5d),
                      borderRadius: BorderRadius.circular(22),
                    ),
                    child: Text(
                      t.top_up,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        height: 1,
                        fontWeight: FontWeight.w600,
                      ),
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

class _MineMenuItem extends StatelessWidget {
  const _MineMenuItem({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: SizedBox(
        height: 56,
        child: Row(
          children: [
            Icon(icon, color: Colors.white, size: 24),
            SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: TextStyle(color: Colors.white, fontSize: 14),
              ),
            ),
            Icon(LucideIcons.chevronRight, color: Color(0xff999999), size: 14),
          ],
        ),
      ),
    );
  }
}

String _cleanNumber(dynamic value) {
  if (value == null) {
    return '0';
  }
  final number = num.tryParse('$value');
  if (number == null) {
    return '$value';
  }
  if (number % 1 == 0) {
    return number.toInt().toString();
  }
  return number.toStringAsFixed(2).replaceFirst(RegExp(r'\.?0+$'), '');
}

void _openMembership(BuildContext context) {
  context.push('/membership');
}

int _intValue(dynamic value) {
  if (value is int) {
    return value;
  }
  if (value is bool) {
    return value ? 1 : 0;
  }
  return int.tryParse('${value ?? 0}') ?? 0;
}

String _text(dynamic value) {
  return value?.toString().trim() ?? '';
}

String _expireText(int seconds) {
  if (seconds <= 0) {
    return '';
  }
  final date = DateTime.fromMillisecondsSinceEpoch(seconds * 1000);
  return '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';
}

String _formatNative(String template, String value) {
  return template.replaceAll('%s', value);
}
