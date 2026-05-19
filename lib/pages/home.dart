import 'dart:convert';
import 'dart:ui';

import 'package:carousel_slider/carousel_slider.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:yogotv/api.dart';
import 'package:yogotv/components/empty.dart';
import 'package:yogotv/components/lazy_image.dart';
import 'package:yogotv/components/loading.dart';
import 'package:yogotv/components/no_more.dart';
import 'package:yogotv/global.dart';
import 'package:yogotv/i18n/strings.g.dart';
import 'package:yogotv/widgets/film_item.dart';

class Home extends StatefulWidget {
  const Home({super.key});

  @override
  State<StatefulWidget> createState() {
    return _Home();
  }
}

class _Home extends State<Home> with TickerProviderStateMixin {
  late final TabController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TabController(length: 3, vsync: this);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(toolbarHeight: 0),
      body: Column(
        children: [
          Ink(
            color: Color(0xff111111),
            child: TabBar(
              controller: _controller,
              dividerHeight: 0,
              indicatorSize: TabBarIndicatorSize.tab,
              indicatorWeight: 1,
              indicatorPadding: EdgeInsets.symmetric(
                horizontal: 32,
                vertical: 10,
              ),
              tabAlignment: TabAlignment.fill,
              unselectedLabelColor: Colors.white54,
              labelPadding: EdgeInsets.symmetric(horizontal: 4),
              tabs: [
                Ink(
                  height: 54,
                  child: Center(
                    child: Text(
                      t.home_tab_recommend,
                      style: TextStyle(fontSize: 16, height: 1),
                    ),
                  ),
                ),
                Ink(
                  height: 54,
                  child: Center(
                    child: Text(
                      t.home_tab_rankings,
                      style: TextStyle(fontSize: 16, height: 1),
                    ),
                  ),
                ),
                Ink(
                  height: 54,
                  child: Center(
                    child: Text(
                      t.categories,
                      style: TextStyle(fontSize: 16, height: 1),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              controller: _controller,
              children: [First(), Ranking(), Category()],
            ),
          ),
        ],
      ),
    );
  }
}

class First extends StatefulWidget {
  const First({super.key});

  @override
  State<StatefulWidget> createState() {
    return _First();
  }
}

class _First extends State<First> with AutomaticKeepAliveClientMixin {
  final _controller = ScrollController();
  dynamic _watchTo;
  dynamic _data;
  bool _loading = true;
  int _currentTop = 0;
  bool _latestLoading = true;
  List<dynamic> _latest = [];
  bool _more = true;
  int _page = 0;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();

    _controller.addListener(() {
      if (_controller.offset == _controller.position.maxScrollExtent &&
          _controller.position.maxScrollExtent != 0) {
        Global.logger.d(_controller.position.maxScrollExtent);
        _loadLatest(page: _page + 1);
      }
    });

    final watchTo = Global.sp.getString('watch_to');

    if (watchTo != null) {
      _watchTo = jsonDecode(watchTo);
    }

    _loadData();
  }

  _loadData() async {
    final res = await api('home');
    if (res.c != 0) {
      return;
    }
    setState(() {
      _data = res.d;
      _loading = false;
    });
    _loadLatest();
  }

  _loadLatest({page = 1}) {
    if (!_more || page <= _page) {
      return;
    }
    api('movie', query: {'page': page}).then((res) {
      if (res.c != 0) {
        return;
      }

      setState(() {
        _latest = [..._latest, ...res.d['data']];
        _latestLoading = false;
        _more = res.d['data'].length == 24;
        _page = page;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final width = (MediaQuery.of(context).size.width - 48) / 2;
    final height = width / 3 * 4;

    return RefreshIndicator(
      edgeOffset: 0,
      onRefresh: () async {
        _data = null;
        _latest = [];
        _latestLoading = true;
        _more = true;
        _page = 0;
        _currentTop = 0;
        await _loadData();
      },
      child: Stack(
        children: [
          CustomScrollView(
            controller: _controller,
            slivers: [
              // SliverAppBar(
              // title: Text(t.site_name),
              // pinned: true,
              // primary: false,
              // floating: true,
              // backgroundColor: Theme.of(context).appBarTheme.backgroundColor,
              // surfaceTintColor: Colors.transparent,
              // actions: [
              //   IconButton(
              //     onPressed: () {
              //       context.push('/search');
              //     },
              //     icon: Icon(LucideIcons.search),
              //   ),
              // ],
              // ),
              ...(_loading
                  ? [SliverFillRemaining(child: Loading())]
                  : _data['top'].length == 0
                  ? [SliverFillRemaining(child: Empty())]
                  : [
                      SliverToBoxAdapter(
                        child: Stack(
                          children: [
                            SizedBox(
                              height: 372,
                              width: MediaQuery.of(context).size.width,
                              child: ImageFiltered(
                                imageFilter: ImageFilter.blur(
                                  sigmaX: 24,
                                  sigmaY: 24,
                                ),
                                child: LazyImage(
                                  url: Global.static(
                                    _data['top'][_currentTop]['image'],
                                  ),
                                  width: MediaQuery.of(context).size.width,
                                  height: MediaQuery.of(context).size.width,
                                  fit: BoxFit.cover,
                                ),
                              ),
                            ),
                            Positioned(
                              top: 24,
                              height: 320,
                              width: MediaQuery.of(context).size.width,
                              child: CarouselSlider(
                                options: CarouselOptions(
                                  height: 320,
                                  viewportFraction: 0.6,
                                  aspectRatio: 0.75,
                                  enlargeFactor: 0.4,
                                  enlargeCenterPage: true,
                                  enlargeStrategy:
                                      CenterPageEnlargeStrategy.zoom,
                                  onPageChanged: (index, reason) {
                                    setState(() {
                                      _currentTop = index;
                                    });
                                  },
                                ),
                                items: _data['top'].map<Widget>((e) {
                                  return Builder(
                                    builder: (BuildContext context) {
                                      return GestureDetector(
                                        onTap: () {
                                          context.push(
                                            '/play',
                                            extra: {'id': e['id']},
                                          );
                                        },
                                        child: Container(
                                          width: 240,
                                          margin: EdgeInsets.symmetric(
                                            horizontal: 8,
                                          ),
                                          child: ClipRRect(
                                            borderRadius: BorderRadius.circular(
                                              8,
                                            ),
                                            child: LazyImage(
                                              url: Global.static(e['image']),
                                              width: 240,
                                              height: 320,
                                              fit: BoxFit.cover,
                                            ),
                                          ),
                                        ),
                                      );
                                    },
                                  );
                                }).toList(),
                              ),
                            ),
                          ],
                        ),
                      ),
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: EdgeInsets.only(left: 16, right: 16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            spacing: 16,
                            children: [
                              Text(
                                t.home_page.recommend,
                                style: TextStyle(fontSize: 18),
                              ),
                              SizedBox(
                                height: 170,
                                child: ListView.builder(
                                  scrollDirection: Axis.horizontal,
                                  itemCount: _data['recommend'].length * 2,
                                  itemBuilder: (context, index) {
                                    if (index % 2 != 0) {
                                      return SizedBox(width: 8);
                                    }
                                    int i = (index / 2).floor();
                                    return GestureDetector(
                                      onTap: () {
                                        context.push(
                                          '/play',
                                          extra: {
                                            'id': _data['recommend'][i]['id'],
                                          },
                                        );
                                      },
                                      child: SizedBox(
                                        width: 108,
                                        height: 170,
                                        child: Column(
                                          spacing: 6,
                                          children: [
                                            ClipRRect(
                                              borderRadius:
                                                  BorderRadius.circular(8),
                                              child: LazyImage(
                                                url: Global.static(
                                                  _data['recommend'][i]['image'],
                                                ),
                                                height: 144,
                                                width: 108,
                                                fit: BoxFit.cover,
                                              ),
                                            ),
                                            SizedBox(
                                              height: 20,
                                              child: Text(
                                                _data['recommend'][i]['title'],
                                                style: TextStyle(
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: EdgeInsets.only(
                            top: 32,
                            left: 16,
                            right: 16,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            spacing: 16,
                            children: [
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  Text(
                                    t.home_page.rank,
                                    style: TextStyle(fontSize: 18),
                                  ),
                                  // GestureDetector(
                                  //   onTap: () {},
                                  //   child: SizedBox(
                                  //     height: 32,
                                  //     child: Row(
                                  //       children: [
                                  //         Text(
                                  //           Translations.of(
                                  //             context,
                                  //           ).home_page.rank_more,
                                  //         ),
                                  //         Center(
                                  //           child: Icon(Icons.arrow_forward_ios, size: 18),
                                  //         ),
                                  //       ],
                                  //     ),
                                  //   ),
                                  // ),
                                ],
                              ),
                              SizedBox(
                                height: 170,
                                child: ListView.builder(
                                  scrollDirection: Axis.horizontal,
                                  itemCount: _data['rank'].length * 2,
                                  itemBuilder: (context, index) {
                                    if (index % 2 != 0) {
                                      return SizedBox(width: 8);
                                    }
                                    int i = (index / 2).floor();
                                    return GestureDetector(
                                      onTap: () {
                                        context.push(
                                          '/play',
                                          extra: {'id': _data['rank'][i]['id']},
                                        );
                                      },
                                      child: SizedBox(
                                        width: 108,
                                        height: 170,
                                        child: Column(
                                          spacing: 6,
                                          children: [
                                            ClipRRect(
                                              borderRadius:
                                                  BorderRadius.circular(8),
                                              child: LazyImage(
                                                url: Global.static(
                                                  _data['rank'][i]['image'],
                                                ),
                                                height: 144,
                                                width: 108,
                                                fit: BoxFit.cover,
                                              ),
                                            ),
                                            SizedBox(
                                              height: 20,
                                              child: Text(
                                                _data['rank'][i]['title'],
                                                style: TextStyle(
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: EdgeInsets.only(
                            top: 32,
                            left: 16,
                            right: 16,
                            bottom: 24,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            spacing: 16,
                            children: [
                              Text(
                                t.home_page.latest,
                                style: TextStyle(fontSize: 18, height: 1),
                              ),
                            ],
                          ),
                        ),
                      ),
                      _latestLoading
                          ? SliverToBoxAdapter()
                          : SliverPadding(
                              padding: EdgeInsets.only(
                                left: 16,
                                right: 16,
                                bottom: 16,
                              ),
                              sliver: SliverGrid.builder(
                                itemCount: _latest.length,
                                gridDelegate:
                                    SliverGridDelegateWithFixedCrossAxisCount(
                                      crossAxisCount: 2,
                                      crossAxisSpacing: 16,
                                      mainAxisSpacing: 16,
                                      mainAxisExtent: height + 52,
                                    ),
                                itemBuilder: (context, index) {
                                  return FilmItem(
                                    id: _latest[index]['id'],
                                    width: width,
                                    height: height,
                                    image: _latest[index]['image'],
                                    title: _latest[index]['title'],
                                    recommend: true,
                                  );
                                },
                              ),
                            ),
                      _more
                          ? SliverToBoxAdapter(
                              child: Padding(
                                padding: EdgeInsets.only(top: 16, bottom: 32),
                                child: Loading(),
                              ),
                            )
                          : SliverToBoxAdapter(
                              child: Padding(
                                padding: EdgeInsets.only(top: 16, bottom: 32),
                                child: NoMore(),
                              ),
                            ),
                    ]),
            ],
          ),
          if (!_loading && _watchTo != null)
            Positioned(
              bottom: MediaQuery.of(context).padding.bottom,
              left: 0,
              right: 0,
              child: Stack(
                children: [
                  Padding(
                    padding: EdgeInsets.only(
                      left: 32,
                      right: 32,
                      top: 32,
                      bottom: 16,
                    ),
                    child: Material(
                      type: MaterialType.transparency,
                      child: Ink(
                        height: 96,
                        padding: EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Color(0xff303030),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Row(
                          spacing: 16,
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(4),
                              child: LazyImage(
                                url: Global.static(_watchTo['image']),
                                width: 48,
                                height: 64,
                                fit: BoxFit.cover,
                              ),
                            ),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    '${_watchTo['title']}',
                                    overflow: TextOverflow.ellipsis,
                                    maxLines: 2,
                                    style: TextStyle(
                                      fontSize: 14,
                                      height: 1.25,
                                    ),
                                  ),
                                  Text(
                                    t.watch_to(
                                      episode: _watchTo['episode'],
                                      time:
                                          '${(_watchTo['position'] / 60).floor().toString().padLeft(2, '0')}:${(_watchTo['position'] % 60).floor().toString().padLeft(2, '0')}',
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                    maxLines: 1,
                                    style: TextStyle(
                                      height: 1.25,
                                      fontSize: 12,
                                      color: Colors.white54,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            IconButton.filled(
                              onPressed: () {
                                context.push(
                                  '/play',
                                  extra: {
                                    'id': _watchTo['id'],
                                    'watchTo': _watchTo,
                                  },
                                );
                                _watchTo = null;
                              },
                              icon: Icon(LucideIcons.play, size: 20),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    right: 0,
                    left: 0,
                    top: 8,
                    child: Center(
                      child: Material(
                        type: MaterialType.transparency,
                        child: InkWell(
                          onTap: () {
                            setState(() {
                              _watchTo = null;
                            });
                          },
                          borderRadius: BorderRadius.circular(24),
                          child: Ink(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              color: Color(0xff303030),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Icon(LucideIcons.chevronsDown),
                          ),
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

class Ranking extends StatefulWidget {
  const Ranking({super.key});
  @override
  State<StatefulWidget> createState() {
    return _Ranking();
  }
}

class _Ranking extends State<Ranking> with AutomaticKeepAliveClientMixin {
  bool _loading = true;
  List<dynamic> _list = [];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  bool get wantKeepAlive => true;

  _loadData() async {
    final result = await api('home/rank');
    if (result.c != 0) {
      return;
    }
    setState(() {
      _list = result.d;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return _loading
        ? Loading()
        : _list.isEmpty
        ? Empty()
        : RefreshIndicator(
            onRefresh: () async {
              await _loadData();
            },
            child: ListView.separated(
              separatorBuilder: (context, index) {
                return Divider(height: 1);
              },
              itemCount: 10,
              itemBuilder: (context, index) {
                return InkWell(
                  onTap: () {
                    context.push('/play', extra: {'id': _list[index]['id']});
                  },
                  child: Ink(
                    padding: EdgeInsets.only(
                      top: 16,
                      bottom: 16,
                      left: 16,
                      right: 16,
                    ),
                    height: 128,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      spacing: 16,
                      children: [
                        Stack(
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: LazyImage(
                                url: Global.static(_list[index]['image']),
                                width: 64,
                                height: 96,
                                fit: BoxFit.cover,
                              ),
                            ),
                            Positioned(
                              top: -12,
                              left: -12,
                              child: Container(
                                width: 32,
                                height: 32,
                                decoration: BoxDecoration(
                                  color: Colors.red,
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                alignment: Alignment.bottomRight,
                              ),
                            ),
                            Positioned(
                              top: -1,
                              left: -2,
                              child: Container(
                                width: 20,
                                height: 20,
                                alignment: Alignment.center,
                                child: Text(
                                  (index + 1).toString(),
                                  style: TextStyle(
                                    height: 1,
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        Expanded(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _list[index]['title'],
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(fontSize: 16, height: 1.2),
                              ),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                crossAxisAlignment: WrapCrossAlignment.start,
                                runAlignment: WrapAlignment.start,
                                children: (_list[index]['tags'] as List)
                                    .asMap()
                                    .entries
                                    .where((e) => e.key < 3)
                                    .map<Widget>((e) {
                                      return Container(
                                        padding: EdgeInsets.symmetric(
                                          horizontal: 4,
                                          vertical: 4,
                                        ),
                                        decoration: BoxDecoration(
                                          color: Colors.white24,
                                          borderRadius: BorderRadius.circular(
                                            4,
                                          ),
                                        ),
                                        child: Text(
                                          e.value,
                                          style: TextStyle(
                                            height: 1,
                                            fontSize: 14,
                                            color: Colors.white60,
                                          ),
                                        ),
                                      );
                                    })
                                    .toList(),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          );
  }
}

class Category extends StatefulWidget {
  const Category({super.key});

  @override
  State<StatefulWidget> createState() {
    return _Category();
  }
}

class _Category extends State<Category> with AutomaticKeepAliveClientMixin {
  final _controller = ScrollController();
  bool _loading = true;
  dynamic _categories;
  bool _latestLoading = true;
  List<dynamic> _latest = [];
  bool _more = true;
  int _page = 0;
  int _areaSelected = 0;
  int _tagSelected = 0;
  int _genderSelected = 0;
  bool _requesting = false;

  @override
  bool get wantKeepAlive => true;

  @override
  initState() {
    super.initState();
    _controller.addListener(() {
      if (_controller.offset == _controller.position.maxScrollExtent &&
          _controller.position.maxScrollExtent != 0) {
        Global.logger.d(_controller.position.maxScrollExtent);
        _loadLatest(page: _page + 1);
      }
    });

    _loadData().then((_) {
      _loadLatest();
    });
  }

  _loadData() async {
    final result = await api('home/categories');
    if (result.c != 0) {
      return;
    }
    _categories = result.d;
  }

  _loadLatest({page = 1}) {
    if (!_more || page <= _page) {
      return;
    }
    api(
      'movie',
      query: {
        'page': page,
        'area': _areaSelected == 0
            ? 0
            : _categories['area'][_areaSelected - 1]['id'],
        'tag': _tagSelected == 0
            ? 0
            : _categories['tags'][_tagSelected - 1]['id'],
        'gender': _genderSelected == 0
            ? 0
            : _categories['gender'][_genderSelected - 1]['id'],
      },
    ).then((res) {
      if (res.c != 0) {
        return;
      }

      setState(() {
        _loading = false;
        _latest = [..._latest, ...res.d['data']];
        _latestLoading = false;
        _more = res.d['data'].length == 24 && page <= 10;
        _page = page;
        _requesting = false;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final width = (MediaQuery.of(context).size.width - 64) / 3;
    final height = width / 3 * 4;

    return _loading
        ? Loading()
        : Column(
            children: [
              // Padding(
              //   padding: EdgeInsets.only(left: 16, right: 16, top: 8),
              //   child: SizedBox(
              //     height: 48,
              //     child: Material(
              //       type: MaterialType.transparency,
              //       child: ListView.separated(
              //         padding: EdgeInsets.symmetric(vertical: 8),
              //         scrollDirection: Axis.horizontal,
              //         separatorBuilder: (BuildContext context, int index) {
              //           return SizedBox(width: 8);
              //         },
              //         itemCount: _categories['area'].length + 1,
              //         itemBuilder: (BuildContext context, int index) {
              //           return Tag(
              //             text: index == 0
              //                 ? t.all
              //                 : _categories['area'][index - 1]['title'],
              //             selected: _areaSelected == index,
              //             onTap: () {
              //               setState(() {
              //                 _areaSelected = index;
              //                 _page = 0;
              //                 _more = true;
              //                 _requesting = true;
              //                 _loadLatest();
              //               });
              //             },
              //           );
              //         },
              //       ),
              //     ),
              //   ),
              // ),
              Padding(
                padding: EdgeInsets.only(left: 16, right: 16),
                child: SizedBox(
                  height: 48,
                  child: Material(
                    type: MaterialType.transparency,
                    child: ListView.separated(
                      padding: EdgeInsets.symmetric(vertical: 8),
                      scrollDirection: Axis.horizontal,
                      separatorBuilder: (BuildContext context, int index) {
                        return SizedBox(width: 8);
                      },
                      itemCount: _categories['tags'].length + 1,
                      itemBuilder: (BuildContext context, int index) {
                        return Tag(
                          text: index == 0
                              ? t.all
                              : _categories['tags'][index - 1]['title'],
                          selected: _tagSelected == index,
                          onTap: () {
                            setState(() {
                              _tagSelected = index;
                              _page = 0;
                              _more = true;
                              _requesting = true;
                              _loadLatest();
                            });
                          },
                        );
                      },
                    ),
                  ),
                ),
              ),
              Padding(
                padding: EdgeInsets.only(left: 16, right: 16, bottom: 8),
                child: SizedBox(
                  height: 48,
                  child: Material(
                    type: MaterialType.transparency,
                    child: ListView.separated(
                      padding: EdgeInsets.symmetric(vertical: 8),
                      scrollDirection: Axis.horizontal,
                      separatorBuilder: (BuildContext context, int index) {
                        return SizedBox(width: 8);
                      },
                      itemCount: _categories['gender'].length + 1,
                      itemBuilder: (BuildContext context, int index) {
                        return Tag(
                          text: index == 0
                              ? t.all
                              : _categories['gender'][index - 1]['title'],
                          selected: _genderSelected == index,
                          onTap: () {
                            setState(() {
                              _genderSelected = index;
                              _page = 0;
                              _more = true;
                              _requesting = true;
                              _loadLatest();
                            });
                          },
                        );
                      },
                    ),
                  ),
                ),
              ),
              Expanded(
                child: RefreshIndicator(
                  onRefresh: () async {
                    _more = true;
                    _page = 0;
                    await _loadData();
                    await _loadLatest();
                  },
                  child: _latestLoading
                      ? Loading()
                      : Padding(
                          padding: EdgeInsets.only(left: 16, right: 16),
                          child: Stack(
                            children: [
                              CustomScrollView(
                                controller: _controller,
                                slivers: [
                                  SliverToBoxAdapter(
                                    child: SizedBox(height: 16),
                                  ),
                                  SliverGrid.builder(
                                    itemCount: _latest.length,
                                    gridDelegate:
                                        SliverGridDelegateWithFixedCrossAxisCount(
                                          crossAxisCount: 3,
                                          crossAxisSpacing: 16,
                                          mainAxisSpacing: 16,
                                          mainAxisExtent: height + 52,
                                        ),
                                    itemBuilder: (context, index) {
                                      return FilmItem(
                                        id: _latest[index]['id'],
                                        width: width,
                                        height: height,
                                        image: _latest[index]['image'],
                                        title: _latest[index]['title'],
                                        recommend: true,
                                      );
                                    },
                                  ),
                                  _more
                                      ? SliverToBoxAdapter(
                                          child: Padding(
                                            padding: EdgeInsets.only(
                                              top: 32,
                                              bottom: 16,
                                            ),
                                            child: Loading(),
                                          ),
                                        )
                                      : SliverToBoxAdapter(
                                          child: Padding(
                                            padding: EdgeInsets.only(
                                              top: 32,
                                              bottom: 16,
                                            ),
                                            child: NoMore(),
                                          ),
                                        ),

                                  SliverToBoxAdapter(
                                    child: SizedBox(height: 16),
                                  ),
                                ],
                              ),
                              if (_requesting && _latest.isNotEmpty)
                                SizedBox(height: 80, child: Loading()),
                            ],
                          ),
                        ),
                ),
              ),
            ],
          );
  }
}

class Tag extends StatelessWidget {
  const Tag({
    super.key,
    required this.text,
    required this.selected,
    required this.onTap,
  });

  final String text;
  final bool selected;
  final void Function() onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Ink(
        padding: EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: selected ? Colors.redAccent.withAlpha(60) : Colors.white10,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Center(
          child: Text(
            text,
            style: TextStyle(
              height: 1,
              fontSize: 14,
              color: selected ? Colors.red.shade400 : Colors.white60,
            ),
          ),
        ),
      ),
    );
  }
}
