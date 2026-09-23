import 'dart:async';
import 'package:flutter/material.dart';

class RateLimitCard extends StatefulWidget {
  final DateTime resetTime;
  final VoidCallback? onRetry;

  const RateLimitCard({
    super.key,
    required this.resetTime,
    this.onRetry,
  });

  @override
  State<RateLimitCard> createState() => _RateLimitCardState();
}

class _RateLimitCardState extends State<RateLimitCard> {
  Timer? _timer;
  late int _remainingSeconds;

  @override
  void initState() {
    super.initState();
    _calculateRemaining();
    _startTimer();
  }

  @override
  void didUpdateWidget(RateLimitCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.resetTime != widget.resetTime) {
      _calculateRemaining();
      _startTimer();
    }
  }

  void _calculateRemaining() {
    final diff = widget.resetTime.difference(DateTime.now()).inSeconds;
    _remainingSeconds = diff > 0 ? diff : 0;
  }

  void _startTimer() {
    _timer?.cancel();
    if (_remainingSeconds <= 0) return;

    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() {
        _calculateRemaining();
        if (_remainingSeconds <= 0) {
          timer.cancel();
        }
      });
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  String _formatDuration(int seconds) {
    final minutes = (seconds ~/ 60).toString().padLeft(2, '0');
    final secs = (seconds % 60).toString().padLeft(2, '0');
    return "$minutes:$secs";
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Card(
      margin: const EdgeInsets.all(16.0),
      color: Colors.amber.withOpacity(0.12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: Colors.amber.withOpacity(0.4), width: 1.5),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.amber.withOpacity(0.2),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.speed_rounded,
                    color: Colors.amber[800],
                    size: 28,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "API Rate Limit Reached",
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: Colors.amber[900],
                            ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        "Background requests paused to respect API limits.",
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                            ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.timer_outlined, size: 20, color: Colors.amber),
                      const SizedBox(width: 8),
                      Text(
                        _remainingSeconds > 0
                            ? "Resuming in ${_formatDuration(_remainingSeconds)}"
                            : "Rate limit reset. Ready to refresh.",
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  if (widget.onRetry != null)
                    TextButton(
                      onPressed: _remainingSeconds <= 0 ? widget.onRetry : null,
                      child: const Text("Retry Now"),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
