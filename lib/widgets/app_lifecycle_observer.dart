import 'package:flutter/material.dart';

class AppLifecycleObserver extends StatefulWidget {
  final Widget child;
  final VoidCallback onResumed;

  const AppLifecycleObserver({
    super.key,
    required this.child,
    required this.onResumed,
  });

  @override
  State<AppLifecycleObserver> createState() => _AppLifecycleObserverState();
}

class _AppLifecycleObserverState extends State<AppLifecycleObserver>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      widget.onResumed();
    }
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}
