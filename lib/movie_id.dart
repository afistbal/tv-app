const _movieIdKeys = ['movie_id', 'movieId', 'moveId', 'id'];

Object? movieIdValue(Object? value) {
  if (value is! Map) {
    return value;
  }
  for (final key in _movieIdKeys) {
    final candidate = value[key];
    if (candidate != null && candidate.toString().trim().isNotEmpty) {
      return candidate;
    }
  }
  return null;
}

int? parseMovieId(Object? value) {
  final raw = movieIdValue(value);
  final int? parsed;
  if (raw is int) {
    parsed = raw;
  } else {
    parsed = int.tryParse(raw?.toString().trim() ?? '');
  }
  return parsed != null && parsed > 0 ? parsed : null;
}
