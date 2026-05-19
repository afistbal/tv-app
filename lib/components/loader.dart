import 'package:flutter/material.dart';
import 'package:yogotv/components/loading.dart';

class Loader extends StatefulWidget {
  final Widget child;
  final bool show;

  const Loader({super.key, required this.show, required this.child});

  @override
  State<StatefulWidget> createState() {
    return _Loader();
  }
}

class _Loader extends State<Loader> {
  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        widget.child,
        widget.show ? Container(color: Colors.black54) : Container(),
        widget.show ? Loading() : Container(),
      ],
    );
  }
}
