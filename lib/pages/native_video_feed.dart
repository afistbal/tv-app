import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:tiktok_events_sdk/tiktok_events_sdk.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:yogotv/adjust_tracking.dart';
import 'package:yogotv/api.dart';
import 'package:yogotv/components/lazy_image.dart';
import 'package:yogotv/global.dart';
import 'package:yogotv/i18n/strings.g.dart';
import 'package:yogotv/movie_cover.dart';
import 'package:yogotv/movie_id.dart';
import 'package:yogotv/pages/membership.dart';
import 'package:yogotv/playback_progress_store.dart';
import 'package:yogotv/purchase.dart';
import 'package:yogotv/states/user.dart';
import 'package:yogotv/video_playback_session.dart';

enum NativeVideoScene { forYou, episode }

enum PrepareResult { none, loading, ready, locked, error }

class _VideoLoading extends StatelessWidget {
  const _VideoLoading();

  static const _asset = 'assets/images/android/video_loading.gif';

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Image.asset(
        _asset,
        width: 42,
        height: 42,
        fit: BoxFit.contain,
        gaplessPlayback: true,
      ),
    );
  }
}

class _VideoLoadFailed extends StatelessWidget {
  const _VideoLoadFailed({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onRetry,
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(LucideIcons.refreshCw, color: Colors.white, size: 30),
              const SizedBox(height: 10),
              Text(
                t.failed,
                style: const TextStyle(color: Colors.white70, fontSize: 14),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class NativeVideoFeed extends StatefulWidget {
  const NativeVideoFeed.forYou({super.key, this.active = true})
    : scene = NativeVideoScene.forYou,
      movieId = null,
      watchTo = null;

  const NativeVideoFeed.episode({
    super.key,
    required this.movieId,
    this.watchTo,
    this.active = true,
  }) : scene = NativeVideoScene.episode;

  final NativeVideoScene scene;
  final int? movieId;
  final dynamic watchTo;
  final bool active;

  @override
  State<NativeVideoFeed> createState() => _NativeVideoFeedState();
}

class ForYouVideoFeed extends NativeVideoFeed {
  const ForYouVideoFeed({super.key, super.active = true}) : super.forYou();
}

class EpisodeVideoPage extends NativeVideoFeed {
  const EpisodeVideoPage({
    super.key,
    required super.movieId,
    super.watchTo,
    super.active = true,
  }) : super.episode();
}

class _NativeVideoFeedState extends State<NativeVideoFeed> {
  static const int _windowRadius = 1;
  static const int _preloadAhead = 2;
  static const Duration _warmPreloadDelay = Duration.zero;
  static const Duration _videoInitializeTimeout = Duration(seconds: 15);
  static const String _autoUnlockKey = 'auto_unlock_next_episode';

  final _pageController = PageController();
  final List<Map<String, dynamic>> _items = [];
  final _controllers = <int, VideoPlayerController>{};
  final _busyIndexes = <int>{};
  final _videoRequests = <String, Future<Map<String, dynamic>?>>{};
  final _subtitleRequests = <String, Future<ClosedCaptionFile>>{};
  final _batchRequests = <String, Future<void>>{};
  final _batchNoVideoIds = <String>{};
  final _completedPlaybackItems = <String>{};

  late final PlaybackProgressStore _playbackProgressStore;

  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = true;
  bool _forYouChromeVisible = true;
  int _current = 0;
  int _nextForYouPage = 2;
  int _syncGeneration = 0;
  bool _episodeExitInProgress = false;
  bool _episodePopAllowed = false;
  Map<String, dynamic>? _series;
  List<dynamic> _episodes = [];

  bool get _isForYou => widget.scene == NativeVideoScene.forYou;
  bool get _iosPlaybackProgressEnabled => !kIsWeb && Platform.isIOS;

  @override
  void initState() {
    super.initState();
    _playbackProgressStore = PlaybackProgressStore(Global.sp);
    _loadInitial();
  }

  @override
  void dispose() {
    _pageController.dispose();
    for (final controller in _controllers.values) {
      VideoPlaybackSession.unregister(controller);
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _loadInitial() async {
    setState(() => _loading = true);
    if (_isForYou) {
      await _loadForYou(refresh: true);
    } else {
      await _loadSeries();
    }
    if (!mounted) {
      return;
    }
    setState(() => _loading = false);
    if (widget.active) {
      _syncGeneration++;
      unawaited(_syncWindow(_current, _syncGeneration));
    } else if (_isForYou && _items.isNotEmpty) {
      unawaited(_prepareIndex(_current, autoplay: false));
    }
  }

  @override
  void didUpdateWidget(covariant NativeVideoFeed oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_routeTargetChanged(oldWidget)) {
      _syncGeneration++;
      unawaited(_suspendPlayback());
      unawaited(_loadInitial());
      return;
    }
    if (oldWidget.active == widget.active) {
      return;
    }
    if (widget.active) {
      _syncGeneration++;
      unawaited(_syncWindow(_current, _syncGeneration));
    } else {
      unawaited(_persistPlaybackProgress(_current));
      _syncGeneration++;
      unawaited(_suspendPlayback());
    }
  }

  bool _routeTargetChanged(NativeVideoFeed oldWidget) {
    return oldWidget.scene != widget.scene ||
        oldWidget.movieId != widget.movieId ||
        _watchToRouteKey(oldWidget.watchTo) != _watchToRouteKey(widget.watchTo);
  }

  String _playbackUid() {
    final stateUid = context.read<UserState>().state?.uid.trim() ?? '';
    return stateUid.isNotEmpty
        ? stateUid
        : (Global.sp.getString('uid') ?? '').trim();
  }

  String _playbackMovieId(Map<String, dynamic> item) {
    return _text(
      item['movie_id'] ?? item['movieId'] ?? item['moveId'] ?? item['id'],
    );
  }

  String _playbackEpisodeId(Map<String, dynamic> item) {
    return _text(item['ep_id'] ?? item['epId']);
  }

  String _playbackItemIdentity(Map<String, dynamic> item) {
    return '${_playbackMovieId(item)}:${_playbackEpisodeId(item)}';
  }

  int? _cachedPlaybackSeconds(Map<String, dynamic> item) {
    if (!_iosPlaybackProgressEnabled) {
      return null;
    }
    return _playbackProgressStore.readSeconds(
      uid: _playbackUid(),
      movieId: _playbackMovieId(item),
      episodeId: _playbackEpisodeId(item),
    );
  }

  Map<String, dynamic> _withIosPlaybackPosition(Map<String, dynamic> item) {
    if (!_iosPlaybackProgressEnabled) {
      return item;
    }
    return {
      ...item,
      'initial_position_ms': (_cachedPlaybackSeconds(item) ?? 0) * 1000,
    };
  }

  Future<void> _loadForYou({
    bool refresh = false,
    bool requestRefresh = false,
  }) async {
    if (_loadingMore && !refresh) {
      return;
    }
    if (!refresh && !_hasMore) {
      return;
    }
    if (!refresh) {
      setState(() => _loadingMore = true);
    }

    final page = refresh ? 1 : _nextForYouPage;
    final lastEpisodeId = refresh || _items.isEmpty
        ? null
        : _items.last['ep_id'];
    final requestData = <String, dynamic>{
      if (requestRefresh) 'refresh': 1,
      if (requestRefresh || !refresh) 'page': page,
      if (!refresh && lastEpisodeId != null) 'last_ep_id': lastEpisodeId,
    };
    var result = await api<Map<String, dynamic>>(
      'foryou',
      method: Method.post,
      data: requestData.isEmpty ? null : requestData,
      loading: false,
    );
    var payload = result.d ?? <String, dynamic>{};
    var rows = _pageRows(payload);
    if (refresh && rows.isEmpty) {
      await Future<void>.delayed(const Duration(milliseconds: 500));
      if (!mounted) {
        return;
      }
      await Global.ensureAnonymousSession();
      result = await api<Map<String, dynamic>>(
        'foryou',
        method: Method.post,
        data: requestData.isEmpty ? null : requestData,
        loading: false,
      );
      payload = result.d ?? <String, dynamic>{};
      rows = _pageRows(payload);
    }
    final responsePage = _intValue(payload['current_page']);
    final hasMore = _inferForYouHasMore(payload, rows.length);
    if (!mounted) {
      return;
    }

    setState(() {
      if (refresh) {
        _disposeAllControllers();
        _videoRequests.clear();
        _batchRequests.clear();
        _batchNoVideoIds.clear();
        _completedPlaybackItems.clear();
        _items.clear();
        _current = 0;
      }
      _items.addAll(rows.map(_normalizeFeedItem).map(_withIosPlaybackPosition));
      _nextForYouPage = (responsePage > 0 ? responsePage : page) + 1;
      _hasMore = hasMore;
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
      final item = <String, dynamic>{
        'id': info['id'] ?? id,
        'movie_id': info['id'] ?? id,
        'ep_id': ep['id'],
        'episode': ep['episode'],
        'total_episodes': episodes.length,
        'title': info['title'],
        'image': _text(ep['image']).isNotEmpty ? ep['image'] : info['image'],
        'is_rename': info['is_rename'],
        'introduction': info['introduction'],
        'favorite': info['favorite'] ?? 0,
        'is_favor': info['is_favorite'] == 1 || info['is_favor'] == true,
        'tags': tags,
        'vip': ep['vip'],
        'lock': ep['lock'],
        'locked': ep['locked'],
        'unlock_coins': ep['unlock_coins'] ?? ep['unlockCoins'],
        'video': _initialVideoForEpisode(ep, ep['video']),
        'subtitle': ep['subtitle_url'] ?? ep['subtitle'],
      };
      item['initial_position_ms'] = _iosPlaybackProgressEnabled
          ? (_cachedPlaybackSeconds(item) ?? 0) * 1000
          : _initialPositionForEpisode(ep);
      return item;
    }).toList();

    if (!mounted) {
      return;
    }
    setState(() {
      _series = data;
      _episodes = episodes;
      _disposeAllControllers();
      _videoRequests.clear();
      _batchRequests.clear();
      _batchNoVideoIds.clear();
      _completedPlaybackItems.clear();
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

  String _initialVideoForEpisode(
    Map<String, dynamic> episode,
    dynamic fallback,
  ) {
    if (widget.watchTo is! Map) {
      return _text(fallback);
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
      return _text(fallback);
    }
    final carriedVideo = _text(watchTo['video'] ?? watchTo['video_url']);
    return carriedVideo.isNotEmpty ? carriedVideo : _text(fallback);
  }

  Future<void> _persistPlaybackProgress(
    int index, {
    bool completed = false,
  }) async {
    if (!_iosPlaybackProgressEnabled || index < 0 || index >= _items.length) {
      return;
    }
    final controller = _controllers[index];
    if (controller == null || !controller.value.isInitialized) {
      return;
    }
    final item = Map<String, dynamic>.from(_items[index]);
    final identity = _playbackItemIdentity(item);
    final shouldRestart =
        completed ||
        _completedPlaybackItems.contains(identity) ||
        controller.value.isCompleted;
    final seconds = shouldRestart ? 0 : controller.value.position.inSeconds;
    final uid = _playbackUid();
    final movieId = _playbackMovieId(item);
    final episodeId = _playbackEpisodeId(item);
    final saved = await _playbackProgressStore.writeSeconds(
      uid: uid,
      movieId: movieId,
      episodeId: episodeId,
      seconds: seconds,
    );
    if (!saved) {
      return;
    }
    if (index < _items.length &&
        _playbackItemIdentity(_items[index]) == identity) {
      _items[index]['initial_position_ms'] = seconds * 1000;
    }
    Global.logger.d(
      'ios playback progress saved movie=$movieId episode=$episodeId seconds=$seconds',
    );
  }

  void _handleVideoEnded(int index) {
    if (index >= 0 && index < _items.length) {
      _completedPlaybackItems.add(_playbackItemIdentity(_items[index]));
      unawaited(_persistPlaybackProgress(index, completed: true));
    }
    _playNext(index);
  }

  Future<void> _openEpisodePageFromForYou(int index) async {
    if (index < 0 || index >= _items.length) {
      return;
    }
    await _persistPlaybackProgress(index);
    await _pauseAndReleaseForNavigation(index);
    if (!mounted || index >= _items.length) {
      return;
    }
    final id = parseMovieId(_items[index]);
    if (id == null) {
      return;
    }
    final playbackPositionMs =
        _controllers[index]?.value.position.inMilliseconds ?? 0;
    context.push(
      '/play',
      extra: {
        'id': id,
        'watchTo': {
          'episode': _items[index]['episode'],
          'episode_id': _items[index]['ep_id'],
          'video': _items[index]['video'],
          'subtitle': _items[index]['subtitle'],
          'position_ms': playbackPositionMs,
        },
      },
    );
  }

  void _handleOpenEpisodePage(int index, int playbackPositionMs) {
    if (_iosPlaybackProgressEnabled) {
      unawaited(_openEpisodePageFromForYou(index));
      return;
    }
    if (index < 0 || index >= _items.length) {
      return;
    }
    final id = parseMovieId(_items[index]);
    if (id == null) {
      return;
    }
    unawaited(_pauseAndReleaseForNavigation(index));
    context.push(
      '/play',
      extra: {
        'id': id,
        'watchTo': {
          'episode': _items[index]['episode'],
          'episode_id': _items[index]['ep_id'],
          'video': _items[index]['video'],
          'subtitle': _items[index]['subtitle'],
          'position_ms': playbackPositionMs,
        },
      },
    );
  }

  void _onPageChanged(int index) {
    final previous = _current;
    if (widget.scene == NativeVideoScene.episode &&
        index > previous &&
        previous >= 0 &&
        previous < _items.length &&
        _isLockedItem(_items[previous]) &&
        !context.read<UserState>().isVip) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _pageController.hasClients) {
          _pageController.jumpToPage(previous);
        }
      });
      return;
    }
    if (index != previous) {
      unawaited(_persistPlaybackProgress(previous));
      if (index >= 0 && index < _items.length) {
        _completedPlaybackItems.remove(_playbackItemIdentity(_items[index]));
      }
    }
    _syncGeneration++;
    setState(() => _current = index);
    if (_isForYou && index >= _items.length - 3) {
      _loadForYou();
    }
    unawaited(_syncWindow(index, _syncGeneration));
  }

  void _playNext(int index) {
    final next = index + 1;
    if (next >= _items.length) {
      if (_isForYou) {
        _loadForYou();
      } else {
        final movieId = parseMovieId(_items[index]);
        if (movieId != null) {
          api<dynamic>(
            'movie/watched',
            method: Method.post,
            data: {'id': movieId},
            loading: false,
            showError: false,
          );
        }
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
    if (!context.read<UserState>().isVip &&
        _isLockedItem(item) &&
        firstLocked >= 0 &&
        index > firstLocked) {
      Global.warning(t.watch_unlock_video_miss_tips);
      return;
    }
    final previous = _current;
    if (index != previous) {
      unawaited(_persistPlaybackProgress(previous));
      _completedPlaybackItems.remove(_playbackItemIdentity(item));
    }
    _pageController.jumpToPage(index);
    setState(() => _current = index);
    _syncGeneration++;
    unawaited(_syncWindow(index, _syncGeneration));
  }

  void _patchItem(int index, Map<String, dynamic> patch) {
    if (!mounted || index < 0 || index >= _items.length) {
      return;
    }
    setState(() {
      final isFavoritePatch =
          patch.containsKey('is_favor') || patch.containsKey('isFavorite');
      if (!isFavoritePatch) {
        _applyItemPatch(index, patch);
        return;
      }

      final movieId = _favoriteMovieId(_items[index]);
      for (var itemIndex = 0; itemIndex < _items.length; itemIndex++) {
        if (_favoriteMovieId(_items[itemIndex]) == movieId) {
          _applyItemPatch(itemIndex, patch);
        }
      }
    });
  }

  void _applyItemPatch(int index, Map<String, dynamic> patch) {
    if (index < 0 || index >= _items.length) {
      return;
    }
    final current = _items[index];
    final itemPatch = _patchForPlayableItem(current, patch);
    final updated = {...current, ...itemPatch};
    _items[index] = updated;
    _syncEpisodePatch(updated, patch);
  }

  Map<String, dynamic> _patchForPlayableItem(
    Map<String, dynamic> current,
    Map<String, dynamic> patch,
  ) {
    final normalized = Map<String, dynamic>.from(patch);
    final patchId = _text(normalized['id']);
    final currentMovieId = _text(current['id']);
    final currentEpisodeId = _text(current['ep_id']);
    final patchMovieId = _text(
      normalized['movie_id'] ?? normalized['movieId'] ?? normalized['moveId'],
    );
    if (patchId.isNotEmpty &&
        currentEpisodeId.isNotEmpty &&
        patchId != currentMovieId &&
        patchMovieId.isEmpty) {
      normalized['ep_id'] = patchId;
      normalized.remove('id');
    }
    if (_text(normalized['video'] ?? current['video']).isNotEmpty) {
      final episodeId = _text(normalized['ep_id'] ?? normalized['id']);
      if (episodeId.isNotEmpty) {
        _batchNoVideoIds.remove(episodeId);
      }
      normalized['lock'] = 0;
      normalized['locked'] = 0;
    }
    return normalized;
  }

  void _syncEpisodePatch(
    Map<String, dynamic> item,
    Map<String, dynamic> patch,
  ) {
    if (_episodes.isEmpty) {
      return;
    }
    final episodePatch = Map<String, dynamic>.from(patch);
    if (_text(episodePatch['video'] ?? item['video']).isNotEmpty) {
      episodePatch['lock'] = 0;
      episodePatch['locked'] = 0;
    }
    _episodes = _episodes.map((raw) {
      final episode = _asMap(raw);
      if (!_sameEpisode(episode, item, patch)) {
        return raw;
      }
      return {...episode, ...episodePatch};
    }).toList();
  }

  bool _sameEpisode(
    Map<String, dynamic> episode,
    Map<String, dynamic> item,
    Map<String, dynamic> patch,
  ) {
    final episodeId = _text(
      episode['id'] ?? episode['ep_id'] ?? episode['epId'],
    );
    final itemEpisodeId = _text(item['ep_id']);
    final patchEpisodeId = _text(
      patch['id'] ?? patch['ep_id'] ?? patch['epId'],
    );
    if (episodeId.isNotEmpty &&
        (episodeId == itemEpisodeId || episodeId == patchEpisodeId)) {
      return true;
    }
    final episodeNo = _intValue(episode['episode']);
    final itemEpisodeNo = _intValue(item['episode']);
    final patchEpisodeNo = _intValue(patch['episode']);
    return episodeNo > 0 &&
        (episodeNo == itemEpisodeNo || episodeNo == patchEpisodeNo);
  }

  Future<PrepareResult> _prepareIndex(
    int index, {
    required bool autoplay,
    bool autoUnlock = false,
    bool allowEpisodeFetch = true,
  }) async {
    if (index < 0 || index >= _items.length) {
      return PrepareResult.none;
    }
    if (!_canPreparePosition(index)) {
      return PrepareResult.locked;
    }
    final existing = _controllers[index];
    if (existing?.value.isInitialized == true) {
      if (widget.active && autoplay && index == _current) {
        await _playOnly(index);
      }
      return PrepareResult.ready;
    }
    if (_busyIndexes.contains(index)) {
      return PrepareResult.loading;
    }

    _busyIndexes.add(index);
    if (mounted) {
      setState(() {});
    }
    try {
      final video = await _ensureVideoFor(
        index,
        autoUnlock: autoUnlock,
        allowEpisodeFetch: allowEpisodeFetch,
      );
      if (video.isEmpty || !mounted || index >= _items.length) {
        if (_isLockedItem(_items[index])) {
          return PrepareResult.locked;
        }
        return PrepareResult.none;
      }

      final controller = VideoPlayerController.networkUrl(
        Uri.parse(Global.static(video)),
      );
      try {
        await controller.initialize().timeout(_videoInitializeTimeout);
      } catch (_) {
        await controller.dispose();
        rethrow;
      }
      await controller.setLooping(_isForYou);
      await _setControllerAudible(controller, false);
      if (!mounted) {
        await controller.dispose();
        return PrepareResult.none;
      }
      final previous = _controllers[index];
      if (previous != null) {
        VideoPlaybackSession.unregister(previous);
        await previous.dispose();
      }
      _controllers[index] = controller;
      VideoPlaybackSession.register(controller);
      unawaited(_attachSubtitle(index, controller));
      if (widget.active && autoplay && index == _current) {
        await _playOnly(index);
      }
      if (mounted) {
        setState(() {});
      }
      return PrepareResult.ready;
    } catch (error) {
      Global.logger.d('video prepare failed index=$index error=$error');
      return PrepareResult.error;
    } finally {
      _busyIndexes.remove(index);
      if (mounted) {
        setState(() {});
      }
    }
  }

  Future<void> _attachSubtitle(
    int index,
    VideoPlayerController controller,
  ) async {
    if (index < 0 || index >= _items.length) {
      return;
    }
    final rawUrl = _text(
      _items[index]['subtitle_url'] ?? _items[index]['subtitle'],
    );
    if (rawUrl.isEmpty) {
      return;
    }
    final url = Global.static(rawUrl);
    try {
      final file = await _subtitleRequests.putIfAbsent(
        url,
        () => _loadSubtitleFile(url),
      );
      if (!mounted || _controllers[index] != controller) {
        return;
      }
      await controller.setClosedCaptionFile(Future.value(file));
    } catch (error) {
      Global.logger.d('subtitle load failed url=$url error=$error');
    }
  }

  Future<ClosedCaptionFile> _loadSubtitleFile(String url) async {
    final response = await Global.dio.get<dynamic>(
      url,
      options: Options(responseType: ResponseType.plain),
    );
    final contents = _text(response.data).replaceFirst('\ufeff', '');
    return WebVTTCaptionFile(contents);
  }

  bool _canPreparePosition(int index) {
    if (index < 0 || index >= _items.length) {
      return false;
    }
    if (widget.scene == NativeVideoScene.episode &&
        _isLockedItem(_items[index]) &&
        !context.read<UserState>().isVip) {
      return false;
    }
    return _text(_items[index]['video']).isNotEmpty ||
        _text(_items[index]['ep_id']).isNotEmpty;
  }

  Future<String> _ensureVideoFor(
    int index, {
    bool notify = true,
    bool autoUnlock = false,
    bool allowEpisodeFetch = true,
  }) async {
    if (index < 0 || index >= _items.length) {
      return '';
    }
    var item = _items[index];
    var video = _text(item['video']);
    if (video.isNotEmpty) {
      return video;
    }
    final epId = _text(item['ep_id']);
    if (epId.isEmpty) {
      return '';
    }
    if (!allowEpisodeFetch) {
      return '';
    }
    final key = '$epId:${autoUnlock ? 1 : 0}';
    final request = _videoRequests.putIfAbsent(key, () async {
      final result = await api<Map<String, dynamic>>(
        'movie/episode',
        method: Method.post,
        data: {'id': epId, 'auto_unlock': autoUnlock ? '1' : '0'},
        loading: false,
      );
      return result.d;
    });
    final episodeVideo = () async {
      Map<String, dynamic>? episode;
      try {
        episode = await request;
      } finally {
        _videoRequests.remove(key);
      }
      if (episode == null || !mounted || index >= _items.length) {
        return '';
      }
      _applyItemPatch(index, episode);
      if (notify && mounted) {
        setState(() {});
      }
      return _text(_items[index]['video']);
    }();

    if (_isForYou || autoUnlock) {
      return episodeVideo;
    }

    final batchVideo =
        _preloadEpisodeBatch(
          index,
          isVip: context.read<UserState>().isVip,
          includeCurrent: true,
        ).then((_) {
          if (!mounted || index >= _items.length) {
            return '';
          }
          return _text(_items[index]['video']);
        });

    final firstVideo = await Future.any<String>([episodeVideo, batchVideo]);
    if (firstVideo.isNotEmpty) {
      return firstVideo;
    }
    final videoFromBatch = await batchVideo;
    if (videoFromBatch.isNotEmpty) {
      return videoFromBatch;
    }
    return episodeVideo;
  }

  Future<void> _syncWindow(int index, int generation) async {
    if (index < 0 || index >= _items.length) {
      return;
    }
    if (!widget.active) {
      await _suspendPlayback();
      return;
    }
    await _prepareIndex(index, autoplay: true);
    if (!mounted ||
        !widget.active ||
        generation != _syncGeneration ||
        index != _current) {
      return;
    }
    final isVip = context.read<UserState>().isVip;
    await _playOnly(index);
    _scheduleWarmPreloads(index, generation, isVip: isVip);
    _scheduleTrim(index);
  }

  void _scheduleWarmPreloads(int index, int generation, {required bool isVip}) {
    Future<void>.delayed(_warmPreloadDelay, () {
      if (!mounted ||
          !widget.active ||
          generation != _syncGeneration ||
          index != _current) {
        return;
      }
      unawaited(_runWarmPreloads(index, generation, isVip: isVip));
    });
  }

  Future<void> _runWarmPreloads(
    int index,
    int generation, {
    required bool isVip,
  }) async {
    await _preloadEpisodeBatch(index, isVip: isVip);
    if (!mounted ||
        !widget.active ||
        generation != _syncGeneration ||
        index != _current) {
      return;
    }
    for (final preload in _controllerPreloadIndices(index, isVip: isVip)) {
      unawaited(
        _prepareIndex(preload, autoplay: false, allowEpisodeFetch: _isForYou),
      );
    }
    _scheduleTrim(index);
  }

  List<int> _controllerPreloadIndices(int index, {required bool isVip}) {
    final indices = <int>[];
    for (var preload = index + 1; preload <= index + _preloadAhead; preload++) {
      if (preload >= _items.length) {
        break;
      }
      if (widget.scene == NativeVideoScene.episode &&
          _isLockedItem(_items[preload]) &&
          !isVip) {
        break;
      }
      indices.add(preload);
    }
    return indices;
  }

  Future<void> _preloadEpisodeBatch(
    int index, {
    required bool isVip,
    bool includeCurrent = false,
  }) async {
    if (_isForYou || index < 0 || index >= _items.length) {
      return;
    }
    final movieId = widget.movieId ?? _intValue(_items[index]['id']);
    if (movieId <= 0) {
      return;
    }
    final ids = <String>[];
    for (final preloadIndex in _batchPreloadIndices(index, isVip: isVip)) {
      if (!includeCurrent && preloadIndex == index) {
        continue;
      }
      final item = _items[preloadIndex];
      final epId = _text(item['ep_id']);
      if (epId.isEmpty ||
          _text(item['video']).isNotEmpty ||
          _batchNoVideoIds.contains(epId)) {
        continue;
      }
      ids.add(epId);
    }
    if (ids.isEmpty) {
      return;
    }
    final uniqueIds = ids.toSet().toList()..sort();
    final key = '$movieId:${uniqueIds.join(',')}';
    final existing = _batchRequests[key];
    if (existing != null) {
      await existing;
      return;
    }
    final task = _fetchEpisodeBatch(movieId, uniqueIds);
    _batchRequests[key] = task;
    try {
      await task;
    } finally {
      _batchRequests.remove(key);
    }
  }

  List<int> _batchPreloadIndices(int index, {required bool isVip}) {
    if (index < 0 || index >= _items.length) {
      return const [];
    }
    final prev = index > 0 ? 1 : 0;
    var next = _preloadAhead;
    final nextOneLocked =
        index + 1 < _items.length && _isLockedItem(_items[index + 1]);
    final nextTwoLocked =
        index + 2 < _items.length && _isLockedItem(_items[index + 2]);
    if (!isVip && (nextOneLocked || nextTwoLocked)) {
      next = 1;
    }
    final indices = <int>[];
    for (var i = index - prev; i <= index + next; i++) {
      if (i < 0 || i >= _items.length) {
        continue;
      }
      if (!isVip && i != index && _isLockedItem(_items[i])) {
        if (i > index) {
          break;
        }
        continue;
      }
      indices.add(i);
    }
    return indices;
  }

  Future<void> _fetchEpisodeBatch(int movieId, List<String> epIds) async {
    try {
      final result = await api<Map<String, dynamic>>(
        'movie/episodes/batch',
        method: Method.post,
        data: {
          'movie_id': movieId,
          'id': epIds.map((id) => int.tryParse(id) ?? id).toList(),
        },
        loading: false,
        showError: false,
      );
      if (!mounted || result.c != 0) {
        return;
      }
      final maps = _extractBatchMaps(result.d);
      if (maps.isEmpty) {
        return;
      }
      setState(() {
        for (final epId in epIds) {
          final raw = maps[epId];
          if (raw == null) {
            continue;
          }
          final patch = {'id': epId, ...raw};
          if (_text(patch['video']).isEmpty) {
            _batchNoVideoIds.add(epId);
            continue;
          }
          final index = _items.indexWhere(
            (item) => _text(item['ep_id']) == epId,
          );
          if (index >= 0) {
            _applyItemPatch(index, patch);
          }
        }
      });
    } catch (error) {
      Global.logger.d('episode batch preload failed error=$error');
    }
  }

  Future<void> _playOnly(int index) async {
    if (!widget.active) {
      await _suspendPlayback();
      return;
    }
    for (final entry in _controllers.entries) {
      if (entry.key == index) {
        if (entry.value.value.isInitialized) {
          await VideoPlaybackSession.play(entry.value);
        }
      } else {
        await VideoPlaybackSession.pause(entry.value);
      }
    }
  }

  Future<void> _pauseAllControllers() async {
    await VideoPlaybackSession.pauseAll();
  }

  Future<void> _suspendPlayback() async {
    await _pauseAllControllers();
    await WakelockPlus.disable();
  }

  Future<void> _setControllerAudible(
    VideoPlayerController controller,
    bool audible,
  ) async {
    await controller.setVolume(!kIsWeb && audible ? 1 : 0);
  }

  Future<void> _pauseAndReleaseForNavigation(int keepIndex) async {
    for (final controller in _controllers.values) {
      await VideoPlaybackSession.pause(controller);
    }
    final remove = _controllers.keys
        .where((index) => index != keepIndex)
        .toList(growable: false);
    for (final index in remove) {
      final controller = _controllers.remove(index);
      if (controller != null) {
        VideoPlaybackSession.unregister(controller);
        await controller.dispose();
      }
    }
  }

  void _scheduleTrim(int anchor) {
    Future<void>.delayed(Duration(milliseconds: 700), () {
      if (!mounted) {
        return;
      }
      unawaited(_trimControllerWindow(anchor));
    });
  }

  Future<void> _trimControllerWindow(int anchor) async {
    final keep = <int>{
      for (var i = anchor - _windowRadius; i <= anchor + _preloadAhead; i++)
        if (i >= 0 && i < _items.length) i,
    };
    final remove = _controllers.keys
        .where((index) => !keep.contains(index))
        .toList();
    for (final index in remove) {
      final controller = _controllers.remove(index);
      if (controller != null) {
        VideoPlaybackSession.unregister(controller);
        await controller.dispose();
      }
    }
  }

  void _disposeAllControllers() {
    for (final controller in _controllers.values) {
      VideoPlaybackSession.unregister(controller);
      controller.dispose();
    }
    _controllers.clear();
    _busyIndexes.clear();
  }

  void _requestEpisodeExit() {
    if (!_iosPlaybackProgressEnabled) {
      _finishEpisodeExit();
      return;
    }
    unawaited(_persistAndExitEpisodePage());
  }

  Future<void> _persistAndExitEpisodePage() async {
    if (_episodeExitInProgress) {
      return;
    }
    _episodeExitInProgress = true;
    await _persistPlaybackProgress(_current);
    if (!mounted) {
      return;
    }
    setState(() => _episodePopAllowed = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _finishEpisodeExit();
      }
    });
  }

  void _finishEpisodeExit() {
    if (context.canPop()) {
      context.pop();
      return;
    }
    context.go('/');
  }

  Widget _withEpisodeExitHandling(Widget child) {
    if (_isForYou || !_iosPlaybackProgressEnabled) {
      return child;
    }
    return PopScope(
      canPop: _episodePopAllowed,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) {
          _requestEpisodeExit();
        }
      },
      child: child,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return _withEpisodeExitHandling(
        Scaffold(backgroundColor: Colors.black, body: _VideoLoading()),
      );
    }
    return _withEpisodeExitHandling(
      Scaffold(
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
                    ? () => _loadForYou(refresh: true, requestRefresh: true)
                    : _loadSeries,
                color: Color(0xffff3d5d),
                backgroundColor: Color(0xff222222),
                child: Stack(
                  children: [
                    PageView.builder(
                      controller: _pageController,
                      scrollDirection: Axis.vertical,
                      physics: const _VideoFeedScrollPhysics(
                        parent: BouncingScrollPhysics(),
                      ),
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
                          active: widget.active && active,
                          index: index,
                          controller: _controllers[index],
                          controllerLoading: _busyIndexes.contains(index),
                          onPrepare: ({bool autoUnlock = false}) =>
                              _prepareIndex(
                                index,
                                autoplay: index == _current,
                                autoUnlock: autoUnlock,
                              ),
                          onPatch: (patch) => _patchItem(index, patch),
                          onEnded: () => _handleVideoEnded(index),
                          onOpenEpisodePage: (playbackPositionMs) =>
                              _handleOpenEpisodePage(index, playbackPositionMs),
                          onSelectEpisode: _selectEpisode,
                          onCloseEpisodePage: _requestEpisodeExit,
                          onChromeVisibilityChanged: _isForYou && active
                              ? (visible) {
                                  if (_forYouChromeVisible == visible ||
                                      !mounted) {
                                    return;
                                  }
                                  setState(() {
                                    _forYouChromeVisible = visible;
                                  });
                                }
                              : null,
                        );
                      },
                    ),
                    if (_isForYou && _forYouChromeVisible)
                      PositionedDirectional(
                        top: MediaQuery.of(context).padding.top,
                        end: 15,
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () => context.push('/search'),
                          child: SizedBox(
                            width: 24,
                            height: 24,
                            child: SvgPicture.asset(
                              'assets/images/android/ic_search_home.svg',
                              width: 24,
                              height: 24,
                              colorFilter: const ColorFilter.mode(
                                Colors.white,
                                BlendMode.srcIn,
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
      ),
    );
  }
}

class _VideoFeedScrollPhysics extends PageScrollPhysics {
  const _VideoFeedScrollPhysics({super.parent});

  static const double _turnPageThreshold = 0.18;

  @override
  _VideoFeedScrollPhysics applyTo(ScrollPhysics? ancestor) {
    return _VideoFeedScrollPhysics(parent: buildParent(ancestor));
  }

  @override
  double get minFlingDistance => 4;

  @override
  double get minFlingVelocity => 120;

  @override
  double? get dragStartDistanceMotionThreshold => 1;

  @override
  Simulation? createBallisticSimulation(
    ScrollMetrics position,
    double velocity,
  ) {
    if ((velocity <= 0.0 && position.pixels <= position.minScrollExtent) ||
        (velocity >= 0.0 && position.pixels >= position.maxScrollExtent)) {
      return super.createBallisticSimulation(position, velocity);
    }

    final viewport = position.viewportDimension;
    if (viewport <= 0) {
      return super.createBallisticSimulation(position, velocity);
    }

    final currentPage = position.pixels / viewport;
    final anchorPage = currentPage.roundToDouble();
    var targetPage = anchorPage;
    final delta = currentPage - anchorPage;
    final tolerance = toleranceFor(position);

    if (velocity > tolerance.velocity || delta > _turnPageThreshold) {
      targetPage = anchorPage + 1;
    } else if (velocity < -tolerance.velocity || delta < -_turnPageThreshold) {
      targetPage = anchorPage - 1;
    }

    final targetPixels = (targetPage * viewport).clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );
    if (targetPixels == position.pixels) {
      return null;
    }
    return ScrollSpringSimulation(
      spring,
      position.pixels,
      targetPixels.toDouble(),
      velocity,
      tolerance: tolerance,
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
    required this.controller,
    required this.controllerLoading,
    required this.onPrepare,
    required this.onPatch,
    required this.onEnded,
    required this.onOpenEpisodePage,
    required this.onSelectEpisode,
    required this.onCloseEpisodePage,
    this.onChromeVisibilityChanged,
  });

  final NativeVideoScene scene;
  final Map<String, dynamic> item;
  final Map<String, dynamic>? series;
  final List<dynamic> episodes;
  final bool active;
  final int index;
  final VideoPlayerController? controller;
  final bool controllerLoading;
  final Future<PrepareResult> Function({bool autoUnlock}) onPrepare;
  final ValueChanged<Map<String, dynamic>> onPatch;
  final VoidCallback onEnded;
  final ValueChanged<int> onOpenEpisodePage;
  final ValueChanged<int> onSelectEpisode;
  final VoidCallback onCloseEpisodePage;
  final ValueChanged<bool>? onChromeVisibilityChanged;

  @override
  State<NativeVideoPage> createState() => _NativeVideoPageState();
}

class _NativeVideoPageState extends State<NativeVideoPage> {
  Timer? _hideTimer;
  VideoPlayerController? _listeningController;
  OverlayEntry? _lockedOverlayEntry;

  bool _loading = false;
  bool _prepareFailed = false;
  bool _uiVisible = true;
  bool _playButtonVisible = false;
  bool _centerButtonVisibleByTap = false;
  bool _favoriteSubmitting = false;
  bool _userPaused = false;
  bool _ignoreNextSurfaceTap = false;
  bool _ended = false;
  bool _reportedWatch = false;
  bool _lockedOverlay = false;
  bool _lockedOverlaySuspended = false;
  bool _handlingLockedAction = false;
  bool _autoHandledLocked = false;
  bool _showProgressText = false;
  bool _isSeeking = false;
  bool _appliedInitialPosition = false;
  bool _videoPaySheetOpen = false;
  String _captionText = '';
  double _speed = 1;
  double? _dragFraction;
  int _positionSeconds = 0;
  Future<List<_VideoRetentionOffer>>? _retentionOffersFuture;
  Future<List<_VideoRetentionCover>>? _retentionCoversFuture;

  bool get _isForYou => widget.scene == NativeVideoScene.forYou;
  bool get _isEpisode => widget.scene == NativeVideoScene.episode;
  bool get _appleRetentionMode =>
      Global.webPreview || (!kIsWeb && Platform.isIOS);

  @override
  void initState() {
    super.initState();
    _syncController(null, widget.controller);
    if (widget.active) {
      _ensureVideoReady();
      _warmVideoRetentionOffersAfterFrame();
    }
  }

  @override
  void didUpdateWidget(covariant NativeVideoPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_text(oldWidget.item['ep_id']) != _text(widget.item['ep_id'])) {
      _resetLockedStateForNewItem();
    }
    if (oldWidget.controller != widget.controller) {
      _syncController(oldWidget.controller, widget.controller);
    }
    if (widget.active && !oldWidget.active) {
      _hideTimer?.cancel();
      _playButtonVisible = false;
      _centerButtonVisibleByTap = false;
      _userPaused = false;
      _ensureVideoReady();
      _warmVideoRetentionOffersAfterFrame();
    } else if (!widget.active && oldWidget.active) {
      _pause();
    }
    _syncLockedOverlayEntry();
  }

  void _closeEpisodePage() {
    widget.onCloseEpisodePage();
  }

  void _resetLockedStateForNewItem() {
    _hideTimer?.cancel();
    _loading = false;
    _prepareFailed = false;
    _lockedOverlay = false;
    _lockedOverlaySuspended = false;
    _handlingLockedAction = false;
    _autoHandledLocked = false;
    _uiVisible = false;
    _playButtonVisible = false;
    _centerButtonVisibleByTap = false;
    _userPaused = false;
    _captionText = '';
    _removeLockedOverlayEntry();
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _listeningController?.removeListener(_onVideoTick);
    _removeLockedOverlayEntry();
    WakelockPlus.disable();
    super.dispose();
  }

  void _syncLockedOverlayEntry() {
    if (!mounted ||
        !_lockedOverlay ||
        _lockedOverlaySuspended ||
        !widget.active) {
      _removeLockedOverlayEntry();
      return;
    }
    if (_lockedOverlayEntry != null) {
      _lockedOverlayEntry?.markNeedsBuild();
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          !_lockedOverlay ||
          _lockedOverlaySuspended ||
          !widget.active) {
        return;
      }
      final overlay = Overlay.maybeOf(context);
      if (overlay == null || _lockedOverlayEntry != null) {
        return;
      }
      final entry = OverlayEntry(
        builder: (overlayContext) => Positioned.fill(
          child: _LockedOverlay(
            onBack: () {
              if (mounted) {
                _closeEpisodePage();
              }
            },
            onGetVip: _openVipPayFromOverlay,
          ),
        ),
      );
      _lockedOverlayEntry = entry;
      overlay.insert(entry);
    });
  }

  void _removeLockedOverlayEntry() {
    _lockedOverlayEntry?.remove();
    _lockedOverlayEntry?.dispose();
    _lockedOverlayEntry = null;
  }

  void _suspendLockedOverlayEntry() {
    _lockedOverlaySuspended = true;
    _removeLockedOverlayEntry();
  }

  void _resumeLockedOverlayEntry() {
    _lockedOverlaySuspended = false;
    _syncLockedOverlayEntry();
  }

  void _syncController(
    VideoPlayerController? oldController,
    VideoPlayerController? controller,
  ) {
    oldController?.removeListener(_onVideoTick);
    if (_listeningController != null && _listeningController != oldController) {
      _listeningController?.removeListener(_onVideoTick);
    }
    _listeningController = controller;
    if (controller != null) {
      _prepareFailed = false;
    }
    _ended = false;
    _playButtonVisible = false;
    _centerButtonVisibleByTap = false;
    _userPaused = false;
    _captionText = '';
    if (controller == null) {
      if (_isEpisode) {
        _uiVisible = false;
      }
      _appliedInitialPosition = false;
      return;
    }
    controller.addListener(_onVideoTick);
    unawaited(_applyInitialPlaybackPosition());
    if (widget.active) {
      unawaited(_playController(controller));
      _startAutoHide();
    }
  }

  Future<void> _ensureVideoReady({bool autoUnlock = false}) async {
    if (widget.controller != null || _loading || widget.controllerLoading) {
      if (widget.active) {
        final controller = widget.controller;
        if (controller != null) {
          _playController(controller);
          _startAutoHide();
        } else if (_isEpisode && mounted) {
          setState(() {
            _uiVisible = false;
            _playButtonVisible = false;
            _centerButtonVisibleByTap = false;
            _userPaused = false;
          });
        }
      }
      return;
    }

    setState(() {
      _loading = true;
      _prepareFailed = false;
      _playButtonVisible = false;
      _centerButtonVisibleByTap = false;
      _userPaused = false;
      if (_isEpisode) {
        _uiVisible = false;
      }
    });
    final result = await widget.onPrepare(autoUnlock: autoUnlock);
    if (!mounted) {
      return;
    }
    final locked = result == PrepareResult.locked;
    final failed =
        result == PrepareResult.none || result == PrepareResult.error;
    setState(() {
      _loading = false;
      _prepareFailed = failed;
      _lockedOverlay = locked;
      if (locked) {
        _uiVisible = false;
        _playButtonVisible = false;
        _centerButtonVisibleByTap = false;
      }
    });
    _syncLockedOverlayEntry();
    if (locked && _isEpisode) {
      _scheduleInitialLockedAction();
    }
  }

  void _scheduleInitialLockedAction() {
    if (_autoHandledLocked || _handlingLockedAction || !widget.active) {
      return;
    }
    _autoHandledLocked = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && widget.active) {
        unawaited(_handleLockedAction());
      }
    });
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

