import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:visibility_detector/visibility_detector.dart';
import 'package:yogotv/api.dart';
import 'package:yogotv/components/empty.dart';
import 'package:yogotv/components/lazy_image.dart';
import 'package:yogotv/components/loading.dart';
import 'package:yogotv/global.dart';
import 'package:yogotv/i18n/strings.g.dart';

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
    if (widget.load && !_load) {
      setState(() {
        _load = true;
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

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: Color(0xff151515),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          title: Text(
            _nativeText(
              en: 'Remove Confirmation',
              zhHant: '移除確認',
              ja: '削除の確認',
              pt: 'Confirmação de remoção',
              vi: 'Xác nhận xóa',
              th: 'ยืนยันการลบ',
              ko: '삭제 확인',
              id: 'Konfirmasi Penghapusan',
              de: 'Entfernen bestätigen',
              ms: 'Pengesahan Padam',
              tr: 'Kaldırma Onayı',
              ar: 'تأكيد الإزالة',
            ),
            style: TextStyle(color: Colors.white, fontSize: 18),
          ),
          content: Text(
            _nativeText(
              en: 'Deletion cannot be restored. Confirm to remove from the list?',
              zhHant: '刪除後無法恢復。確認要從清單中移除嗎？',
              ja: '削除すると復元できません。リストから削除しますか？',
              pt: 'A exclusão não pode ser restaurada. Confirmar remoção da lista?',
              vi: 'Không thể khôi phục sau khi xóa. Xác nhận xóa khỏi danh sách?',
              th: 'การลบไม่สามารถกู้คืนได้ ยืนยันการลบออกจากรายการหรือไม่?',
              ko: '삭제 후 복원할 수 없습니다. 목록에서 삭제하시겠습니까?',
              id: 'Penghapusan tidak dapat dipulihkan. Konfirmasi hapus dari daftar?',
              de: 'Das Löschen kann nicht rückgängig gemacht werden. Aus der Liste entfernen?',
              ms: 'Pemadaman tidak boleh dipulihkan. Sahkan untuk alih keluar daripada senarai?',
              tr: 'Silme işlemi geri alınamaz. Listeden kaldırmayı onaylıyor musunuz?',
              ar: 'لا يمكن استعادة الحذف. هل تريد التأكيد للإزالة من القائمة؟',
            ),
            style: TextStyle(color: Colors.white70, fontSize: 14, height: 1.4),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(
                t.cancel,
                style: TextStyle(color: Colors.white.withAlpha(204)),
              ),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(
                t.confirm,
                style: TextStyle(color: Color(0xffff3d5d)),
              ),
            ),
          ],
        );
      },
    );

    if (confirmed != true || !mounted) {
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
                        child: TabBar(
                          controller: _tabController,
                          isScrollable: true,
                          tabAlignment: TabAlignment.start,
                          dividerColor: Colors.transparent,
                          indicatorColor: Colors.white,
                          indicatorWeight: 2,
                          indicatorSize: TabBarIndicatorSize.label,
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
                          onTap: (_) => _exitManageMode(),
                          tabs: [
                            Tab(text: t.my_list),
                            Tab(text: _watchHistoryText()),
                          ],
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
                                    fontWeight: FontWeight.w800,
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

  int _page = 0;
  bool _more = true;
  bool _loading = true;
  bool _requesting = false;
  bool _managing = false;

  @override
  bool get wantKeepAlive => true;

  bool get isEmpty => _items.isEmpty;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    _scrollController.addListener(_onScroll);
    _load(page: 1);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
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
    final ids = _selectedIds.join(',');
    final result = await api<dynamic>(
      widget.deletePath,
      method: Method.post,
      data: {'id': ids},
      loading: true,
    );
    if (result.c != 0 || !mounted) {
      return false;
    }

    setState(() {
      _items.removeWhere((item) => _selectedIds.contains(_rowId(item)));
      _selectedIds.clear();
      _managing = false;
    });
    widget.onSelectionChanged(0);
    return true;
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
      if (refresh || page == 1) {
        _loading = true;
      }
    });

    final result = await api<Map<String, dynamic>>(
      widget.listPath,
      method: Method.post,
      data: {'page': page},
      loading: false,
    );

    if (!mounted) {
      return;
    }

    if (result.c != 0 || result.d == null) {
      setState(() {
        _loading = false;
        _requesting = false;
        _more = false;
      });
      return;
    }

    final payload = result.d!;
    final rows = _rowsFromPayload(payload);
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
      _loading = false;
      _requesting = false;
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
    final id = item['movie_id'] ?? item['moveId'] ?? item['id'];
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
      child: _loading && _items.isEmpty
          ? Loading()
          : RefreshIndicator(
              color: Colors.white,
              backgroundColor: Color(0xffff3d5d),
              onRefresh: _refresh,
              child: _items.isEmpty
                  ? ListView(
                      physics: AlwaysScrollableScrollPhysics(),
                      children: [
                        SizedBox(
                          height: MediaQuery.of(context).size.height * 0.65,
                          child: Empty(),
                        ),
                      ],
                    )
                  : ListView.builder(
                      key: PageStorageKey(widget.storageKey),
                      controller: _scrollController,
                      physics: AlwaysScrollableScrollPhysics(),
                      padding: EdgeInsets.only(bottom: _managing ? 78 : 16),
                      itemExtent: 136,
                      itemCount: _items.length + (_more ? 1 : 0),
                      itemBuilder: (context, index) {
                        if (index >= _items.length) {
                          return Loading();
                        }
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
                                cacheHeight: (120 * ratio).round(),
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
                                fontWeight: FontWeight.w800,
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
                    fontWeight: FontWeight.w800,
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
  return data is List ? data : <dynamic>[];
}

int _currentPage(Map<String, dynamic> payload, int fallback) {
  final page =
      payload['current_page'] ?? payload['currentPage'] ?? payload['page'];
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

String _rowId(dynamic item) {
  if (item is! Map) {
    return '';
  }
  return _text(item['id']);
}

String _posterUrl(dynamic item) {
  if (item is! Map) {
    return '';
  }
  final image = _text(item['image']);
  if (image.isEmpty) {
    return '';
  }
  return Global.static(image);
}

String _titleText(dynamic item) {
  if (item is! Map) {
    return t.untitled;
  }
  final title = _text(item['title']);
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

  return tags
      .map((tag) {
        if (tag is Map) {
          final value = _text(
            tag['unique_id'] ??
                tag['source_tag_name'] ??
                tag['matched_unique_id'] ??
                tag['label'] ??
                tag['title'] ??
                tag['name'],
          );
          return _prettifyTag(value);
        }
        return _prettifyTag(_text(tag));
      })
      .where((tag) => tag.isNotEmpty)
      .take(3)
      .join('  ');
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
