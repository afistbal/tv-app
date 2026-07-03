import 'package:flutter/material.dart';
import 'package:yogotv/pages/native_video_feed.dart';

class Recommend extends StatelessWidget {
  final int? id;

  const Recommend({super.key, this.id});

  @override
  Widget build(BuildContext context) {
    return const NativeVideoFeed.forYou();
  }
}
