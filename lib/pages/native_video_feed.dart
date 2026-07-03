import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:yogotv/api.dart';
import 'package:yogotv/components/lazy_image.dart';
import 'package:yogotv/components/loading.dart';
import 'package:yogotv/global.dart';
import 'package:yogotv/i18n/strings.g.dart';
import 'package:yogotv/states/user.dart';

enum NativeVideoScene { forYou, episode }

class NativeVideoFeed extends StatefulWidget {
  const NativeVideoFeed.forYou({super.key})
    : scene = NativeVideoScene.forYou,
      movieId = null,
      watchTo = null;

  const NativeVideoFeed.episode({
    super.key,
    required this.movieId,
    this.watchTo,
  }) : scene = NativeVideoScene.episode;

  final NativeVideoScene scene;
  final int? movieId;
  final dynamic watchTo;

  @override
  State<NativeVideoFeed> createState() => _NativeVideoFeedState();
}

class _NativeVideoFeedState extends State<NativeVideoFeed> {
  final _pageController = PageController();
  final List<Map<String, dynamic>> _items = [];

  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = true;
  int _current = 0;
  Map<String, dynamic>? _series;
  List<dynamic> _episodes = [];

  bool get _isForYou => widget.scene == NativeVideoScene.forYou;

  @override
  void initState() {
    super.initState();
    _loadInitial();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _loadInitial() async {
    setState(() => _loading = true);
    if (_isForYou) {
      await _loadForYou(refresh: true);
    } else {
      await _loadSeries();
    }
    if (mounted) {
      setState(() => _loading = false);
    }
  }

  Future<void> _loadForYou({bool refresh = false}) async {
    if (_loadingMore && !refresh) {
      return;
    }
    if (!refresh && !_hasMore) {
      return;
    }
    if (!refresh) {
      setState(() => _loadingMore = true);
    }

    final result = await api<Map<String, dynamic>>(
      'foryou',
      method: Method.post,
      loading: false,
    );
    final rows = _pageRows(result.d);
    if (!mounted) {
      return;
    }

    setState(() {
      if (refresh) {
        _items.clear();
        _current = 0;
      }
      _items.addAll(rows.map(_normalizeFeedItem));
      _hasMore = rows.length >= 10;
      _loadingMore = false;
    });
  }

  Future<void> _loadSeries() async {
    final id = widget.movieId;
    if (id == null) {
      return;
    }
    final result = await api<Map<String, dynamic>>(
      'movie/info',
      method: Method.post,
      data: {'id': id},
      loading: false,
    );
    final data = result.d ?? {};
    final info = _asMap(data['info']);
    final episodes = data['episodes'] is List ? data['episodes'] as List : [];
    final tags = data['tags'] is List ? data['tags'] as List : [];
    final items = episodes.map((episode) {
      final ep = _asMap(episode);
      return <String, dynamic>{
        'id': info['id'] ?? id,
        'ep_id': ep['id'],
        'episode': ep['episode'],
        'total_episodes': episodes.length,
        'title': info['title'],
        'image': _text(ep['image']).isNotEmpty ? ep['image'] : info['image'],
        'introduction': info['introduction'],
        'favorite': info['favorite'] ?? 0,
        'is_favor': info['is_favorite'] == 1 || info['is_favor'] == true,
        'tags': tags,
        'vip': ep['vip'],
        'locked': ep['locked'],
        'video': ep['video'],
        'subtitle': ep['subtitle'],
        'initial_position_ms': _initialPositionForEpisode(ep),
      };
    }).toList();

    if (!mounted) {
      return;
    }
    setState(() {
      _series = data;
      _episodes = episodes;
      _items
        ..clear()
        ..addAll(items);
      _current = _initialEpisodeIndex(items);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_pageController.hasClients || _current <= 0) {
        return;
      }
      _pageController.jumpToPage(_current);
    });
  }

  int _initialEpisodeIndex(List<Map<String, dynamic>> items) {
    final targetEpisodeId = _watchToEpisodeId(widget.watchTo);
    if (targetEpisodeId.isNotEmpty) {
      final byId = items.indexWhere(
        (item) => _text(item['ep_id']) == targetEpisodeId,
      );
      if (byId >= 0) {
        return byId;
      }
    }
    final targetEpisode = int.tryParse(
      _text(widget.watchTo is Map ? widget.watchTo['episode'] : null),
    );
    if (targetEpisode != null) {
      final byNo = items.indexWhere(
        (item) => _intValue(item['episode']) == targetEpisode,
      );
      if (byNo >= 0) {
        return byNo;
      }
    }
    return 0;
  }

  int _initialPositionForEpisode(Map<String, dynamic> episode) {
    if (widget.watchTo is! Map) {
      return 0;
    }
    final watchTo = widget.watchTo as Map;
    final targetId = _text(
      watchTo['episode_id'] ?? watchTo['ep_id'] ?? watchTo['epId'],
    );
    final targetEpisode = _intValue(watchTo['episode']);
    final sameEpisode =
        (targetId.isNotEmpty && _text(episode['id']) == targetId) ||
        (targetEpisode > 0 && _intValue(episode['episode']) == targetEpisode);
    if (!sameEpisode) {
      return 0;
    }
    return _intValue(
      watchTo['position_ms'] ??
          watchTo['playback_position_ms'] ??
          watchTo['playbackPositionMs'],
    );
  }

