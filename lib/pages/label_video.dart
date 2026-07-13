import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';
import 'package:yogotv/api.dart';
import 'package:yogotv/components/lazy_image.dart';
import 'package:yogotv/components/loading.dart';
import 'package:yogotv/i18n/strings.g.dart';

class LabelVideo extends StatefulWidget {
  const LabelVideo({super.key, required this.title, required this.tagId});

  final String title;
  final String tagId;

  @override
  State<LabelVideo> createState() => _LabelVideoState();
}

class _LabelVideoState extends State<LabelVideo>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _Toolbar(title: widget.title, onBack: context.pop),
            SizedBox(
              height: 44,
              child: TabBar(
                controller: _tabController,
                dividerColor: Colors.transparent,
                indicatorColor: Color(0xffff3d5d),
                indicatorSize: TabBarIndicatorSize.label,
                labelColor: Colors.white,
                unselectedLabelColor: Color(0xff999999),
                labelStyle: TextStyle(fontSize: 14, height: 1),
                tabs: [
                  Tab(text: t.popular),
                  Tab(text: t.new_string),
                ],
              ),
            ),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _LabelVideoList(tagId: widget.tagId, type: 'popular'),
                  _LabelVideoList(tagId: widget.tagId, type: 'new'),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LabelVideoList extends StatefulWidget {
  const _LabelVideoList({required this.tagId, required this.type});

  final String tagId;
  final String type;

  @override
  State<_LabelVideoList> createState() => _LabelVideoListState();
}

class _LabelVideoListState extends State<_LabelVideoList>
    with AutomaticKeepAliveClientMixin {
  final _scrollController = ScrollController();
  final List<dynamic> _items = [];
  int _page = 1;
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = true;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _load(refresh: true);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_loading || _loadingMore || !_hasMore) {
      return;
    }
    if (_scrollController.position.extentAfter < 420) {
      _load();
    }
  }

  Future<void> _load({bool refresh = false}) async {
    if (_loadingMore || (!refresh && !_hasMore)) {
      return;
    }
    final page = refresh ? 1 : _page + 1;
    setState(() {
      if (refresh) {
        _loading = true;
      } else {
        _loadingMore = true;
      }
    });
    final result = await api<Map<String, dynamic>>(
      'movie/tag-list',
      method: Method.post,
      data: {'page': page, 'tag': widget.tagId, 'type': widget.type},
      loading: false,
    );
    if (!mounted) {
      return;
    }
    final rows = _pageRows(result.d);
    setState(() {
      if (refresh) {
        _items
          ..clear()
          ..addAll(rows);
      } else {
        _items.addAll(rows);
      }
      _page = _pageNumber(result.d, page);
      _hasMore = _hasNextPage(result.d, rows);
      _loading = false;
      _loadingMore = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (_loading && _items.isEmpty) {
      return Loading();
    }
    return RefreshIndicator(
      color: Colors.white,
      backgroundColor: Color(0xff222222),
      onRefresh: () => _load(refresh: true),
      child: ListView.builder(
        controller: _scrollController,
        physics: AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.fromLTRB(15, 12, 15, 16),
        itemCount: _items.length + (_loadingMore ? 1 : 0),
        itemBuilder: (context, index) {
          if (index >= _items.length) {
            return Padding(padding: EdgeInsets.all(16), child: Loading());
          }
          return _LabelVideoItem(item: _items[index]);
        },
      ),
    );
  }
}

class _LabelVideoItem extends StatelessWidget {
  const _LabelVideoItem({required this.item});

  final dynamic item;

  @override
  Widget build(BuildContext context) {
    final map = _asMap(item);
    final title = _text(map['title']);
    final image = _text(map['image'] ?? map['coverUrl'] ?? map['cover_url']);
    final tags = _tagLine(map);
    final id = map['id'] ?? map['movie_id'] ?? map['movieId'] ?? map['moveId'];
    return InkWell(
      onTap: id == null ? null : () => context.push('/play', extra: {'id': id}),
      child: SizedBox(
        height: 118,
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: image.isEmpty
                  ? Container(width: 84, height: 112, color: Color(0xff212121))
                  : LazyImage(
                      url: image,
                      width: 84,
                      height: 112,
                      fit: BoxFit.cover,
                    ),
            ),
            SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      height: 1.2,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  if (tags.isNotEmpty) ...[
                    SizedBox(height: 8),
                    Text(
                      tags,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: Color(0xff999999), fontSize: 12),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Toolbar extends StatelessWidget {
  const _Toolbar({required this.title, required this.onBack});

  final String title;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 44,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Positioned(
            left: 15,
            child: InkWell(
              onTap: onBack,
              child: SvgPicture.asset(
                'assets/images/android/ic_toolbar_back.svg',
                width: 24,
                height: 24,
              ),
            ),
          ),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 56),
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: Colors.white, fontSize: 17),
            ),
          ),
        ],
      ),
    );
  }
}

List<dynamic> _pageRows(Map<String, dynamic>? data) {
  final value = data?['data'] ?? data?['list'] ?? data?['items'];
  return value is List ? value : [];
}

int _pageNumber(Map<String, dynamic>? data, int fallback) {
  final value = data?['current_page'] ?? data?['currentPage'] ?? data?['page'];
  return int.tryParse('$value') ?? fallback;
}

bool _hasNextPage(Map<String, dynamic>? data, List<dynamic> rows) {
  final next = data?['next_page_url'] ?? data?['nextPageUrl'];
  if (next != null) {
    return _text(next).isNotEmpty;
  }
  final total = int.tryParse('${data?['total'] ?? ''}');
  final perPage = int.tryParse(
    '${data?['per_page'] ?? data?['perPage'] ?? ''}',
  );
  final page = int.tryParse('${data?['current_page'] ?? data?['page'] ?? ''}');
  if (total != null && perPage != null && page != null && perPage > 0) {
    return page * perPage < total;
  }
  return rows.length >= 10;
}

Map<String, dynamic> _asMap(dynamic value) {
  if (value is Map<String, dynamic>) {
    return value;
  }
  if (value is Map) {
    return Map<String, dynamic>.from(value);
  }
  return {};
}

String _tagLine(Map<String, dynamic> item) {
  final raw = item['tags'] ?? item['tagList'] ?? item['tag_list'];
  if (raw is! List) {
    return '';
  }
  return raw.map(_tagName).where((tag) => tag.isNotEmpty).take(3).join('  ');
}

String _tagName(dynamic tag) {
  if (tag is Map) {
    final raw = _text(
      tag['unique_id'] ??
          tag['source_tag_name'] ??
          tag['local_label'] ??
          tag['name'],
    );
    return _readableTag(raw);
  }
  return _readableTag(_text(tag));
}

String _readableTag(String value) {
  final normalized = value.trim().replaceAll('_', ' ');
  if (normalized.isEmpty || RegExp(r'^[0-9a-fA-F]{6,}$').hasMatch(normalized)) {
    return '';
  }
  return normalized
      .split(RegExp(r'\s+'))
      .where((word) => word.isNotEmpty)
      .map((word) {
        final first = word.substring(0, 1).toUpperCase();
        final rest = word.length > 1 ? word.substring(1) : '';
        return '$first$rest';
      })
      .join(' ');
}

String _text(dynamic value) => value?.toString().trim() ?? '';
