import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';
import 'package:yogotv/api.dart';
import 'package:yogotv/components/android_toolbar.dart';
import 'package:yogotv/global.dart';
import 'package:yogotv/i18n/strings.g.dart';

class Wallet extends StatefulWidget {
  const Wallet({super.key});

  @override
  State<Wallet> createState() => _WalletState();
}

class _WalletState extends State<Wallet> {
  String _coins = '0';
  bool _autoUnlock = false;

  @override
  void initState() {
    super.initState();
    _autoUnlock = Global.sp.getBool(_autoUnlockKey) ?? false;
    _loadData();
  }

  Future<void> _loadData() async {
    final balanceFuture = api<dynamic>(
      'user/balance',
      method: Method.post,
      loading: false,
    );
    final configFuture = api<Map<String, dynamic>>(
      'user/config',
      method: Method.post,
      loading: false,
    );
    final balance = await balanceFuture;
    final config = await configFuture;
    if (!mounted) {
      return;
    }
    final auto = _boolValue(_asMap(config.d?['wallet'])['auto_unlock_next']);
    await Global.sp.setBool(_autoUnlockKey, auto);
    setState(() {
      _coins = _cleanNumber(balance.d);
      _autoUnlock = auto;
    });
  }

  Future<void> _setAutoUnlock(bool next) async {
    final result = await api<Map<String, dynamic>>(
      'user/config',
      method: Method.post,
      loading: true,
      data: {
        'wallet': {'auto_unlock_next': next},
      },
    );
    if (!mounted || result.c != 0) {
      return;
    }
    await Global.sp.setBool(_autoUnlockKey, next);
    setState(() => _autoUnlock = next);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            AndroidToolbar(title: t.wallet, onBack: context.pop),
            Expanded(
              child: RefreshIndicator(
                color: Colors.white,
                backgroundColor: const Color(0xff222222),
                onRefresh: _loadData,
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.only(bottom: 15),
                  children: [
                    const SizedBox(height: 24),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Image.asset(
                          'assets/images/android/ic_coin.png',
                          width: 16,
                          height: 16,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          t.coins,
                          style: const TextStyle(
                            color: Color(0xff999999),
                            fontSize: 14,
                            height: 1.2,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 15),
                      child: Text(
                        _coins,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 28,
                          height: 1.1,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(height: 36),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 15),
                      child: _AndroidButton(
                        text: t.top_up,
                        onTap: () => context.push('/top-up'),
                      ),
                    ),
                    const SizedBox(height: 16),
                    _WalletRow(
                      text: t.transaction_history,
                      onTap: () => context.push('/wallet/history', extra: 1),
                    ),
                    _WalletRow(
                      text: t.episodes_unlocked,
                      onTap: () => context.push('/wallet/history', extra: 2),
                    ),
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => _setAutoUnlock(!_autoUnlock),
                      child: SizedBox(
                        height: 56,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 15),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  t.auto_unlock_next_episode,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 14,
                                    height: 1.2,
                                  ),
                                ),
                              ),
                              SvgPicture.asset(
                                _autoUnlock
                                    ? 'assets/images/android/ic_switch_on.svg'
                                    : 'assets/images/android/ic_switch_off.svg',
                                width: 44,
                                height: 22,
                              ),
                            ],
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
      ),
    );
  }
}

class WalletHistory extends StatefulWidget {
  const WalletHistory({super.key, required this.type});

  final int type;

  @override
  State<WalletHistory> createState() => _WalletHistoryState();
}

class _WalletHistoryState extends State<WalletHistory> {
  final _scrollController = ScrollController();
  final List<Map<String, dynamic>> _items = [];
  late int _activeType;
  int _page = 1;
  int _loadGeneration = 0;
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = true;