  Future<void> _playController(
    VideoPlayerController controller, {
    bool userInitiated = false,
  }) async {
    try {
      if (!widget.active) {
        await controller.setVolume(0);
        await controller.pause();
        return;
      }
      await controller.setVolume(kIsWeb ? 0 : 1);
      await VideoPlaybackSession.play(controller);
      if (!kIsWeb) {
        await WakelockPlus.enable();
      }
      if (mounted) {
        setState(() {
          _playButtonVisible = false;
          _centerButtonVisibleByTap = false;
          _userPaused = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _playButtonVisible = userInitiated;
          _centerButtonVisibleByTap = userInitiated && _isEpisode;
          _userPaused = userInitiated;
        });
      }
    }
  }

  Future<void> _applyInitialPlaybackPosition() async {
    if (_appliedInitialPosition) {
      return;
    }
    final controller = widget.controller;
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
    final controller = widget.controller;
    if (controller == null || !controller.value.isInitialized) {
      return;
    }
    final seconds = controller.value.position.inSeconds;
    final captionText = controller.value.caption.text.trim();
    if ((seconds != _positionSeconds || captionText != _captionText) &&
        mounted) {
      setState(() {
        _positionSeconds = seconds;
        _captionText = captionText;
      });
    }
    if (!_reportedWatch && controller.value.isPlaying) {
      _reportedWatch = true;
      _reportWatchProgress();
    }
    if (controller.value.isCompleted && !_ended) {
      _ended = true;
      widget.onEnded();
    }
  }