  void _onPageChanged(int index) {
    setState(() => _current = index);
    if (_isForYou && index >= _items.length - 3) {
      _loadForYou();
    }
  }

  void _playNext(int index) {
    final next = index + 1;
    if (next >= _items.length) {
      if (_isForYou) {
        _loadForYou();
      } else {
        api<dynamic>(
          'movie/watched',
          method: Method.post,
          data: {'id': _items[index]['id']},
          loading: false,
        );
      }
      return;
    }
    _pageController.animateToPage(
      next,
      duration: Duration(milliseconds: 260),
      curve: Curves.easeOut,
    );
  }

  void _selectEpisode(int index) {
    if (index < 0 || index >= _items.length) {
      return;
    }
    final item = _items[index];
    final firstLocked = _items.indexWhere(_isLockedItem);
    if (_isLockedItem(item) && firstLocked >= 0 && index > firstLocked) {
      Global.warning(t.watch_unlock_video_miss_tips);
      return;
    }
    _pageController.jumpToPage(index);
    setState(() => _current = index);
  }

  void _patchItem(int index, Map<String, dynamic> patch) {
    if (!mounted || index < 0 || index >= _items.length) {
      return;
    }
    setState(() {
      _items[index] = {..._items[index], ...patch};
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(backgroundColor: Colors.black, body: Loading());
    }
    return Scaffold(
      backgroundColor: Colors.black,
      body: _items.isEmpty
          ? Center(
              child: Text(
                t.no_content,
                style: TextStyle(color: Colors.white54),
              ),
            )
          : RefreshIndicator(
              onRefresh: _isForYou
                  ? () => _loadForYou(refresh: true)
                  : _loadSeries,
              color: Color(0xffff3d5d),
              backgroundColor: Color(0xff222222),
              child: Stack(
                children: [
                  PageView.builder(
                    controller: _pageController,
                    scrollDirection: Axis.vertical,
                    itemCount: _items.length,
                    onPageChanged: _onPageChanged,
                    itemBuilder: (context, index) {
                      final active = index == _current;
                      return NativeVideoPage(
                        key: ValueKey(
                          '${widget.scene}-${_items[index]['ep_id']}-$index',
                        ),
                        scene: widget.scene,
                        item: _items[index],
                        series: _series,
                        episodes: _episodes,
                        active: active,
                        index: index,
                        onPatch: (patch) => _patchItem(index, patch),
                        onEnded: () => _playNext(index),
                        onOpenEpisodePage: (playbackPositionMs) {
                          final id = _intValue(_items[index]['id']);
                          context.push(
                            '/play',
                            extra: {
                              'id': id,
                              'watchTo': {
                                'episode': _items[index]['episode'],
                                'episode_id': _items[index]['ep_id'],
                                'position_ms': playbackPositionMs,
                              },
                            },
                          );
                        },
                        onSelectEpisode: _selectEpisode,
                      );
                    },
                  ),
                  if (_isForYou)
                    Positioned(
                      top: MediaQuery.of(context).padding.top + 10,
                      right: 15,
                      child: IconButton(
                        onPressed: () => context.push('/search'),
                        icon: Icon(LucideIcons.search, color: Colors.white),
                      ),
                    ),
                ],
              ),
            ),
    );
  }
}

class NativeVideoPage extends StatefulWidget {
  const NativeVideoPage({
    super.key,
    required this.scene,
    required this.item,
    required this.series,
    required this.episodes,
    required this.active,
    required this.index,
    required this.onPatch,
    required this.onEnded,
    required this.onOpenEpisodePage,
    required this.onSelectEpisode,
  });

  final NativeVideoScene scene;
  final Map<String, dynamic> item;
  final Map<String, dynamic>? series;
  final List<dynamic> episodes;
  final bool active;
  final int index;
  final ValueChanged<Map<String, dynamic>> onPatch;
  final VoidCallback onEnded;
  final ValueChanged<int> onOpenEpisodePage;
  final ValueChanged<int> onSelectEpisode;

  @override
  State<NativeVideoPage> createState() => _NativeVideoPageState();
}

class _NativeVideoPageState extends State<NativeVideoPage> {
  VideoPlayerController? _controller;
  Timer? _hideTimer;

  bool _loading = false;
  bool _uiVisible = true;
  bool _playButtonVisible = false;
  bool _ended = false;
  bool _reportedWatch = false;
  bool _lockedOverlay = false;
  bool _showProgressText = false;
  bool _isSeeking = false;
  bool _appliedInitialPosition = false;
  double _speed = 1;
  double? _dragFraction;
  int _positionSeconds = 0;

  bool get _isForYou => widget.scene == NativeVideoScene.forYou;
  bool get _isEpisode => widget.scene == NativeVideoScene.episode;

  @override
  void initState() {
    super.initState();
    if (widget.active) {
      _ensureVideoReady();
    }
  }

  @override
  void didUpdateWidget(covariant NativeVideoPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active && !oldWidget.active) {
      _ensureVideoReady();
    } else if (!widget.active && oldWidget.active) {
      _pause();
    }
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _controller?.dispose();
    WakelockPlus.disable();
    super.dispose();
  }

