import 'package:flutter/material.dart';
import 'package:visibility_detector/visibility_detector.dart';
import 'package:yogotv/api.dart';
import 'package:yogotv/components/empty.dart';
import 'package:yogotv/components/loading.dart';
import 'package:yogotv/global.dart';
import 'package:yogotv/i18n/strings.g.dart';
import 'package:yogotv/widgets/film_item.dart';

class MyList extends StatefulWidget {
  final bool load;
  const MyList({super.key, required this.load});

  @override
  State<StatefulWidget> createState() {
    return _MyList();
  }
}

class _MyList extends State<MyList> {
  late final PageController _controller;
  bool _load = false;
  int _current = 0;

  @override
  void initState() {
    super.initState();
    _controller = PageController();
  }

  @override
  void didUpdateWidget(covariant MyList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.load && !_load) {
      setState(() {
        _load = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          height: kToolbarHeight + MediaQuery.of(context).padding.top,
          width: MediaQuery.of(context).size.width,
          color: Theme.of(context).appBarTheme.backgroundColor,
          alignment: Alignment.bottomLeft,
          padding: EdgeInsets.only(left: 16, bottom: 16, right: 16),
          child: Row(
            spacing: 16,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              GestureDetector(
                onTap: () {
                  setState(() {
                    _current = 0;
                    _controller.jumpToPage(0);
                  });
                },
                child: Text(
                  t.my_list,
                  style: TextStyle(
                    fontSize: 20,
                    height: 1,
                    color: _current == 0
                        ? Theme.of(context).colorScheme.primary
                        : null,
                  ),
                ),
              ),
              GestureDetector(
                onTap: () {
                  setState(() {
                    _current = 1;
                    _controller.jumpToPage(1);
                  });
                },
                child: Text(
                  t.history,
                  style: TextStyle(
                    fontSize: 20,
                    height: 1,
                    color: _current == 1
                        ? Theme.of(context).colorScheme.primary
                        : null,
                  ),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: _load
              ? PageView(
                  controller: _controller,
                  onPageChanged: (value) {
                    setState(() {
                      _current = value;
                    });
                  },
                  children: [
                    _Content(url: 'movie/my-list'),
                    _Content(url: 'movie/history'),
                  ],
                )
              : Container(),
        ),
      ],
    );
  }
}

class _Content extends StatefulWidget {
  final String url;

  const _Content({required this.url});
  @override
  State<StatefulWidget> createState() {
    return _ContentState();
  }
}

class _ContentState extends State<_Content> with AutomaticKeepAliveClientMixin {
  final _controller = ScrollController();
  List<dynamic> _list = [];
  int _page = 0;
  bool _more = true;
  bool _loading = true;

  @override
  bool get wantKeepAlive => true;

  @override
  initState() {
    super.initState();

    _controller.addListener(() {
      if (_controller.offset == _controller.position.maxScrollExtent &&
          _controller.position.maxScrollExtent != 0) {
        _loadData(page: _page + 1);
      }
    });
    _loadData();
  }

  _loadData({page = 1}) async {
    if (!_more || page <= _page) {
      return;
    }
    final result = await api(widget.url, query: {'page': page});
    if (result.c != 0) {
      return;
    }
    setState(() {
      if (page == 1) {
        _list = result.d['data'];
      } else {
        _list = [..._list, ...result.d['data']];
      }

      _more = result.d['data'].length == 24;
      _page = page;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final width = (MediaQuery.of(context).size.width - 48) / 2;
    final height = width / 3 * 4;
    return VisibilityDetector(
      key: Key(widget.url),
      onVisibilityChanged: (info) {
        if (info.visibleBounds.isEmpty) {
          return;
        }
        if (widget.url == 'movie/my-list' &&
            Global.sp.getBool('update_favorite') == true) {
          Global.sp.remove('update_favorite');
          _page = 0;
          _more = true;
          _loadData();
        }
        if (widget.url == 'movie/history' &&
            Global.sp.getBool('update_history') == true) {
          Global.sp.remove('update_history');
          _page = 0;
          _more = true;
          _loadData();
        }
      },
      child: _loading
          ? Loading()
          : RefreshIndicator(
              onRefresh: () async {
                _list = [];
                _more = true;
                _page = 0;
                await _loadData();
              },
              child: _list.isEmpty
                  ? ListView(
                      itemExtent: MediaQuery.of(context).size.width,
                      children: [Empty()],
                    )
                  : GridView.builder(
                      controller: _controller,
                      physics: AlwaysScrollableScrollPhysics(),
                      padding: EdgeInsets.all(16),
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 2,
                        mainAxisSpacing: 16,
                        crossAxisSpacing: 16,
                        mainAxisExtent: height + 52,
                      ),
                      itemCount: _list.length,
                      itemBuilder: (context, index) {
                        return FilmItem(
                          id: _list[index]['movie_id'],
                          width: width,
                          height: height,
                          image: _list[index]['image'],
                          title: _list[index]['title'],
                          recommend: false,
                        );
                      },
                    ),
            ),
    );
  }
}