  Future<void> _reportWatchProgress() async {
    if (!widget.active) {
      return;
    }
    final movieId = parseMovieId(widget.item);
    if (movieId == null) {
      return;
    }
    final result = await api<dynamic>(
      'movie/history/report',
      method: Method.post,
      data: {
        'type': 'ep_prog',
        'movie_id': movieId,
        'ep_id': widget.item['ep_id'],
        'ep_no': widget.item['episode'],
        'duration': 1,
      },
      loading: false,
      showError: false,
    );
    if (result.c == 0) {
      await Global.sp.setBool('update_history', true);
      Global.watchHistoryUpdates.value++;
    }
  }

  void _startAutoHide({bool showCenterButton = false}) {
    _hideTimer?.cancel();
    final controllerReady = widget.controller?.value.isInitialized == true;
    if (_isEpisode && !controllerReady) {
      setState(() {
        _uiVisible = false;
        _centerButtonVisibleByTap = false;
      });
      return;
    }
    setState(() {
      _uiVisible = true;
      if (_isEpisode) {
        _centerButtonVisibleByTap = showCenterButton;
      }
    });
    if (!_isEpisode) {
      return;
    }
    _hideTimer = Timer(Duration(seconds: 5), () {
      if (mounted && widget.controller?.value.isPlaying == true) {
        setState(() => _uiVisible = false);
      }
    });
  }

  void _togglePlay() {
    final controller = widget.controller;
    if (controller == null || !controller.value.isInitialized) {
      return;
    }
    _startAutoHide();
    if (controller.value.isPlaying) {
      Global.logger.d(
        'native_video_interaction pause scene=${_isForYou ? 'for_you' : 'video'} ep=${widget.item['episode']}',
      );
      setState(() {
        _playButtonVisible = true;
        if (_isEpisode) {
          _centerButtonVisibleByTap = true;
        }
        _userPaused = true;
      });
      unawaited(VideoPlaybackSession.pause(controller));
      WakelockPlus.disable();
    } else {
      Global.logger.d(
        'native_video_interaction play scene=${_isForYou ? 'for_you' : 'video'} ep=${widget.item['episode']}',
      );
      setState(() {
        _playButtonVisible = false;
        if (_isEpisode) {
          _centerButtonVisibleByTap = true;
        }
        _userPaused = false;
      });
      _playController(controller, userInitiated: true);
    }
  }

