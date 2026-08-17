import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:visibility_detector/visibility_detector.dart';
import 'package:yogotv/api.dart';
import 'package:yogotv/components/android_prompt_dialog.dart';
import 'package:yogotv/components/lazy_image.dart';
import 'package:yogotv/global.dart';
import 'package:yogotv/i18n/strings.g.dart';
import 'package:yogotv/movie_cover.dart';
import 'package:yogotv/movie_id.dart';

class MyList extends StatefulWidget {
  const MyList({super.key, required this.load});

  final bool load;

  @override
  State<MyList> createState() => _MyListState();
}

class _MyListState extends State<MyList>
    with SingleTickerProviderStateMixin, AutomaticKeepAliveClientMixin {
  late final TabController _tabController;
  final GlobalKey<_MyListContentState> _collectKey = GlobalKey();
  final GlobalKey<_MyListContentState> _historyKey = GlobalKey();

  bool _load = false;
  bool _managing = false;
  int _selectedCount = 0;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(_handleTabChange);
    _load = widget.load;
  }

  @override
  void didUpdateWidget(covariant MyList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.load && !oldWidget.load) {
      if (!_load) {
        setState(() {
          _load = true;
        });
      }
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && widget.load) {
          _currentContent?.refreshFromServer();
        }
      });
    }
  }

  @override
  void dispose() {
    _tabController.removeListener(_handleTabChange);
    _tabController.dispose();
    super.dispose();
  }

  void _handleTabChange() {
    if (!_tabController.indexIsChanging) {
      _exitManageMode();
      _currentContent?.refreshFromServer();
    }
  }

  void _enterManageMode() {
    final current = _currentContent;
    if (current == null || current.isEmpty) {
      return;
    }
    setState(() {
      _managing = true;
      _selectedCount = 0;
    });
    current.setManaging(true);
  }

  void _exitManageMode() {
    if (!_managing) {
      return;
    }
    setState(() {
      _managing = false;
      _selectedCount = 0;
    });
    _collectKey.currentState?.setManaging(false);
    _historyKey.currentState?.setManaging(false);
  }

  Future<void> _deleteSelected() async {
    if (_selectedCount == 0) {
      return;
    }

    final confirmed = await showAndroidPromptDialog(
      context: context,
      title: t.remove_confirmation,
      content: t.deletion_cannot_be_restored_confirm_to_remove_from_the_list,
    );

    if (!confirmed || !mounted) {
      return;
    }

    final current = _currentContent;
    if (current == null) {
      return;
    }
    final deleted = await current.deleteSelected();
    if (!mounted) {
      return;
    }
    if (deleted) {
      _exitManageMode();
    }
  }

  _MyListContentState? get _currentContent {
    return _tabController.index == 0
        ? _collectKey.currentState
        : _historyKey.currentState;
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        bottom: false,
        child: Stack(
          children: [
            Column(
              children: [
                SizedBox(
                  height: 44,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                        child: SizedBox(
                          height: 36,
                          child: TabBar(
                            controller: _tabController,
                            isScrollable: true,
                            tabAlignment: TabAlignment.start,
                            dividerColor: Colors.transparent,
                            indicator: const _MyListTabIndicator(),
                            indicatorSize: TabBarIndicatorSize.label,
                            labelColor: Colors.white,
                            unselectedLabelColor: Colors.white.withAlpha(128),
                            labelStyle: TextStyle(
                              fontSize: 16,
                              height: 1,
                              fontWeight: FontWeight.w700,
                            ),
                            unselectedLabelStyle: TextStyle(
                              fontSize: 16,
                              height: 1,
                              fontWeight: FontWeight.w400,
                            ),
                            labelPadding: EdgeInsets.symmetric(horizontal: 15),
                            onTap: (_) => _exitManageMode(),
                            tabs: [
                              Tab(text: t.my_list),
                              Tab(text: _watchHistoryText()),
                            ],
                          ),
                        ),
                      ),
                      AnimatedSwitcher(
                        duration: Duration(milliseconds: 160),
                        child: _managing
                            ? TextButton(
                                key: ValueKey('done'),
                                onPressed: _exitManageMode,
                                style: TextButton.styleFrom(
                                  foregroundColor: Color(0xffff3d5d),
                                  padding: EdgeInsets.symmetric(horizontal: 15),
                                ),
                                child: Text(
                                  t.done,
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              )
                            : IconButton(
                                key: ValueKey('manage'),
                                onPressed: _enterManageMode,
                                icon: _ManageIcon(),
                                tooltip: t.my_list_manage,
                              ),
                      ),
                      SizedBox(width: 6),
                    ],
                  ),
                ),
                Expanded(
                  child: _load
                      ? TabBarView(
                          controller: _tabController,
                          physics: _managing
                              ? NeverScrollableScrollPhysics()
                              : null,
                          children: [
                            _MyListContent(
                              key: _collectKey,
                              storageKey: 'my-list-collect',
                              listPath: 'movie/my-list',
                              deletePath: 'movie/favorite/delete',
                              history: false,
                              onSelectionChanged: (count) {
                                if (mounted && _tabController.index == 0) {
                                  setState(() => _selectedCount = count);
                                }
                              },
                            ),
                            _MyListContent(
                              key: _historyKey,
                              storageKey: 'my-list-history',
                              listPath: 'movie/history',
                              deletePath: 'movie/history/delete',
                              history: true,
                              onSelectionChanged: (count) {
                                if (mounted && _tabController.index == 1) {
                                  setState(() => _selectedCount = count);
                                }
                              },
                            ),
                          ],
                        )
                      : SizedBox.shrink(),
                ),
              ],
            ),
            if (_managing)
              Positioned(
                left: 0,
                right: 0,
                bottom: 10 + MediaQuery.of(context).padding.bottom,
                child: Center(
                  child: _DeleteButton(
                    count: _selectedCount,
                    onPressed: _selectedCount > 0 ? _deleteSelected : null,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _MyListTabIndicator extends Decoration {
  const _MyListTabIndicator();

  @override
  BoxPainter createBoxPainter([VoidCallback? onChanged]) {
    return _MyListTabIndicatorPainter();
  }
}

class _MyListTabIndicatorPainter extends BoxPainter {
  @override
  void paint(Canvas canvas, Offset offset, ImageConfiguration configuration) {
    final size = configuration.size;
    if (size == null) {
      return;
    }
    final paint = Paint()..color = Colors.white;
    final left = offset.dx + (size.width - 24) / 2;
    final top = offset.dy + size.height - 2;
    canvas.drawRect(Rect.fromLTWH(left, top, 24, 2), paint);
  }
}

class _MyListContent extends StatefulWidget {
  const _MyListContent({
    super.key,
    required this.storageKey,
    required this.listPath,
    required this.deletePath,
    required this.history,
    required this.onSelectionChanged,
  });

  final String storageKey;
  final String listPath;
  final String deletePath;
  final bool history;
  final ValueChanged<int> onSelectionChanged;

  @override
  State<_MyListContent> createState() => _MyListContentState();
}

class _MyListContentState extends State<_MyListContent>
    with AutomaticKeepAliveClientMixin {
  late final ScrollController _scrollController;
  final List<dynamic> _items = [];
  final Set<String> _selectedIds = {};
  final Set<String> _hiddenIds = {};

  int _page = 0;
  bool _more = true;
  bool _requesting = false;
  bool _refreshPending = false;
  bool _managing = false;
  int _requestGeneration = 0;

  @override
  bool get wantKeepAlive => true;

  bool get isEmpty => _items.isEmpty;

  void refreshFromServer() {
    if (_requesting) {
      _refreshPending = true;
      return;
    }
    _load(page: 1, refresh: true);
  }

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    _scrollController.addListener(_onScroll);
    if (widget.history) {
      Global.watchHistoryUpdates.addListener(_handleHistoryUpdate);
    }
    _load(page: 1);
  }

  @override
  void dispose() {
    if (widget.history) {
      Global.watchHistoryUpdates.removeListener(_handleHistoryUpdate);
    }
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _handleHistoryUpdate() {
    Global.sp.remove('update_history');
    refreshFromServer();
  }

  void _onScroll() {
    if (!_scrollController.hasClients || !_more || _requesting) {
      return;
    }
    final position = _scrollController.position;
    if (position.maxScrollExtent - position.pixels < 320) {
      _load(page: _page + 1);
    }
  }

  void setManaging(bool managing) {
    if (!mounted) {
      return;
    }
    setState(() {
      _managing = managing;
      _selectedIds.clear();
    });
    widget.onSelectionChanged(0);
  }

  Future<bool> deleteSelected() async {
    if (_selectedIds.isEmpty) {
      return false;
    }
    final selectedIds = Set<String>.from(_selectedIds);
    final ids = selectedIds.join(',');
    Global.payTrace(
      'my_list delete begin path=${widget.deletePath} selectedMovieIds=$ids itemCount=${_items.length}',
    );
    _requestGeneration++;
    final result = await api<dynamic>(
      widget.deletePath,
      method: Method.post,
      data: {'id': ids},
      loading: true,
    );
    Global.payTrace(
      'my_list delete response path=${widget.deletePath} ids=$ids c=${result.c} m=${result.m} d=${result.d}',
    );
    if (result.c != 0 || !mounted) {
      return false;
    }

    setState(() {
      _hiddenIds.addAll(selectedIds);
      _items.removeWhere((item) {
        if (item is! Map) {
          return false;
        }
        final localIds = {
          _rowId(item),
          _text(item['movie_id']),
          _text(item['movieId']),
          _text(item['moveId']),
          _text(item['id']),
        }..remove('');
        return localIds.intersection(selectedIds).isNotEmpty;
      });
      _selectedIds.clear();
      _managing = false;
    });
    Global.payTrace('my_list delete local itemCount=${_items.length}');
    widget.onSelectionChanged(0);
    _requesting = false;
    await _reloadAfterDelete();
    return true;
  }

  Future<void> _reloadAfterDelete() async {
    final reloadGeneration = ++_requestGeneration;
    final result = await api<dynamic>(
      widget.listPath,
      method: Method.post,
      data: {'page': 1},
      loading: false,
    );
    if (!mounted || reloadGeneration != _requestGeneration) {
      return;
    }
    final payload = _payloadMap(result.d);
    final serverRows = _rowsFromPayload(payload);
    final rows = serverRows
        .where((item) => !_hiddenIds.contains(_rowId(item)))
        .toList();
    final nextPage = _currentPage(payload, 1);
    setState(() {
      _items
        ..clear()
        ..addAll(rows);
      _page = nextPage;
      _more =
          result.c == 0 &&
          payload.isNotEmpty &&
          _hasMore(payload, nextPage, rows.length);
      _requesting = false;
    });
    Global.payTrace(
      'my_list delete reload applied c=${result.c} serverCount=${serverRows.length} visibleCount=${rows.length}',
    );
  }

  Future<void> _refresh() async {
    await _load(page: 1, refresh: true);
  }

  Future<void> _load({required int page, bool refresh = false}) async {
    if (_requesting || (!refresh && page <= _page) || (!refresh && !_more)) {
      return;
    }

    setState(() {
      _requesting = true;
    });
    final requestGeneration = ++_requestGeneration;

    final result = await api<dynamic>(
      widget.listPath,
      method: Method.post,
      data: {'page': page},
      loading: false,
    );

    if (!mounted) {
      return;
    }
    if (requestGeneration != _requestGeneration) {
      return;
    }

    final payload = _payloadMap(result.d);
    if (result.c != 0 || payload.isEmpty) {
      setState(() {
        _requesting = false;
        _more = false;
      });
      _runPendingRefresh();
      return;
    }

    final serverRows = _rowsFromPayload(payload);
    final rows = serverRows
        .where((item) => !_hiddenIds.contains(_rowId(item)))
        .toList();
    final nextPage = _currentPage(payload, page);
    final more = _hasMore(payload, nextPage, rows.length);

    setState(() {
      if (refresh || page == 1) {
        _items
          ..clear()
          ..addAll(rows);
        _selectedIds.clear();
        widget.onSelectionChanged(0);
      } else {
        _items.addAll(rows);
      }
      _page = nextPage;
      _more = more;
      _requesting = false;
    });
    _runPendingRefresh();
  }

  void _runPendingRefresh() {
    if (!_refreshPending || !mounted) {
      return;
    }
    _refreshPending = false;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _load(page: 1, refresh: true);
      }
    });
  }

  void _handleVisible() {
    final flag = widget.history ? 'update_history' : 'update_favorite';
    if (Global.sp.getBool(flag) == true) {
      Global.sp.remove(flag);
      _page = 0;
      _more = true;
      _load(page: 1, refresh: true);
    }
  }

  void _toggleSelect(dynamic item) {
    final id = _rowId(item);
    if (id.isEmpty) {
      return;
    }
    setState(() {
      if (!_selectedIds.add(id)) {
        _selectedIds.remove(id);
      }
    });
    widget.onSelectionChanged(_selectedIds.length);
  }

  void _openItem(BuildContext context, dynamic item) {
    if (item is! Map) {
      return;
    }
    final id = parseMovieId(item);
    if (id == null) {
      return;
    }
    context.push('/play', extra: {'id': id, 'watchTo': item['progress']});
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    return VisibilityDetector(
      key: Key(widget.storageKey),
      onVisibilityChanged: (info) {
        if (info.visibleFraction > 0) {
          _handleVisible();
        }
      },
      child: RefreshIndicator(
        color: Colors.white,
        backgroundColor: Color(0xffff3d5d),
        onRefresh: _refresh,
        child: _items.isEmpty
            ? ListView(
                physics: AlwaysScrollableScrollPhysics(),
                children: [
                  SizedBox(
                    height: MediaQuery.of(context).size.height * 0.65,
                    child: _MyListEmpty(),
                  ),
                ],
              )
            : ListView.builder(
                key: PageStorageKey(widget.storageKey),
                controller: _scrollController,
                physics: AlwaysScrollableScrollPhysics(),
                padding: EdgeInsets.only(bottom: _managing ? 78 : 16),
                itemExtent: 136,
                itemCount: _items.length,
                itemBuilder: (context, index) {
                  final item = _items[index];
                  final selected = _selectedIds.contains(_rowId(item));
                  return _NativeMyListItem(
                    item: item,
                    managing: _managing,
                    selected: selected,
                    onTap: () => _managing
                        ? _toggleSelect(item)
                        : _openItem(context, item),
                  );
                },
              ),
      ),
    );
  }
}

class _MyListEmpty extends StatelessWidget {
  const _MyListEmpty();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 100,
            height: 100,
            child: SvgPicture.asset(
              'assets/images/android/ic_logo_loading.svg',
              fit: BoxFit.contain,
            ),
          ),
          SizedBox(height: 15),
          Text(
            t.theres_nothing_here,
            style: TextStyle(color: Color(0xff999999), fontSize: 14),
          ),
        ],
      ),
    );
  }
}

