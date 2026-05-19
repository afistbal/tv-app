import 'package:flutter/material.dart';
import 'package:yogotv/i18n/strings.g.dart';

class NoMore extends StatelessWidget {
  const NoMore({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(t.no_more, style: TextStyle(color: Colors.white54)),
    );
  }
}