  void _onVideoTapUp(TapUpDetails details) {
    if (_ignoreNextSurfaceTap) {
      _ignoreNextSurfaceTap = false;
      return;
    }
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

  void _markChromeTap() {
    _ignoreNextSurfaceTap = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _ignoreNextSurfaceTap = false;
      }
    });
  }

  void _onLongPressStart(LongPressStartDetails _) {
    widget.controller?.setPlaybackSpeed(2);
    Global.logger.d(
      'native_video_interaction long_press_start scene=${_isForYou ? 'for_you' : 'video'}',
    );
    _notifyChromeVisible(false);
    setState(() {
      _uiVisible = false;
      _playButtonVisible = false;
      _centerButtonVisibleByTap = false;
    });
  }

  void _onLongPressEnd(LongPressEndDetails _) {
    widget.controller?.setPlaybackSpeed(_speed);
    Global.logger.d(
      'native_video_interaction long_press_end scene=${_isForYou ? 'for_you' : 'video'}',
    );
    _notifyChromeVisible(true);
    setState(() => _uiVisible = true);
    _startAutoHide();
  }

  void _toggleUi() {
    if (_lockedOverlay) {
      return;
    }
    Global.logger.d(
      'native_video_interaction toggle_ui visible=${!_uiVisible} ep=${widget.item['episode']}',
    );
    final nextVisible = !_uiVisible;
    setState(() {
      _uiVisible = nextVisible;
      if (_isEpisode) {
        _centerButtonVisibleByTap = nextVisible;
      }
    });
    if (_uiVisible) {
      _startAutoHide(showCenterButton: true);
    } else {
      _centerButtonVisibleByTap = false;
      _hideTimer?.cancel();
    }
  }

  void _onSeekStart() {
    _hideTimer?.cancel();
    final controller = widget.controller;
    if (controller == null || !controller.value.isInitialized) {
      return;
    }
    setState(() {
      _isSeeking = true;
      _showProgressText = true;
      _dragFraction = _progressFraction(controller);
      _uiVisible = false;
      _playButtonVisible = false;
      _centerButtonVisibleByTap = false;
    });
    Global.logger.d(
      'native_video_interaction seek_start scene=${_isForYou ? 'for_you' : 'video'}',
    );
    _notifyChromeVisible(false);
  }

  void _onSeekChanged(double value) {
    setState(() {
      _dragFraction = value.clamp(0.0, 1.0);
      _showProgressText = true;
    });
  }

  Future<void> _onSeekEnd(double value) async {
    final controller = widget.controller;
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
      _centerButtonVisibleByTap = false;
      _userPaused = false;
    });
    Global.logger.d(
      'native_video_interaction seek_end scene=${_isForYou ? 'for_you' : 'video'} value=${value.toStringAsFixed(3)}',
    );
    _notifyChromeVisible(true);
    if (widget.active) {
      await _playController(controller);
      _startAutoHide();
    }
  }

  void _notifyChromeVisible(bool visible) {
    if (_isForYou) {
      widget.onChromeVisibilityChanged?.call(visible);
    }
  }

  void _pause() {
    _hideTimer?.cancel();
    final controller = widget.controller;
    if (controller != null) {
      unawaited(controller.setVolume(0));
      unawaited(VideoPlaybackSession.pause(controller));
    }
    _centerButtonVisibleByTap = false;
    WakelockPlus.disable();
  }

  Future<void> _toggleFavorite() async {
    if (_favoriteSubmitting) {
      return;
    }
    final favor = _boolValue(
      widget.item['is_favor'] ?? widget.item['isFavorite'],
    );
    final movieId = parseMovieId(widget.item);
    if (movieId == null) {
      return;
    }
    final path = favor ? 'movie/favorite/delete' : 'movie/favorite';
    final nextFavor = !favor;

    setState(() => _favoriteSubmitting = true);
    widget.onPatch({'is_favor': nextFavor, 'isFavorite': nextFavor});
    try {
      final result = await api<dynamic>(
        path,
        method: Method.post,
        data: {'id': movieId},
        loading: false,
      );
      if (result.c == 0) {
        Global.logger.d(
          'native_video_favorite toggled movie=$movieId favorite=$nextFavor',
        );
        Global.sp.setBool('update_favorite', true);
        return;
      }

      widget.onPatch({'is_favor': favor, 'isFavorite': favor});
    } on Exception catch (error) {
      Global.logger.d(
        'native_video_favorite failed movie=$movieId error=$error',
      );
      widget.onPatch({'is_favor': favor, 'isFavorite': favor});
    } finally {
      if (mounted) {
        setState(() => _favoriteSubmitting = false);
      }
    }
  }

  Future<void> _share() async {
    final id = parseMovieId(widget.item);
    final episode = widget.item['episode'] ?? widget.item['ep_no'];
    if (id == null || _text(episode).isEmpty) {
      return;
    }

    final result = await api<dynamic>(
      'share/url',
      method: Method.post,
      data: {'id': id, 'episode': int.tryParse(_text(episode)) ?? episode},
      loading: true,
    );
    final payload = result.d;
    final url = payload is Map ? _text(payload['url']) : '';
    if (result.c == 0 && url.isNotEmpty) {
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
          onCopy: () async {
            await Clipboard.setData(ClipboardData(text: url));
            if (context.mounted) {
              Navigator.pop(context);
            }
            Global.success(t.success);
          },
          onFacebook: () async {
            if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) {
              final installed = await canLaunchUrl(Uri.parse('fb://'));
              if (!installed) {
                Global.warning(_notFindText(t.facebook));
                return;
              }
              if (!context.mounted) {
                return;
              }
              Navigator.pop(context);
              final launched = await _launchExternal(
                'fb://share?link=${Uri.encodeComponent(url)}',
              );
              if (!launched) {
                Global.warning(_notFindText(t.facebook));
              }
              return;
            }
            final launched = await _launchExternal(
              'fb://share?link=${Uri.encodeComponent(url)}',
            );
            final fallbackLaunched =
                !launched &&
                await _launchExternal(
                  'https://www.facebook.com/sharer/sharer.php?u=${Uri.encodeComponent(url)}',
                );
            if (!launched && !fallbackLaunched) {
              Global.warning(_notFindText(t.facebook));
            }
          },
          onX: () async {
            if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) {
              final installed = await canLaunchUrl(Uri.parse('twitter://'));
              if (!installed) {
                Global.warning(_notFindText(t.x_app));
                return;
              }
              if (!context.mounted) {
                return;
              }
              Navigator.pop(context);
              final message = '${_title()} $url'.trim();
              final launched = await _launchExternal(
                'twitter://post?message=${Uri.encodeComponent(message)}',
              );
              if (!launched) {
                Global.warning(_notFindText(t.x_app));
              }
              return;
            }
            final launched = await _launchExternal(
              'https://twitter.com/intent/tweet?url=${Uri.encodeComponent(url)}&text=${Uri.encodeComponent(_title())}',
            );
            if (!launched) {
              Global.warning(_notFindText(t.x_app));
            }
          },
        );
      },
    );
  }

  Future<bool> _launchExternal(String url) async {
    try {
      final launched = await launchUrl(
        Uri.parse(url),
        mode: LaunchMode.externalApplication,
      );
      Global.logger.d('share_launch url=$url launched=$launched');
      return launched;
    } on Exception catch (error) {
      Global.logger.d('share_launch_failed url=$url error=$error');
      return false;
    }
  }

  Future<void> _showSpeedSheet() async {
    final selected = await showModalBottomSheet<double>(
      context: context,
      backgroundColor: Colors.transparent,
      useSafeArea: false,
      builder: (context) {
        return _PlaybackSpeedSheet(currentSpeed: _speed);
      },
    );
    if (selected != null) {
      setState(() => _speed = selected);
      widget.controller?.setPlaybackSpeed(selected);
    }
  }

  void _showIntro() {
    unawaited(_openIntroSheet());
  }

  Future<void> _openIntroSheet() async {
    final tag = await showModalBottomSheet<_VideoTagData>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black,
      builder: (sheetContext) {
        return SafeArea(
          top: false,
          child: _ShortIntroSheet(
            title: _introTitle(),
            introduction: _introIntroduction(),
            image: _introImage(),
            tags: _introTags(),
            onTag: (tag) => Navigator.of(sheetContext).pop(tag),
          ),
        );
      },
    );
    if (tag != null && mounted) {
      _openTag(tag);
    }
  }

  void _openTag(_VideoTagData tag) {
    if (tag.id.isEmpty) {
      return;
    }
    context.push(
      Uri(
        path: '/label',
        queryParameters: {'title': tag.name, 'tag': tag.id},
      ).toString(),
    );
  }

  Map<String, dynamic> _introSeriesInfo() {
    return _asMap(widget.series?['info']);
  }

  String _introTitle() {
    final itemTitle = _text(widget.item['title']);
    return itemTitle.isNotEmpty
        ? itemTitle
        : _text(_introSeriesInfo()['title']);
  }

  String _introIntroduction() {
    final itemIntroduction = _text(widget.item['introduction']);
    return itemIntroduction.isNotEmpty
        ? itemIntroduction
        : _text(_introSeriesInfo()['introduction']);
  }

  String _introImage() {
    final itemImage = _posterUrl(widget.item);
    return itemImage.isNotEmpty ? itemImage : _posterUrl(_introSeriesInfo());
  }

  List<_VideoTagData> _introTags() {
    final itemTags = _videoTags(widget.item);
    return itemTags.isNotEmpty ? itemTags : _videoTags(_introSeriesInfo());
  }

  void _showEpisodes() {
    if (widget.episodes.isEmpty) {
      return;
    }
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) {
        return _EpisodeSheet(
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
    if (_handlingLockedAction) {
      return;
    }
    _handlingLockedAction = true;
    _showLockedOverlay();
    try {
      if (context.read<UserState>().isVip) {
        final episode = await _fetchEpisode(autoUnlock: false);
        if (!mounted) {
          return;
        }
        if (episode != null &&
            !_isEpisodeLocked(episode) &&
            _text(episode['video']).isNotEmpty) {
          widget.onPatch(episode);
          _clearLockedState();
          await widget.onPrepare(autoUnlock: false);
        }
        return;
      }

      if (await _isAutoUnlockEnabled()) {
        final episode = await _fetchEpisode(autoUnlock: true);
        if (!mounted) {
          return;
        }
        if (episode != null &&
            !_isEpisodeLocked(episode) &&
            _text(episode['video']).isNotEmpty) {
          widget.onPatch(episode);
          _clearLockedState();
          await widget.onPrepare(autoUnlock: true);
          return;
        }
        final unlockCoins = _unlockCoinsFrom(episode) > 0
            ? _unlockCoinsFrom(episode)
            : _unlockCoinsFrom(widget.item);
        await _showTopUpAndVerify(unlockCoins);
        return;
      }

      final episode = await _fetchEpisode(autoUnlock: false);
      if (!mounted) {
        return;
      }
      if (episode != null &&
          !_isEpisodeLocked(episode) &&
          _text(episode['video']).isNotEmpty) {
        widget.onPatch(episode);
        _clearLockedState();
        await widget.onPrepare(autoUnlock: false);
        return;
      }

      final unlockCoins = _unlockCoinsFrom(episode) > 0
          ? _unlockCoinsFrom(episode)
          : _unlockCoinsFrom(widget.item);
      if (unlockCoins > 0) {
        await _showCoinUnlock(unlockCoins);
        return;
      }
      await _showTopUpAndVerify(unlockCoins);
    } finally {
      _handlingLockedAction = false;
    }
  }

  Future<void> _openVipPayFromOverlay() async {
    if (_handlingLockedAction) {
      return;
    }
    _handlingLockedAction = true;
    try {
      final episode = await _fetchEpisode(autoUnlock: false);
      if (!mounted || !widget.active) {
        return;
      }
      if (episode != null) {
        widget.onPatch(episode);
        if (!_isEpisodeLocked(episode) && _text(episode['video']).isNotEmpty) {
          _clearLockedState();
          await widget.onPrepare(autoUnlock: false);
          return;
        }
      }
      final unlockCoins = _unlockCoinsFrom(episode) > 0
          ? _unlockCoinsFrom(episode)
          : _unlockCoinsFrom(widget.item);
      await _showTopUpAndVerify(unlockCoins);
    } finally {
      _handlingLockedAction = false;
    }
  }

  Future<bool> _isAutoUnlockEnabled() async {
    if (Global.sp.containsKey(_NativeVideoFeedState._autoUnlockKey)) {
      return Global.sp.getBool(_NativeVideoFeedState._autoUnlockKey) == true;
    }
    final config = await api<Map<String, dynamic>>(
      'user/config',
      method: Method.post,
      loading: false,
    );
    final wallet = _asMap(config.d?['wallet']);
    final enabled = _boolValue(wallet['auto_unlock_next']);
    await Global.sp.setBool(_NativeVideoFeedState._autoUnlockKey, enabled);
    return enabled;
  }

  void _restoreLockedOverlayIfStillLocked() {
    if (!mounted || !_isEpisode || !widget.active) {
      return;
    }
    final hasVideo = _text(widget.item['video']).isNotEmpty;
    if (!hasVideo && _isLockedItem(widget.item)) {
      setState(() {
        _lockedOverlay = true;
      });
      _syncLockedOverlayEntry();
    }
  }

  void _showLockedOverlay() {
    if (!mounted || !_isEpisode || !_isLockedItem(widget.item)) {
      return;
    }
    setState(() {
      _lockedOverlay = true;
      _uiVisible = false;
      _playButtonVisible = false;
    });
    _syncLockedOverlayEntry();
  }

  void _clearLockedState() {
    if (!mounted) {
      return;
    }
    setState(() {
      _lockedOverlay = false;
      _uiVisible = true;
    });
    _removeLockedOverlayEntry();
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
      await _showTopUpAndVerify(unlockCoins);
      return;
    }
    var openedTopUp = false;
    _suspendLockedOverlayEntry();
    bool? confirmed;
    try {
      confirmed = await showModalBottomSheet<bool>(
        context: context,
        backgroundColor: Colors.transparent,
        builder: (sheetContext) => _CoinUnlockSheet(
          unlockCoins: unlockCoins,
          balanceCoins: balanceCoins,
          onSubscribe: () {
            openedTopUp = true;
            Navigator.pop(sheetContext, false);
          },
        ),
      );
    } finally {
      if (mounted) {
        _resumeLockedOverlayEntry();
      }
    }
    if (openedTopUp) {
      await _showTopUpAndVerify(unlockCoins);
      return;
    }
    if (confirmed != true) {
      _restoreLockedOverlayIfStillLocked();
      return;
    }
    if (confirmed == true) {
      final episode = await _fetchEpisode(autoUnlock: true);
      if (episode != null &&
          !_isEpisodeLocked(episode) &&
          _text(episode['video']).isNotEmpty) {
        widget.onPatch(episode);
        _clearLockedState();
        await widget.onPrepare(autoUnlock: true);
      } else {
        Global.warning(t.unlock_failed(code: ''));
        _restoreLockedOverlayIfStillLocked();
      }
    }
  }

  Future<void> _showTopUpAndVerify(int unlockCoins) async {
    if (_videoPaySheetOpen) {
      return;
    }
    Global.payTrace('video open pay sheet unlockCoins=$unlockCoins');
    _videoPaySheetOpen = true;
    final retentionOffersFuture = _prefetchVideoRetentionOffers();
    _suspendLockedOverlayEntry();
    VipPayResult? payResult;
    try {
      payResult = await showVipPayBottomSheet(
        context,
        episodeCoins: _isEpisode ? unlockCoins.toString() : null,
      );
      if (!mounted || !widget.active) {
        return;
      }
      if (payResult == null) {
        Global.payTrace('video pay sheet cancelled');
        final handledRetention = await _runVideoRetentionOffers(
          unlockCoins,
          retentionOffersFuture,
        );
        if (!handledRetention) {
          _restoreLockedOverlayIfStillLocked();
        }
        return;
      }
      Global.payTrace('video pay sheet result=$payResult');
      await _verifyPendingUnlockAfterTopUp(unlockCoins, payResult);
    } finally {
      _videoPaySheetOpen = false;
      if (mounted) {
        _resumeLockedOverlayEntry();
      }
    }
  }

  void _openVipPayFromAction() {
    unawaited(_openVipPayFromActionFlow());
  }

  Future<void> _openVipPayFromActionFlow() async {
    if (_videoPaySheetOpen) {
      return;
    }
    _videoPaySheetOpen = true;
    final unlockCoins = _unlockCoinsFrom(widget.item);
    final retentionOffersFuture = _prefetchVideoRetentionOffers();
    VipPayResult? payResult;
    try {
      payResult = await showVipPayBottomSheet(
        context,
        episodeCoins: _isEpisode ? unlockCoins.toString() : null,
      );
    } finally {
      _videoPaySheetOpen = false;
    }
    if (!mounted || !widget.active) {
      return;
    }
    if (payResult == null) {
      Global.payTrace('video action pay sheet cancelled');
      await _runVideoRetentionOffers(unlockCoins, retentionOffersFuture);
      return;
    }
    Global.payTrace('video action pay sheet result=$payResult');
    await _verifyPendingUnlockAfterTopUp(unlockCoins, payResult);
  }

  Future<List<_VideoRetentionOffer>> _prefetchVideoRetentionOffers() {
    return _prefetchVideoRetentionOffersInternal();
  }

  void _warmVideoRetentionOffersAfterFrame() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !widget.active) {
        return;
      }
      unawaited(_prefetchVideoRetentionOffersInternal());
    });
  }

  Future<List<_VideoRetentionOffer>> _prefetchVideoRetentionOffersInternal({
    bool forceRefresh = false,
  }) {
    if (!_appleRetentionMode || context.read<UserState>().isVip) {
      return Future.value(const []);
    }
    _retentionCoversFuture ??= _fetchVideoRetentionCovers();
    if (!forceRefresh && _retentionOffersFuture != null) {
      return _retentionOffersFuture!;
    }
    final task = _fetchVideoRetentionOffers();
    _retentionOffersFuture = task;
    unawaited(
      task.then<void>(
        (offers) {
          if (offers.isEmpty && identical(_retentionOffersFuture, task)) {
            _retentionOffersFuture = null;
          }
        },
        onError: (_, _) {
          if (identical(_retentionOffersFuture, task)) {
            _retentionOffersFuture = null;
          }
        },
      ),
    );
    return task;
  }

  Future<List<_VideoRetentionOffer>> _fetchVideoRetentionOffers() async {
    try {
      await Global.ensureAnonymousSession();
      Global.payTrace('video retention products request price_type=1');
      final products = await api<dynamic>(
        'applePay/products',
        method: Method.post,
        data: {'price_type': 1},
        loading: false,
        showError: false,
      );
      Global.payTrace(
        'video retention products response c=${products.c} m=${products.m}',
      );
      if (products.c != 0) {
        return const [];
      }
      var offers = _orderedVideoRetentionOffers(
        _videoRetentionRows(products.d),
      );
      if (offers.isEmpty) {
        return const [];
      }
      if (!Global.webPreview && !kIsWeb && Platform.isIOS) {
        final productIds = offers
            .map((offer) => offer.storeProductId)
            .where((id) => id.trim().isNotEmpty)
            .toSet();
        unawaited(Purchase.warmUpProductDetails(productIds));
        var eligibility = Purchase.cachedIntroductoryOfferEligibility(
          productIds,
        );
        if (eligibility.isEmpty) {
          eligibility = await Purchase.introductoryOfferEligibility(productIds);
        }
        if (eligibility.isEmpty) {
          Global.payTrace(
            'video retention eligibility empty, retry after warmup',
          );
          await Purchase.warmUpProductDetails(productIds);
          eligibility = await Purchase.introductoryOfferEligibility(productIds);
        }
        if (eligibility.isEmpty) {
          Global.payTrace('video retention eligibility empty after retry');
          return const [];
        }
        offers = offers.where((offer) {
          return eligibility[offer.storeProductId] == true;
        }).toList();
        if (offers.isEmpty) {
          Global.payTrace('video retention no eligible offers');
          return const [];
        }
        Global.payTrace(
          'video retention eligible offers=${offers.map((offer) => offer.storeProductId).join(',')}',
        );
      }
      unawaited(
        Purchase.warmUpProductDetails(
          offers.map((offer) => offer.storeProductId),
        ),
      );
      return offers;
    } on Exception catch (error) {
      Global.logger.d('video retention products failed error=$error');
      Global.payTrace('video retention products failed error=$error');
      return const [];
    }
  }

  Future<List<_VideoRetentionCover>> _fetchVideoRetentionCovers() async {
    try {
      final videos = await api<dynamic>(
        'feed/membership?page=1',
        method: Method.post,
        loading: false,
        showError: false,
      );
      if (videos.c != 0) {
        return const [];
      }
      return _videoRetentionCoverRows(videos.d)
          .take(5)
          .map(_VideoRetentionCover.fromRaw)
          .where((cover) => cover.image.isNotEmpty)
          .toList();
    } on Exception catch (error) {
      Global.logger.d('video retention covers failed error=$error');
      return const [];
    }
  }

  Future<bool> _runVideoRetentionOffers(
    int unlockCoins,
    Future<List<_VideoRetentionOffer>> offersFuture,
  ) async {
    if (!_appleRetentionMode || context.read<UserState>().isVip) {
      return false;
    }
    var offers = await offersFuture;
    if (offers.isEmpty) {
      _retentionOffersFuture = null;
      offers = await _prefetchVideoRetentionOffersInternal(forceRefresh: true);
    }
    if (!mounted || !widget.active || offers.isEmpty) {
      return false;
    }
    for (var index = 0; index < offers.length; index += 1) {
      if (!mounted || !widget.active) {
        return false;
      }
      final isVip = context.read<UserState>().isVip;
      if (isVip) {
        return true;
      }
      final offer = offers[index];
      final retentionStep = _videoRetentionStepForOffer(
        offer,
        fallbackStep: index + 1,
      );
      final selection = await _showVideoRetentionOffer(
        offer,
        step: retentionStep,
        total: offers.length,
      );
      if (!mounted || !widget.active) {
        return false;
      }
      if (selection == null) {
        Global.payTrace('video retention dismissed step=$retentionStep');
        continue;
      }
      final selected = selection.offer;
      final purchased =
          selection.purchased || await _purchaseVideoRetentionOffer(selected);
      if (!mounted || !widget.active) {
        return purchased;
      }
      if (!purchased) {
        Global.payTrace('video retention purchase cancelled');
        return false;
      }
      Global.payTrace('video retention purchase success');
      await _verifyPendingUnlockAfterTopUp(unlockCoins, VipPayResult.vip);
      return true;
    }
    return false;
  }

  Future<_VideoRetentionOfferSelection?> _showVideoRetentionOffer(
    _VideoRetentionOffer offer, {
    required int step,
    required int total,
  }) {
    final usesFinalClosePurchase =
        step >= 3 && !offer.isQuarterly && !Global.deleteAccountEnabled;
    return showModalBottomSheet<_VideoRetentionOfferSelection>(
      context: context,
      isScrollControlled: true,
      isDismissible: !usesFinalClosePurchase,
      enableDrag: false,
      barrierColor: Colors.black.withAlpha(184),
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return _VideoRetentionOfferSheet(
          offer: offer,
          step: step,
          total: total,
          coversFuture:
              _retentionCoversFuture ??
              Future<List<_VideoRetentionCover>>.value(
                const <_VideoRetentionCover>[],
              ),
          enableFinalClosePurchase: usesFinalClosePurchase,
          onOfferPurchase: _purchaseVideoRetentionOffer,
          onFinalClosePurchase: (selectedOffer) async {
            final purchased = await _purchaseVideoRetentionOffer(selectedOffer);
            if (Global.webPreview) {
              return false;
            }
            return purchased;
          },
        );
      },
    );
  }

  Future<bool> _purchaseVideoRetentionOffer(_VideoRetentionOffer offer) async {
    Global.payTrace(
      'video retention purchase localProductId=${offer.localProductId} appleProductId=${offer.storeProductId}',
    );
    final priceType = await Purchase.introductoryPriceType(
      offer.storeProductId,
    );
    await _trackVideoRetentionCheckout(offer);
    final result = Global.webPreview
        ? await Purchase.previewCreate(
            localProductId: offer.localProductId,
            appleProductId: offer.storeProductId,
            type: 1,
            priceType: priceType,
          )
        : await Purchase.making(
            localProductId: offer.localProductId,
            appleProductId: offer.storeProductId,
            type: 1,
            priceType: priceType,
          );
    if (result) {
      await _trackVideoRetentionSubscribe(offer);
    }
    return result;
  }

  Future<void> _trackVideoRetentionCheckout(_VideoRetentionOffer offer) async {
    if (Global.webPreview) {
      Global.payTrace('web preview skip retention checkout tracking');
      return;
    }
    final price = double.tryParse(offer.price) ?? 0;
    AdjustTracking.trackInitiateCheckout(
      productId: offer.storeProductId,
      amount: price,
    );
    try {
      await TikTokEventsSdk.logEvent(
        event: TikTokEvent(
          eventName: 'checkout',
          properties: EventProperties(
            description: offer.storeProductId,
            value: price,
            currency: CurrencyCode.USD,
          ),
        ),
      );
    } on Object catch (error) {
      Global.logger.d('video retention checkout tracking failed: $error');
      Global.payTrace('video retention checkout tracking failed $error');
    }
  }

  Future<void> _trackVideoRetentionSubscribe(_VideoRetentionOffer offer) async {
    if (Global.webPreview) {
      Global.payTrace('web preview skip retention subscribe tracking');
      return;
    }
    final price = double.tryParse(offer.price) ?? 0;
    try {
      await TikTokEventsSdk.logEvent(
        event: TikTokEvent(
          eventName: 'subscribe',
          properties: EventProperties(
            description: offer.storeProductId,
            value: price,
            currency: CurrencyCode.USD,
          ),
        ),
      );
    } on Object catch (error) {
      Global.logger.d('video retention subscribe tracking failed: $error');
      Global.payTrace('video retention subscribe tracking failed $error');
    }
  }

  Future<void> _verifyPendingUnlockAfterTopUp(
    int unlockCoins,
    VipPayResult? payResult,
  ) async {
    final delays = [
      Duration.zero,
      Duration(milliseconds: 800),
      Duration(milliseconds: 1600),
      Duration(seconds: 3),
    ];
    for (var index = 0; index < delays.length; index += 1) {
      final delay = delays[index];
      if (delay > Duration.zero) {
        await Future.delayed(delay);
      }
      if (!mounted || !widget.active) {
        return;
      }
      Global.payTrace('video verify attempt=${index + 1}');
      final handled = await _tryContinueAfterTopUp(unlockCoins, payResult);
      if (handled) {
        Global.payTrace('video verify handled');
        return;
      }
    }
    Global.payTrace('video verify timeout');
    _restoreLockedOverlayIfStillLocked();
  }

  Future<bool> _tryContinueAfterTopUp(
    int unlockCoins,
    VipPayResult? payResult,
  ) async {
    if (payResult != VipPayResult.coins) {
      final vipHandled = await _tryContinueAfterVipPayment();
      if (vipHandled != false) {
        return vipHandled == true;
      }
      if (payResult == VipPayResult.vip) {
        return false;
      }
    }

    if (unlockCoins <= 0) {
      return false;
    }
    final balance = await api<dynamic>(
      'user/balance',
      method: Method.post,
      loading: false,
    );
    if (!mounted || !widget.active) {
      return true;
    }
    if (_intValue(balance.d) < unlockCoins) {
      Global.payTrace('coin balance not enough balance=${balance.d}');
      return false;
    }
    if (await _isAutoUnlockEnabled()) {
      Global.payTrace('coin auto unlock fetch episode');
      final episode = await _fetchEpisode(autoUnlock: true);
      if (!mounted || !widget.active) {
        return true;
      }
      if (episode != null &&
          !_isEpisodeLocked(episode) &&
          _text(episode['video']).isNotEmpty) {
        widget.onPatch(episode);
        _clearLockedState();
        await widget.onPrepare(autoUnlock: true);
        Global.payTrace('coin auto unlock success');
        return true;
      }
      Global.payTrace('coin auto unlock failed');
      return false;
    }
    Global.payTrace('coin show unlock dialog');
    await _showCoinUnlock(unlockCoins);
    return true;
  }

  Future<bool?> _tryContinueAfterVipPayment() async {
    final vip = await api<Map<String, dynamic>>(
      'user/membership',
      method: Method.post,
      loading: false,
    );
    if (!mounted || !widget.active) {
      return null;
    }
    final expire = _intValue(vip.d?['vip_expire_at']);
    Global.logger.d(
      'native_video_vip_check expire=$expire userVip=${context.read<UserState>().isVip}',
    );
    Global.payTrace(
      'vip check c=${vip.c} expire=$expire userVip=${context.read<UserState>().isVip}',
    );
    if (expire <= 0 && !context.read<UserState>().isVip) {
      return false;
    }
    if (expire > 0) {
      context.read<UserState>().setVip(1);
    }
    final episode = await _fetchEpisode(autoUnlock: false);
    if (!mounted || !widget.active) {
      return null;
    }
    if (episode != null &&
        !_isEpisodeLocked(episode) &&
        _text(episode['video']).isNotEmpty) {
      Global.logger.d(
        'native_video_vip_unlocked ep=${episode['episode'] ?? widget.item['episode']}',
      );
      widget.onPatch(episode);
      _clearLockedState();
      await widget.onPrepare(autoUnlock: false);
      Global.payTrace('vip unlock success');
      return true;
    }
    Global.payTrace('vip unlock episode failed');
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final videoReady = controller?.value.isInitialized == true;
    final lockedCoverOnly =
        _isEpisode &&
        !videoReady &&
        !_lockedOverlay &&
        _isLockedItem(widget.item);
    final controlsVisible =
        videoReady && _uiVisible && !_isSeeking && !lockedCoverOnly;
    final centerButtonVisible =
        !lockedCoverOnly &&
        videoReady &&
        (_isEpisode
            ? controlsVisible && _centerButtonVisibleByTap
            : _playButtonVisible);
    final centerButtonPlaying =
        _isEpisode && !_userPaused && (controller?.value.isPlaying == true);
    final videoSize = controller?.value.size ?? Size.zero;
    final isLandscapeVideo = videoReady && videoSize.width > videoSize.height;
    final lockedBackgroundImage = _introImage();
    return Stack(
      fit: StackFit.expand,
      children: [
        ColoredBox(color: Colors.black),
        if (_lockedOverlay && !videoReady && lockedBackgroundImage.isNotEmpty)
          Positioned.fill(
            child: ImageFiltered(
              imageFilter: ui.ImageFilter.blur(sigmaX: 16, sigmaY: 16),
              child: Transform.scale(
                scale: 1.08,
                child: LazyImage(
                  url: lockedBackgroundImage,
                  width: double.infinity,
                  height: double.infinity,
                  fit: BoxFit.cover,
                ),
              ),
            ),
          ),
        if (videoReady)
          Positioned.fill(
            bottom: _isEpisode ? 52 : 0,
            child: GestureDetector(
              onTapUp: _onVideoTapUp,
              onLongPressStart: _onLongPressStart,
              onLongPressEnd: _onLongPressEnd,
              child: FittedBox(
                // Preserve the full frame for landscape videos; portrait
                // shorts keep the existing edge-to-edge presentation.
                fit: isLandscapeVideo ? BoxFit.contain : BoxFit.cover,
                child: SizedBox(
                  width: controller!.value.size.width,
                  height: controller.value.size.height,
                  child: IgnorePointer(child: VideoPlayer(controller)),
                ),
              ),
            ),
          ),
        if (videoReady)
          Positioned.fill(
            bottom: _isEpisode ? 52 : 0,
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTapUp: _onVideoTapUp,
              onLongPressStart: _onLongPressStart,
              onLongPressEnd: _onLongPressEnd,
            ),
          ),
        if (videoReady && _captionText.isNotEmpty && !_lockedOverlay)
          _VideoSubtitle(text: _captionText, bottom: _isEpisode ? 170 : 180),
        if (_loading)
          const _VideoLoading()
        else if (_prepareFailed && !videoReady && !_lockedOverlay)
          _VideoLoadFailed(onRetry: _ensureVideoReady)
        else if (!videoReady && !_lockedOverlay)
          const _VideoLoading(),
        if (!_lockedOverlay && !lockedCoverOnly) ...[
          if (_isEpisode)
            _EpisodeTopBar(
              visible: controlsVisible,
              title: _androidIntText(
                t.ep_int(d: r'$d'),
                _intValue(widget.item['episode']),
              ),
              speed: _speed,
              onBack: _closeEpisodePage,
              onSpeed: _showSpeedSheet,
            ),
          _RightActions(
            visible: controlsVisible,
            isVip: context.read<UserState>().isVip,
            favorite: _boolValue(
              widget.item['is_favor'] ?? widget.item['isFavorite'],
            ),
            favoriteCount: _favoriteText(widget.item['favorite']),
            onVip: _openVipPayFromAction,
            onFavorite: _toggleFavorite,
            onShare: _share,
            onPointerDown: _markChromeTap,
          ),
          _BottomInfo(
            visible: controlsVisible,
            title: _title(),
            description: _description(),
            tags: _videoTags(widget.item),
            watchText: _watchText(),
            showWatchEpisode: _isForYou,
            showSelectEpisode: _isEpisode,
            onTitle: _showIntro,
            onTag: _openTag,
            onWatchEpisode: () => widget.onOpenEpisodePage(
              controller?.value.position.inMilliseconds ?? 0,
            ),
            onPointerDown: _markChromeTap,
          ),
          if (_isEpisode)
            _EpisodeSelectButton(
              visible: controlsVisible,
              text: _watchText(),
              onTap: _showEpisodes,
            ),
          if (videoReady)
            _ProgressTimeOverlay(
              visible: _showProgressText,
              current: _seekPreviewDuration(controller!, _dragFraction),
              total: controller.value.duration,
              bottomOffset: _isEpisode ? 52 : 0,
            ),
          if (videoReady)
            _ProgressBar(
              controller: controller!,
              dragging: _isSeeking,
              dragFraction: _dragFraction,
              bottomOffset: _isEpisode ? 52 : 0,
              onChangeStart: (_) => _onSeekStart(),
              onChanged: _onSeekChanged,
              onChangeEnd: _onSeekEnd,
            ),
          if (centerButtonVisible)
            Center(
              child: _CenterPlayButton(
                playing: centerButtonPlaying,
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

  String _description() {
    final introduction = _text(
      widget.item['introduction'],
    ).replaceAll('\n', '');
    final episode = _intValue(widget.item['episode']);
    if (episode <= 0) {
      return introduction;
    }
    final epText = _androidIntText(t.ep_int(d: r'$d'), episode);
    if (introduction.isEmpty) {
      return epText;
    }
    return '$epText | $introduction';
  }

  String _watchText() {
    final episode = _intValue(widget.item['episode']);
    final total = _intValue(
      widget.item['total_episodes'] ?? widget.episodes.length,
    );
    if (_isForYou && total > 0) {
      return _androidIntText(t.watch_full_series_episodes(d: r'$d'), total);
    }
    if (_isEpisode && total > 0) {
      return _androidPairText(
        t.ep_strings(s: r'$s', s2: r'$s2'),
        episode,
        total,
      );
    }
    return _androidIntText(t.ep_int(d: r'$d'), episode);
  }
}

class _ShortIntroSheet extends StatelessWidget {
  const _ShortIntroSheet({
    required this.title,
    required this.introduction,
    required this.image,
    required this.tags,
    required this.onTag,
  });

  final String title;
  final String introduction;
  final String image;
  final List<_VideoTagData> tags;
  final ValueChanged<_VideoTagData> onTag;

  @override
  Widget build(BuildContext context) {
    final ratio = MediaQuery.of(context).devicePixelRatio.clamp(1.0, 3.0);
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
      ),
      child: Stack(
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(15, 15, 15, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: image.isEmpty
                      ? Container(
                          width: 110,
                          height: 145,
                          color: Color(0xff212121),
                        )
                      : LazyImage(
                          url: image,
                          width: 110,
                          height: 145,
                          fit: BoxFit.cover,
                          cacheWidth: (110 * ratio).round(),
                        ),
                ),
                SizedBox(height: 12),
                Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    height: 1.2,
                  ),
                ),
                if (introduction.isNotEmpty) ...[
                  SizedBox(height: 4),
                  Text(
                    introduction,
                    style: TextStyle(
                      color: Color(0xff999999),
                      fontSize: 14,
                      height: 1.25,
                    ),
                  ),
                ],
                if (tags.isNotEmpty) ...[
                  SizedBox(height: 12),
                  Wrap(
                    spacing: 4,
                    runSpacing: 4,
                    children: tags
                        .map(
                          (tag) => _IntroTag(tag: tag, onTap: () => onTag(tag)),
                        )
                        .toList(),
                  ),
                ],
              ],
            ),
          ),
          PositionedDirectional(
            top: 0,
            end: 0,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => Navigator.of(context).pop(),
              child: Padding(
                padding: EdgeInsets.all(15),
                child: SvgPicture.asset(
                  'assets/images/android/ic_close.svg',
                  width: 24,
                  height: 24,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _IntroTag extends StatelessWidget {
  const _IntroTag({required this.tag, required this.onTap});

  final _VideoTagData tag;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: tag.id.isEmpty ? null : onTap,
      borderRadius: BorderRadius.circular(4),
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        decoration: BoxDecoration(
          color: Color(0xff212121),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          tag.name,
          style: TextStyle(color: Color(0xff999999), fontSize: 12, height: 1.2),
        ),
      ),
    );
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

class _VideoSubtitle extends StatelessWidget {
  const _VideoSubtitle({required this.text, required this.bottom});

  final String text;
  final double bottom;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: 24,
      right: 24,
      bottom: bottom,
      child: IgnorePointer(
        child: Align(
          alignment: Alignment.center,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: 860),
            child: Text(
              text,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.w700,
                decoration: TextDecoration.none,
                shadows: [
                  Shadow(
                    color: Colors.black,
                    blurRadius: 4,
                    offset: Offset(0, 1),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
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
    required this.onPointerDown,
  });

  final bool visible;
  final bool isVip;
  final bool favorite;
  final String favoriteCount;
  final VoidCallback onVip;
  final VoidCallback onFavorite;
  final VoidCallback onShare;
  final VoidCallback onPointerDown;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      right: 15,
      top: 0,
      bottom: 0,
      child: Center(
        child: Transform.translate(
          offset: Offset(0, 20),
          child: Listener(
            behavior: HitTestBehavior.translucent,
            onPointerDown: (_) => onPointerDown(),
            child: AnimatedOpacity(
              opacity: visible ? 1 : 0,
              duration: Duration(milliseconds: 120),
              child: IgnorePointer(
                ignoring: !visible,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (!isVip)
                      _ActionButton(
                        asset: 'ic_video_vip.svg',
                        label: t.vip,
                        color: Color(0xffffd000),
                        onTap: onVip,
                      ),
                    _ActionButton(
                      asset: favorite
                          ? 'ic_collection.svg'
                          : 'ic_collection_nor.svg',
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
    required this.onCopy,
    required this.onFacebook,
    required this.onX,
  });

  final Future<void> Function() onCopy;
  final Future<void> Function() onFacebook;
  final Future<void> Function() onX;

  @override
  Widget build(BuildContext context) {
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
                      style: TextStyle(color: Color(0xfffff9f9), fontSize: 16),
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
                    onTap: onFacebook,
                  ),
                  SizedBox(width: 30),
                  _ShareTarget(
                    icon: 'ic_share_x.png',
                    label: t.x_app,
                    onTap: onX,
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
    required this.onTag,
    required this.onWatchEpisode,
    required this.onPointerDown,
  });

  final bool visible;
  final String title;
  final String description;
  final List<_VideoTagData> tags;
  final String watchText;
  final bool showWatchEpisode;
  final bool showSelectEpisode;
  final VoidCallback onTitle;
  final ValueChanged<_VideoTagData> onTag;
  final VoidCallback onWatchEpisode;
  final VoidCallback onPointerDown;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: 0,
      right: 0,
      bottom: showSelectEpisode ? 72 : 0,
      child: AnimatedOpacity(
        opacity: visible ? 1 : 0,
        duration: Duration(milliseconds: 120),
        child: IgnorePointer(
          ignoring: !visible,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 15),
                child: InkWell(
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
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      SizedBox(width: 4),
                      SvgPicture.asset(
                        'assets/images/android/ic_arrow_all.svg',
                        width: 16,
                        height: 16,
                        colorFilter: const ColorFilter.mode(
                          Colors.white,
                          BlendMode.srcIn,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (description.isNotEmpty) ...[
                SizedBox(height: 4),
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 15),
                  child: Text(
                    description,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: Colors.white, fontSize: 14),
                  ),
                ),
              ],
              if (tags.isNotEmpty) ...[
                SizedBox(height: 8),
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 15),
                  child: SizedBox(
                    height: 20,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: tags.take(3).map((tag) {
                        return InkWell(
                          onTap: tag.id.isEmpty ? null : () => onTag(tag),
                          child: Container(
                            constraints: BoxConstraints(minHeight: 20),
                            margin: EdgeInsetsDirectional.only(end: 4),
                            padding: EdgeInsets.symmetric(horizontal: 4),
                            decoration: BoxDecoration(
                              color: Color(0x40ffffff),
                              borderRadius: BorderRadius.circular(2),
                            ),
                            alignment: Alignment.center,
                            child: Text(
                              tag.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                height: 1.1,
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ),
              ],
              if (showWatchEpisode) ...[
                SizedBox(height: 10),
                _EpisodeEntryButton(
                  text: watchText,
                  onTap: onWatchEpisode,
                  onPointerDown: onPointerDown,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _EpisodeEntryButton extends StatelessWidget {
  const _EpisodeEntryButton({
    required this.text,
    required this.onTap,
    required this.onPointerDown,
  });

  final String text;
  final VoidCallback onTap;
  final VoidCallback onPointerDown;

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: (_) => onPointerDown(),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          height: 48,
          width: double.infinity,
          padding: EdgeInsets.symmetric(horizontal: 15),
          color: Colors.black.withAlpha(77),
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
      ),
    );
  }
}

class _EpisodeSelectButton extends StatelessWidget {
  const _EpisodeSelectButton({
    required this.visible,
    required this.text,
    required this.onTap,
  });

  final bool visible;
  final String text;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: 15,
      right: 15,
      bottom: 8,
      child: AnimatedOpacity(
        opacity: visible ? 1 : 0,
        duration: Duration(milliseconds: 120),
        child: IgnorePointer(
          ignoring: !visible,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(8),
            child: Container(
              height: 36,
              padding: EdgeInsets.symmetric(horizontal: 15),
              decoration: BoxDecoration(
                color: Color(0xff212121),
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
                    'assets/images/android/ic_arrow_top.svg',
                    width: 16,
                    height: 16,
                  ),
                ],
              ),
            ),
          ),
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

class _PlaybackSpeedSheet extends StatelessWidget {
  const _PlaybackSpeedSheet({required this.currentSpeed});

  final double currentSpeed;

  static const _speeds = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0];

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Color(0xff141414),
        borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
      ),
      child: SafeArea(
        top: false,
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
                        t.playback_speed,
                        style: TextStyle(
                          color: Color(0xfffff9f9),
                          fontSize: 16,
                          height: 1.2,
                        ),
                      ),
                    ),
                    InkWell(
                      onTap: () => Navigator.pop(context),
                      borderRadius: BorderRadius.circular(12),
                      child: Padding(
                        padding: EdgeInsets.symmetric(vertical: 16),
                        child: SvgPicture.asset(
                          'assets/images/android/ic_close.svg',
                          width: 24,
                          height: 24,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(height: 12),
              for (var i = 0; i < _speeds.length; i++) ...[
                if (i > 0) SizedBox(height: 12),
                _PlaybackSpeedItem(
                  speed: _speeds[i],
                  selected: (_speeds[i] - currentSpeed).abs() < 0.001,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _PlaybackSpeedItem extends StatelessWidget {
  const _PlaybackSpeedItem({required this.speed, required this.selected});

  final double speed;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => Navigator.pop(context, speed),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        height: 44,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? Color(0xffff3d5d) : Color(0xff212121),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          '${speed.toStringAsFixed(speed == speed.roundToDouble() ? 1 : 2)}x',
          style: TextStyle(color: Colors.white, fontSize: 16, height: 1.2),
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
    required this.bottomOffset,
  });

  final bool visible;
  final Duration current;
  final Duration total;
  final double bottomOffset;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: 0,
      right: 0,
      bottom: 42 + bottomOffset,
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
    required this.bottomOffset,
    required this.onChangeStart,
    required this.onChanged,
    required this.onChangeEnd,
  });

  final VideoPlayerController controller;
  final bool dragging;
  final double? dragFraction;
  final double bottomOffset;
  final ValueChanged<double> onChangeStart;
  final ValueChanged<double> onChanged;
  final ValueChanged<double> onChangeEnd;

  @override
  Widget build(BuildContext context) {
    final durationMs = controller.value.duration.inMilliseconds;
    final value = dragFraction ?? _progressFraction(controller);
    final trackHeight = dragging ? 6.0 : 2.0;
    final thumbRadius = dragging ? 8.0 : 0.0;

    double fractionFromLocalOffset(Offset localPosition, double width) {
      if (width <= 0) {
        return 0;
      }
      return (localPosition.dx / width).clamp(0.0, 1.0);
    }

    return Positioned(
      left: 15,
      right: 15,
      bottom: bottomOffset,
      child: SizedBox(
        height: 24,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;
            final playedWidth = durationMs <= 0 ? 0.0 : width * value;
            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapDown: durationMs <= 0
                  ? null
                  : (details) {
                      final next = fractionFromLocalOffset(
                        details.localPosition,
                        width,
                      );
                      onChangeStart(next);
                      onChanged(next);
                    },
              onTapUp: durationMs <= 0
                  ? null
                  : (details) {
                      onChangeEnd(
                        fractionFromLocalOffset(details.localPosition, width),
                      );
                    },
              onHorizontalDragStart: durationMs <= 0
                  ? null
                  : (details) {
                      final next = fractionFromLocalOffset(
                        details.localPosition,
                        width,
                      );
                      onChangeStart(next);
                      onChanged(next);
                    },
              onHorizontalDragUpdate: durationMs <= 0
                  ? null
                  : (details) {
                      onChanged(
                        fractionFromLocalOffset(details.localPosition, width),
                      );
                    },
              onHorizontalDragEnd: durationMs <= 0
                  ? null
                  : (_) {
                      onChangeEnd(dragFraction ?? value);
                    },
              child: Stack(
                alignment: Alignment.bottomLeft,
                children: [
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    height: trackHeight,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: Colors.white.withAlpha(77),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ),
                  Positioned(
                    left: 0,
                    bottom: 0,
                    width: playedWidth,
                    height: trackHeight,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ),
                  if (thumbRadius > 0)
                    Positioned(
                      left: (playedWidth - thumbRadius).clamp(
                        0.0,
                        (width - thumbRadius * 2).clamp(0.0, width),
                      ),
                      bottom: trackHeight / 2 - thumbRadius,
                      child: Container(
                        width: thumbRadius * 2,
                        height: thumbRadius * 2,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _VideoTagData {
  const _VideoTagData({required this.name, required this.id});

  final String name;
  final String id;
}

List<_VideoTagData> _videoTags(Map<String, dynamic> item) {
  final raw = item['tags'] ?? item['tagList'] ?? item['tag_list'];
  if (raw is! List) {
    return [];
  }
  return raw.map(_videoTag).where((tag) => tag.name.isNotEmpty).toList();
}

_VideoTagData _videoTag(dynamic tag) {
  if (tag is Map) {
    return _VideoTagData(name: _tagDisplayName(tag), id: _tagRequestId(tag));
  }
  final raw = _text(tag);
  if (raw.isEmpty || _looksLikeTagId(raw)) {
    return const _VideoTagData(name: '', id: '');
  }
  return _VideoTagData(name: _formatFeedTag(raw), id: raw);
}

String _tagDisplayName(Map tag) {
  final candidates = [
    tag['unique_id'],
    tag['source_tag_name'],
    tag['local_label'],
    tag['tag_name'],
    tag['label'],
    tag['title'],
    tag['matched_unique_id'],
    tag['name'],
  ];
  for (final candidate in candidates) {
    final raw = _text(candidate);
    if (raw.isEmpty || _looksLikeTagId(raw)) {
      continue;
    }
    final formatted = _formatFeedTag(raw);
    if (formatted.isNotEmpty) {
      return formatted;
    }
  }
  return '';
}

String _tagRequestId(Map tag) {
  final candidates = [
    tag['name'],
    tag['unique_id'],
    tag['matched_unique_id'],
    tag['source_tag_name'],
    tag['tag_name'],
    tag['id'],
  ];
  for (final candidate in candidates) {
    final raw = _text(candidate);
    if (raw.isNotEmpty) {
      return raw;
    }
  }
  return '';
}

String _formatFeedTag(String value) {
  final normalized = value.trim().replaceAll('_', ' ');
  if (normalized.isEmpty) {
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

bool _looksLikeTagId(String value) {
  return RegExp(r'^[0-9a-fA-F]{6,}$').hasMatch(value.trim());
}

String _androidIntText(String value, int number) {
  return value
      .replaceAll('%1\$d', '$number')
      .replaceAll(r'%1$d', '$number')
      .replaceAll('%d', '$number')
      .replaceAll(r'$d', '$number')
      .replaceAll('"', '');
}

String _androidPairText(String value, int first, int second) {
  return value
      .replaceAll('%1\$s', '$first')
      .replaceAll(r'%1$s', '$first')
      .replaceAll('%2\$s', '$second')
      .replaceAll(r'%2$s', '$second')
      .replaceAll(r'$s2', '$second')
      .replaceAll(r'$s', '$first')
      .replaceAll('"', '');
}

const _videoRetentionHeaderAsset =
    'assets/images/video-retention-promo/bg@2x.png';
const _videoRetentionCouponAsset =
    'assets/images/video-retention-promo/bg_coupon@2x.png';
const _videoRetentionCloseAsset =
    'assets/images/video-retention-promo/close.svg';
const _videoRetentionProductIds = {
  'weekly_retention_1',
  'weekly_retention_2',
  'quarterly',
};

class _VideoRetentionOffer {
  const _VideoRetentionOffer({
    required this.raw,
    required this.localProductId,
    required this.storeProductId,
    required this.name,
    required this.discountType,
    required this.price,
    required this.renewalPrice,
    required this.isWeekly,
    required this.isQuarterly,
  });

  final Map<String, dynamic> raw;
  final String localProductId;
  final String storeProductId;
  final String name;
  final int discountType;
  final String price;
  final String renewalPrice;
  final bool isWeekly;
  final bool isQuarterly;

  String get priceLabel => _videoRetentionMoneyLabel(price);
  String get renewalLabel => _videoRetentionMoneyLabel(renewalPrice);
  int get discountPercent =>
      _videoRetentionDiscountPercent(price, renewalPrice);

  static _VideoRetentionOffer? fromRaw(dynamic value) {
    final map = _asMap(value);
    if (map.isEmpty) {
      return null;
    }

    final localProductId = _videoRetentionFirstNotEmpty([
      map['id'],
      map['local_product_id'],
      map['localProductId'],
      map['product_local_id'],
    ]);
    final storeProductId = _videoRetentionFirstNotEmpty([
      map['product_id'],
      map['apple_product_id'],
      map['ios_product_id'],
      map['google_product_id'],
      map['googleProductId'],
      map['store_product_id'],
      map['name'],
    ]);
    if (localProductId.isEmpty || storeProductId.isEmpty) {
      return null;
    }
    if (!_videoRetentionAllowsProduct(map, localProductId, storeProductId)) {
      return null;
    }

    final name = _videoRetentionFirstNotEmpty([
      map['name'],
      map['display_name'],
      map['displayName'],
      map['title'],
      map['base_plan_id'],
      map['basePlanId'],
      map['product_id'],
    ]);
    final plan = _videoRetentionFirstNotEmpty([
      map['base_plan_id'],
      map['basePlanId'],
      map['plan_id'],
      map['planId'],
      map['period'],
      map['duration'],
      map['product_id'],
      map['name'],
    ]).toLowerCase();
    final catalogPrice = _text(map['price']);
    final firstPrice = _videoRetentionFirstNotEmpty([
      map['first_price'],
      map['firstPrice'],
      map['offer_price'],
      map['offerPrice'],
      map['discount_price'],
      map['discountPrice'],
      map['intro_price'],
      map['introPrice'],
    ]);
    final renewalCandidate = _videoRetentionFirstNotEmpty([
      map['renewal_price'],
      map['renewalPrice'],
      map['origin_price'],
      map['originPrice'],
      map['original_price'],
      map['originalPrice'],
      map['normal_price'],
      map['normalPrice'],
      map['regular_price'],
      map['regularPrice'],
    ]);
    final price = firstPrice.isNotEmpty ? firstPrice : catalogPrice;
    final renewalPrice = renewalCandidate.isNotEmpty
        ? renewalCandidate
        : catalogPrice.isNotEmpty
        ? catalogPrice
        : price;
    if (price.isEmpty || renewalPrice.isEmpty) {
      return null;
    }

    return _VideoRetentionOffer(
      raw: map,
      localProductId: localProductId,
      storeProductId: storeProductId,
      name: name,
      discountType: _intValue(map['discount_type'] ?? map['discountType']),
      price: price,
      renewalPrice: renewalPrice,
      isWeekly: _videoRetentionLooksWeekly(plan),
      isQuarterly: _videoRetentionLooksQuarterly(plan),
    );
  }
}

class _VideoRetentionCover {
  const _VideoRetentionCover({required this.id, required this.image});

  final String id;
  final String image;

  static _VideoRetentionCover fromRaw(dynamic value) {
    final map = _asMap(value);
    return _VideoRetentionCover(
      id: _videoRetentionFirstNotEmpty([
        map['movie_id'],
        map['movieId'],
        map['id'],
      ]),
      image: _posterUrl(map),
    );
  }
}

class _VideoRetentionOfferSelection {
  const _VideoRetentionOfferSelection({
    required this.offer,
    required this.purchased,
  });

  final _VideoRetentionOffer offer;
  final bool purchased;
}

class _VideoRetentionOfferSheet extends StatefulWidget {
  const _VideoRetentionOfferSheet({
    required this.offer,
    required this.step,
    required this.total,
    required this.coversFuture,
    required this.enableFinalClosePurchase,
    required this.onOfferPurchase,
    required this.onFinalClosePurchase,
  });

  final _VideoRetentionOffer offer;
  final int step;
  final int total;
  final Future<List<_VideoRetentionCover>> coversFuture;
  final bool enableFinalClosePurchase;
  final Future<bool> Function(_VideoRetentionOffer offer) onOfferPurchase;
  final Future<bool> Function(_VideoRetentionOffer offer) onFinalClosePurchase;

  @override
  State<_VideoRetentionOfferSheet> createState() =>
      _VideoRetentionOfferSheetState();
}

class _VideoRetentionOfferSheetState extends State<_VideoRetentionOfferSheet> {
  bool _ctaPurchaseInFlight = false;
  bool _closePurchaseAttempted = false;
  bool _closePurchaseInFlight = false;

  bool get _isStep3 => widget.step >= 3 || widget.offer.isQuarterly;

  Future<void> _handleCta() async {
    if (_ctaPurchaseInFlight || _closePurchaseInFlight) {
      return;
    }

    _ctaPurchaseInFlight = true;
    var purchased = false;
    try {
      purchased = await widget.onOfferPurchase(widget.offer);
    } on Exception catch (error) {
      Global.logger.d('video retention cta purchase failed: $error');
    } finally {
      if (!purchased) {
        _ctaPurchaseInFlight = false;
        if (_isStep3) {
          _closePurchaseAttempted = true;
        }
      }
    }
    if (!mounted) {
      return;
    }
    if (purchased) {
      Navigator.pop(
        context,
        _VideoRetentionOfferSelection(offer: widget.offer, purchased: true),
      );
    }
  }

  Future<void> _handleClose() async {
    if (_ctaPurchaseInFlight) {
      return;
    }
    if (!widget.enableFinalClosePurchase || _closePurchaseAttempted) {
      Navigator.pop(context);
      return;
    }
    if (_closePurchaseInFlight) {
      return;
    }

    setState(() => _closePurchaseInFlight = true);
    var purchased = false;
    try {
      purchased = await widget.onFinalClosePurchase(widget.offer);
    } on Exception catch (error) {
      Global.logger.d('video retention final close purchase failed: $error');
    } finally {
      if (mounted && !purchased) {
        setState(() {
          _closePurchaseAttempted = true;
          _closePurchaseInFlight = false;
        });
      }
    }
    if (!mounted) {
      return;
    }
    if (purchased) {
      Navigator.pop(
        context,
        _VideoRetentionOfferSelection(offer: widget.offer, purchased: true),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final wide = media.size.width >= 560;
    final radius = wide
        ? BorderRadius.circular(20)
        : BorderRadius.vertical(top: Radius.circular(20));

    return Align(
      alignment: Alignment.bottomCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: wide ? 420 : double.infinity,
          maxHeight: media.size.height * 0.88,
        ),
        child: Container(
          decoration: BoxDecoration(
            color: Color(0xff222222),
            borderRadius: radius,
          ),
          clipBehavior: Clip.hardEdge,
          child: Stack(
            children: [
              SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(
                  14,
                  0,
                  14,
                  16 + media.padding.bottom,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _VideoRetentionHeader(step: widget.step, isStep3: _isStep3),
                    SizedBox(height: _isStep3 ? 10 : 18),
                    if (_isStep3)
                      _VideoRetentionStep3Card(offer: widget.offer)
                    else
                      _VideoRetentionCouponCard(
                        offer: widget.offer,
                        step: widget.step,
                      ),
                    if (_isStep3)
                      _VideoRetentionStep3Cta(
                        priceLabel: widget.offer.priceLabel,
                        onTap: _handleCta,
                      )
                    else ...[
                      _VideoRetentionCta(
                        priceLabel: widget.offer.priceLabel,
                        onTap: _handleCta,
                      ),
                      if (widget.step == 2)
                        _VideoRetentionStep2Disclaimer(
                          renewalLabel: widget.offer.renewalLabel,
                        ),
                    ],
                    _VideoRetentionShorts(coversFuture: widget.coversFuture),
                  ],
                ),
              ),
              PositionedDirectional(
                top: 14,
                end: 14,
                child: InkWell(
                  onTap: _closePurchaseInFlight ? null : _handleClose,
                  borderRadius: BorderRadius.circular(16),
                  child: Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: Colors.white.withAlpha(31),
                      shape: BoxShape.circle,
                    ),
                    alignment: Alignment.center,
                    child: SvgPicture.asset(
                      _videoRetentionCloseAsset,
                      width: 14,
                      height: 14,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _VideoRetentionHeader extends StatelessWidget {
  const _VideoRetentionHeader({required this.step, required this.isStep3});

  final int step;
  final bool isStep3;

  @override
  Widget build(BuildContext context) {
    final headerHeight = isStep3 ? 82.0 : (step == 2 ? 82.0 : 64.0);
    return SizedBox(
      height: headerHeight,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          PositionedDirectional(
            top: 0,
            start: -20,
            end: -20,
            child: Image.asset(
              _videoRetentionHeaderAsset,
              fit: BoxFit.contain,
              alignment: Alignment.topCenter,
            ),
          ),
          Positioned.fill(
            child: Padding(
              padding: EdgeInsets.only(top: 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    isStep3
                        ? t.retention_promo_title_step3
                        : t.retention_promo_title,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      height: 1.2,
                      fontWeight: FontWeight.w600,
                      decoration: TextDecoration.none,
                    ),
                  ),
                  SizedBox(height: isStep3 ? 6 : 4),
                  if (isStep3)
                    Container(
                      padding: EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(4),
                        gradient: LinearGradient(
                          colors: [Color(0xfffff86d), Color(0xffe8a42d)],
                        ),
                      ),
                      child: Text(
                        t.retention_promo_badge_onetime,
                        style: TextStyle(
                          color: Color(0xff3b2a12),
                          fontSize: 13,
                          height: 1.2,
                          fontWeight: FontWeight.w600,
                          decoration: TextDecoration.none,
                        ),
                      ),
                    )
                  else
                    Text(
                      step == 2
                          ? t.retention_promo_subtitle_step2
                          : t.retention_promo_subtitle_step1,
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white.withAlpha(191),
                        fontSize: 12,
                        height: 1.2,
                        fontWeight: FontWeight.w400,
                        decoration: TextDecoration.none,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _VideoRetentionCouponCard extends StatelessWidget {
  const _VideoRetentionCouponCard({required this.offer, required this.step});

  final _VideoRetentionOffer offer;
  final int step;

  @override
  Widget build(BuildContext context) {
    final pricingLines = _videoRetentionPricingLines(offer, step);
    return Padding(
      padding: EdgeInsets.only(bottom: 24),
      child: SizedBox(
        height: 126,
        width: double.infinity,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Image.asset(_videoRetentionCouponAsset, fit: BoxFit.fill),
            Transform.translate(
              offset: Offset(0, -3),
              child: Column(
                children: [
                  Expanded(
                    flex: 91,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          t.retention_promo_surprise_discount,
                          style: TextStyle(
                            color: Color(0xff633e25),
                            fontSize: 12,
                            height: 1,
                            decoration: TextDecoration.none,
                          ),
                        ),
                        SizedBox(height: 8),
                        Text(
                          '${offer.discountPercent}%',
                          style: TextStyle(
                            color: Color(0xff633e25),
                            fontSize: 38,
                            height: 1,
                            fontWeight: FontWeight.w600,
                            decoration: TextDecoration.none,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    flex: 35,
                    child: Padding(
                      padding: EdgeInsets.symmetric(horizontal: 16),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: pricingLines
                            .map(
                              (line) => Text(
                                line,
                                textAlign: TextAlign.center,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: Color(0xbf633e25),
                                  fontSize: 10,
                                  height: 1.4,
                                  decoration: TextDecoration.none,
                                ),
                              ),
                            )
                            .toList(),
                      ),
                    ),
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

class _VideoRetentionStep3Card extends StatelessWidget {
  const _VideoRetentionStep3Card({required this.offer});

  final _VideoRetentionOffer offer;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(18, 16, 18, 14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [Color(0xffffecd4), Color(0xfff3cb93)],
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            t.retention_promo_exclusive_title,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Color(0xff633e25),
              fontSize: 18,
              height: 1.2,
              fontWeight: FontWeight.w500,
              decoration: TextDecoration.none,
            ),
          ),
          Text(
            t.retention_promo_exclusive_subtitle,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Color(0xff633e25),
              fontSize: 10,
              height: 1.3,
              decoration: TextDecoration.none,
            ),
          ),
          SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                offer.renewalLabel,
                style: TextStyle(
                  color: Color(0x80633e25),
                  fontSize: 14,
                  height: 1.2,
                  fontWeight: FontWeight.w500,
                  decoration: TextDecoration.none,
                ),
              ),
              SizedBox(width: 8),
              Text(
                t.retention_promo_off_badge(percent: offer.discountPercent),
                style: TextStyle(
                  color: Color(0xffc90000),
                  fontSize: 12,
                  height: 1.2,
                  fontWeight: FontWeight.w500,
                  decoration: TextDecoration.none,
                ),
              ),
            ],
          ),
          SizedBox(height: 2),
          Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                offer.priceLabel,
                style: TextStyle(
                  color: Color(0xffc90000),
                  fontSize: 36,
                  height: 1,
                  fontWeight: FontWeight.w700,
                  decoration: TextDecoration.none,
                ),
              ),
              Padding(
                padding: EdgeInsetsDirectional.only(start: 8, bottom: 3),
                child: Text(
                  t.retention_promo_period_90days,
                  style: TextStyle(
                    color: Color(0xbf633e25),
                    fontSize: 10,
                    height: 1.2,
                    decoration: TextDecoration.none,
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: 6),
          Text(
            t.retention_promo_per_day(
              price: _videoRetentionPerDayLabel(offer.price, 90),
            ),
            style: TextStyle(
              color: Color(0xff633e25),
              fontSize: 10,
              height: 1.2,
              decoration: TextDecoration.none,
            ),
          ),
        ],
      ),
    );
  }
}

class _VideoRetentionCta extends StatelessWidget {
  const _VideoRetentionCta({required this.priceLabel, required this.onTap});

  final String priceLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: 24),
      child: _VideoRetentionCtaButton(priceLabel: priceLabel, onTap: onTap),
    );
  }
}

class _VideoRetentionStep3Cta extends StatelessWidget {
  const _VideoRetentionStep3Cta({
    required this.priceLabel,
    required this.onTap,
  });

  final String priceLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(top: 24, bottom: 12),
      child: _VideoRetentionCtaButton(priceLabel: priceLabel, onTap: onTap),
    );
  }
}

class _VideoRetentionCtaButton extends StatelessWidget {
  const _VideoRetentionCtaButton({
    required this.priceLabel,
    required this.onTap,
  });

  final String priceLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: double.infinity,
        height: 40,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: Color(0xffff3d5d),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          t.retention_promo_cta_sale(price: priceLabel),
          style: TextStyle(
            color: Colors.white,
            fontSize: 16,
            height: 1.2,
            fontWeight: FontWeight.w500,
            decoration: TextDecoration.none,
          ),
        ),
      ),
    );
  }
}

class _VideoRetentionStep2Disclaimer extends StatelessWidget {
  const _VideoRetentionStep2Disclaimer({required this.renewalLabel});

  final String renewalLabel;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(8, 0, 8, 10),
      child: Text(
        t.retention_promo_terms_step2(renewal: renewalLabel),
        textAlign: TextAlign.center,
        style: TextStyle(
          color: Colors.white.withAlpha(140),
          fontSize: 10,
          height: 1.4,
          decoration: TextDecoration.none,
        ),
      ),
    );
  }
}

class _VideoRetentionShorts extends StatelessWidget {
  const _VideoRetentionShorts({required this.coversFuture});

  final Future<List<_VideoRetentionCover>> coversFuture;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          t.retention_promo_vip_shorts,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Colors.white,
            fontSize: 16,
            height: 1.2,
            fontWeight: FontWeight.w500,
            decoration: TextDecoration.none,
          ),
        ),
        SizedBox(height: 12),
        FutureBuilder<List<_VideoRetentionCover>>(
          future: coversFuture,
          builder: (context, snapshot) {
            final covers = snapshot.data ?? const <_VideoRetentionCover>[];
            return Row(
              children: [
                for (var index = 0; index < 5; index += 1) ...[
                  Expanded(
                    child: _VideoRetentionPoster(
                      cover: index < covers.length ? covers[index] : null,
                    ),
                  ),
                  if (index < 4) SizedBox(width: 8),
                ],
              ],
            );
          },
        ),
      ],
    );
  }
}

class _VideoRetentionPoster extends StatelessWidget {
  const _VideoRetentionPoster({required this.cover});

  final _VideoRetentionCover? cover;

  @override
  Widget build(BuildContext context) {
    final image = cover?.image ?? '';
    final ratio = MediaQuery.of(context).devicePixelRatio.clamp(1.0, 3.0);
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: AspectRatio(
        aspectRatio: 2 / 3,
        child: image.isEmpty
            ? ColoredBox(color: Colors.white.withAlpha(20))
            : LayoutBuilder(
                builder: (context, constraints) {
                  final width = constraints.maxWidth;
                  final height = constraints.maxHeight;
                  return LazyImage(
                    url: image,
                    width: width,
                    height: height,
                    fit: BoxFit.cover,
                    cacheWidth: (width * ratio).round(),
                    cacheHeight: (height * ratio).round(),
                  );
                },
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
    return Stack(
      children: [
        Positioned.fill(
          child: IgnorePointer(
            child: ClipRect(
              child: BackdropFilter(
                filter: ui.ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                child: ColoredBox(color: Colors.black.withAlpha(150)),
              ),
            ),
          ),
        ),
        Center(
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 25),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 55),
                  child: Text(
                    t.unlock_get_vip_tips,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.w500,
                      decoration: TextDecoration.none,
                    ),
                  ),
                ),
                SizedBox(height: 20),
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 25),
                  child: SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: onGetVip,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Color(0xffff3d5d),
                        foregroundColor: Colors.white,
                        padding: EdgeInsets.symmetric(
                          horizontal: 60,
                          vertical: 12,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: Text(t.get_vip),
                    ),
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
    );
  }
}

class _CoinUnlockSheet extends StatefulWidget {
  const _CoinUnlockSheet({
    required this.unlockCoins,
    required this.balanceCoins,
    required this.onSubscribe,
  });

  final int unlockCoins;
  final int balanceCoins;
  final VoidCallback onSubscribe;

  @override
  State<_CoinUnlockSheet> createState() => _CoinUnlockSheetState();
}

class _CoinUnlockSheetState extends State<_CoinUnlockSheet> {
  late bool _autoUnlock;

  @override
  void initState() {
    super.initState();
    _autoUnlock =
        Global.sp.getBool(_NativeVideoFeedState._autoUnlockKey) == true;
  }

  Future<void> _setAutoUnlock(bool next) async {
    setState(() => _autoUnlock = next);
    await Global.sp.setBool(_NativeVideoFeedState._autoUnlockKey, next);
    unawaited(
      api<Map<String, dynamic>>(
        'user/config',
        method: Method.post,
        loading: false,
        data: {
          'wallet': {'auto_unlock_next': next},
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.only(top: 20),
        child: Stack(
          children: [
            Container(
              height: 78,
              padding: EdgeInsets.symmetric(horizontal: 15),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xffffecd4), Color(0xfff3cb93)],
                ),
                borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
              ),
              child: Align(
                alignment: Alignment.topCenter,
                child: Padding(
                  padding: EdgeInsets.only(top: 12),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          t.vip_access_to_all_episodes,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Color(0xff633e25),
                            fontSize: 14,
                          ),
                        ),
                      ),
                      InkWell(
                        onTap: widget.onSubscribe,
                        borderRadius: BorderRadius.only(
                          topRight: Radius.circular(12),
                          bottomLeft: Radius.circular(12),
                        ),
                        child: Container(
                          padding: EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 5,
                          ),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [Color(0xffc17846), Color(0xff603c24)],
                            ),
                            borderRadius: BorderRadiusDirectional.only(
                              topEnd: Radius.circular(12),
                              bottomStart: Radius.circular(12),
                            ),
                          ),
                          child: Text(
                            t.subscribe,
                            style: TextStyle(color: Colors.white, fontSize: 12),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Container(
              margin: EdgeInsets.only(top: 48),
              decoration: BoxDecoration(
                color: Color(0xff151515),
                borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: 15, vertical: 18),
                    child: Row(
                      children: [
                        _CoinUnlockValue(
                          label: t.episode_unlock_price,
                          value: widget.unlockCoins.toString(),
                        ),
                        SizedBox(width: 12),
                        _CoinUnlockValue(
                          label: t.balance,
                          value: widget.balanceCoins.toString(),
                        ),
                        InkWell(
                          onTap: () => Navigator.pop(context, false),
                          borderRadius: BorderRadius.circular(12),
                          child: SvgPicture.asset(
                            'assets/images/android/ic_close.svg',
                            width: 24,
                            height: 24,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: 15),
                    child: InkWell(
                      onTap: () => Navigator.pop(context, true),
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        height: 44,
                        decoration: BoxDecoration(
                          color: Color(0xffff3d5d),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          t.unlock_now,
                          style: TextStyle(color: Colors.white, fontSize: 14),
                        ),
                      ),
                    ),
                  ),
                  SizedBox(height: 16),
                  InkWell(
                    onTap: () {
                      unawaited(_setAutoUnlock(!_autoUnlock));
                    },
                    borderRadius: BorderRadius.circular(8),
                    child: Padding(
                      padding: EdgeInsets.all(8),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(
                            width: 24,
                            height: 24,
                            child: Checkbox(
                              value: _autoUnlock,
                              onChanged: (value) {
                                final next = value == true;
                                unawaited(_setAutoUnlock(next));
                              },
                              activeColor: Color(0xffff3d5d),
                              checkColor: Colors.white,
                              side: BorderSide(color: Color(0xff999999)),
                            ),
                          ),
                          SizedBox(width: 8),
                          Text(
                            t.auto_unlock_next_episode,
                            style: TextStyle(
                              color: Color(0xff999999),
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  SizedBox(height: 12),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CoinUnlockValue extends StatelessWidget {
  const _CoinUnlockValue({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Row(
        children: [
          Text(label, style: TextStyle(color: Color(0xff999999), fontSize: 14)),
          SizedBox(width: 4),
          Image.asset('assets/images/android/ic_coin.png', width: 14),
          SizedBox(width: 4),
          Expanded(
            child: Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: Colors.white, fontSize: 14),
            ),
          ),
        ],
      ),
    );
  }
}

class _EpisodeSheet extends StatefulWidget {
  const _EpisodeSheet({
    required this.episodes,
    required this.currentEpisode,
    required this.onSelect,
  });

  final List<dynamic> episodes;
  final int currentEpisode;
  final ValueChanged<int> onSelect;

  @override
  State<_EpisodeSheet> createState() => _EpisodeSheetState();
}

class _EpisodeSheetState extends State<_EpisodeSheet> {
  static const int _groupSize = 30;

  final _scrollController = ScrollController();
  int _selectedGroup = 0;
  bool _tabScroll = false;

  @override
  void initState() {
    super.initState();
    final currentIndex = widget.episodes.indexWhere((episode) {
      return _intValue(_asMap(episode)['episode']) == widget.currentEpisode;
    });
    _selectedGroup = _groupForIndex(currentIndex < 0 ? 0 : currentIndex);
    _scrollController.addListener(_syncTabFromScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (currentIndex >= 0 && _scrollController.hasClients) {
        _scrollController.jumpTo(_offsetForIndex(currentIndex));
      }
    });
  }

  @override
  void dispose() {
    _scrollController.removeListener(_syncTabFromScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _syncTabFromScroll() {
    if (_tabScroll || !_scrollController.hasClients) {
      return;
    }
    final position = _scrollController.position;
    final isAtBottom =
        position.pixels >= position.maxScrollExtent - precisionErrorTolerance;
    final rowHeight = _itemExtent(context) + 12;
    final firstRow = (_scrollController.offset / rowHeight).floor();
    final group = isAtBottom
        ? _groupTitles.length - 1
        : _groupForIndex(firstRow * 6);
    if (group != _selectedGroup && mounted) {
      setState(() => _selectedGroup = group);
    }
  }

  void _scrollToGroup(int group) {
    final index = (group * _groupSize).clamp(0, widget.episodes.length - 1);
    final targetOffset = _offsetForIndex(
      index,
    ).clamp(0.0, _scrollController.position.maxScrollExtent).toDouble();
    setState(() => _selectedGroup = group);
    _tabScroll = true;
    _scrollController
        .animateTo(
          targetOffset,
          duration: Duration(milliseconds: 180),
          curve: Curves.easeOut,
        )
        .whenComplete(() {
          _tabScroll = false;
          _syncTabFromScroll();
        });
  }

  double _offsetForIndex(int index) {
    final row = index ~/ 6;
    return row * (_itemExtent(context) + 12);
  }

  int _groupForIndex(int index) {
    if (widget.episodes.isEmpty) {
      return 0;
    }
    return (index / _groupSize).floor().clamp(0, _groupTitles.length - 1);
  }

  double _itemExtent(BuildContext context) {
    final width = MediaQuery.of(context).size.width - 30;
    return (width - 14 * 5) / 6;
  }

  List<String> get _groupTitles {
    if (widget.episodes.isEmpty) {
      return const [];
    }
    return [
      for (var start = 0; start < widget.episodes.length; start += _groupSize)
        '${start + 1}-${(start + _groupSize).clamp(0, widget.episodes.length)}',
    ];
  }

  @override
  Widget build(BuildContext context) {
    final groups = _groupTitles;
    return SafeArea(
      top: false,
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.5,
        child: Container(
          padding: EdgeInsets.fromLTRB(15, 0, 15, 15),
          decoration: BoxDecoration(
            color: Color(0xff151515),
            borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                height: 56,
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        t.episodes,
                        style: TextStyle(
                          color: Color(0xfffff9f9),
                          fontSize: 16,
                        ),
                      ),
                    ),
                    InkWell(
                      onTap: () => Navigator.pop(context),
                      borderRadius: BorderRadius.circular(12),
                      child: SvgPicture.asset(
                        'assets/images/android/ic_close.svg',
                        width: 24,
                        height: 24,
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(
                height: 26,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: groups.length,
                  separatorBuilder: (_, _) => SizedBox(width: 18),
                  itemBuilder: (context, index) {
                    final selected = index == _selectedGroup;
                    return InkWell(
                      onTap: () => _scrollToGroup(index),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            groups[index],
                            style: TextStyle(
                              color: selected
                                  ? Color(0xffff3d5d)
                                  : Colors.white,
                              fontSize: 14,
                            ),
                          ),
                          Spacer(),
                          Container(
                            height: 1,
                            width: 34,
                            color: selected
                                ? Color(0xffff3d5d)
                                : Colors.transparent,
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
              Expanded(
                child: GridView.builder(
                  controller: _scrollController,
                  physics: ClampingScrollPhysics(),
                  padding: EdgeInsets.symmetric(vertical: 10),
                  itemCount: widget.episodes.length,
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 6,
                    mainAxisSpacing: 12,
                    crossAxisSpacing: 14,
                  ),
                  itemBuilder: (context, index) {
                    final episode = _asMap(widget.episodes[index]);
                    final epNo = _intValue(episode['episode']);
                    final locked =
                        !context.read<UserState>().isVip &&
                        _isEpisodeLocked(episode);
                    final selected = epNo == widget.currentEpisode;
                    return _EpisodeTile(
                      episode: epNo,
                      selected: selected,
                      locked: locked,
                      onTap: () => widget.onSelect(index),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EpisodeTile extends StatelessWidget {
  const _EpisodeTile({
    required this.episode,
    required this.selected,
    required this.locked,
    required this.onTap,
  });

  final int episode;
  final bool selected;
  final bool locked;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Stack(
        children: [
          Positioned.fill(
            child: Container(
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: selected ? Color(0x15ff3d5d) : Color(0xff212121),
                borderRadius: BorderRadius.circular(4),
                border: selected
                    ? Border.all(color: Color(0xffff3d5d), width: 1)
                    : null,
              ),
              child: Text(
                episode.toString(),
                style: TextStyle(color: Colors.white, fontSize: 14),
              ),
            ),
          ),
          if (locked)
            PositionedDirectional(
              top: 0,
              end: 0,
              child: SvgPicture.asset(
                'assets/images/android/ic_ep_lock.svg',
                width: 12,
                height: 12,
              ),
            ),
          if (selected)
            PositionedDirectional(end: 4, bottom: 4, child: _WaveMark()),
        ],
      ),
    );
  }
}

class _WaveMark extends StatefulWidget {
  @override
  State<_WaveMark> createState() => _WaveMarkState();
}

class _WaveMarkState extends State<_WaveMark>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: 760),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 8,
      height: 8,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          final value = _controller.value;
          return Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              _WaveBar(height: 3 + (value * 3)),
              _WaveBar(height: 8 - (value * 3)),
              _WaveBar(height: 4 + ((1 - value) * 3)),
            ],
          );
        },
      ),
    );
  }
}

class _WaveBar extends StatelessWidget {
  const _WaveBar({required this.height});

  final double height;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 2,
      height: height,
      decoration: BoxDecoration(
        color: Color(0xffff3d5d),
        borderRadius: BorderRadius.circular(1),
      ),
    );
  }
}

Map<String, Map<String, dynamic>> _extractBatchMaps(
  Map<String, dynamic>? data,
) {
  final rawMaps = data?['maps'] ?? data?['eps'];
  if (rawMaps is! Map) {
    return const {};
  }
  return rawMaps.map((key, value) {
    return MapEntry(_text(key), _asMap(value));
  });
}

Map<String, dynamic> _normalizeFeedItem(dynamic value) {
  final item = _asMap(value);
  return {
    ...item,
    'id': item['id'] ?? item['movie_id'] ?? item['movieId'] ?? item['moveId'],
    'movie_id':
        item['movie_id'] ?? item['movieId'] ?? item['moveId'] ?? item['id'],
    'ep_id': item['ep_id'] ?? item['epId'],
    'total_episodes': item['total_episodes'] ?? item['totalEpisode'],
    'is_favor': item['is_favor'] ?? item['isFavorite'],
  };
}

String _favoriteMovieId(Map<String, dynamic> item) {
  return _text(
    item['movie_id'] ?? item['movieId'] ?? item['moveId'] ?? item['id'],
  );
}

List<dynamic> _pageRows(Map<String, dynamic>? data) {
  final value = data?['data'] ?? data?['list'] ?? data?['items'];
  return value is List ? value : [];
}

List<dynamic> _videoRetentionRows(dynamic payload) {
  return _videoRetentionListFromPayload(payload, const [
    'subscription',
    'offers',
    'products',
    'data',
    'list',
    'items',
  ]);
}

List<dynamic> _videoRetentionCoverRows(dynamic payload) {
  return _videoRetentionListFromPayload(payload, const [
    'data',
    'list',
    'items',
    'videos',
  ]);
}

List<dynamic> _videoRetentionListFromPayload(
  dynamic payload,
  List<String> keys,
) {
  dynamic current = payload;
  for (var depth = 0; depth < 4; depth += 1) {
    if (current is List) {
      return current;
    }
    if (current is! Map) {
      return const [];
    }
    for (final key in keys) {
      final value = current[key];
      if (value is List) {
        return value;
      }
    }
    current =
        current['data'] ??
        current['list'] ??
        current['items'] ??
        current['subscription'] ??
        current['offers'] ??
        current['products'];
  }
  return current is List ? current : const [];
}

List<_VideoRetentionOffer> _orderedVideoRetentionOffers(List<dynamic> rows) {
  final offers = rows
      .map(_VideoRetentionOffer.fromRaw)
      .whereType<_VideoRetentionOffer>()
      .toList();
  if (offers.isEmpty) {
    return const [];
  }

  final hasDiscountType = offers.any((offer) => offer.discountType > 0);
  if (!hasDiscountType) {
    return offers..sort(_compareVideoRetentionOfferFallback);
  }

  final ordered = <_VideoRetentionOffer>[];
  final seen = <String>{};

  void addFirst(bool Function(_VideoRetentionOffer offer) test) {
    for (final offer in offers) {
      final key = '${offer.localProductId}:${offer.storeProductId}';
      if (!seen.contains(key) && test(offer)) {
        ordered.add(offer);
        seen.add(key);
        return;
      }
    }
  }

  addFirst((offer) => offer.isWeekly && offer.discountType == 1);
  addFirst((offer) => offer.isWeekly && offer.discountType == 2);
  addFirst((offer) => offer.isQuarterly && offer.discountType == 1);

  final rest = offers.where((offer) {
    return !seen.contains('${offer.localProductId}:${offer.storeProductId}');
  }).toList()..sort(_compareVideoRetentionOfferFallback);
  ordered.addAll(rest);
  return ordered;
}

int _compareVideoRetentionOfferFallback(
  _VideoRetentionOffer a,
  _VideoRetentionOffer b,
) {
  final period = _videoRetentionPeriodRank(
    a,
  ).compareTo(_videoRetentionPeriodRank(b));
  if (period != 0) {
    return period;
  }
  final price = _videoRetentionMoneyNumber(
    b.price,
  ).compareTo(_videoRetentionMoneyNumber(a.price));
  if (price != 0) {
    return price;
  }
  return a.localProductId.compareTo(b.localProductId);
}

int _videoRetentionPeriodRank(_VideoRetentionOffer offer) {
  if (offer.isWeekly) {
    return 0;
  }
  if (offer.isQuarterly) {
    return 1;
  }
  return 2;
}

int _videoRetentionStepForOffer(
  _VideoRetentionOffer offer, {
  required int fallbackStep,
}) {
  if (offer.isWeekly && offer.discountType == 1) {
    return 1;
  }
  if (offer.isWeekly && offer.discountType == 2) {
    return 2;
  }
  if (offer.isQuarterly) {
    return 3;
  }
  return fallbackStep.clamp(1, 3).toInt();
}

String _videoRetentionFirstNotEmpty(List<dynamic> values) {
  for (final value in values) {
    final text = _text(value);
    if (text.isNotEmpty) {
      return text;
    }
  }
  return '';
}

bool _videoRetentionAllowsProduct(
  Map<String, dynamic> map,
  String localProductId,
  String storeProductId,
) {
  final ids = [
    localProductId,
    storeProductId,
    map['product_id'],
    map['apple_product_id'],
    map['ios_product_id'],
    map['google_product_id'],
    map['googleProductId'],
    map['store_product_id'],
    map['name'],
    map['base_plan_id'],
    map['basePlanId'],
  ];
  return ids.any(
    (id) => _videoRetentionProductIds.contains(_text(id).toLowerCase()),
  );
}

bool _videoRetentionLooksWeekly(String value) {
  final text = value.toLowerCase();
  return text.contains('weekly') ||
      text.contains('week') ||
      text.contains('p1w');
}

bool _videoRetentionLooksQuarterly(String value) {
  final text = value.toLowerCase();
  return text.contains('quarter') ||
      text.contains('quarterly') ||
      text.contains('season') ||
      text.contains('3month') ||
      text.contains('3_month') ||
      text.contains('p3m') ||
      text.contains('90');
}

List<String> _videoRetentionPricingLines(_VideoRetentionOffer offer, int step) {
  if (step == 1) {
    return [
      t.retention_promo_terms_step1_line1(price: offer.priceLabel),
      t.retention_promo_terms_step1_line2(renewal: offer.renewalLabel),
    ];
  }
  if (step == 2) {
    return [t.retention_promo_coupon_pricing_step2(price: offer.priceLabel)];
  }
  if (offer.isWeekly) {
    return [
      t.retention_promo_terms_weekly(
        price: offer.priceLabel,
        renewal: offer.renewalLabel,
      ),
    ];
  }
  return [
    t.retention_promo_terms_quarterly(
      price: offer.priceLabel,
      renewal: offer.renewalLabel,
    ),
  ];
}

String _videoRetentionMoneyLabel(String value) {
  final clean = _text(value);
  if (clean.isEmpty) {
    return r'$0.00';
  }
  if (clean.contains(r'$')) {
    return clean;
  }
  return '\$$clean';
}

double _videoRetentionMoneyNumber(String value) {
  return double.tryParse(value.replaceAll(RegExp(r'[^0-9.]'), '')) ?? 0;
}

int _videoRetentionDiscountPercent(String price, String renewalPrice) {
  final p = _videoRetentionMoneyNumber(price);
  final r = _videoRetentionMoneyNumber(renewalPrice);
  if (p <= 0 || r <= 0 || p >= r) {
    return 0;
  }
  final raw = ((r - p) / r) * 100;
  final rounded = (raw / 10).round().clamp(0, 9);
  return rounded.toInt() * 10;
}

String _videoRetentionPerDayLabel(String price, int days) {
  final value = _videoRetentionMoneyNumber(price);
  if (value <= 0 || days <= 0) {
    return r'$0.00';
  }
  final perDay = ((value / days) * 100).floor() / 100;
  return '\$${perDay.toStringAsFixed(2)}';
}

bool _inferForYouHasMore(Map<String, dynamic> data, int rowCount) {
  final rawHasMore = data['has_more'];
  if (rawHasMore == true || rawHasMore == 1 || rawHasMore == '1') {
    return true;
  }
  if (rawHasMore == false || rawHasMore == 0 || rawHasMore == '0') {
    return false;
  }
  final perPage = _intValue(data['per_page']);
  final count = _intValue(data['count']);
  final batchSize = perPage > 0
      ? perPage
      : count > 0
      ? count
      : 10;
  return rowCount > 0 && rowCount >= batchSize;
}

String _watchToEpisodeId(dynamic watchTo) {
  if (watchTo is! Map) {
    return '';
  }
  return _text(watchTo['episode_id'] ?? watchTo['ep_id'] ?? watchTo['epId']);
}

String _watchToRouteKey(dynamic watchTo) {
  if (watchTo is! Map) {
    return '';
  }
  return [
    _text(watchTo['episode_id'] ?? watchTo['ep_id'] ?? watchTo['epId']),
    _text(watchTo['episode'] ?? watchTo['episodeNum'] ?? watchTo['ep']),
    _text(
      watchTo['position_ms'] ??
          watchTo['playback_position_ms'] ??
          watchTo['playbackPositionMs'],
    ),
    _text(watchTo['video'] ?? watchTo['video_url']),
  ].join('|');
}

String _posterUrl(Map<String, dynamic> item) {
  final image = movieCoverPath(item);
  return image.isEmpty ? '' : Global.static(image);
}

String _favoriteText(dynamic value) {
  final number = num.tryParse(_text(value)) ?? 0;
  if (number > 0) {
    return '${number.toInt()}K';
  }
  return '1K';
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
  if (_intValue(item['vip']) != 1) {
    return false;
  }
  final lock = item['lock'];
  final locked = item['locked'];
  return lock == true || locked == 1 || locked == '1' || locked == true;
}

int _unlockCoinsFrom(dynamic item) {
  if (item is! Map) {
    return 0;
  }
  return _intValue(
    item['unlock_coins'] ??
        item['unlockCoins'] ??
        item['coins'] ??
        item['episode_coins'],
  );
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
