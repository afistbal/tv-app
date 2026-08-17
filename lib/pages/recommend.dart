import 'package:flutter/material.dart';
import 'package:yogotv/movie_id.dart';
import 'package:yogotv/pages/native_video_feed.dart';

class Recommend extends StatelessWidget {
  final int? id;
  final bool active;

  Recommend({super.key, Object? id, this.active = true})
    : id = parseMovieId(id);

  @override
  Widget build(BuildContext context) {
    return ForYouVideoFeed(active: active);
  }
}
