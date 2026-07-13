import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

class AndroidToolbar extends StatelessWidget {
  const AndroidToolbar({
    super.key,
    required this.title,
    required this.onBack,
    this.trailing,
  });

  final String title;
  final VoidCallback onBack;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 44,
      child: Stack(
        alignment: Alignment.center,
        children: [
          PositionedDirectional(
            start: 15,
            top: 10,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onBack,
              child: SizedBox(
                width: 24,
                height: 24,
                child: SvgPicture.asset(
                  'assets/images/android/ic_toolbar_back.svg',
                  width: 24,
                  height: 24,
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 39),
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 17,
                fontWeight: FontWeight.w500,
                height: 22 / 17,
              ),
            ),
          ),
          if (trailing != null)
            PositionedDirectional(end: 15, top: 0, bottom: 0, child: trailing!),
        ],
      ),
    );
  }
}
