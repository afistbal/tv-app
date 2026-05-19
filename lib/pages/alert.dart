import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:yogotv/i18n/strings.g.dart';

class Alert extends Page {
  final String title;
  final String content;
  const Alert({super.key, required this.title, required this.content});

  @override
  Route createRoute(BuildContext context) {
    return DialogRoute(
      context: context,
      settings: this,
      builder: (context) {
        return AlertDialog(
          title: Text(title),
          content: Text(content),
          actions: [
            FilledButton(
              onPressed: () {
                context.pop(true);
              },
              child: Text(t.ok),
            ),
            FilledButton.tonal(
              onPressed: () {
                context.pop();
              },
              child: Text(t.cancel),
            ),
          ],
        );
      },
    );
  }
}
