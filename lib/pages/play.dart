import 'package:flutter/material.dart';
import 'package:yogotv/movie_id.dart';
import 'package:yogotv/pages/native_video_feed.dart';

class Play extends StatelessWidget {
  final int? id;
  final dynamic watchTo;

  Play({super.key, Object? id, this.watchTo}) : id = parseMovieId(id);

  @override
  Widget build(BuildContext context) {
    return EpisodeVideoPage(movieId: id, watchTo: watchTo);
  }
}
