import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:yogotv/global.dart';

class LazyImage extends StatefulWidget {
  final String url;
  final double width;
  final double height;
  final BoxFit fit;

  const LazyImage({
    super.key,
    required this.url,
    required this.width,
    required this.height,
    this.fit = BoxFit.fitHeight,
  });

  @override
  State<StatefulWidget> createState() {
    return _LazyImage();
  }
}

class _LazyImage extends State<LazyImage> {
  @override
  Widget build(BuildContext context) {
    return CachedNetworkImage(
      imageUrl: widget.url,
      width: widget.width,
      height: widget.height,
      fit: widget.fit,
      placeholder: (context, url) {
        return Container(
          color: Color(0x10ffffff),
          alignment: Alignment.center,
          child: Text(
            'YogoTV',
            style: TextStyle(
              color: Colors.white24,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
        );
      },
      errorWidget: (context, url, error) {
        Global.logger.d(error);
        return Container(
          color: Color(0x10ffffff),
          alignment: Alignment.center,
          child: Text(
            'YogoTV',
            style: TextStyle(
              color: Colors.red.withAlpha(100),
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
        );
      },
    );
  }
}
