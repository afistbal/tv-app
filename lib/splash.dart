import 'package:flutter/material.dart';
import 'package:loading_animation_widget/loading_animation_widget.dart'
    show LoadingAnimationWidget;

class Splash extends StatefulWidget {
  const Splash({super.key});

  @override
  State<StatefulWidget> createState() {
    return _Splash();
  }
}

class _Splash extends State<Splash> {
  @override
  void initState() {
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        spacing: 8,
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(40),
            child: Image.asset('assets/images/icon.png', width: 80, height: 80),
          ),
          Center(
            child: Text(
              'YogoTV',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ),
          SizedBox(height: 160),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 64),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              spacing: 8,
              children: [
                // Text('100%', style: TextStyle(fontSize: 16)),
                // LinearProgressIndicator(
                //   borderRadius: BorderRadius.circular(4),
                //   minHeight: 8,
                //   value: 0.5,
                // ),
                LoadingAnimationWidget.discreteCircle(
                  size: 32,
                  color: Colors.white60,
                ),
                // Text(
                //   'LOADING',
                //   style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                // ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
