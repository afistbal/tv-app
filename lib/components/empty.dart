import 'package:flutter/material.dart';
import 'package:yogotv/i18n/strings.g.dart';

class Empty extends StatelessWidget {
  const Empty({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            t.no_content,
            textAlign: TextAlign.center,
            style: TextStyle(color: Color(0xff999999), fontSize: 14),
          ),
        ],
      ),
    );
  }
}
