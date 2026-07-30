import 'dart:async';

import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
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
  String? _lastHandledLink;

  Future<void> init() async {
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
  }

  Future<void> dispose() async {
    await _subscription?.cancel();
    _subscription = null;
  }

  void _handleLink(String? rawLink) {
    final link = rawLink?.trim();
    if (link == null || link.isEmpty || link == _lastHandledLink) {
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
    Global.logger.d('deep link open movie=$movieId episode=$episodeNum');
    _router.go(
      '/play',
      extra: {
        'id': movieId,
        'watchTo': {
          if (episodeNum != null && episodeNum > 0) 'episode': episodeNum,
        },
      },
    );
  }

  bool _isSupportedUri(Uri uri) {
    final scheme = uri.scheme.toLowerCase();
    if (scheme == 'com.yogotv.app') {
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
