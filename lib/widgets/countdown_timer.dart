import 'package:flutter/material.dart';

// Custom widget for the countdown refresh timer
class CountdownTimer extends StatefulWidget {
  final Duration duration;
  final VoidCallback onRefresh;
  const CountdownTimer({super.key, required this.duration, required this.onRefresh});

  @override
  CountdownTimerState createState() => CountdownTimerState();
}

class CountdownTimerState extends State<CountdownTimer>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: widget.duration,
    );
    _controller.addListener(() {
      setState(() {});
    });
    reset();
  }

  void reset() {
    _controller.reset();
    _controller.reverse(from: 1.0);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onRefresh,
      child: SizedBox(
        width: 40,
        height: 40,
        child: Stack(
          alignment: Alignment.center,
          children: [
            CircularProgressIndicator(
              value: _controller.value,
              strokeWidth: 2.0,
              backgroundColor: Colors.grey.withOpacity(0.5),
            ),
            Text(
              (_controller.duration! * _controller.value).inSeconds.ceil().toString(),
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
