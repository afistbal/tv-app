import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:yogotv/api.dart';
import 'package:yogotv/app_config.dart';
import 'package:yogotv/components/empty.dart';
import 'package:yogotv/components/lazy_image.dart';
import 'package:yogotv/components/loading.dart';
import 'package:yogotv/global.dart';
import 'package:yogotv/i18n/strings.g.dart';

class Home extends StatefulWidget {
  const Home({super.key});

  @override
  State<Home> createState() => _Home();
}

class _Home extends State<Home>
    with AutomaticKeepAliveClientMixin, SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    Future.delayed(Duration(milliseconds: 500), () {
      _prefetchMovieGridTab('new');
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _HomeToolbar(),
            SizedBox(height: 8),
            SizedBox(
              height: 40,
              child: TabBar(
                controller: _tabController,
                isScrollable: true,
                tabAlignment: TabAlignment.start,
                dividerColor: Colors.transparent,
                indicatorSize: TabBarIndicatorSize.label,
                indicatorColor: Colors.white,
                indicatorWeight: 2,
                labelColor: Colors.white,
                unselectedLabelColor: Colors.white.withAlpha(204),
                labelStyle: TextStyle(
                  fontSize: 16,
                  height: 1,
                  fontWeight: FontWeight.w800,
                ),
                unselectedLabelStyle: TextStyle(
                  fontSize: 16,
                  height: 1,
                  fontWeight: FontWeight.w500,
                ),
                labelPadding: EdgeInsets.symmetric(horizontal: 15),
                tabs: [
                  Tab(text: t.popular),
                  Tab(text: t.new_string),
                  Tab(text: t.categories),
                ],
              ),
            ),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _MovieGrid(
                    key: PageStorageKey('home-popular'),
                    tab: 'popular',
                    columns: 2,
                  ),
                  _MovieGrid(
                    key: PageStorageKey('home-new'),
                    tab: 'new',
                    columns: 2,
                  ),
                  _CategoryMovieGrid(key: PageStorageKey('home-category')),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HomeToolbar extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(15, 4, 15, 0),
      child: Row(
        children: [
          Expanded(
            child: InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () => context.push('/search'),
              child: Container(
                height: 36,
                padding: EdgeInsets.symmetric(horizontal: 10),
                decoration: BoxDecoration(
                  color: Color(0xff151515),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(
                      LucideIcons.search,
                      size: 16,
                      color: Color(0xff999999),
                    ),
                    SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        t.search_placeholder,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Color(0xff999999),
                          fontSize: 14,
                          height: 1,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          SizedBox(width: 10),
          InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () => context.push('/membership'),
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: 4),
              child: Image.asset(
                'assets/images/android/ic_home_vip.png',
                height: 28,
                fit: BoxFit.contain,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MovieGrid extends StatefulWidget {
  const _MovieGrid({super.key, required this.tab, required this.columns});

  final String tab;
  final int columns;

  @override
  State<_MovieGrid> createState() => _MovieGridState();
}

class _MovieGridState extends State<_MovieGrid>
    with AutomaticKeepAliveClientMixin {
  late final ScrollController _scrollController;
  final List<dynamic> _items = [];

  int _page = 0;
  bool _loading = true;
  bool _requesting = false;
  bool _more = true;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController(
      initialScrollOffset: _scrollOffsets[widget.tab] ?? 0,
    );
    _scrollController.addListener(_onScroll);
    final cache = _discoverCache[widget.tab];
    if (cache != null) {
      _items.addAll(cache.items);
      _page = cache.page;
      _more = cache.more;
      _loading = false;
    } else {
      _load(page: 1);
    }
  }

  @override
  void dispose() {
    if (_scrollController.hasClients) {
      _scrollOffsets[widget.tab] = _scrollController.offset;
    }
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients || !_more || _requesting) {
      return;
    }
    _scrollOffsets[widget.tab] = _scrollController.offset;
    final position = _scrollController.position;
    if (position.maxScrollExtent - position.pixels < 480) {
      _load(page: _page + 1);
    }
  }

  Future<void> _refresh() async {
    await _load(page: 1, refresh: true);
  }

  Future<void> _load({required int page, bool refresh = false}) async {
    if (_requesting || (!refresh && page <= _page) || (!refresh && !_more)) {
      return;
    }

    if (!refresh && page == 1) {
      final prefetch = _discoverPrefetches[widget.tab];
      if (prefetch != null) {
        setState(() {
          _requesting = true;
        });
        await prefetch;
        if (!mounted) {
          return;
        }
        final cache = _discoverCache[widget.tab];
        if (cache != null) {
          setState(() {
            _items
              ..clear()
              ..addAll(cache.items);
            _page = cache.page;
            _more = cache.more;
            _loading = false;
            _requesting = false;
          });
          return;
        }
      }
    }

    setState(() {
      _requesting = true;
      if (refresh) {
        _loading = true;
        _more = true;
      }
    });

    final result = await api<Map<String, dynamic>>(
      'movie/discover',
      method: Method.post,
      data: {'page': page, 'pageSize': 20, 'tab': widget.tab},
      loading: false,
    );

    if (!mounted) {
      return;
    }

    final payload = result.d;
    final rows = payload == null ? <dynamic>[] : _rowsFromPayload(payload);
    final nextPage = payload == null ? page : _currentPage(payload, page);
    final more = payload != null && _hasMore(payload, nextPage, rows.length);

    if (page == 1 && payload != null) {
      _discoverCache[widget.tab] = _DiscoverCache(
        items: List<dynamic>.of(rows),
        page: nextPage,
        more: more,
      );
    }

    setState(() {
      if (refresh || page == 1) {
        _items
          ..clear()
          ..addAll(rows);
      } else {
        _items.addAll(rows);
      }
      _page = nextPage;
      _more = more;
      _loading = false;
      _requesting = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    if (_loading && _items.isEmpty) {
      return Loading();
    }

    if (_items.isEmpty) {
      return RefreshIndicator(
        color: Colors.white,
        backgroundColor: Color(0xffff3d5d),
        onRefresh: _refresh,
        child: ListView(
          physics: AlwaysScrollableScrollPhysics(),
          children: [SizedBox(height: 360, child: Empty())],
        ),
      );
    }

    return RefreshIndicator(
      color: Colors.white,
      backgroundColor: Color(0xffff3d5d),
      onRefresh: _refresh,
      child: CustomScrollView(
        controller: _scrollController,
        cacheExtent: 360,
        physics: AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverPadding(
            padding: EdgeInsets.fromLTRB(15, 0, 15, 24),
            sliver: _MovieSliverGrid(items: _items, columns: widget.columns),
          ),
          SliverToBoxAdapter(
            child: SizedBox(
              height: 56,
              child: _more && _items.isNotEmpty ? Loading() : null,
            ),
          ),
        ],
      ),
    );
  }
}

class _CategoryMovieGrid extends StatefulWidget {
  const _CategoryMovieGrid({super.key});

  @override
  State<_CategoryMovieGrid> createState() => _CategoryMovieGridState();
}

class _CategoryMovieGridState extends State<_CategoryMovieGrid>
    with AutomaticKeepAliveClientMixin {
  late final ScrollController _scrollController;
  final List<dynamic> _items = [];
  List<dynamic> _tags = [];

  int _selectedTag = 0;
  int _page = 0;
  bool _loading = true;
  bool _requesting = false;
  bool _more = true;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController(
      initialScrollOffset: _scrollOffsets['category'] ?? 0,
    );
    _scrollController.addListener(_onScroll);
    final cache = _categoryCache;
    if (cache != null) {
      _tags = List<dynamic>.of(cache.tags);
      _items.addAll(cache.items);
      _selectedTag = cache.selectedTag;
      _page = cache.page;
      _more = cache.more;
      _loading = false;
    } else {
      _loadTags();
    }
  }

  @override
  void dispose() {
    if (_scrollController.hasClients) {
      _scrollOffsets['category'] = _scrollController.offset;
    }
    _saveCategoryCache();
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients || !_more || _requesting) {
      return;
    }
    _scrollOffsets['category'] = _scrollController.offset;
    final position = _scrollController.position;
    if (position.maxScrollExtent - position.pixels < 480) {
      _loadMovies(page: _page + 1);
    }
  }

  Future<void> _loadTags() async {
    final result = await api<List<dynamic>>(
      'movie/tag-labels',
      method: Method.post,
      loading: false,
    );

    if (!mounted) {
      return;
    }

    setState(() {
      _tags = result.d ?? [];
    });
    await _loadMovies(page: 1, refresh: true);
  }

  Future<void> _refresh() async {
    await _loadMovies(page: 1, refresh: true);
  }

  Future<void> _selectTag(int index) async {
    if (index == _selectedTag) {
      return;
    }
    setState(() {
      _selectedTag = index;
      _loading = true;
      _items.clear();
      _page = 0;
      _more = true;
    });
    _scrollOffsets['category'] = 0;
    _categoryCache = null;
    await _loadMovies(page: 1, refresh: true);
  }

  Future<void> _loadMovies({required int page, bool refresh = false}) async {
    if (_requesting || (!refresh && page <= _page) || (!refresh && !_more)) {
      return;
    }

    setState(() {
      _requesting = true;
      if (refresh) {
        _loading = true;
        _more = true;
      }
    });

    final tag = _tagId(_tags.elementAtOrNull(_selectedTag));
    final result = await api<Map<String, dynamic>>(
      'movie',
      method: Method.post,
      data: {'page': page, if (tag.isNotEmpty) 'tag': tag},
      loading: false,
    );

    if (!mounted) {
      return;
    }

    final payload = result.d;
    final rows = payload == null ? <dynamic>[] : _rowsFromPayload(payload);
    final nextPage = payload == null ? page : _currentPage(payload, page);

    setState(() {
      if (refresh || page == 1) {
        _items
          ..clear()
          ..addAll(rows);
      } else {
        _items.addAll(rows);
      }
      _page = nextPage;
      _more = payload != null && _hasMore(payload, nextPage, rows.length);
      _loading = false;
      _requesting = false;
    });
    _saveCategoryCache();
  }

  void _saveCategoryCache() {
    _categoryCache = _CategoryCache(
      tags: List<dynamic>.of(_tags),
      items: List<dynamic>.of(_items),
      selectedTag: _selectedTag,
      page: _page,
      more: _more,
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    return Column(
      children: [
        if (_tags.isNotEmpty)
          SizedBox(
            height: 44,
            child: ListView.separated(
              padding: EdgeInsets.symmetric(horizontal: 15),
              scrollDirection: Axis.horizontal,
              itemBuilder: (context, index) {
                final active = index == _selectedTag;
                return Center(
                  child: InkWell(
                    borderRadius: BorderRadius.circular(999),
                    onTap: () => _selectTag(index),
                    child: AnimatedContainer(
                      duration: Duration(milliseconds: 180),
                      padding: EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 7,
                      ),
                      decoration: BoxDecoration(
                        color: active ? Color(0xffff3d5d) : Color(0xff151515),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        _tagLabel(_tags[index]),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          height: 1,
                          fontWeight: active
                              ? FontWeight.w700
                              : FontWeight.w500,
                        ),
                      ),
                    ),
                  ),
                );
              },
              separatorBuilder: (context, index) => SizedBox(width: 8),
              itemCount: _tags.length,
            ),
          ),
        Expanded(
          child: _loading && _items.isEmpty
              ? Loading()
              : _items.isEmpty
              ? RefreshIndicator(
                  color: Colors.white,
                  backgroundColor: Color(0xffff3d5d),
                  onRefresh: _refresh,
                  child: ListView(
                    physics: AlwaysScrollableScrollPhysics(),
                    children: [SizedBox(height: 320, child: Empty())],
                  ),
                )
              : RefreshIndicator(
                  color: Colors.white,
                  backgroundColor: Color(0xffff3d5d),
                  onRefresh: _refresh,
                  child: CustomScrollView(
                    controller: _scrollController,
                    cacheExtent: 360,
                    physics: AlwaysScrollableScrollPhysics(),
                    slivers: [
                      SliverPadding(
                        padding: EdgeInsets.fromLTRB(15, 0, 15, 24),
                        sliver: _MovieSliverGrid(items: _items, columns: 3),
                      ),
                      SliverToBoxAdapter(
                        child: SizedBox(
                          height: 56,
                          child: _more && _items.isNotEmpty ? Loading() : null,
                        ),
                      ),
                    ],
                  ),
                ),
        ),
      ],
    );
  }
}

class _MovieSliverGrid extends StatelessWidget {
  const _MovieSliverGrid({required this.items, required this.columns});

  final List<dynamic> items;
  final int columns;

  static const int _debugImageLimit = int.fromEnvironment(
    'HOME_IMAGE_LIMIT',
    defaultValue: 0,
  );

  @override
  Widget build(BuildContext context) {
    final gap = columns == 2 ? 9.0 : 10.0;

    final visibleItems = _debugImageLimit > 0
        ? items.take(_debugImageLimit).toList()
        : items;

    return SliverGrid.builder(
      itemCount: visibleItems.length,
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: columns,
        crossAxisSpacing: gap,
        mainAxisSpacing: 12,
        childAspectRatio: columns == 2 ? 0.61 : 0.56,
      ),
      itemBuilder: (context, index) {
        return _MovieCard(item: visibleItems[index]);
      },
    );
  }
}

class _MovieCard extends StatelessWidget {
  const _MovieCard({required this.item});

  static const bool _debugDisableImages = bool.fromEnvironment(
    'HOME_DISABLE_IMAGES',
  );

  final dynamic item;

  @override
  Widget build(BuildContext context) {
    final map = item is Map ? item as Map : <String, dynamic>{};
    final imageUrl = _posterUrl(map);
    final title = _text(map['title'] ?? map['book_title'] ?? map['name']);
    final tags = _tagLine(map);

    return RepaintBoundary(
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () => _openPlay(context, map),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth.isFinite
                ? constraints.maxWidth
                : MediaQuery.sizeOf(context).width / 2;
            final pixelRatio = MediaQuery.devicePixelRatioOf(context).clamp(
              1.0,
              3.0,
            );
            final cacheWidth = (width * pixelRatio).round();
            final cacheHeight = (width * 4 / 3 * pixelRatio).round();

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AspectRatio(
                  aspectRatio: 3 / 4,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: imageUrl.isEmpty || _debugDisableImages
                        ? _PosterPlaceholder()
                        : LazyImage(
                            url: imageUrl,
                            width: double.infinity,
                            height: double.infinity,
                            fit: BoxFit.cover,
                            cacheWidth: cacheWidth,
                            cacheHeight: cacheHeight,
                          ),
                  ),
                ),
                SizedBox(height: 8),
                Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    height: 1.18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (tags.isNotEmpty) ...[
                  SizedBox(height: 4),
                  Text(
                    tags,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Color(0xff999999),
                      fontSize: 12,
                      height: 1.15,
                    ),
                  ),
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}

class _DiscoverCache {
  const _DiscoverCache({
    required this.items,
    required this.page,
    required this.more,
  });

  final List<dynamic> items;
  final int page;
  final bool more;
}

class _CategoryCache {
  const _CategoryCache({
    required this.tags,
    required this.items,
    required this.selectedTag,
    required this.page,
    required this.more,
  });

  final List<dynamic> tags;
  final List<dynamic> items;
  final int selectedTag;
  final int page;
  final bool more;
}

final Map<String, _DiscoverCache> _discoverCache = {};
final Map<String, Future<void>> _discoverPrefetches = {};
final Map<String, double> _scrollOffsets = {};
_CategoryCache? _categoryCache;

Future<void> _prefetchMovieGridTab(String tab) {
  if (_discoverCache.containsKey(tab)) {
    return Future.value();
  }
  final existing = _discoverPrefetches[tab];
  if (existing != null) {
    return existing;
  }

  final future = api<Map<String, dynamic>>(
    'movie/discover',
    method: Method.post,
    data: {'page': 1, 'pageSize': 20, 'tab': tab},
    loading: false,
  ).then((result) {
    final payload = result.d;
    if (payload == null) {
      return;
    }
    final rows = _rowsFromPayload(payload);
    final page = _currentPage(payload, 1);
    _discoverCache[tab] = _DiscoverCache(
      items: List<dynamic>.of(rows),
      page: page,
      more: _hasMore(payload, page, rows.length),
    );
  }).whenComplete(() {
    _discoverPrefetches.remove(tab);
  });

  _discoverPrefetches[tab] = future;
  return future;
}

class _PosterPlaceholder extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      color: Color(0xff151515),
      alignment: Alignment.center,
      child: Text(
        AppConfig.current.brandDisplayName,
        textAlign: TextAlign.center,
        style: TextStyle(
          color: Colors.white24,
          fontSize: 12,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

List<dynamic> _rowsFromPayload(Map<String, dynamic> payload) {
  final data = payload['data'] ?? payload['list'] ?? payload['rows'];
  return data is List ? data : <dynamic>[];
}

int _currentPage(Map<String, dynamic> payload, int fallback) {
  final page = payload['current_page'] ?? payload['currentPage'] ?? payload['page'];
  return int.tryParse(_text(page)) ?? fallback;
}

bool _hasMore(Map<String, dynamic> payload, int page, int rowCount) {
  final perPage =
      int.tryParse(_text(payload['per_page'] ?? payload['pageSize'])) ?? 20;
  final total = int.tryParse(
    _text(payload['count'] ?? payload['total'] ?? payload['totalCount']),
  );
  if (total != null && total > 0) {
    return page * perPage < total;
  }
  return rowCount >= perPage;
}

void _openPlay(BuildContext context, dynamic item) {
  if (item is! Map) {
    return;
  }

  final id = item['id'] ?? item['movie_id'];
  if (id == null) {
    return;
  }

  context.push('/play', extra: {'id': id});
}

String _posterUrl(dynamic item) {
  if (item is! Map) {
    return '';
  }
  final path = _posterPath(item);
  if (path.isEmpty) {
    return '';
  }
  return Global.static(path);
}

String _posterPath(Map item) {
  final rename = item['is_rename'];
  final id = item['movie_id'] ?? item['id'];
  final isRename = rename == 1 || rename == '1' || rename == true;
  if (isRename && id != null && _text(id).isNotEmpty) {
    return 'movie_images/$id.webp';
  }

  return _text(
    item['image'] ??
        item['cover'] ??
        item['poster'] ??
        item['cover_url'] ??
        item['coverUrl'] ??
        item['image_url'],
  );
}

String _tagLine(Map item) {
  final tags = item['tags'] ?? item['tagList'] ?? item['tag_list'];
  if (tags is! List) {
    return _text(item['tags_text'] ?? item['tag']);
  }

  final names = tags
      .map((tag) {
        if (tag is Map) {
          return _readableTag(
            _text(
              tag['local_label'] ??
                  tag['unique_id'] ??
                  tag['source_tag_name'] ??
                  tag['matched_unique_id'] ??
                  tag['label'] ??
                  tag['title'] ??
                  tag['name'],
            ),
          );
        }
        return _readableTag(_text(tag));
      })
      .where((name) => name.isNotEmpty)
      .toList();
  return names.join('  ');
}

String _tagLabel(dynamic tag) {
  if (tag is Map) {
    return _text(tag['local_label'] ?? tag['name'] ?? tag['source_tag_name']);
  }
  return _text(tag);
}

String _tagId(dynamic tag) {
  if (tag is Map) {
    return _text(
      tag['matched_unique_id'] ??
          tag['source_tag_name'] ??
          tag['unique_id'] ??
          tag['name'],
    );
  }
  return '';
}

String _readableTag(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty || RegExp(r'^[0-9a-fA-F]{12,}$').hasMatch(trimmed)) {
    return '';
  }
  return trimmed
      .replaceAll('_', '')
      .split(' ')
      .where((part) => part.trim().isNotEmpty)
      .map((part) {
        if (part.isEmpty) {
          return part;
        }
        return part[0].toUpperCase() + part.substring(1);
      })
      .join(' ');
}

String _text(dynamic value) {
  if (value == null) {
    return '';
  }
  return value.toString();
}
