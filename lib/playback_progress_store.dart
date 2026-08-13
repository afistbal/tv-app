import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Persists resume positions without tying them to an app version.
class PlaybackProgressStore {
  const PlaybackProgressStore(this._preferences);

  static const String _namespace = 'playback_progress';

  final SharedPreferences _preferences;

  int? readSeconds({
    required String uid,
    required String movieId,
    required String episodeId,
  }) {
    final key = _storageKey(uid: uid, movieId: movieId, episodeId: episodeId);
    return key == null ? null : _preferences.getInt(key);
  }

  Future<bool> writeSeconds({
    required String uid,
    required String movieId,
    required String episodeId,
    required int seconds,
  }) {
    final key = _storageKey(uid: uid, movieId: movieId, episodeId: episodeId);
    if (key == null) {
      return Future<bool>.value(false);
    }
    return _preferences.setInt(key, seconds < 0 ? 0 : seconds);
  }

  static String? _storageKey({
    required String uid,
    required String movieId,
    required String episodeId,
  }) {
    final normalizedUid = uid.trim();
    final normalizedMovieId = movieId.trim();
    final normalizedEpisodeId = episodeId.trim();
    if (normalizedUid.isEmpty ||
        normalizedMovieId.isEmpty ||
        normalizedEpisodeId.isEmpty) {
      return null;
    }
    return [
      _namespace,
      _encode(normalizedUid),
      _encode(normalizedMovieId),
      _encode(normalizedEpisodeId),
    ].join(':');
  }

  static String _encode(String value) {
    return base64Url.encode(utf8.encode(value)).replaceAll('=', '');
  }
}
