String movieCoverPath(dynamic item) {
  if (item is! Map) {
    return '';
  }

  final id =
      item['movie_id'] ?? item['movieId'] ?? item['moveId'] ?? item['id'];
  final rename = item['is_rename'];
  final isRename = rename == 1 || rename == '1' || rename == true;
  if (isRename && id != null && _coverText(id).isNotEmpty) {
    return 'movie_images/${_coverText(id)}.webp';
  }

  return _coverText(
    item['image'] ??
        item['cover'] ??
        item['cover_url'] ??
        item['coverUrl'] ??
        item['poster'] ??
        item['image_url'],
  );
}

String _coverText(dynamic value) => value?.toString().trim() ?? '';
