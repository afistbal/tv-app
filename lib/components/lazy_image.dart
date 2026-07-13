import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:yogotv/global.dart';

class LazyImage extends StatefulWidget {
  final String url;
  final double width;
  final double height;
  final BoxFit fit;
  final int? cacheWidth;
  final int? cacheHeight;

  const LazyImage({
    super.key,
    required this.url,
    required this.width,
    required this.height,
    this.fit = BoxFit.fitHeight,
    this.cacheWidth,
    this.cacheHeight,
  });

  @override
  State<StatefulWidget> createState() {
    return _LazyImage();
  }
}

class _LazyImage extends State<LazyImage> {
  @override
  Widget build(BuildContext context) {
    if (widget.url.trim().isEmpty) {
      return _ImageStandIn(width: widget.width, height: widget.height);
    }
    if (Global.webPreview) {
      return Image.network(
        widget.url,
        width: widget.width,
        height: widget.height,
        fit: widget.fit,
        filterQuality: FilterQuality.low,
        gaplessPlayback: true,
        webHtmlElementStrategy: WebHtmlElementStrategy.prefer,
        errorBuilder: (context, error, stackTrace) {
          return _ImageStandIn(width: widget.width, height: widget.height);
        },
      );
    }

    return CachedNetworkImage(
      imageUrl: widget.url,
      width: widget.width,
      height: widget.height,
      fit: widget.fit,
      memCacheWidth: widget.cacheWidth,
      memCacheHeight: widget.cacheHeight,
      fadeInDuration: Duration.zero,
      fadeOutDuration: Duration.zero,
      placeholderFadeInDuration: Duration.zero,
      useOldImageOnUrlChange: true,
      placeholder: (context, url) {
        return _ImageStandIn(width: widget.width, height: widget.height);
      },
      errorWidget: (context, url, error) {
        Global.logger.d(error);
        return _ImageStandIn(width: widget.width, height: widget.height);
      },
    );
  }
}

class _ImageStandIn extends StatelessWidget {
  const _ImageStandIn({required this.width, required this.height});

  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      height: height,
      child: ColoredBox(color: Color(0xff212121)),
    );
  }
}
