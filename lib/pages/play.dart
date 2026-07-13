import 'package:flutter/material.dart';
import 'package:yogotv/pages/native_video_feed.dart';

class Play extends StatelessWidget {
  final int? id;
  final dynamic watchTo;

  const Play({super.key, this.id, this.watchTo});

  @override
  Widget build(BuildContext context) {
    return EpisodeVideoPage(movieId: id, watchTo: watchTo);
  }
}
