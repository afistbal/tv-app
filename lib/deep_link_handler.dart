import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';
import 'package:yogotv/adjust_tracking.dart';
import 'package:yogotv/global.dart';

class DeepLinkHandler {
  DeepLinkHandler(this._router);

  static const MethodChannel _methodChannel = MethodChannel(
    'yogotv.com/deep_link',
  );
  static const EventChannel _eventChannel = EventChannel(
    'yogotv.com/deep_link/events',
  );

  final GoRouter _router;
  StreamSubscription<dynamic>? _subscription;
  StreamSubscription<String>? _adjustSubscription;
  String? _lastHandledLink;
  DateTime? _lastHandledAt;

  static const Duration _duplicateLinkWindow = Duration(seconds: 1);

  Future<void> init() async {
    if (kIsWeb) {
      return;
    }

    try {
      final initialLink = await _methodChannel.invokeMethod<String>(
        'initialLink',
      );
      _handleLink(initialLink);
    } catch (error) {
      Global.logger.d('deep link initial failed: $error');
    }

    _subscription = _eventChannel.receiveBroadcastStream().listen(
      (event) => _handleLink(event?.toString()),
      onError: (error) {
        Global.logger.d('deep link stream failed: $error');
      },
    );
    _adjustSubscription = AdjustTracking.deepLinkUpdates.listen((link) {
      final pending = AdjustTracking.takePendingDeepLink();
      _handleLink(pending.isNotEmpty ? pending : link);
    });
    _handleLink(AdjustTracking.takePendingDeepLink());
  }

  Future<void> dispose() async {
    await _subscription?.cancel();
    await _adjustSubscription?.cancel();
    _subscription = null;
    _adjustSubscription = null;
  }

  void _handleLink(String? rawLink) {
    final link = rawLink?.trim();
    if (link == null || link.isEmpty) {
      return;
    }
    final now = DateTime.now();
    if (link == _lastHandledLink &&
        _lastHandledAt != null &&
        now.difference(_lastHandledAt!) < _duplicateLinkWindow) {
      return;
    }
    final uri = Uri.tryParse(link);
    if (uri == null || !_isSupportedUri(uri)) {
      return;
    }

    final movieId = _intQuery(uri, ['movieId', 'movie_id', 'id']);
    if (movieId == null || movieId <= 0) {
      return;
    }

    final episodeNum = _intQuery(uri, [
      'episodeNum',
      'episode',
      'episode_no',
      'ep',
      'v',
    ]);

    _lastHandledLink = link;
    _lastHandledAt = now;
    unawaited(AdjustTracking.recordDeepLink(link));
    Global.logger.d('deep link open movie=$movieId episode=$episodeNum');
    final playExtra = {
      'id': movieId,
      'openId': now.microsecondsSinceEpoch,
      'source': 'deep_link',
      'watchTo': {
        if (episodeNum != null && episodeNum > 0) 'episode': episodeNum,
      },
    };
    _router.go('/');
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_router.push<void>('/play', extra: playExtra));
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  bool _isSupportedUri(Uri uri) {
    final scheme = uri.scheme.toLowerCase();
    if (scheme == 'com.yogotv.app') {
      return true;
    }
    if (scheme == 'https' &&
        (uri.host.toLowerCase() == 'yogoshort.com' ||
            uri.host.toLowerCase() == 'www.yogoshort.com') &&
        (uri.path == '/open' || uri.path.startsWith('/open/'))) {
      return true;
    }
    return scheme == 'open' &&
        uri.host.toLowerCase() == 'yogo.com' &&
        uri.path == '/movie';
  }

  int? _intQuery(Uri uri, List<String> keys) {
    for (final key in keys) {
      final value = uri.queryParameters[key]?.trim();
      if (value == null || value.isEmpty) {
        continue;
      }
      final parsed = int.tryParse(value);
      if (parsed != null) {
        return parsed;
      }
    }
    return null;
  }
}