  Future<void> _ensureVideoReady({bool autoUnlock = false}) async {
    if (_controller != null || _loading) {
      if (widget.active) {
        final controller = _controller;
        if (controller != null) {
          _playController(controller);
        }
        _startAutoHide();
      }
      return;
    }

    var video = _text(widget.item['video']);
    if (video.isEmpty && _text(widget.item['ep_id']).isNotEmpty) {
      setState(() => _loading = true);
      final episode = await _fetchEpisode(autoUnlock: autoUnlock);
      if (!mounted) {
        return;
      }
      setState(() => _loading = false);
      if (episode == null) {
        return;
      }
      widget.onPatch(episode);
      final locked = _isEpisodeLocked(episode);
      if (locked) {
        setState(() => _lockedOverlay = true);
        return;
      }
      video = _text(episode['video']);
    }

    if (video.isEmpty) {
      if (_isLockedItem(widget.item)) {
        setState(() => _lockedOverlay = true);
      }
      return;
    }

    await _createController(video, _text(widget.item['subtitle']));
  }

  Future<Map<String, dynamic>?> _fetchEpisode({bool autoUnlock = false}) async {
    final result = await api<Map<String, dynamic>>(
      'movie/episode',
      method: Method.post,
      data: {'id': widget.item['ep_id'], 'auto_unlock': autoUnlock ? '1' : '0'},
      loading: false,
    );
    return result.d;
  }

  Future<void> _createController(String video, String subtitle) async {
    await _controller?.dispose();
    _controller = VideoPlayerController.networkUrl(
      Uri.parse(Global.static(video)),
    );
    _controller!.addListener(_onVideoTick);
    await _controller!.initialize();
    if (kIsWeb) {
      await _controller!.setVolume(0);
    }
    if (!mounted) {
      return;
    }
    await _applyInitialPlaybackPosition();
    setState(() {
      _ended = false;
      _playButtonVisible = false;
    });
    if (widget.active) {
      await _playController(_controller!);
      _startAutoHide();
    }
  }

  Future<void> _playController(VideoPlayerController controller) async {
    try {
      if (kIsWeb) {
        await controller.setVolume(0);
      }
      await controller.play();
      if (!kIsWeb) {
        await WakelockPlus.enable();
      }
      if (mounted) {
        setState(() => _playButtonVisible = false);
      }
    } catch (_) {
      if (mounted) {
        setState(() => _playButtonVisible = true);
      }
    }
  }

