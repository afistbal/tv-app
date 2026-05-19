import 'dart:math';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_svg/svg.dart';
import 'package:flutter_tabler_icons/flutter_tabler_icons.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:yogotv/api.dart';
import 'package:yogotv/i18n/strings.g.dart';
import 'package:yogotv/states/user.dart';

class Profile extends StatefulWidget {
  const Profile({super.key});

  @override
  State<StatefulWidget> createState() {
    return _Profile();
  }
}

class _Profile extends State<Profile> {
  int _totalEarn = 0;
  int _ownedEarn = 0;
  // int _todayEarn = 0;

  @override
  initState() {
    super.initState();

    _loadData();
  }

  _loadData() async {
    final result = await api('earn/info');
    if (result.c != 0) {
      return;
    }
    setState(() {
      _totalEarn = result.d['total'];
      _ownedEarn = result.d['owned'];
      // _todayEarn = result.d['today'];
    });
  }

  @override
  Widget build(BuildContext context) {
    final userState = context.read<UserState>();
    return Column(
      children: [
        AppBar(title: Text(t.profile), centerTitle: false),
        Expanded(
          child: RefreshIndicator(
            onRefresh: () async {
              await _loadData();
            },
            child: SingleChildScrollView(
              physics: AlwaysScrollableScrollPhysics(),
              child: Material(
                type: MaterialType.transparency,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: EdgeInsets.all(16),
                      child: Ink(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              Colors.deepPurpleAccent.withAlpha(20),
                              Colors.amberAccent.withAlpha(20),
                            ],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            InkWell(
                              onTap: () {
                                context.push('/login');
                              },
                              borderRadius: BorderRadius.only(
                                topLeft: Radius.circular(8),
                                topRight: Radius.circular(8),
                              ),
                              child: Padding(
                                padding: EdgeInsets.all(16),
                                child: Row(
                                  spacing: 16,
                                  children: [
                                    userState.signed &&
                                            FirebaseAuth
                                                    .instance
                                                    .currentUser
                                                    ?.providerData
                                                    .firstOrNull
                                                    ?.photoURL !=
                                                null
                                        ? ClipRRect(
                                            borderRadius: BorderRadius.circular(
                                              32,
                                            ),
                                            child: Image.network(
                                              FirebaseAuth
                                                  .instance
                                                  .currentUser!
                                                  .providerData
                                                  .firstOrNull!
                                                  .photoURL!,
                                              width: 64,
                                              height: 64,
                                            ),
                                          )
                                        : Ink(
                                            width: 64,
                                            height: 64,
                                            decoration: BoxDecoration(
                                              color: Colors.red.withAlpha(50),
                                              borderRadius:
                                                  BorderRadius.circular(32),
                                            ),
                                            child: Icon(
                                              LucideIcons.userRound200,
                                              size: 32,
                                            ),
                                          ),
                                    Expanded(
                                      child: Column(
                                        spacing: 4,
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            userState.signed
                                                ? userState.state!.name
                                                : t.check_login,
                                            style: TextStyle(fontSize: 20),
                                          ),
                                          Text(
                                            userState.signed
                                                ? (userState.isVip
                                                      ? t.vip_1
                                                      : t.vip_0)
                                                : t.anonymous,
                                            style: TextStyle(
                                              fontSize: 14,
                                              color: Colors.white54,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    Icon(Icons.arrow_forward_ios, size: 18),
                                  ],
                                ),
                              ),
                            ),
                            Divider(height: 1),
                            Padding(
                              padding: EdgeInsets.symmetric(
                                vertical: 16,
                                horizontal: 16,
                              ),
                              child: InkWell(
                                onTap: () {
                                  context.push('/earn/detail');
                                },
                                borderRadius: BorderRadius.only(
                                  bottomLeft: Radius.circular(8),
                                  bottomRight: Radius.circular(8),
                                ),
                                child: Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceAround,
                                  spacing: 4,
                                  children: [
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.center,
                                        spacing: 8,
                                        children: [
                                          Text(
                                            _totalEarn.toString(),
                                            style: TextStyle(
                                              fontSize: 24,
                                              height: 1,
                                            ),
                                          ),
                                          Text(
                                            t.earn.total_earn,
                                            textAlign: TextAlign.center,
                                            style: TextStyle(
                                              fontSize: 14,
                                              height: 1,
                                              color: Colors.white54,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.center,
                                        spacing: 8,
                                        children: [
                                          Text(
                                            _ownedEarn.toString(),
                                            style: TextStyle(
                                              fontSize: 24,
                                              height: 1,
                                            ),
                                          ),
                                          Text(
                                            t.earn.owned_earn,
                                            textAlign: TextAlign.center,
                                            style: TextStyle(
                                              fontSize: 14,
                                              height: 1,
                                              color: Colors.white54,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.center,
                                        spacing: 8,
                                        children: [
                                          Icon(
                                            TablerIcons.credit_card,
                                            color: Colors.amberAccent,
                                          ),
                                          Text(
                                            t.withdraw,
                                            textAlign: TextAlign.center,
                                            style: TextStyle(
                                              fontSize: 14,
                                              height: 1,
                                              color: Colors.amberAccent,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    Padding(
                      padding: EdgeInsets.only(left: 16, right: 16, bottom: 16),
                      child: InkWell(
                        onTap: () {
                          context.push('/membership');
                        },
                        borderRadius: BorderRadius.circular(8),
                        child: Ink(
                          height: 110,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                Colors.deepOrangeAccent.withAlpha(30),
                                Colors.indigoAccent.withAlpha(30),
                              ],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Padding(
                            padding: EdgeInsets.all(16),
                            child: Row(
                              children: [
                                Column(
                                  spacing: 16,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Ink(
                                      padding: EdgeInsets.symmetric(
                                        horizontal: 16,
                                        vertical: 8,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.primary,
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Row(
                                        spacing: 4,
                                        children: [
                                          Icon(LucideIcons.gem, size: 16),
                                          Text(t.vip),
                                        ],
                                      ),
                                    ),
                                    Text(
                                      t.enjoy,
                                      style: TextStyle(
                                        color: Colors.white70,
                                        height: 1,
                                      ),
                                    ),
                                  ],
                                ),
                                Expanded(
                                  child: Stack(
                                    children: [
                                      Positioned(
                                        top: 0,
                                        bottom: 0,
                                        right: 0,
                                        child: SvgPicture.asset(
                                          'assets/images/gift.svg',
                                          width: 64,
                                          height: 64,
                                        ),
                                      ),
                                      Positioned(
                                        right: 16,
                                        bottom: 0,
                                        child: Transform.rotate(
                                          angle: -pi / 4,
                                          child: SvgPicture.asset(
                                            'assets/images/gem.svg',
                                            width: 48,
                                            height: 48,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                    Padding(
                      padding: EdgeInsets.only(left: 16, right: 16, bottom: 16),
                      child: Ink(
                        decoration: BoxDecoration(
                          color: Color(0x05ffffff),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Wrap(
                          children: [
                            ...(userState.isAdmin
                                ? [
                                    ListTile(
                                      onTap: () {
                                        context.push('/admin');
                                      },
                                      contentPadding: EdgeInsets.symmetric(
                                        vertical: 4,
                                        horizontal: 16,
                                      ),
                                      leading: Icon(LucideIcons.userCog),
                                      title: Text(t.admin),
                                      trailing: Icon(
                                        Icons.arrow_forward_ios,
                                        size: 18,
                                      ),
                                    ),
                                    Divider(height: 1),
                                  ]
                                : []),
                            ListTile(
                              onTap: () {
                                context.push('/help');
                              },
                              contentPadding: EdgeInsets.symmetric(
                                vertical: 4,
                                horizontal: 16,
                              ),
                              leading: Icon(LucideIcons.circleQuestionMark),
                              title: Text(t.feedback_help),
                              trailing: Icon(Icons.arrow_forward_ios, size: 18),
                            ),
                            Divider(height: 1),
                            ListTile(
                              onTap: () {
                                context.push('/language');
                              },
                              contentPadding: EdgeInsets.symmetric(
                                vertical: 4,
                                horizontal: 16,
                              ),
                              leading: Icon(LucideIcons.globe),
                              title: Text(t.language),
                              trailing: Icon(Icons.arrow_forward_ios, size: 18),
                            ),
                            Divider(height: 1),
                            ListTile(
                              onTap: () {
                                context.push('/about');
                              },
                              contentPadding: EdgeInsets.symmetric(
                                vertical: 4,
                                horizontal: 16,
                              ),
                              leading: Icon(LucideIcons.info),
                              title: Text(t.about_us),
                              trailing: Icon(Icons.arrow_forward_ios, size: 18),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
