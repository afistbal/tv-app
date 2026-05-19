import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:yogotv/i18n/strings.g.dart';

class Empty extends StatelessWidget {
  const Empty({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        mainAxisAlignment: MainAxisAlignment.center,
        spacing: 16,
        children: [
          Icon(LucideIcons.box100, size: 96, color: Colors.white54),
          Text(t.no_content, style: TextStyle(color: Colors.white54)),
        ],
      ),
    );
  }
}