class _NativeMyListItem extends StatelessWidget {
  const _NativeMyListItem({
    required this.item,
    required this.managing,
    required this.selected,
    required this.onTap,
  });

  final dynamic item;
  final bool managing;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final image = _posterUrl(item);
    final tags = _tagText(item);
    final title = _titleText(item);
    final ep = _episodeText(item);
    final ratio = MediaQuery.of(context).devicePixelRatio.clamp(1.0, 3.0);

    return InkWell(
      onTap: onTap,
      child: SizedBox(
        height: 136,
        child: Stack(
          alignment: Alignment.centerLeft,
          clipBehavior: Clip.none,
          children: [
            Positioned(left: 15, child: _CheckboxIcon(selected: selected)),
            AnimatedPositioned(
              duration: Duration(milliseconds: 180),
              curve: Curves.easeOutCubic,
              left: managing ? 34 : 0,
              right: managing ? -34 : 0,
              top: 0,
              bottom: 0,
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 15),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: RepaintBoundary(
                        child: image.isEmpty
                            ? _PosterFallback()
                            : LazyImage(
                                url: image,
                                width: 90,
                                height: 120,
                                fit: BoxFit.cover,
                                cacheWidth: (90 * ratio).round(),
                              ),
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
                              title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              textDirection: Directionality.of(context),
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 14,
                                height: 1.25,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            SizedBox(height: 4),
                            Text(
                              tags,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: Color(0xff999999),
                                fontSize: 12,
                                height: 1.2,
                              ),
                            ),
                            SizedBox(height: 4),
                            Text(
                              ep,
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

class _DeleteButton extends StatelessWidget {
  const _DeleteButton({required this.count, required this.onPressed});

  final int count;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    return Opacity(
      opacity: enabled ? 1 : 0.5,
      child: Material(
        color: enabled ? Color(0xffff3d5d) : Color(0xff333333),
        borderRadius: BorderRadius.circular(22),
        child: InkWell(
          borderRadius: BorderRadius.circular(22),
          onTap: onPressed,
          child: SizedBox(
            width: 200,
            height: 44,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(LucideIcons.trash2, size: 20, color: Colors.white),
                SizedBox(width: 8),
                Text(
                  '${t.delete} ($count)',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ManageIcon extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 24,
      height: 24,
      child: CustomPaint(painter: _ManageIconPainter()),
    );
  }
}

class _ManageIconPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    double sx(double value) => value / 24 * size.width;
    double sy(double value) => value / 24 * size.height;

    canvas.drawLine(Offset(sx(11), sy(7)), Offset(sx(22), sy(7)), paint);
    canvas.drawLine(Offset(sx(11), sy(18)), Offset(sx(22), sy(18)), paint);
    canvas.drawCircle(Offset(sx(4), sy(18)), sx(2), paint);

    final path = Path()
      ..moveTo(sx(2), sy(7))
      ..lineTo(sx(3.5), sy(8.5))
      ..lineTo(sx(6.5), sy(5.5));
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _CheckboxIcon extends StatelessWidget {
  const _CheckboxIcon({required this.selected});

  final bool selected;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 20,
      height: 20,
      child: CustomPaint(painter: _CheckboxPainter(selected: selected)),
    );
  }
}

class _CheckboxPainter extends CustomPainter {
  const _CheckboxPainter({required this.selected});

  final bool selected;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 0.75;
    final borderPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..color = selected ? Color(0xffff3d5d) : Color(0xff999999);

    if (selected) {
      canvas.drawCircle(
        center,
        radius,
        Paint()
          ..style = PaintingStyle.fill
          ..color = Color(0xffff3d5d),
      );
    }
    canvas.drawCircle(center, radius, borderPaint);

    if (selected) {
      final checkPaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..color = Colors.white;
      final path = Path()
        ..moveTo(size.width * 0.25, size.height * 0.51)
        ..lineTo(size.width * 0.42, size.height * 0.67)
        ..lineTo(size.width * 0.75, size.height * 0.35);
      canvas.drawPath(path, checkPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _CheckboxPainter oldDelegate) {
    return oldDelegate.selected != selected;
  }
}

class _PosterFallback extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 90,
      height: 120,
      color: Color(0xff212121),
      alignment: Alignment.center,
      child: Icon(LucideIcons.image, color: Colors.white24, size: 26),
    );
  }
}

String _watchHistoryText() {
  return _nativeText(
    en: 'Watch History',
    zhHant: '觀看記錄',
    ja: '視聴履歴',
    pt: 'Histórico de exibição',
    vi: 'Lịch sử xem',
    th: 'ประวัติการรับชม',
    ko: '시청 기록',
    id: 'Riwayat Tontonan',
    de: 'Wiedergabeverlauf',
    ms: 'Sejarah Tontonan',
    tr: 'İzleme Geçmişi',
    ar: 'سجل المشاهدة',
  );
}

String _nativeText({
  required String en,
  required String zhHant,
  required String ja,
  required String pt,
  required String vi,
  required String th,
  required String ko,
  required String id,
  required String de,
  required String ms,
  required String tr,
  required String ar,
}) {
  final locale = LocaleSettings.currentLocale;
  switch (locale) {
    case AppLocale.zhHant:
      return zhHant;
    case AppLocale.ja:
      return ja;
    case AppLocale.pt:
      return pt;
    case AppLocale.vi:
      return vi;
    case AppLocale.th:
      return th;
    case AppLocale.ko:
      return ko;
    case AppLocale.id:
      return id;
    case AppLocale.de:
      return de;
    case AppLocale.ms:
      return ms;
    case AppLocale.tr:
      return tr;
    case AppLocale.ar:
      return ar;
    case AppLocale.en:
      return en;
  }
}

List<dynamic> _rowsFromPayload(Map<String, dynamic> payload) {
  final data = payload['data'] ?? payload['list'] ?? payload['rows'];
  if (data is Map) {
    final nested = data['data'] ?? data['list'] ?? data['rows'];
    return nested is List ? nested : <dynamic>[];
  }
  return data is List ? data : <dynamic>[];
}

Map<String, dynamic> _payloadMap(dynamic value) {
  if (value is Map<String, dynamic>) {
    return value;
  }
  if (value is Map) {
    return Map<String, dynamic>.from(value);
  }
  if (value is List) {
    return {'data': value};
  }
  return {};
}

int _currentPage(Map<String, dynamic> payload, int fallback) {
  final nested = payload['data'];
  if (nested is Map) {
    final page =
        nested['current_page'] ?? nested['currentPage'] ?? nested['page'];
    final parsed = int.tryParse(_text(page));
    if (parsed != null) {
      return parsed;
    }
  }
  final page =
      payload['current_page'] ?? payload['currentPage'] ?? payload['page'];
  return int.tryParse(_text(page)) ?? fallback;
}

bool _hasMore(Map<String, dynamic> payload, int page, int rowCount) {
  final nested = payload['data'];
  final pagePayload = nested is Map ? nested : payload;
  final perPage =
      int.tryParse(_text(pagePayload['per_page'] ?? pagePayload['pageSize'])) ??
      20;
  final total = int.tryParse(
    _text(
      pagePayload['count'] ?? pagePayload['total'] ?? pagePayload['totalCount'],
    ),
  );
  if (total != null && total > 0) {
    return page * perPage < total;
  }
  return rowCount >= perPage;
}

String _rowId(dynamic item) {
  if (item is! Map) {
    return '';
  }
  return _text(
    item['movie_id'] ?? item['movieId'] ?? item['moveId'] ?? item['id'],
  );
}

String _posterUrl(dynamic item) {
  final image = movieCoverPath(item);
  if (image.isEmpty) {
    return '';
  }
  return Global.static(image);
}

String _titleText(dynamic item) {
  if (item is! Map) {
    return t.untitled;
  }
  final title = _text(item['title'] ?? item['book_title'] ?? item['name']);
  return title.isEmpty ? t.untitled : title;
}

String _tagText(dynamic item) {
  if (item is! Map) {
    return '';
  }
  final tags = item['tags'] ?? item['tagList'];
  if (tags is! List) {
    return '';
  }

  return tags.map(_tagName).where((tag) => tag.isNotEmpty).take(3).join(' , ');
}

String _tagName(dynamic tag) {
  if (tag is Map) {
    final candidates = [
      tag['unique_id'],
      tag['source_tag_name'],
      tag['local_label'],
      tag['matched_unique_id'],
      tag['label'],
      tag['title'],
      tag['name'],
    ];
    for (final candidate in candidates) {
      final value = _prettifyTag(_text(candidate));
      if (value.isNotEmpty && !_looksLikeTagId(value)) {
        return value;
      }
    }
    return '';
  }
  final value = _prettifyTag(_text(tag));
  return _looksLikeTagId(value) ? '' : value;
}

bool _looksLikeTagId(String value) {
  return RegExp(r'^[0-9a-fA-F]{6,}$').hasMatch(value.trim());
}

String _episodeText(dynamic item) {
  if (item is! Map) {
    return 'Ep.0/0';
  }
  final progress = item['progress'];
  final epNo = progress is Map
      ? _text(
          progress['ep_no'] ?? progress['episode'] ?? progress['episode_no'],
        )
      : '';
  final current = epNo.isEmpty
      ? _text(item['episode'] ?? item['ep_no'] ?? item['epNo'])
      : epNo;
  final total = _text(
    item['episodes'] ?? item['total_episodes'] ?? item['totalEpisode'],
  );
  return 'Ep.${current.isEmpty ? '0' : current}/${total.isEmpty ? '0' : total}';
}

String _prettifyTag(String value) {
  final normalized = value.replaceAll('_', ' ').trim();
  if (normalized.isEmpty) {
    return '';
  }
  return normalized
      .split(RegExp(r'\s+'))
      .map((word) {
        if (word.isEmpty) {
          return word;
        }
        return word[0].toUpperCase() + word.substring(1);
      })
      .join(' ');
}

String _text(dynamic value) {
  if (value == null) {
    return '';
  }
  return value.toString().trim();
}
