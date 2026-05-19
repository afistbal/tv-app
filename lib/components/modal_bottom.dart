import 'package:flutter/material.dart';

class ModalBottom extends StatelessWidget {
  final String title;
  final Widget child;
  const ModalBottom({super.key, required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: EdgeInsets.only(left: 24, right: 8, top: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                spacing: 8,
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 32,
                      child: Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: Text(
                          title,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 18),
                        ),
                      ),
                    ),
                  ),
                  CloseButton(),
                ],
              ),
            ),
            child,
          ],
        ),
      ),
    );
  }
}
