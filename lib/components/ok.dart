import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

class Ok extends StatelessWidget {
  final String message;
  const Ok({super.key, required this.message});

  @override
  Widget build(BuildContext context) {
    return Column(
      spacing: 16,
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.stretch,

      children: [
        Icon(LucideIcons.circleCheck200, color: Colors.lightGreen, size: 72),
        Text(
          message,
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 16, color: Colors.white60),
        ),
      ],
    );
  }
}
