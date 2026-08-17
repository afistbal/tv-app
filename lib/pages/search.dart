import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:yogotv/api.dart';
import 'package:yogotv/components/lazy_image.dart';
import 'package:yogotv/global.dart';
import 'package:yogotv/i18n/strings.g.dart';
import 'package:yogotv/movie_cover.dart';
import 'package:yogotv/movie_id.dart';

class Search extends StatefulWidget {
  const Search({super.key});

  @override
  State<Search> createState() => _Search();
}

class _Search extends State<Search> {
  static const _historyKey = 'search_video_keywords';

  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  final _scrollController = ScrollController();

  Timer? _searchTimer;
  List<dynamic> _results = [];
  List<dynamic> _popular = [];
  List<String> _history = [];

  int _page = 1;
  bool _expandedHistory = false;
  bool _loading = false;
  bool _loadingPopular = true;
  bool _requesting = false;
  bool _hasNext = false;
  bool _searched = false;
  int _searchGeneration = 0;
  String _requestingKeyword = '';
  String _lastSearchedKeyword = '';

  @override
  void initState() {
    super.initState();
    _history = Global.sp.getStringList(_historyKey) ?? [];
    _scrollController.addListener(_onScroll);
    _controller.addListener(_onKeywordChanged);
    _loadPopular();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _focusNode.requestFocus();
      }
    });
  }

  @override
  void dispose() {
    _searchTimer?.cancel();
    _controller.removeListener(_onKeywordChanged);
    _controller.dispose();
    _focusNode.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _onKeywordChanged() {
    _searchTimer?.cancel();
    final keyword = _controller.text.trim();
    if (keyword.isEmpty) {
      setState(() {
        _searched = false;
        _loading = false;
        _requesting = false;
        _results = [];
        _hasNext = false;
        _page = 1;
        _searchGeneration++;
        _requestingKeyword = '';
        _lastSearchedKeyword = '';
      });
      return;
    }
    _searchTimer = Timer(Duration(seconds: 1), () {
      _search(keyword, page: 1);
    });
  }

  void _onScroll() {
    if (!_searched || !_hasNext || _loading || _requesting) {
      return;
    }
    if (!_scrollController.hasClients) {
      return;
    }
    final position = _scrollController.position;
    if (position.maxScrollExtent - position.pixels < 420) {
      _search(_controller.text.trim(), page: _page + 1);
    }
  }

  Future<void> _loadPopular() async {
    setState(() {
      _loadingPopular = true;
    });
    final result = await api<Map<String, dynamic>>(
      'feed/search_feed',
      method: Method.post,
      data: {'page': 1},
      loading: false,
    );
    if (!mounted) {
      return;
    }
    setState(() {
      _popular = _pageItems(result.d);
      _loadingPopular = false;
    });
  }

  Future<void> _search(
    String keyword, {
    required int page,
    bool force = false,
  }) async {
    if (keyword.isEmpty || (page > 1 && _requesting)) {
      return;
    }
    if (!force &&
        page == 1 &&
        _searched &&
        !_loading &&
        !_requesting &&
        _lastSearchedKeyword.toLowerCase() == keyword.toLowerCase()) {
      return;
    }
    if (page == 1 &&
        _requesting &&
        _requestingKeyword.toLowerCase() == keyword.toLowerCase()) {
      return;
    }

    final requestGeneration = page == 1
        ? ++_searchGeneration
        : _searchGeneration;

    if (page == 1) {
      _requesting = true;
      _requestingKeyword = keyword;
    }

    if (page == 1) {
      await _addHistory(keyword);
      setState(() {
        _searched = true;
        _loading = true;
        _requesting = true;
        _requestingKeyword = keyword;
        _page = 1;
        _hasNext = false;
        _results = [];
      });
    } else {
      setState(() {
        _requesting = true;
      });
    }

    final result = await api<Map<String, dynamic>>(
      'movie',
      method: Method.post,
      data: {'page': page, 'keyword': keyword, 'tag': ''},
      loading: false,
    );

    if (!mounted ||
        requestGeneration != _searchGeneration ||
        keyword != _controller.text.trim()) {
      return;
    }

    final items = _pageItems(result.d);
    setState(() {
      if (page == 1) {
        _results = items;
      } else {
        _results = [..._results, ...items];
      }
      _page = _pageNumber(result.d, page);
      _hasNext = _hasNextPage(result.d, items);
      _loading = false;
      _requesting = false;
      _requestingKeyword = '';
      _lastSearchedKeyword = keyword;
      _searched = true;
    });
  }

  Future<void> _addHistory(String keyword) async {
    final normalized = keyword.trim();
    if (normalized.isEmpty) {
      return;
    }
    final next = [
      normalized,
      ..._history.where(
        (item) => item.toLowerCase() != normalized.toLowerCase(),
      ),
    ].take(12).toList();
    await Global.sp.setStringList(_historyKey, next);
    if (mounted) {
      setState(() {
        _history = next;
      });
    }
  }

  Future<void> _clearHistory() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: EdgeInsets.symmetric(horizontal: 24),
          child: Container(
            padding: EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Color(0xff212121),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  t.delete_search_history,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    height: 1.2,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                SizedBox(height: 16),
                Text(
                  t.clear_search_history_des,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Color(0xff999999),
                    fontSize: 14,
                    height: 1.25,
                  ),
                ),
                SizedBox(height: 24),
                _SearchDialogButton(
                  label: t.confirm,
                  color: Color(0xffff3d5d),
                  onPressed: () => Navigator.pop(context, true),
                ),
                SizedBox(height: 16),
                _SearchDialogButton(
                  label: t.cancel,
                  color: Color(0xff333333),
                  onPressed: () => Navigator.pop(context, false),
                ),
              ],
            ),
          ),
        );
      },
    );
    if (confirmed != true) {
      return;
    }
    await Global.sp.remove(_historyKey);
    if (mounted) {
      setState(() {
        _history = [];
        _expandedHistory = false;
      });
    }
  }

  void _submit([String? value]) {
    final keyword = (value ?? _controller.text).trim();
    if (keyword.isEmpty) {
      return;
    }
    _searchTimer?.cancel();
    _focusNode.unfocus();
    _search(keyword, page: 1);
  }

  void _searchHistoryItem(String keyword) {
    _searchTimer?.cancel();
    _controller.text = keyword;
    _controller.selection = TextSelection.collapsed(offset: keyword.length);
    _focusNode.unfocus();
    _search(keyword, page: 1);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _Toolbar(
              controller: _controller,
              focusNode: _focusNode,
              onBack: () => context.pop(),
              onSubmit: _submit,
              onClear: () {
                _searchTimer?.cancel();
                _controller.clear();
              },
            ),
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Offstage(offstage: _searched, child: _buildLanding()),
                  Offstage(offstage: !_searched, child: _buildResultList()),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLanding() {
    return RefreshIndicator(
      onRefresh: _loadPopular,
      color: Colors.white,
      backgroundColor: Color(0xff222222),
      child: CustomScrollView(
        physics: AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverPadding(
            padding: EdgeInsets.symmetric(horizontal: 15),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                if (_controller.text.trim().isEmpty && _history.isNotEmpty) ...[
                  _HistoryHeader(
                    expanded: _expandedHistory,
                    showExpand: _history.length > 6,
                    onClear: _clearHistory,
                    onToggle: () {
                      setState(() {
                        _expandedHistory = !_expandedHistory;
                      });
                    },
                  ),
                  _HistoryGrid(
                    items: _history.take(_expandedHistory ? 12 : 6).toList(),
                    onTap: _searchHistoryItem,
                  ),
                ],
                if (_loadingPopular)
                  Padding(
                    padding: EdgeInsets.only(top: 80),
                    child: _SearchLoading(),
                  )
                else if (_popular.isNotEmpty) ...[
                  Padding(
                    padding: EdgeInsets.symmetric(vertical: 10),
                    child: Text(
                      t.popular_now,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        height: 1.2,
                      ),
                    ),
                  ),
                  _PopularGrid(items: _popular),
                  SizedBox(height: 32),
                ],
              ]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildResultList() {
    if (_loading) {
      return ListView(
        physics: AlwaysScrollableScrollPhysics(),
        children: [SizedBox(height: 40), _SearchLoading()],
      );
    }
    if (_results.isEmpty) {
      return RefreshIndicator(
        onRefresh: () => _search(_controller.text.trim(), page: 1, force: true),
        color: Colors.white,
        backgroundColor: Color(0xff222222),
        child: ListView(
          controller: _scrollController,
          physics: AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.zero,
          children: [
            _SearchEmpty(),
            if (_loadingPopular)
              _SearchLoading()
            else if (_popular.isNotEmpty) ...[
              Padding(
                padding: EdgeInsets.fromLTRB(15, 0, 15, 10),
                child: Text(
                  t.popular_now,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    height: 1.2,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 15),
                child: _PopularGrid(items: _popular),
              ),
              SizedBox(height: 32),
            ],
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: () => _search(_controller.text.trim(), page: 1, force: true),
      color: Colors.white,
      backgroundColor: Color(0xff222222),
      child: ListView.builder(
        controller: _scrollController,
        physics: AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.only(top: 4, bottom: 28),
        itemCount: _results.length + (_requesting && _page > 1 ? 1 : 0),
        itemBuilder: (context, index) {
          if (index >= _results.length) {
            return Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: _SearchLoading(),
            );
          }
          return _SearchResultItem(item: _results[index]);
        },
      ),
    );
  }
}

class _SearchLoading extends StatelessWidget {
  const _SearchLoading();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 40,
      child: Center(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(Color(0xff999999)),
              ),
            ),
            SizedBox(width: 8),
            Text(
              t.loading,
              style: TextStyle(
                color: Color(0xff999999),
                fontSize: 14,
                height: 1,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SearchDialogButton extends StatelessWidget {
  const _SearchDialogButton({
    required this.label,
    required this.color,
    required this.onPressed,
  });

  final String label;
  final Color color;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 44,
      child: TextButton(
        style: TextButton.styleFrom(
          backgroundColor: color,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
        onPressed: onPressed,
        child: Text(label, style: TextStyle(fontSize: 16)),
      ),
    );
  }
}

class _Toolbar extends StatelessWidget {
  const _Toolbar({
    required this.controller,
    required this.focusNode,
    required this.onBack,
    required this.onSubmit,
    required this.onClear,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final VoidCallback onBack;
  final ValueChanged<String> onSubmit;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 44,
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 15),
        child: Row(
          children: [
            InkWell(
              onTap: onBack,
              borderRadius: BorderRadius.circular(18),
              child: SizedBox(
                width: 24,
                height: 36,
                child: Icon(
                  LucideIcons.chevronLeft,
                  color: Colors.white,
                  size: 24,
                ),
              ),
            ),
            SizedBox(width: 15),
            Expanded(
              child: Container(
                height: 36,
                padding: EdgeInsets.symmetric(horizontal: 10),
                decoration: BoxDecoration(
                  color: Color(0xff333333),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(
                      LucideIcons.search,
                      color: Color(0xff999999),
                      size: 16,
                    ),
                    SizedBox(width: 10),
                    Expanded(
                      child: Theme(
                        data: Theme.of(context).copyWith(
                          inputDecorationTheme: InputDecorationTheme(
                            filled: false,
                            fillColor: Colors.transparent,
                            border: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            focusedBorder: InputBorder.none,
                            disabledBorder: InputBorder.none,
                          ),
                        ),
                        child: TextField(
                          controller: controller,
                          focusNode: focusNode,
                          maxLength: 32,
                          textInputAction: TextInputAction.done,
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            height: 1.1,
                          ),
                          cursorColor: Colors.white,
                          decoration: InputDecoration(
                            isDense: true,
                            filled: false,
                            fillColor: Colors.transparent,
                            contentPadding: EdgeInsets.zero,
                            counterText: '',
                            border: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            focusedBorder: InputBorder.none,
                            disabledBorder: InputBorder.none,
                            hintText: t.search_anything_you_like,
                            hintStyle: TextStyle(
                              color: Color(0xff999999),
                              fontSize: 14,
                            ),
                          ),
                          onSubmitted: onSubmit,
                          onTapOutside: (_) {
                            FocusManager.instance.primaryFocus?.unfocus();
                          },
                        ),
                      ),
                    ),
                    ValueListenableBuilder<TextEditingValue>(
                      valueListenable: controller,
                      builder: (context, value, child) {
                        if (value.text.isEmpty) {
                          return SizedBox.shrink();
                        }
                        return InkWell(
                          onTap: onClear,
                          borderRadius: BorderRadius.circular(12),
                          child: Padding(
                            padding: EdgeInsets.all(4),
                            child: Container(
                              width: 16,
                              height: 16,
                              decoration: BoxDecoration(
                                color: Color(0xff999999).withAlpha(128),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                LucideIcons.x,
                                color: Colors.white,
                                size: 11,
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HistoryHeader extends StatelessWidget {
  const _HistoryHeader({
    required this.expanded,
    required this.showExpand,
    required this.onClear,
    required this.onToggle,
  });

  final bool expanded;
  final bool showExpand;
  final VoidCallback onClear;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              t.search_history,
              style: TextStyle(
                color: Color(0xff999999),
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          InkWell(
            onTap: onClear,
            borderRadius: BorderRadius.circular(14),
            child: Padding(
              padding: EdgeInsets.all(3),
              child: Icon(
                LucideIcons.trash2,
                color: Color(0xff999999),
                size: 18,
              ),
            ),
          ),
          if (showExpand) ...[
            Container(
              width: 1,
              height: 12,
              margin: EdgeInsets.symmetric(horizontal: 10),
              color: Color(0xff666666),
            ),
            InkWell(
              onTap: onToggle,
              borderRadius: BorderRadius.circular(14),
              child: AnimatedRotation(
                turns: expanded ? 0.5 : 0,
                duration: Duration(milliseconds: 300),
                child: Padding(
                  padding: EdgeInsets.all(3),
                  child: Icon(
                    LucideIcons.chevronDown,
                    color: Color(0xff999999),
                    size: 18,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _HistoryGrid extends StatelessWidget {
  const _HistoryGrid({required this.items, required this.onTap});

  final List<String> items;
  final ValueChanged<String> onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 10),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final itemWidth = (constraints.maxWidth - 15) / 2;
          return Wrap(
            spacing: 15,
            runSpacing: 8,
            children: items.map((item) {
              return InkWell(
                onTap: () => onTap(item),
                borderRadius: BorderRadius.circular(6),
                child: SizedBox(
                  width: itemWidth,
                  height: 24,
                  child: Row(
                    children: [
                      Icon(
                        LucideIcons.history,
                        color: Color(0xff999999),
                        size: 16,
                      ),
                      SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          item,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            height: 1.1,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          );
        },
      ),
    );
  }
}

class _PopularGrid extends StatelessWidget {
  const _PopularGrid({required this.items});

  final List<dynamic> items;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = (constraints.maxWidth - 20) / 3;
        final imageHeight = width / 3 * 4;
        return Wrap(
          spacing: 10,
          runSpacing: 12,
          children: items.map((item) {
            final map = _asMap(item);
            final image = _posterUrl(map);
            final movieId = parseMovieId(map);
            return InkWell(
              onTap: movieId == null
                  ? null
                  : () => context.push('/play', extra: {'id': movieId}),
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(
                width: width,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: image.isEmpty
                          ? _ImagePlaceholder(width: width, height: imageHeight)
                          : LazyImage(
                              url: image,
                              width: width,
                              height: imageHeight,
                              fit: BoxFit.cover,
                              cacheWidth:
                                  (width *
                                          MediaQuery.of(
                                            context,
                                          ).devicePixelRatio)
                                      .round(),
                            ),
                    ),
                    SizedBox(height: 8),
                    Text(
                      _text(map['title']),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        height: 1.15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }).toList(),
        );
      },
    );
  }
}

class _SearchResultItem extends StatelessWidget {
  const _SearchResultItem({required this.item});

  final dynamic item;

  @override
  Widget build(BuildContext context) {
    final map = _asMap(item);
    final image = _posterUrl(map);
    final tags = _tagNames(map);
    final movieId = parseMovieId(map);
    return InkWell(
      onTap: movieId == null
          ? null
          : () => context.push('/play', extra: {'id': movieId}),
      child: Container(
        height: 136,
        padding: EdgeInsets.symmetric(horizontal: 15, vertical: 8),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: image.isEmpty
                  ? _ImagePlaceholder(width: 90, height: 120)
                  : LazyImage(
                      url: image,
                      width: 90,
                      height: 120,
                      fit: BoxFit.cover,
                      cacheWidth: (90 * MediaQuery.of(context).devicePixelRatio)
                          .round(),
                    ),
            ),
            SizedBox(width: 14),
            Expanded(
              child: SizedBox(
                height: 120,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _text(map['title']),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        height: 1.2,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    SizedBox(height: 4),
                    Expanded(
                      child: Text(
                        _text(map['introduction'] ?? map['description']),
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Color(0xff999999),
                          fontSize: 12,
                          height: 1.35,
                        ),
                      ),
                    ),
                    if (tags.isNotEmpty)
                      Text(
                        tags.join('  '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Color(0xff999999),
                          fontSize: 12,
                          height: 1.2,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SearchEmpty extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 60),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SvgPicture.asset(
            'assets/images/android/ic_logo_loading.svg',
            width: 128,
            height: 128,
            fit: BoxFit.none,
          ),
          SizedBox(height: 8),
          Text(
            t.no_search_found,
            style: TextStyle(color: Color(0xff999999), fontSize: 14),
          ),
        ],
      ),
    );
  }
}

class _ImagePlaceholder extends StatelessWidget {
  const _ImagePlaceholder({required this.width, required this.height});

  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      color: Color(0xff212121),
      alignment: Alignment.center,
      child: Icon(LucideIcons.image, color: Colors.white24, size: 24),
    );
  }
}

List<dynamic> _pageItems(Map<String, dynamic>? data) {
  if (data == null) {
    return [];
  }
  final value =
      data['data'] ?? data['list'] ?? data['items'] ?? data['records'];
  if (value is List) {
    return value;
  }
  return [];
}

int _pageNumber(Map<String, dynamic>? data, int fallback) {
  final value = data?['currentPage'] ?? data?['current_page'] ?? data?['page'];
  if (value is int) {
    return value;
  }
  return int.tryParse('$value') ?? fallback;
}

bool _hasNextPage(Map<String, dynamic>? data, List<dynamic> items) {
  final direct = data?['hasNext'] ?? data?['has_next'];
  if (direct is bool) {
    return direct;
  }
  final current = _pageNumber(data, 1);
  final last = data?['lastPage'] ?? data?['last_page'] ?? data?['totalPage'];
  final lastPage = last is int ? last : int.tryParse('$last');
  if (lastPage != null) {
    return current < lastPage;
  }
  return items.length >= 10;
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

String _posterUrl(Map<String, dynamic> item) {
  final image = movieCoverPath(item);
  return image.isEmpty ? '' : Global.static(image);
}

List<String> _tagNames(Map<String, dynamic> item) {
  final raw = item['tagList'] ?? item['tag_list'] ?? item['tags'];
  if (raw is List) {
    return raw.map(_tagName).where((name) => name.isNotEmpty).toList();
  }
  return [];
}

String _tagName(dynamic tag) {
  if (tag is Map) {
    final candidates = [
      tag['name'],
      tag['source_tag_name'],
      tag['local_label'],
      tag['matched_unique_id'],
      tag['label'],
      tag['title'],
      tag['unique_id'],
    ];
    for (final candidate in candidates) {
      final value = _formatTag(_text(candidate));
      if (value.isNotEmpty && !_looksLikeTagId(value)) {
        return value;
      }
    }
    return '';
  }
  final value = _formatTag(_text(tag));
  return _looksLikeTagId(value) ? '' : value;
}

String _formatTag(String value) {
  final normalized = value.replaceAll('_', ' ').trim();
  if (normalized.isEmpty) {
    return '';
  }
  return normalized
      .split(RegExp(r'\s+'))
      .where((word) => word.isNotEmpty)
      .map((word) => word[0].toUpperCase() + word.substring(1))
      .join(' ');
}

bool _looksLikeTagId(String value) {
  return RegExp(r'^[0-9a-fA-F]{6,}$').hasMatch(value.trim());
}

String _text(dynamic value) {
  return value?.toString().trim() ?? '';
}