  Future<void> _applyInitialPlaybackPosition() async {
    if (_appliedInitialPosition) {
      return;
    }
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      return;
    }
    final positionMs = _intValue(widget.item['initial_position_ms']);
    if (positionMs <= 0) {
      return;
    }
    _appliedInitialPosition = true;
    final duration = controller.value.duration;
    final target = Duration(milliseconds: positionMs);
    if (duration.inMilliseconds > 0 && target >= duration) {
      return;
    }
    await controller.seekTo(target);
  }

  void _onVideoTick() {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      return;
    }
    final seconds = controller.value.position.inSeconds;
    if (seconds != _positionSeconds && mounted) {
      setState(() => _positionSeconds = seconds);
    }
    if (!_reportedWatch && controller.value.isPlaying && seconds >= 5) {
      _reportedWatch = true;
      _reportWatchProgress();
    }
    if (controller.value.isCompleted && !_ended) {
      _ended = true;
      widget.onEnded();
    }
  }

  void _reportWatchProgress() {
    if (!widget.active) {
      return;
    }
    api<dynamic>(
      'movie/history/report',
      method: Method.post,
      data: {
        'type': 'ep_prog',
        'movie_id': widget.item['id'],
        'ep_id': widget.item['ep_id'],
        'ep_no': widget.item['episode'],
        'duration': 1,
      },
      loading: false,
    );
  }

  void _startAutoHide() {
    _hideTimer?.cancel();
    setState(() => _uiVisible = true);
    if (!_isEpisode) {
      return;
    }
    _hideTimer = Timer(Duration(seconds: 5), () {
      if (mounted && _controller?.value.isPlaying == true) {
        setState(() => _uiVisible = false);
      }
    });
  }

  void _togglePlay() {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      return;
    }
    _startAutoHide();
    if (controller.value.isPlaying) {
      controller.pause();
      setState(() => _playButtonVisible = true);
      WakelockPlus.disable();
    } else {
      _playController(controller);
    }
  }

  void _onVideoTapUp(TapUpDetails details) {
    if (_isForYou) {
      _togglePlay();
    } else {
      final size = MediaQuery.sizeOf(context);
      final dx = details.localPosition.dx - size.width / 2;
      final dy = details.localPosition.dy - size.height / 2;
      final tappedCenterButton = _uiVisible && dx.abs() <= 72 && dy.abs() <= 72;
      if (tappedCenterButton) {
        _togglePlay();
      } else {
        _toggleUi();
      }
    }
  }

  void _onLongPressStart(LongPressStartDetails _) {
    _controller?.setPlaybackSpeed(2);
    setState(() => _uiVisible = false);
  }

  void _onLongPressEnd(LongPressEndDetails _) {
    _controller?.setPlaybackSpeed(_speed);
    setState(() => _uiVisible = true);
    _startAutoHide();
  }

  void _toggleUi() {
    if (_lockedOverlay) {
      return;
    }
    setState(() => _uiVisible = !_uiVisible);
    if (_uiVisible) {
      _startAutoHide();
    }
  }

  void _onSeekStart() {
    _hideTimer?.cancel();
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      return;
    }
    setState(() {
      _isSeeking = true;
      _showProgressText = true;
      _dragFraction = _progressFraction(controller);
      _uiVisible = false;
    });
  }

  void _onSeekChanged(double value) {
    setState(() {
      _dragFraction = value.clamp(0.0, 1.0);
      _showProgressText = true;
    });
  }

  Future<void> _onSeekEnd(double value) async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      return;
    }
    final duration = controller.value.duration;
    final target = Duration(
      milliseconds: (duration.inMilliseconds * value.clamp(0.0, 1.0)).round(),
    );
    await controller.seekTo(target);
    if (!mounted) {
      return;
    }
    setState(() {
      _isSeeking = false;
      _showProgressText = false;
      _dragFraction = null;
      _uiVisible = true;
      _playButtonVisible = false;
    });
    if (widget.active) {
      await _playController(controller);
      _startAutoHide();
    }
  }

  void _pause() {
    _hideTimer?.cancel();
    _controller?.pause();
    WakelockPlus.disable();
  }

  Future<void> _toggleFavorite() async {
    final favor = _boolValue(
      widget.item['is_favor'] ?? widget.item['isFavorite'],
    );
    final path = favor ? 'movie/favorite/delete' : 'movie/favorite';
    final result = await api<dynamic>(
      path,
      method: Method.post,
      data: {'id': widget.item['id'].toString()},
      loading: false,
    );
    if (result.c == 0) {
      widget.onPatch({'is_favor': !favor});
      Global.sp.setBool('update_favorite', true);
      setState(() {});
    }
  }

  Future<void> _share() async {
    final result = await api<Map<String, dynamic>>(
      'share/url',
      method: Method.post,
      data: {'id': widget.item['id'], 'episode': widget.item['episode']},
      loading: false,
    );
    final url = _text(result.d?['url']);
    if (url.isNotEmpty) {
      await _showShareSheet(url);
    }
  }

  Future<void> _showShareSheet(String url) async {
    await showModalBottomSheet(
      context: context,
      backgroundColor: Color(0xff151515),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
      ),
      builder: (context) {
        return _ShareSheet(
          url: url,
          onCopy: () async {
            await Clipboard.setData(ClipboardData(text: url));
            if (context.mounted) {
              Navigator.pop(context);
            }
            Global.success(t.success);
          },
          onLaunch: (targetUrl, appName) async {
            final ok = await launchUrl(
              Uri.parse(targetUrl),
              mode: LaunchMode.externalApplication,
            );
            if (!ok) {
              Global.warning(_notFindText(appName));
            }
          },
        );
      },
    );
  }

  Future<void> _showSpeedSheet() async {
    final selected = await showModalBottomSheet<double>(
      context: context,
      backgroundColor: Color(0xff151515),
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                  t.playback_speed,
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
                ),
              ),
              for (final speed in [0.75, 1.0, 1.25, 1.5, 2.0])
                ListTile(
                  title: Text(speed == 1 ? t.speed : '${speed}x'),
                  trailing: _speed == speed
                      ? Icon(LucideIcons.check, color: Color(0xffff3d5d))
                      : null,
                  onTap: () => Navigator.pop(context, speed),
                ),
            ],
          ),
        );
      },
    );
    if (selected != null) {
      setState(() => _speed = selected);
      _controller?.setPlaybackSpeed(selected);
    }
  }

  void _showIntro() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Color(0xff151515),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: EdgeInsets.fromLTRB(20, 18, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _title(),
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                ),
                SizedBox(height: 12),
                Text(
                  _text(widget.item['introduction']),
                  style: TextStyle(color: Colors.white70, height: 1.35),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showEpisodes() {
    if (widget.episodes.isEmpty) {
      return;
    }
    showModalBottomSheet(
      context: context,
      backgroundColor: Color(0xff151515),
      isScrollControlled: true,
      builder: (context) {
        return _EpisodeSheet(
          title: _title(),
          episodes: widget.episodes,
          currentEpisode: _intValue(widget.item['episode']),
          onSelect: (index) {
            Navigator.pop(context);
            widget.onSelectEpisode(index);
          },
        );
      },
    );
  }

  Future<void> _handleLockedAction() async {
    final episode = await _fetchEpisode(autoUnlock: false);
    if (!mounted) {
      return;
    }
    if (episode != null &&
        !_isEpisodeLocked(episode) &&
        _text(episode['video']).isNotEmpty) {
      widget.onPatch(episode);
      setState(() => _lockedOverlay = false);
      await _createController(
        _text(episode['video']),
        _text(episode['subtitle']),
      );
      return;
    }

    final unlockCoins = _intValue(
      episode?['unlock_coins'] ?? episode?['unlockCoins'],
    );
    if (unlockCoins > 0) {
      await _showCoinUnlock(unlockCoins);
      return;
    }
    await context.push('/membership');
    if (mounted) {
      await _ensureVideoReady(autoUnlock: false);
    }
  }

  Future<void> _showCoinUnlock(int unlockCoins) async {
    final balance = await api<dynamic>(
      'user/balance',
      method: Method.post,
      loading: false,
    );
    final balanceCoins = _intValue(balance.d);
    if (!mounted) {
      return;
    }
    if (balanceCoins < unlockCoins) {
      await _showTopUpSheet(unlockCoins);
      return;
    }
    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Color(0xff151515),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: EdgeInsets.fromLTRB(20, 18, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        t.unlock_current_episode,
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(context, false),
                      icon: Icon(LucideIcons.x),
                    ),
                  ],
                ),
                SizedBox(height: 12),
                _CoinRow(label: t.episode, value: unlockCoins.toString()),
                _CoinRow(label: t.coins, value: balanceCoins.toString()),
                SizedBox(height: 18),
                SizedBox(
                  width: double.infinity,
                  height: 44,
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(context, true),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Color(0xffff3d5d),
                      foregroundColor: Colors.white,
                    ),
                    child: Text(t.unlock_now),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
    if (confirmed == true) {
      final episode = await _fetchEpisode(autoUnlock: true);
      if (episode != null &&
          !_isEpisodeLocked(episode) &&
          _text(episode['video']).isNotEmpty) {
        widget.onPatch(episode);
        setState(() => _lockedOverlay = false);
        await _createController(
          _text(episode['video']),
          _text(episode['subtitle']),
        );
      } else {
        Global.warning(t.unlock_failed(code: ''));
      }
    }
  }

  Future<void> _showTopUpSheet(int unlockCoins) async {
    await showModalBottomSheet(
      context: context,
      backgroundColor: Color(0xff151515),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: EdgeInsets.fromLTRB(20, 18, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  t.unlock_get_vip_tips,
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
                ),
                SizedBox(height: 10),
                Text(
                  '${t.episode}: $unlockCoins ${t.coins}',
                  style: TextStyle(color: Colors.white70),
                ),
                SizedBox(height: 18),
                SizedBox(
                  width: double.infinity,
                  height: 44,
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.pop(context);
                      context.push('/membership');
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Color(0xffff3d5d),
                      foregroundColor: Colors.white,
                    ),
                    child: Text(t.get_vip),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    final videoReady = controller?.value.isInitialized == true;
    final cover = _posterUrl(widget.item);
    final controlsVisible = _isForYou ? !_isSeeking : _uiVisible && !_isSeeking;
    final centerButtonVisible =
        videoReady &&
        (_isEpisode
            ? controlsVisible
            : (_playButtonVisible || !controller!.value.isPlaying));
    return Stack(
      fit: StackFit.expand,
      children: [
        ColoredBox(color: Colors.black),
        if (videoReady)
          GestureDetector(
            onTapUp: _onVideoTapUp,
            onLongPressStart: _onLongPressStart,
            onLongPressEnd: _onLongPressEnd,
            child: FittedBox(
              fit: BoxFit.cover,
              child: SizedBox(
                width: _controller!.value.size.width,
                height: _controller!.value.size.height,
                child: IgnorePointer(child: VideoPlayer(_controller!)),
              ),
            ),
          )
        else if (cover.isNotEmpty)
          LazyImage(
            url: cover,
            width: MediaQuery.of(context).size.width,
            height: MediaQuery.of(context).size.height,
            fit: BoxFit.cover,
          ),
        if (videoReady)
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTapUp: _onVideoTapUp,
              onLongPressStart: _onLongPressStart,
              onLongPressEnd: _onLongPressEnd,
            ),
          ),
        if (_loading)
          Center(child: Loading())
        else if (!videoReady && !_lockedOverlay)
          Center(
            child: InkWell(
              onTap: () => _ensureVideoReady(),
              customBorder: CircleBorder(),
              child: SvgPicture.asset(
                'assets/images/android/ic_play.svg',
                width: 89,
                height: 89,
              ),
            ),
          ),
        if (_lockedOverlay)
          _LockedOverlay(onBack: context.pop, onGetVip: _handleLockedAction),
        if (!_lockedOverlay) ...[
          if (_isEpisode)
            _EpisodeTopBar(
              visible: controlsVisible,
              title: _title(),
              speed: _speed,
              onBack: context.pop,
              onSpeed: _showSpeedSheet,
            ),
          _RightActions(
            visible: controlsVisible,
            isVip: context.read<UserState>().isVip,
            favorite: _boolValue(
              widget.item['is_favor'] ?? widget.item['isFavorite'],
            ),
            favoriteCount: _favoriteText(widget.item['favorite']),
            onVip: () => context.push('/membership'),
            onFavorite: _toggleFavorite,
            onShare: _share,
          ),
          _BottomInfo(
            visible: controlsVisible,
            title: _title(),
            description: _text(widget.item['introduction']),
            tags: _tagNames(widget.item),
            watchText: _watchText(),
            showWatchEpisode: _isForYou,
            showSelectEpisode: _isEpisode,
            onTitle: _showIntro,
            onWatchEpisode: () => widget.onOpenEpisodePage(
              controller?.value.position.inMilliseconds ?? 0,
            ),
            onSelectEpisode: _showEpisodes,
          ),
          if (videoReady)
            _ProgressTimeOverlay(
              visible: _showProgressText,
              current: _seekPreviewDuration(controller!, _dragFraction),
              total: controller.value.duration,
            ),
          if (videoReady)
            _ProgressBar(
              controller: controller!,
              dragging: _isSeeking,
              dragFraction: _dragFraction,
              onChangeStart: (_) => _onSeekStart(),
              onChanged: _onSeekChanged,
              onChangeEnd: _onSeekEnd,
            ),
          if (centerButtonVisible)
            Center(
              child: _CenterPlayButton(
                playing: controller!.value.isPlaying,
                onPressed: _togglePlay,
              ),
            ),
        ],
      ],
    );
  }

  String _title() {
    return _text(
      widget.item['title'] ?? _asMap(widget.series?['info'])['title'],
    );
  }

  String _watchText() {
    final episode = _intValue(widget.item['episode']);
    final total = _intValue(
      widget.item['total_episodes'] ?? widget.episodes.length,
    );
    if (total > 0) {
      return '${t.episode} $episode / $total';
    }
    return '${t.episode} $episode';
  }
}

