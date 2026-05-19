import 'package:animated_flip_counter/animated_flip_counter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_tabler_icons/flutter_tabler_icons.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:yogotv/api.dart';
import 'package:yogotv/components/loading.dart';
import 'package:yogotv/global.dart';
import 'package:yogotv/i18n/strings.g.dart';
import 'package:yogotv/mobad.dart';
import 'package:yogotv/states/main.dart';

class Earn extends StatefulWidget {
  final bool load;

  const Earn({super.key, required this.load});

  @override
  State<StatefulWidget> createState() {
    return _Earn();
  }
}

class _Earn extends State<Earn> {
  bool _loaded = false;
  bool _loading = true;
  dynamic _data;

  @override
  void initState() {
    super.initState();
  }

  _loadData() async {
    final result = await api('earn');
    setState(() {
      _data = result.d;
      _loading = false;
    });
  }

  @override
  void didUpdateWidget(covariant Earn oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_loaded && widget.load) {
      _loaded = true;
      _loadData();
    }
  }

  int _getTypeValue(int type) {
    return _data['type'].firstWhere((e) => e['type'] == type)['value'];
  }

  int _getEarnValue(int type) {
    final d = _data['earn'].firstWhere(
      (e) => e['type'] == type,
      orElse: () {
        return null;
      },
    );
    return d == null ? 0 : d['value'];
  }

  Future<String> _todo() async {
    return (await api<String>('earn/todo')).d ?? '';
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      edgeOffset: kToolbarHeight + MediaQuery.of(context).padding.top,
      onRefresh: () async {
        await _loadData();
      },
      child: Column(
        children: [
          AppBar(title: Text(t.earn.earn), centerTitle: false),
          Expanded(
            child: _loading
                ? Loading()
                : SingleChildScrollView(
                    padding: EdgeInsets.only(bottom: 16),
                    physics: const AlwaysScrollableScrollPhysics(),
                    child: Column(
                      spacing: 16,
                      children: [
                        Padding(
                          padding: EdgeInsets.only(
                            left: 16,
                            right: 16,
                            top: 16,
                          ),
                          child: Row(
                            spacing: 16,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: InkWell(
                                  onTap: () {
                                    context.push('/earn/detail');
                                  },
                                  borderRadius: BorderRadius.circular(16),
                                  child: Ink(
                                    padding: EdgeInsets.all(16),
                                    decoration: BoxDecoration(
                                      gradient: LinearGradient(
                                        colors: [
                                          Colors.lightGreenAccent.withAlpha(40),
                                          Colors.cyanAccent.withAlpha(40),
                                        ],
                                        begin: Alignment.topLeft,
                                        end: Alignment.bottomRight,
                                      ),
                                      borderRadius: BorderRadius.circular(16),
                                    ),
                                    child: Column(
                                      spacing: 8,
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          spacing: 4,
                                          crossAxisAlignment:
                                              CrossAxisAlignment.center,
                                          mainAxisAlignment:
                                              MainAxisAlignment.spaceBetween,
                                          children: [
                                            Expanded(
                                              child: Text(
                                                t.earn.total_earn,
                                                style: TextStyle(
                                                  color: Colors.white70,
                                                  height: 1,
                                                ),
                                              ),
                                            ),
                                            Icon(
                                              LucideIcons.chevronRight,
                                              color: Colors.white70,
                                              size: 16,
                                            ),
                                          ],
                                        ),
                                        AnimatedFlipCounter(
                                          value: _data['total'],
                                          textStyle: TextStyle(
                                            fontSize: 32,
                                            color: Colors.white,
                                            height: 1,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                              Expanded(
                                child: InkWell(
                                  onTap: () {
                                    context.push('/earn/detail');
                                  },
                                  borderRadius: BorderRadius.circular(16),
                                  child: Ink(
                                    padding: EdgeInsets.all(16),
                                    decoration: BoxDecoration(
                                      gradient: LinearGradient(
                                        colors: [
                                          Colors.lightGreenAccent.withAlpha(40),
                                          Colors.cyanAccent.withAlpha(40),
                                        ],
                                        begin: Alignment.topLeft,
                                        end: Alignment.bottomRight,
                                      ),
                                      borderRadius: BorderRadius.circular(16),
                                    ),
                                    child: Column(
                                      spacing: 8,
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          spacing: 4,
                                          crossAxisAlignment:
                                              CrossAxisAlignment.center,
                                          mainAxisAlignment:
                                              MainAxisAlignment.spaceBetween,
                                          children: [
                                            Expanded(
                                              child: Text(
                                                t.earn.today_earn,
                                                style: TextStyle(
                                                  color: Colors.white70,
                                                  height: 1,
                                                ),
                                              ),
                                            ),
                                            Icon(
                                              LucideIcons.chevronRight,
                                              color: Colors.white70,
                                              size: 16,
                                            ),
                                          ],
                                        ),
                                        AnimatedFlipCounter(
                                          value: _data['today'],
                                          textStyle: TextStyle(
                                            fontSize: 32,
                                            color: Colors.white,
                                            height: 1,
                                          ),
                                        ),
                                      ],
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
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  Colors.deepOrangeAccent.withAlpha(40),
                                  Colors.deepPurpleAccent.withAlpha(40),
                                ],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Column(
                              children: [
                                Padding(
                                  padding: EdgeInsets.only(
                                    top: 16,
                                    left: 16,
                                    right: 16,
                                    bottom: 16,
                                  ),
                                  child: Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.center,
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(
                                        t.earn.today_tasks,
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleMedium
                                            ?.copyWith(color: Colors.amber),
                                      ),
                                      Text(
                                        t.earn.progress(
                                          current:
                                              (_getTypeValue(17) -
                                                          _getEarnValue(1) ==
                                                      0
                                                  ? 1
                                                  : 0) +
                                              (_getTypeValue(18) -
                                                          _getEarnValue(2) ==
                                                      0
                                                  ? 1
                                                  : 0),
                                          total: 2,
                                        ),
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodyLarge
                                            ?.copyWith(
                                              color: Colors.white.withAlpha(
                                                150,
                                              ),
                                            ),
                                      ),
                                    ],
                                  ),
                                ),
                                Divider(
                                  color: Colors.grey.withAlpha(30),
                                  height: 1,
                                ),
                                Wrap(
                                  children: [
                                    InkWell(
                                      onTap: () {
                                        context.read<MainState>().setIndex(0);
                                      },
                                      child: Padding(
                                        padding: EdgeInsets.symmetric(
                                          horizontal: 16,
                                          vertical: 16,
                                        ),
                                        child: Row(
                                          spacing: 16,
                                          crossAxisAlignment:
                                              CrossAxisAlignment.center,
                                          children: [
                                            Expanded(
                                              child: Column(
                                                spacing: 4,
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    t.earn
                                                        .earn_coins_per_min_watching(
                                                          coins: _getTypeValue(
                                                            1,
                                                          ).toString(),
                                                          minutes: 1,
                                                        ),
                                                    style: TextStyle(height: 1),
                                                  ),
                                                  Text(
                                                    t.earn.remaining_coins(
                                                      remaining:
                                                          (_getTypeValue(17) -
                                                                  _getEarnValue(
                                                                    1,
                                                                  ))
                                                              .toString(),
                                                    ),
                                                    style: Theme.of(context)
                                                        .textTheme
                                                        .bodySmall
                                                        ?.copyWith(
                                                          color: Colors.green
                                                              .withAlpha(180),
                                                        ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                            Ink(
                                              padding: EdgeInsets.symmetric(
                                                horizontal: 8,
                                                vertical: 8,
                                              ),
                                              decoration: BoxDecoration(
                                                color: Theme.of(
                                                  context,
                                                ).colorScheme.primary,
                                                borderRadius:
                                                    BorderRadius.circular(4),
                                              ),
                                              child: Center(
                                                child: Text(
                                                  t.earn.go_watch_dramas,
                                                  style: Theme.of(context)
                                                      .textTheme
                                                      .bodyMedium
                                                      ?.copyWith(
                                                        height: 1,
                                                        fontSize: 12,
                                                        color: Colors.white,
                                                      ),
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                    Divider(
                                      color: Colors.grey.withAlpha(30),
                                      height: 1,
                                    ),
                                    InkWell(
                                      onTap: () async {
                                        final close = Global.loading();
                                        final cipher = await _todo();
                                        rewardedAd((done) async {
                                          if (!done) {
                                            close();
                                            return;
                                          }
                                          final result = await api<int>(
                                            'earn/watch-video',
                                            method: Method.post,
                                            data: {'cipher': cipher},
                                          );

                                          if (result.c == 0) {
                                            await _loadData();
                                          }

                                          close();

                                          if (result.c != 0) {
                                            return;
                                          }
                                          Global.success(
                                            t.earn.earn_amount(
                                              amount: result.d ?? 0,
                                            ),
                                          );
                                        });
                                      },
                                      child: Padding(
                                        padding: EdgeInsets.symmetric(
                                          horizontal: 16,
                                          vertical: 16,
                                        ),
                                        child: Row(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.center,
                                          spacing: 16,
                                          children: [
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                spacing: 4,
                                                children: [
                                                  Text(
                                                    t.earn
                                                        .earn_coins_watching_videos(
                                                          coins: _getTypeValue(
                                                            2,
                                                          ).toString(),
                                                        ),
                                                    style: TextStyle(height: 1),
                                                  ),
                                                  Text(
                                                    t.earn.remaining_coins(
                                                      remaining:
                                                          (_getTypeValue(18) -
                                                                  _getEarnValue(
                                                                    2,
                                                                  ))
                                                              .toString(),
                                                    ),
                                                    style: Theme.of(context)
                                                        .textTheme
                                                        .bodySmall
                                                        ?.copyWith(
                                                          color: Colors.green
                                                              .withAlpha(180),
                                                        ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                            Ink(
                                              decoration: BoxDecoration(
                                                color: Theme.of(
                                                  context,
                                                ).colorScheme.primary,
                                                borderRadius:
                                                    BorderRadius.circular(4),
                                              ),
                                              padding: EdgeInsets.symmetric(
                                                horizontal: 8,
                                                vertical: 8,
                                              ),
                                              child: Center(
                                                child: Text(
                                                  t.earn.go_watch_videos,
                                                  style: Theme.of(context)
                                                      .textTheme
                                                      .bodyMedium
                                                      ?.copyWith(
                                                        height: 1,
                                                        fontSize: 12,
                                                        color: Colors.white,
                                                      ),
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                        Padding(
                          padding: EdgeInsets.only(left: 16, right: 16),
                          child: Ink(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  Colors.indigoAccent.withAlpha(40),
                                  Colors.deepOrangeAccent.withAlpha(40),
                                ],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Column(
                              children: [
                                Padding(
                                  padding: EdgeInsets.only(
                                    top: 16,
                                    left: 16,
                                    right: 16,
                                    bottom: 16,
                                  ),
                                  child: Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.center,
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(
                                        t.earn.check_in_tasks,
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleMedium
                                            ?.copyWith(color: Colors.amber),
                                      ),
                                      Text(
                                        t.earn.progress(
                                          current:
                                              (_data['watch_signed'] ? 1 : 0) +
                                              (_data['sign_signed'] ? 1 : 0),
                                          total: 2,
                                        ),
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodyLarge
                                            ?.copyWith(
                                              color: Colors.white.withAlpha(
                                                150,
                                              ),
                                            ),
                                      ),
                                    ],
                                  ),
                                ),
                                Divider(
                                  color: Colors.grey.withAlpha(30),
                                  height: 1,
                                ),
                                Wrap(
                                  children: [
                                    InkWell(
                                      onTap: () {
                                        context.read<MainState>().setIndex(0);
                                      },
                                      child: Column(
                                        children: [
                                          Padding(
                                            padding: EdgeInsets.symmetric(
                                              horizontal: 16,
                                              vertical: 16,
                                            ),
                                            child: Row(
                                              spacing: 16,
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.center,
                                              children: [
                                                Expanded(
                                                  child: Column(
                                                    crossAxisAlignment:
                                                        CrossAxisAlignment
                                                            .start,
                                                    spacing: 4,
                                                    children: [
                                                      Text(
                                                        t
                                                            .earn
                                                            .earn_coins_daily_watching,
                                                        style: TextStyle(
                                                          height: 1,
                                                        ),
                                                      ),
                                                      Text(
                                                        _data['watch_signed']
                                                            ? t.earn.completed
                                                            : t
                                                                  .earn
                                                                  .not_watched_today,
                                                        style: Theme.of(context)
                                                            .textTheme
                                                            .bodySmall
                                                            ?.copyWith(
                                                              color: Colors
                                                                  .green
                                                                  .withAlpha(
                                                                    180,
                                                                  ),
                                                            ),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                                Ink(
                                                  padding: EdgeInsets.symmetric(
                                                    horizontal: 8,
                                                    vertical: 8,
                                                  ),
                                                  decoration: BoxDecoration(
                                                    color: _data['watch_signed']
                                                        ? Colors.white12
                                                        : Theme.of(
                                                            context,
                                                          ).colorScheme.primary,
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          4,
                                                        ),
                                                  ),
                                                  child: Center(
                                                    child: Text(
                                                      t.earn.go_watch_dramas,
                                                      style: Theme.of(context)
                                                          .textTheme
                                                          .bodyMedium
                                                          ?.copyWith(
                                                            height: 1,
                                                            fontSize: 12,
                                                            color:
                                                                _data['watch_signed']
                                                                ? Colors.white38
                                                                : Colors.white,
                                                          ),
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                          Ink(
                                            height: 64,
                                            padding: EdgeInsets.only(
                                              left: 16,
                                              right: 16,
                                              bottom: 16,
                                            ),
                                            child: ListView.builder(
                                              clipBehavior: Clip.hardEdge,
                                              scrollDirection: Axis.horizontal,
                                              itemCount: 7 * 2,
                                              itemBuilder: (context, index) {
                                                if (index == 13) {
                                                  return null;
                                                }
                                                if (index % 2 != 0) {
                                                  return SizedBox(width: 4);
                                                }
                                                final key = (index / 2).ceil();
                                                return Signin(
                                                  index: key,
                                                  amount: _getTypeValue(
                                                    key + 3,
                                                  ),
                                                  signed:
                                                      key <
                                                      _data['can_sign_watch'],
                                                );
                                              },
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    Divider(
                                      color: Colors.grey.withAlpha(30),
                                      height: 1,
                                    ),
                                    InkWell(
                                      onTap: _data['sign_signed']
                                          ? null
                                          : () async {
                                              final close = Global.loading();
                                              final result = await api(
                                                'earn/sign',
                                                method: Method.post,
                                              );
                                              if (result.c == 0) {
                                                await _loadData();
                                              }
                                              close();
                                              if (result.c != 0) {
                                                return;
                                              }
                                              Global.success(
                                                t.earn.earn_amount(
                                                  amount: result.d ?? 0,
                                                ),
                                              );
                                            },
                                      borderRadius: BorderRadius.only(
                                        bottomLeft: Radius.circular(16),
                                        bottomRight: Radius.circular(16),
                                      ),
                                      child: Column(
                                        children: [
                                          Padding(
                                            padding: EdgeInsets.symmetric(
                                              horizontal: 16,
                                              vertical: 16,
                                            ),
                                            child: Row(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.center,
                                              spacing: 16,
                                              children: [
                                                Expanded(
                                                  child: Column(
                                                    crossAxisAlignment:
                                                        CrossAxisAlignment
                                                            .start,
                                                    spacing: 4,
                                                    children: [
                                                      Text(
                                                        t
                                                            .earn
                                                            .earn_coins_daily_check_in,
                                                        style: TextStyle(
                                                          height: 1,
                                                        ),
                                                      ),
                                                      Text(
                                                        _data['sign_signed']
                                                            ? t.earn.completed
                                                            : t
                                                                  .earn
                                                                  .not_checked_in_today,
                                                        style: Theme.of(context)
                                                            .textTheme
                                                            .bodySmall
                                                            ?.copyWith(
                                                              color: Colors
                                                                  .green
                                                                  .withAlpha(
                                                                    180,
                                                                  ),
                                                            ),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                                Ink(
                                                  decoration: BoxDecoration(
                                                    color: _data['sign_signed']
                                                        ? Colors.white12
                                                        : Theme.of(
                                                            context,
                                                          ).colorScheme.primary,
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          4,
                                                        ),
                                                  ),
                                                  padding: EdgeInsets.symmetric(
                                                    horizontal: 8,
                                                    vertical: 8,
                                                  ),
                                                  child: Center(
                                                    child: Text(
                                                      t.earn.go_check_in,
                                                      style: Theme.of(context)
                                                          .textTheme
                                                          .bodyMedium
                                                          ?.copyWith(
                                                            height: 1,
                                                            fontSize: 12,
                                                            color:
                                                                _data['sign_signed']
                                                                ? Colors.white38
                                                                : Colors.white,
                                                          ),
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                          Ink(
                                            height: 64,
                                            padding: EdgeInsets.only(
                                              left: 16,
                                              right: 16,
                                              bottom: 16,
                                            ),
                                            child: ListView.builder(
                                              clipBehavior: Clip.hardEdge,
                                              scrollDirection: Axis.horizontal,
                                              itemCount: 7 * 2,
                                              itemBuilder: (context, index) {
                                                if (index == 13) {
                                                  return null;
                                                }
                                                if (index % 2 != 0) {
                                                  return SizedBox(width: 4);
                                                }
                                                final key = (index / 2).ceil();
                                                return Signin(
                                                  index: key,
                                                  amount: _getTypeValue(
                                                    key + 10,
                                                  ),
                                                  signed:
                                                      key <
                                                      _data['can_sign_sign'],
                                                );
                                              },
                                            ),
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
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class Signin extends StatelessWidget {
  final int index;
  final int amount;
  final bool signed;

  const Signin({
    super.key,
    required this.index,
    required this.amount,
    required this.signed,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 80,
      height: 48,
      decoration: BoxDecoration(
        gradient: signed
            ? null
            : LinearGradient(
                colors: [
                  Colors.orange.shade400,
                  Colors.amber.shade200,
                  Colors.orange.shade400,
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
        color: signed ? Colors.white10 : null,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Stack(
        children: [
          Positioned(
            top: 4,
            left: 4,
            child: Icon(
              TablerIcons.coin_filled,
              size: 16,
              color: Colors.black12,
            ),
            // Text(
            //   '💎',
            //   style: TextStyle(
            //     fontSize: 12,
            //     shadows: [
            //       BoxShadow(
            //         color: Colors.black,
            //         blurRadius: 4,
            //         spreadRadius: 4,
            //       ),
            //     ],
            //   ),
            // ),
          ),
          Positioned(
            top: 4,
            left: 0,
            right: 0,
            bottom: 0,
            child: Column(
              spacing: 4,
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Text(
                  '$amount',
                  style: TextStyle(
                    color: signed ? Colors.white24 : Colors.black54,
                    fontWeight: FontWeight.bold,
                    height: 1,
                    fontSize: 14,
                  ),
                ),
                Text(
                  signed ? t.earn.completed : t.earn.day(day: index + 1),
                  style: TextStyle(
                    color: signed ? Colors.white24 : Colors.black38,
                    fontSize: 10,
                    height: 1,
                    fontWeight: FontWeight.bold,
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