  @override
  void initState() {
    super.initState();
    _activeType = widget.type;
    _scrollController.addListener(_onScroll);
    _load(refresh: true);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.extentAfter < 240) {
      _load();
    }
  }

  Future<void> _load({bool refresh = false}) async {
    if (_loadingMore || (!refresh && !_hasMore)) {
      return;
    }
    final generation = refresh ? ++_loadGeneration : _loadGeneration;
    final requestedType = _activeType;
    if (refresh) {
      setState(() {
        _loading = true;
        _page = 1;
        _hasMore = true;
      });
    } else {
      setState(() => _loadingMore = true);
    }

    final result = await api<Map<String, dynamic>>(
      'user/balance/transactions',
      method: Method.post,
      loading: false,
      data: {'type': requestedType, 'page': _page},
    );
    if (!mounted ||
        generation != _loadGeneration ||
        requestedType != _activeType) {
      return;
    }
    final payload = result.d ?? {};
    final rows = _listOfMaps(payload['data']);
    final perPage = _intValue(payload['per_page']);
    setState(() {
      if (refresh) {
        _items.clear();
      }
      _items.addAll(rows);
      _page += 1;
      _hasMore = perPage > 0 ? rows.length >= perPage : rows.isNotEmpty;
      _loading = false;
      _loadingMore = false;
    });
  }

  void _switchType(int type) {
    if (type == _activeType) {
      return;
    }
    setState(() {
      _activeType = type;
      _items.clear();
      _page = 1;
      _hasMore = true;
      _loading = true;
      _loadingMore = false;
    });
    if (_scrollController.hasClients) {
      _scrollController.jumpTo(0);
    }
    _load(refresh: true);
  }

  @override
  Widget build(BuildContext context) {
    final isIn = _activeType == 1;
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            AndroidToolbar(title: t.details, onBack: context.pop),
            _WalletHistoryTabs(activeType: _activeType, onChanged: _switchType),
            Expanded(
              child: RefreshIndicator(
                color: Colors.white,
                backgroundColor: const Color(0xff222222),
                onRefresh: () => _load(refresh: true),
                child: _loading
                    ? const Center(
                        child: CircularProgressIndicator(color: Colors.white),
                      )
                    : ListView.separated(
                        controller: _scrollController,
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 15,
                          vertical: 12,
                        ),
                        itemBuilder: (context, index) {
                          if (index >= _items.length) {
                            return const SizedBox(height: 44);
                          }
                          final item = _items[index];
                          return isIn
                              ? _TransactionInCard(item: item)
                              : _TransactionOutCard(item: item);
                        },
                        separatorBuilder: (_, _) => const SizedBox(height: 12),
                        itemCount: _items.length + (_loadingMore ? 1 : 0),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _WalletRow extends StatelessWidget {
  const _WalletRow({required this.text, required this.onTap});

  final String text;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: SizedBox(
        height: 56,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 15),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  text,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    height: 1.2,
                  ),
                ),
              ),
              SvgPicture.asset(
                'assets/images/android/ic_arrow_right.svg',
                width: 14,
                height: 14,
                colorFilter: const ColorFilter.mode(
                  Color(0xff999999),
                  BlendMode.srcIn,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _WalletHistoryTabs extends StatelessWidget {
  const _WalletHistoryTabs({required this.activeType, required this.onChanged});

  final int activeType;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 57,
      child: Row(
        children: [
          Expanded(
            child: _WalletHistoryTab(
              text: 'Recharge',
              active: activeType == 1,
              onTap: () => onChanged(1),
            ),
          ),
          Expanded(
            child: _WalletHistoryTab(
              text: 'Consumption',
              active: activeType == 2,
              onTap: () => onChanged(2),
            ),
          ),
        ],
      ),
    );
  }
}

class _WalletHistoryTab extends StatelessWidget {
  const _WalletHistoryTab({
    required this.text,
    required this.active,
    required this.onTap,
  });

  final String text;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            text,
            style: TextStyle(
              color: active ? const Color(0xffff3d5d) : Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w700,
              height: 1.2,
            ),
          ),
          const SizedBox(height: 8),
          Container(
            width: 40,
            height: 3,
            color: active ? const Color(0xffff3d5d) : Colors.transparent,
          ),
        ],
      ),
    );
  }
}

class _TransactionInCard extends StatelessWidget {
  const _TransactionInCard({required this.item});

  final Map<String, dynamic> item;

