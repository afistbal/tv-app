import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:yogotv/app_config.dart';
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
    if (Global.webPreview) {
      return Stack(
        children: [
          Container(
            width: widget.width,
            height: widget.height,
            color: Color(0x10ffffff),
            alignment: Alignment.center,
            child: Text(
              AppConfig.current.brandDisplayName,
              style: TextStyle(
                color: Colors.white24,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          Image.network(
            widget.url,
            width: widget.width,
            height: widget.height,
            fit: widget.fit,
            cacheWidth: widget.cacheWidth,
            cacheHeight: widget.cacheHeight,
            filterQuality: FilterQuality.low,
            gaplessPlayback: true,
            webHtmlElementStrategy: WebHtmlElementStrategy.fallback,
            errorBuilder: (context, error, stackTrace) {
              Global.logger.d(error);
              return Container(
                width: widget.width,
                height: widget.height,
                color: Color(0x10ffffff),
                alignment: Alignment.center,
                child: Text(
                  AppConfig.current.brandDisplayName,
                  style: TextStyle(
                    color: Colors.red.withAlpha(100),
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              );
            },
          ),
        ],
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
        return Container(
          color: Color(0x10ffffff),
          alignment: Alignment.center,
          child: Text(
            AppConfig.current.brandDisplayName,
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
            AppConfig.current.brandDisplayName,
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
