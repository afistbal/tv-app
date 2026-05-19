import 'package:flutter/material.dart';
import 'package:flutter_tabler_icons/flutter_tabler_icons.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:yogotv/api.dart';
import 'package:yogotv/components/empty.dart';
import 'package:yogotv/components/loading.dart';
import 'package:yogotv/components/no_more.dart';
import 'package:yogotv/i18n/strings.g.dart';

class EarnDetail extends StatefulWidget {
  const EarnDetail({super.key});

  @override
  State<StatefulWidget> createState() {
    return _EarnDetail();
  }
}

class _EarnDetail extends State<EarnDetail> {
  final ScrollController _controller = ScrollController();
  int _totalEarn = 0;
  int _ownedEarn = 0;
  List<dynamic> _list = [];
  bool _loading = true;
  bool _more = true;
  int _page = 0;

  @override
  initState() {
    super.initState();

    _controller.addListener(() {
      if (_controller.offset == _controller.position.maxScrollExtent &&
          _controller.position.maxScrollExtent != 0) {
        _loadLatest(page: _page + 1);
      }
    });

    _loadData();
  }

  _loadData() async {
    final info = await api('earn/info');
    if (info.c != 0) {
      return;
    }
    setState(() {
      _totalEarn = info.d['total'];
      _ownedEarn = info.d['owned'];
    });
    await _loadLatest();
  }

  _loadLatest({page = 1}) async {
    final list = await api('earn/detail', query: {'page': page});
    if (list.c != 0) {
      return;
    }

    setState(() {
      if (page == 1) {
        _list = list.d['data'];
      } else {
        _list = [..._list, ...list.d['data']];
      }
      _loading = false;
      _page = page;
      _more = list.d['data'].length == 24;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(t.earn.my_reward)),
      body: _loading
          ? Loading()
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: 16,
              children: [
                Padding(
                  padding: EdgeInsets.all(16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          spacing: 8,
                          children: [
                            Text(
                              _ownedEarn.toString(),
                              style: TextStyle(fontSize: 32, height: 1),
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
                          crossAxisAlignment: CrossAxisAlignment.center,
                          spacing: 8,
                          children: [
                            Text(
                              _totalEarn.toString(),
                              style: TextStyle(fontSize: 32, height: 1),
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
                    ],
                  ),
                ),
                Padding(
                  padding: EdgeInsets.only(left: 16, right: 16),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: () {
                      context.push('/earn/withdraw');
                    },
                    child: Ink(
                      decoration: BoxDecoration(
                        color: Colors.orange,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      padding: EdgeInsets.symmetric(
                        horizontal: 0,
                        vertical: 10,
                      ),
                      child: Row(
                        spacing: 4,
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Icon(TablerIcons.credit_card, size: 24),
                          Text(
                            t.withdraw,
                            textAlign: TextAlign.center,
                            style: TextStyle(height: 1, fontSize: 16),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                Divider(height: 1),
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    spacing: 4,
                    children: [
                      Icon(LucideIcons.gift, color: Colors.white70, size: 20),
                      Text(
                        t.earn.reward_records,
                        style: TextStyle(fontSize: 16, color: Colors.white70),
                      ),
                    ],
                  ),
                ),
                Divider(height: 1),
                Expanded(
                  child: _list.isEmpty
                      ? Empty()
                      : SafeArea(
                          bottom: true,
                          top: false,
                          child: ListView.separated(
                            controller: _controller,
                            padding: EdgeInsets.symmetric(horizontal: 16),
                            itemCount: _list.length + 1,
                            separatorBuilder: (context, index) {
                              return Divider(height: 1);
                            },
                            itemBuilder: (context, index) {
                              if (index == _list.length) {
                                return Padding(
                                  padding: EdgeInsets.all(16),
                                  child: _more ? Loading() : NoMore(),
                                );
                              }
                              return Padding(
                                padding: EdgeInsets.symmetric(
                                  horizontal: 0,
                                  vertical: 12,
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.max,
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  crossAxisAlignment: CrossAxisAlignment.center,
                                  spacing: 16,
                                  children: [
                                    Expanded(
                                      child: Column(
                                        spacing: 8,
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            t['earn.${'type_${_list[index]['type'] >= 3 && _list[index]['type'] <= 9
                                                ? 3
                                                : _list[index]['type'] >= 10 && _list[index]['type'] <= 16
                                                ? 4
                                                : _list[index]['type']}'}'],
                                            style: TextStyle(
                                              height: 1,
                                              fontSize: 16,
                                            ),
                                          ),
                                          Text(
                                            DateFormat(
                                              'yyyy-MM-dd HH:mm:ss +00:00',
                                            ).format(
                                              DateTime.parse(
                                                _list[index]['created_at'],
                                              ),
                                            ),
                                            style: TextStyle(
                                              fontSize: 14,
                                              color: Colors.white60,
                                              height: 1,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    Column(
                                      spacing: 8,
                                      crossAxisAlignment:
                                          CrossAxisAlignment.end,
                                      children: [
                                        Text(
                                          '${_list[index]['change'] > 0 ? '+' : ''}${_list[index]['change']}',
                                          style: TextStyle(
                                            fontSize: 16,
                                            height: 1,
                                            color: _list[index]['change'] > 0
                                                ? Colors.green.shade400
                                                : Colors.red.shade400,
                                          ),
                                        ),
                                        Text(
                                          _list[index]['amount'].toString(),
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
                              );
                            },
                          ),
                        ),
                ),
              ],
            ),
    );
  }
}
