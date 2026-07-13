import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:video_player/video_player.dart';

class VideoPlaybackSession {
  static final Set<VideoPlayerController> _controllers = {};
  static VideoPlayerController? _current;

  static void register(VideoPlayerController controller) {
    _controllers.add(controller);
  }

  static void unregister(VideoPlayerController controller) {
    if (_current == controller) {
      _current = null;
    }
    _controllers.remove(controller);
  }

  static Future<void> play(VideoPlayerController controller) async {
    register(controller);
    for (final other in List<VideoPlayerController>.of(_controllers)) {
      if (other == controller) {
        continue;
      }
      await _silenceAndPause(other);
    }
    _current = controller;
    await controller.setVolume(kIsWeb ? 0 : 1);
    await controller.play();
  }

  static Future<void> pause(VideoPlayerController controller) async {
    await _silenceAndPause(controller);
    if (_current == controller) {
      _current = null;
    }
  }

  static Future<void> pauseAll() async {
    for (final controller in List<VideoPlayerController>.of(_controllers)) {
      await _silenceAndPause(controller);
    }
    _current = null;
  }

  static void silenceAllNow() {
    for (final controller in List<VideoPlayerController>.of(_controllers)) {
      unawaited(_silenceAndPause(controller));
    }
    _current = null;
  }

  static Future<void> _silenceAndPause(VideoPlayerController controller) async {
    try {
      await controller.setVolume(0);
      await controller.pause();
    } catch (_) {
      _controllers.remove(controller);
      if (_current == controller) {
        _current = null;
      }
    }
  }
}
