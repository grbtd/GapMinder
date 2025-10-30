import 'dart:async';
import 'package:flutter/material.dart';

class CountdownTimer extends StatefulWidget {
  final VoidCallback onRefresh;
  final Key? key; // Allow passing a key

  const CountdownTimer({this.key, required this.onRefresh}) : super(key: key);

  @override
  CountdownTimerState createState() => CountdownTimerState();
}

class CountdownTimerState extends State<CountdownTimer> {
  Timer? _timer;
  int _remaining = 60;
  double _progress = 1.0;

  @override
  void initState() {
    super.initState();
    startTimer();
  }

  void startTimer() {
    _timer?.cancel();
    _remaining = 60;
    _progress = 1.0;
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() {
        if (_remaining > 0) {
          _remaining--;
          _progress = _remaining / 60.0;
        } else {
          widget.onRefresh();
          // The refresh action will trigger a rebuild, which calls reset()
        }
      });
    });
  }

  void reset() {
    if (!mounted) return;
    setState(() {
      _timer?.cancel();
      startTimer();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        widget.onRefresh();
        reset();
      },
      child: SizedBox(
        width: 24,
        height: 24,
        child: CircularProgressIndicator(
          value: _progress,
          strokeWidth: 2.5,
          // **CHANGE**: Use the theme's primary color
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
    );
  }
}

