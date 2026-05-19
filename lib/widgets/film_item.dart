import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:yogotv/components/lazy_image.dart';
import 'package:yogotv/global.dart';

class FilmItem extends StatelessWidget {
  final int id;
  final double width;
  final double height;
  final String image;
  final String title;
  final bool recommend;

  const FilmItem({
    super.key,
    required this.id,
    required this.width,
    required this.height,
    required this.image,
    required this.title,
    required this.recommend,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        // if (recommend) {
        //   context.push('/recommend', extra: {'id': id});
        // }

        context.push('/play', extra: {'id': id});
      },
      child: Container(
        width: width,
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(8)),
        clipBehavior: Clip.hardEdge,
        child: Column(
          spacing: 8,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LazyImage(
                url: Global.static(image),
                width: width,
                height: height,
                fit: BoxFit.cover,
              ),
            ),
            Text(
              title,
              maxLines: 2,
              style: TextStyle(overflow: TextOverflow.ellipsis, height: 1.25),
            ),
          ],
        ),
      ),
    );
  }
}
