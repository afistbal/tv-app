import 'package:flutter/material.dart';
import 'package:yogotv/i18n/strings.g.dart';

class Recommend extends StatefulWidget {
  final int? id;
  const Recommend({super.key, this.id});

  @override
  State<StatefulWidget> createState() {
    return _Recommend();
  }
}

class _Recommend extends State<Recommend> {
  @override
  void initState() {
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(t.title_recommend)),
      body: Center(child: Text('1')),
    );
  }
}