double _progressFraction(VideoPlayerController controller) {
  final duration = controller.value.duration.inMilliseconds;
  if (duration <= 0) {
    return 0;
  }
  return (controller.value.position.inMilliseconds / duration).clamp(0.0, 1.0);
}

Duration _seekPreviewDuration(
  VideoPlayerController controller,
  double? dragFraction,
) {
  final duration = controller.value.duration;
  if (dragFraction == null) {
    return controller.value.position;
  }
  return Duration(
    milliseconds: (duration.inMilliseconds * dragFraction.clamp(0.0, 1.0))
        .round(),
  );
}

class _RightActions extends StatelessWidget {
  const _RightActions({
    required this.visible,
    required this.isVip,
    required this.favorite,
    required this.favoriteCount,
    required this.onVip,
    required this.onFavorite,
    required this.onShare,
  });

  final bool visible;
  final bool isVip;
  final bool favorite;
  final String favoriteCount;
  final VoidCallback onVip;
  final VoidCallback onFavorite;
  final VoidCallback onShare;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      right: 15,
      bottom: 138,
      child: AnimatedOpacity(
        opacity: visible ? 1 : 0,
        duration: Duration(milliseconds: 120),
        child: IgnorePointer(
          ignoring: !visible,
          child: Column(
            children: [
              if (!isVip)
                _ActionButton(
                  asset: 'ic_video_vip.svg',
                  label: t.vip,
                  color: Color(0xffffd000),
                  onTap: onVip,
                ),
              _ActionButton(
                asset: favorite ? 'ic_collection.svg' : 'ic_collection_nor.svg',
                label: favoriteCount,
                color: favorite ? Color(0xffffd000) : Colors.white,
                onTap: onFavorite,
              ),
              _ActionButton(
                asset: 'ic_share.svg',
                label: t.share,
                color: Colors.white,
                onTap: onShare,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.asset,
    required this.label,
    required this.color,
    required this.onTap,
  });

  final String asset;
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(top: 12),
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          width: 44,
          child: Column(
            children: [
              SvgPicture.asset(
                'assets/images/android/$asset',
                width: 36,
                height: 36,
              ),
              SizedBox(height: 4),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(color: color, fontSize: 12),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ShareSheet extends StatelessWidget {
  const _ShareSheet({
    required this.url,
    required this.onCopy,
    required this.onLaunch,
  });

  final String url;
  final Future<void> Function() onCopy;
  final Future<void> Function(String url, String appName) onLaunch;

  @override
  Widget build(BuildContext context) {
    final encoded = Uri.encodeComponent(url);
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(15, 0, 15, 15),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              height: 56,
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      t.share_to,
                      style: TextStyle(
                        color: Color(0xfffff9f9),
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: Icon(LucideIcons.x, color: Colors.white),
                  ),
                ],
              ),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(8, 28, 8, 15),
              child: Row(
                children: [
                  _ShareTarget(
                    icon: 'ic_share_facebook.png',
                    label: t.facebook,
                    onTap: () => onLaunch(
                      'https://www.facebook.com/sharer/sharer.php?u=$encoded',
                      t.facebook,
                    ),
                  ),
                  SizedBox(width: 30),
                  _ShareTarget(
                    icon: 'ic_share_x.png',
                    label: t.x_app,
                    onTap: () => onLaunch(
                      'https://twitter.com/intent/tweet?url=$encoded',
                      t.x_app,
                    ),
                  ),
                  SizedBox(width: 30),
                  _ShareTarget(
                    icon: 'ic_share_link.png',
                    label: t.copy_link,
                    onTap: onCopy,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ShareTarget extends StatelessWidget {
  const _ShareTarget({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final String icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(
        width: 74,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset(
              'assets/images/android/$icon',
              width: 54,
              height: 54,
              fit: BoxFit.contain,
            ),
            SizedBox(height: 4),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}

class _BottomInfo extends StatelessWidget {
  const _BottomInfo({
    required this.visible,
    required this.title,
    required this.description,
    required this.tags,
    required this.watchText,
    required this.showWatchEpisode,
    required this.showSelectEpisode,
    required this.onTitle,
    required this.onWatchEpisode,
    required this.onSelectEpisode,
  });

  final bool visible;
  final String title;
  final String description;
  final List<String> tags;
  final String watchText;
  final bool showWatchEpisode;
  final bool showSelectEpisode;
  final VoidCallback onTitle;
  final VoidCallback onWatchEpisode;
  final VoidCallback onSelectEpisode;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: 15,
      right: 15,
      bottom: showSelectEpisode ? 44 : 14,
      child: AnimatedOpacity(
        opacity: visible ? 1 : 0,
        duration: Duration(milliseconds: 120),
        child: IgnorePointer(
          ignoring: !visible,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              InkWell(
                onTap: onTitle,
                child: Row(
                  children: [
                    Flexible(
                      child: Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    SizedBox(width: 4),
                    Icon(
                      LucideIcons.chevronRight,
                      color: Colors.white,
                      size: 16,
                    ),
                  ],
                ),
              ),
              if (description.isNotEmpty) ...[
                SizedBox(height: 4),
                Text(
                  description,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: Colors.white, fontSize: 14),
                ),
              ],
              if (tags.isNotEmpty) ...[
                SizedBox(height: 8),
                Wrap(
                  spacing: 10,
                  runSpacing: 4,
                  children: tags.take(4).map((tag) {
                    return Text(
                      '#$tag',
                      style: TextStyle(color: Colors.white70, fontSize: 12),
                    );
                  }).toList(),
                ),
              ],
              if (showWatchEpisode) ...[
                SizedBox(height: 10),
                _EpisodeEntryButton(text: watchText, onTap: onWatchEpisode),
              ],
              if (showSelectEpisode)
                _EpisodeEntryButton(text: watchText, onTap: onSelectEpisode),
            ],
          ),
        ),
      ),
    );
  }
}

class _EpisodeEntryButton extends StatelessWidget {
  const _EpisodeEntryButton({required this.text, required this.onTap});

  final String text;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        height: 40,
        padding: EdgeInsets.symmetric(horizontal: 15),
        decoration: BoxDecoration(
          color: Colors.black.withAlpha(80),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            SvgPicture.asset(
              'assets/images/android/ic_video_ep.svg',
              width: 18,
              height: 18,
            ),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: Colors.white, fontSize: 14),
              ),
            ),
            SvgPicture.asset(
              'assets/images/android/ic_arrow_all.svg',
              width: 16,
              height: 16,
            ),
          ],
        ),
      ),
    );
  }
}

class _EpisodeTopBar extends StatelessWidget {
  const _EpisodeTopBar({
    required this.visible,
    required this.title,
    required this.speed,
    required this.onBack,
    required this.onSpeed,
  });

