import 'package:flutter/material.dart';
import 'package:yogotv/pages/native_video_feed.dart';

class Recommend extends StatelessWidget {
  final int? id;
  final bool active;

  const Recommend({super.key, this.id, this.active = true});

  @override
  Widget build(BuildContext context) {
    return ForYouVideoFeed(active: active);
  }
}