  @override
  Widget build(BuildContext context) {
    final source = _asMap(item['source_info'] ?? item['sourceInfo']);
    final coins = _cleanNumber(source['coins'] ?? item['change']);
    final extCoins = _cleanNumber(source['ext_coins'] ?? source['extCoins']);
    final hasExtra = _numValue(extCoins) > 0;
    final cash = _cleanNumber(source['cash']);
    return _HistoryCard(
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Image.asset(
                      'assets/images/android/ic_coin.png',
                      width: 14,
                      height: 14,
                    ),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text.rich(
                        TextSpan(
                          text: coins,
                          children: [
                            if (hasExtra)
                              TextSpan(
                                text: ' +$extCoins',
                                style: const TextStyle(
                                  color: Color(0xff999999),
                                  fontSize: 12,
                                ),
                              ),
                          ],
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          height: 1.2,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  _timeText(item['create_time'] ?? item['createTime']),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xff999999),
                    fontSize: 12,
                    height: 1.2,
                  ),
                ),
              ],
            ),
          ),
          if (cash.isNotEmpty && cash != '0') ...[
            const SizedBox(width: 10),
            Text(
              '\$$cash',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                height: 1.2,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _TransactionOutCard extends StatelessWidget {
  const _TransactionOutCard({required this.item});

  final Map<String, dynamic> item;

  @override
  Widget build(BuildContext context) {
    final movieId = _intValue(item['movie_id'] ?? item['movieId']);
    final episode = _intValue(item['episode_index'] ?? item['episodeIndex']);
    final epText = _androidIntText(t.ep_int(d: r'$d'), episode);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: movieId > 0
          ? () => context.push(
              '/play',
              extra: {
                'id': movieId,
                'watchTo': {'episode': episode},
              },
            )
          : null,
      child: _HistoryCard(
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _text(item['episode_name'] ?? item['episodeName']),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      height: 1.2,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(
                        child: Text(
                          epText,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            height: 1.2,
                          ),
                        ),
                      ),
                      const SizedBox(width: 4),
                      SvgPicture.asset(
                        'assets/images/android/ic_arrow_right.svg',
                        width: 14,
                        height: 14,
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _timeText(item['create_time'] ?? item['createTime']),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xff999999),
                      fontSize: 12,
                      height: 1.2,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 50),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _text(item['change']),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    height: 1.2,
                  ),
                ),
                const SizedBox(width: 4),
                Image.asset(
                  'assets/images/android/ic_coin.png',
                  width: 14,
                  height: 14,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _HistoryCard extends StatelessWidget {
  const _HistoryCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
      decoration: BoxDecoration(
        color: const Color(0xff212121),
        borderRadius: BorderRadius.circular(8),
      ),
      child: child,
    );
  }
}

class _AndroidButton extends StatelessWidget {
  const _AndroidButton({required this.text, required this.onTap});

  final String text;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        height: 44,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: const Color(0xffff3d5d),
          borderRadius: BorderRadius.circular(22),
        ),
        child: Text(
          text,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 16,
            height: 1.2,
          ),
        ),
      ),
    );
  }
}

const String _autoUnlockKey = 'auto_unlock_next_episode';

List<Map<String, dynamic>> _listOfMaps(dynamic value) {
  if (value is List) {
    return value
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
  }
  return [];
}

Map<String, dynamic> _asMap(dynamic value) {
  if (value is Map) {
    return Map<String, dynamic>.from(value);
  }
  return {};
}

String _text(dynamic value) => value?.toString() ?? '';

int _intValue(dynamic value) {
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.toInt();
  }
  return int.tryParse(_text(value)) ?? 0;
}

num _numValue(dynamic value) {
  if (value is num) {
    return value;
  }
  return num.tryParse(_text(value)) ?? 0;
}

bool _boolValue(dynamic value) {
  if (value is bool) {
    return value;
  }
  if (value is num) {
    return value != 0;
  }
  final text = _text(value).toLowerCase();
  return text == '1' || text == 'true';
}

String _cleanNumber(dynamic value) {
  final raw = _text(value);
  final parsed = num.tryParse(raw);
  if (parsed == null) {
    return raw.isEmpty ? '0' : raw;
  }
  if (parsed == parsed.roundToDouble()) {
    return parsed.toInt().toString();
  }
  return parsed.toString();
}

String _timeText(dynamic seconds) {
  final value = _intValue(seconds);
  if (value <= 0) {
    return '';
  }
  final time = DateTime.fromMillisecondsSinceEpoch(value * 1000);
  String two(int number) => number.toString().padLeft(2, '0');
  return '${time.year}-${two(time.month)}-${two(time.day)} '
      '${two(time.hour)}:${two(time.minute)}:${two(time.second)}';
}

String _androidIntText(String value, int number) {
  return value
      .replaceAll('%1\$d', '$number')
      .replaceAll('%d', '$number')
      .replaceAll(r'$d', '$number')
      .replaceAll('"', '');
}