  final bool visible;
  final String title;
  final double speed;
  final VoidCallback onBack;
  final VoidCallback onSpeed;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: MediaQuery.of(context).padding.top,
      left: 0,
      right: 0,
      height: 44,
      child: AnimatedOpacity(
        opacity: visible ? 1 : 0,
        duration: Duration(milliseconds: 120),
        child: IgnorePointer(
          ignoring: !visible,
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 11),
            child: Row(
              children: [
                InkWell(
                  onTap: onBack,
                  child: Row(
                    children: [
                      SvgPicture.asset(
                        'assets/images/android/ic_back.svg',
                        width: 24,
                        height: 24,
                      ),
                      SizedBox(width: 15),
                      SizedBox(
                        width: MediaQuery.of(context).size.width * 0.48,
                        child: Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: Colors.white, fontSize: 17),
                        ),
                      ),
                    ],
                  ),
                ),
                Spacer(),
                InkWell(
                  onTap: onSpeed,
                  child: Row(
                    children: [
                      SvgPicture.asset(
                        'assets/images/android/ic_video_speed.svg',
                        width: 18,
                        height: 18,
                      ),
                      SizedBox(width: 2),
                      Text(
                        speed == 1 ? t.speed : '${speed}x',
                        style: TextStyle(color: Colors.white, fontSize: 14),
                      ),
                    ],
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

class _CenterPlayButton extends StatelessWidget {
  const _CenterPlayButton({required this.playing, required this.onPressed});

  final bool playing;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onPressed,
      customBorder: CircleBorder(),
      child: SvgPicture.asset(
        'assets/images/android/${playing ? 'ic_pause.svg' : 'ic_play.svg'}',
        width: 89,
        height: 89,
      ),
    );
  }
}

class _ProgressTimeOverlay extends StatelessWidget {
  const _ProgressTimeOverlay({
    required this.visible,
    required this.current,
    required this.total,
  });

  final bool visible;
  final Duration current;
  final Duration total;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: 0,
      right: 0,
      bottom: 42,
      child: AnimatedOpacity(
        opacity: visible ? 1 : 0,
        duration: Duration(milliseconds: 100),
        child: IgnorePointer(
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                _formatVideoTime(current),
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                ' / ',
                style: TextStyle(color: Colors.white60, fontSize: 20),
              ),
              Text(
                _formatVideoTime(total),
                style: TextStyle(color: Colors.white60, fontSize: 20),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProgressBar extends StatelessWidget {
  const _ProgressBar({
    required this.controller,
    required this.dragging,
    required this.dragFraction,
    required this.onChangeStart,
    required this.onChanged,
    required this.onChangeEnd,
  });

  final VideoPlayerController controller;
  final bool dragging;
  final double? dragFraction;
  final ValueChanged<double> onChangeStart;
  final ValueChanged<double> onChanged;
  final ValueChanged<double> onChangeEnd;

  @override
  Widget build(BuildContext context) {
    final durationMs = controller.value.duration.inMilliseconds;
    final value = dragFraction ?? _progressFraction(controller);
    return Positioned(
      left: 15,
      right: 15,
      bottom: 0,
      child: SizedBox(
        height: 24,
        child: SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: dragging ? 3 : 2,
            activeTrackColor: Colors.white,
            inactiveTrackColor: Colors.white24,
            thumbColor: Colors.white,
            overlayColor: Colors.white24,
            thumbShape: RoundSliderThumbShape(
              enabledThumbRadius: dragging ? 5 : 0,
            ),
            overlayShape: SliderComponentShape.noOverlay,
          ),
          child: Slider(
            min: 0,
            max: 1,
            value: durationMs <= 0 ? 0 : value,
            onChangeStart: durationMs <= 0 ? null : onChangeStart,
            onChanged: durationMs <= 0 ? null : onChanged,
            onChangeEnd: durationMs <= 0 ? null : onChangeEnd,
          ),
        ),
      ),
    );
  }
}

class _LockedOverlay extends StatelessWidget {
  const _LockedOverlay({required this.onBack, required this.onGetVip});

  final VoidCallback onBack;
  final VoidCallback onGetVip;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black.withAlpha(180),
      child: Stack(
        children: [
          Center(
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 50),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    t.unlock_get_vip_tips,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: onGetVip,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Color(0xffff3d5d),
                        foregroundColor: Colors.white,
                        padding: EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: Text(t.get_vip),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            top: MediaQuery.of(context).padding.top,
            left: 0,
            child: IconButton(
              onPressed: onBack,
              icon: Icon(LucideIcons.chevronLeft, color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }
}

class _EpisodeSheet extends StatelessWidget {
  const _EpisodeSheet({
    required this.title,
    required this.episodes,
    required this.currentEpisode,
    required this.onSelect,
  });

  final String title;
  final List<dynamic> episodes;
  final int currentEpisode;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.55,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(20, 14, 8, 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  CloseButton(color: Colors.white),
                ],
              ),
            ),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 20),
              child: Text(
                '${t.episode} $currentEpisode / ${episodes.length}',
                style: TextStyle(color: Color(0xff999999), fontSize: 14),
              ),
            ),
            SizedBox(height: 12),
            Expanded(
              child: GridView.builder(
                padding: EdgeInsets.fromLTRB(20, 0, 20, 24),
                itemCount: episodes.length,
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 6,
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 14,
                ),
                itemBuilder: (context, index) {
                  final episode = _asMap(episodes[index]);
                  final epNo = _intValue(episode['episode']);
                  final locked = _isEpisodeLocked(episode);
                  final selected = epNo == currentEpisode;
                  return InkWell(
                    onTap: () => onSelect(index),
                    borderRadius: BorderRadius.circular(8),
                    child: Stack(
                      children: [
                        Container(
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: selected
                                ? Color(0xffff3d5d)
                                : Color(0xff2b2b2b),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            epNo.toString(),
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        if (locked)
                          Positioned(
                            top: 4,
                            right: 4,
                            child: Icon(
                              LucideIcons.lock,
                              color: Colors.white70,
                              size: 12,
                            ),
                          ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CoinRow extends StatelessWidget {
  const _CoinRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Text(label, style: TextStyle(color: Colors.white70)),
          Spacer(),
          Image.asset(
            'assets/images/android/ic_coin.png',
            width: 16,
            height: 16,
          ),
          SizedBox(width: 6),
          Text(value, style: TextStyle(color: Colors.white)),
        ],
      ),
    );
  }
}

Map<String, dynamic> _normalizeFeedItem(dynamic value) {
  final item = _asMap(value);
  return {
    ...item,
    'ep_id': item['ep_id'] ?? item['epId'],
    'total_episodes': item['total_episodes'] ?? item['totalEpisode'],
    'is_favor': item['is_favor'] ?? item['isFavorite'],
  };
}

List<dynamic> _pageRows(Map<String, dynamic>? data) {
  final value = data?['data'] ?? data?['list'] ?? data?['items'];
  return value is List ? value : [];
}

String _watchToEpisodeId(dynamic watchTo) {
  if (watchTo is! Map) {
    return '';
  }
  return _text(watchTo['episode_id'] ?? watchTo['ep_id'] ?? watchTo['epId']);
}

String _posterUrl(Map<String, dynamic> item) {
  final image = _text(item['image'] ?? item['coverUrl'] ?? item['cover_url']);
  return image.isEmpty ? '' : Global.static(image);
}

List<String> _tagNames(Map<String, dynamic> item) {
  final raw = item['tags'] ?? item['tagList'] ?? item['tag_list'];
  if (raw is! List) {
    return [];
  }
  return raw
      .map((tag) {
        if (tag is Map) {
          return _text(
            tag['source_tag_name'] ?? tag['local_label'] ?? tag['name'],
          );
        }
        return _text(tag);
      })
      .where((tag) => tag.isNotEmpty)
      .toList();
}

String _favoriteText(dynamic value) {
  final number = num.tryParse(_text(value)) ?? 0;
  if (number >= 1000) {
    return '${(number / 1000).toStringAsFixed(1)}K';
  }
  return number.toInt().toString();
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

bool _isLockedItem(Map<String, dynamic> item) {
  return _isEpisodeLocked(item) && _text(item['video']).isEmpty;
}

bool _isEpisodeLocked(Map<dynamic, dynamic> item) {
  final lock = item['lock'];
  final locked = item['locked'];
  return lock == true || locked == 1 || locked == '1' || locked == true;
}

bool _boolValue(dynamic value) {
  return value == true || value == 1 || value == '1';
}

int _intValue(dynamic value) {
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.toInt();
  }
  return int.tryParse(_text(value)) ?? 0;
}

String _formatVideoTime(Duration duration) {
  final totalSeconds = duration.inSeconds;
  final hours = totalSeconds ~/ 3600;
  final minutes = (totalSeconds % 3600) ~/ 60;
  final seconds = totalSeconds % 60;
  String two(int value) => value.toString().padLeft(2, '0');
  if (hours > 0) {
    return '$hours:${two(minutes)}:${two(seconds)}';
  }
  return '${two(minutes)}:${two(seconds)}';
}

String _notFindText(String appName) {
  return t.not_find_s(s: appName).replaceAll('%1', '');
}

String _text(dynamic value) {
  return value?.toString().trim() ?? '';
}
