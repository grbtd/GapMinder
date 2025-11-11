import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../api/realtime_trains_service.dart';
import '../helpers/text_formatter.dart';
import '../models/station.dart';
import '../models/departure.dart';
import '../models/service_detail.dart';
import '../widgets/blinking_widget.dart';
import '../widgets/countdown_timer.dart';
import '../widgets/app_lifecycle_observer.dart'; // <-- 1. IMPORT
import 'service_detail_screen.dart';

class DepartureScreen extends StatefulWidget {
  final Station station;

  const DepartureScreen({super.key, required this.station});

  @override
  State<DepartureScreen> createState() => _DepartureScreenState();
}

class _DepartureScreenState extends State<DepartureScreen> {
  final RealtimeTrainsService _apiService = RealtimeTrainsService();
  final GlobalKey<CountdownTimerState> _countdownKey = GlobalKey<CountdownTimerState>();

  List<Departure>? _departures;
  String? _error;
  bool _isLoading = true;
  bool _isGroupingByPlatform = false;
  Map<String, List<Departure>> _groupedDepartures = {};
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _loadDepartures();
    _startAutoRefresh();
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  // --- 2. ADD THIS METHOD ---
  void _handleAppResumed() {
    // App came to foreground, force a refresh and restart timer
    _loadDepartures(isRefresh: true);
    _startAutoRefresh();
  }

  void _startAutoRefresh() {
    _refreshTimer?.cancel();
    _countdownKey.currentState?.reset();
    _refreshTimer = Timer.periodic(const Duration(seconds: 60), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      _loadDepartures(isRefresh: true);
    });
  }

  Future<void> _loadDepartures({bool isRefresh = false}) async {
    if (!mounted) return;

    // Only show loading spinner on initial load
    if (!isRefresh) {
      setState(() {
        _isLoading = true;
        _error = null;
      });
    }

    try {
      final departures = await _apiService.fetchDepartures(widget.station.crsCode);
      if (!mounted) return;

      setState(() {
        _departures = departures;
        _groupDepartures();
        _isLoading = false;
        _error = null; // Clear any previous errors
      });
    } catch (e) {
      if (!mounted) return;
      // --- ADDED: Silent refresh logic ---
      if (!isRefresh || _departures == null) {
        setState(() {
          _error = "Failed to load departures: ${e.toString()}";
          _isLoading = false;
        });
      }
      // --- END ADDED ---
    }
    _countdownKey.currentState?.reset();
  }

  void _groupDepartures() {
    if (_departures == null) return;

    final platformPattern = RegExp(r'(\d+)');
    List<String> platforms = _departures!
        .map((d) => d.serviceType?.trim().toUpperCase() == 'BUS' ? 'BUS' : (d.platform ?? 'TBC'))
        .where((p) => p.isNotEmpty)
        .toSet()
        .toList();

    platforms.sort((a, b) {
      if (a == b) return 0;
      if (a == 'BUS') return 1;
      if (b == 'BUS') return -1;
      if (a == 'TBC') return 1;
      if (b == 'TBC') return -1;

      final matchA = platformPattern.firstMatch(a);
      final matchB = platformPattern.firstMatch(b);

      final numA = matchA != null ? int.tryParse(matchA.group(1)!) ?? 0 : a;
      final numB = matchB != null ? int.tryParse(matchB.group(1)!) ?? 0 : b;

      if (numA is int && numB is int) {
        return numA.compareTo(numB);
      }
      return a.compareTo(b);
    });

    Map<String, List<Departure>> grouped = {};
    for (var platform in platforms) {
      grouped[platform] = _departures!
          .where((d) =>
              (d.serviceType?.trim().toUpperCase() == 'BUS' ? 'BUS' : (d.platform ?? 'TBC')) ==
              platform)
          .toList();
    }

    _groupedDepartures = grouped;
  }

  void _onDepartureTapped(Departure departure) {
    if (departure.serviceUid.isEmpty && departure.status != 'CANCELLED') {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text("Cannot track this service."),
        backgroundColor: Colors.red,
      ));
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ServiceDetailScreen(
          station: widget.station,
          departure: departure,
        ),
      ),
    );
  }

  String _formatTime(String? time) {
    if (time == null || time.length != 4) return "--:--";
    try {
      return "${time.substring(0, 2)}:${time.substring(2, 4)}";
    } catch (e) {
      return "--:--";
    }
  }

  String _formatStatusText(String status, {bool isGrouped = false}) {
    switch (status) {
      case "LATE": return "LATE";
      case "EARLY": return "EARLY";
      case "ON TIME": return "ON TIME";
      case "CANCELLED": return "CANCELLED";
      case "AT_PLAT": return isGrouped ? "AT PLAT" : "AT PLATFORM";
      case "APPR_STAT":
      case "APPR_PLAT": return isGrouped ? "APPR" : "APPROACHING";
      default:
        return status;
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppLifecycleObserver(
      onResumed: _handleAppResumed,
      child: Scaffold(
        appBar: AppBar(
          title: Text("${widget.station.name} Departures"),
          actions: [
            if (_departures != null && _departures!.isNotEmpty)
              IconButton(
                icon: Icon(
                  _isGroupingByPlatform ? Icons.access_time : Icons.train,
                ),
                onPressed: () {
                  setState(() {
                    _isGroupingByPlatform = !_isGroupingByPlatform;
                  });
                },
              ),
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: CountdownTimer(
                key: _countdownKey,
                onRefresh: () => _loadDepartures(isRefresh: true),
              ),
            ),
          ],
        ),
        body: _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading && _departures == null) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
        ),
      );
    }

    if (_departures == null || _departures!.isEmpty) {
      return const Center(child: Text("No departures found."));
    }

    return _isGroupingByPlatform ? _buildGroupedView() : _buildListView();
  }

  Widget _buildListView() {
    return LayoutBuilder(builder: (context, constraints) {
      if (constraints.maxWidth > 600) {
        return GridView.builder(
          padding: const EdgeInsets.all(8.0),
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 400.0,
            mainAxisSpacing: 8.0,
            crossAxisSpacing: 8.0,
            childAspectRatio: 3.5,
          ),
          itemCount: _departures!.length,
          itemBuilder: (context, index) {
            return _buildDepartureCard(_departures![index]);
          },
        );
      } else {
        return ListView.builder(
          itemCount: _departures!.length,
          itemBuilder: (context, index) {
            return _buildDepartureCard(_departures![index]);
          },
        );
      }
    });
  }

  Widget _buildGroupedView() {
    return LayoutBuilder(
      builder: (context, constraints) {
        bool isWide = constraints.maxWidth > 600;

        if (isWide) {
          // Wide layout: Use a wrapping horizontal layout
          return SingleChildScrollView(
            padding: const EdgeInsets.all(16.0),
            child: Wrap(
              spacing: 16.0,
              runSpacing: 16.0,
              children: _groupedDepartures.entries.map((entry) {
                return _buildPlatformColumn(entry.key, entry.value, isWide: true);
              }).toList(),
            ),
          );
        } else {
          // Narrow layout: Use a vertical list
          return ListView(
            padding: const EdgeInsets.all(8.0),
            children: _groupedDepartures.entries.map((entry) {
              return _buildPlatformColumn(entry.key, entry.value, isWide: false);
            }).toList(),
          );
        }
      },
    );
  }

  Widget _buildPlatformColumn(String platform, List<Departure> departures, {bool isWide = false}) {
    final limitedDepartures = departures.take(3).toList();

    final columnContent = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 16.0),
          child: Text(
            platform == 'TBC'
                ? "Platform TBC"
                : (platform == 'BUS' ? "Buses" : "Platform $platform"),
            style: Theme.of(context).textTheme.titleLarge,
          ),
        ),
        const Divider(),
        ...limitedDepartures.map((dep) => _buildDepartureCard(dep, isGrouped: true)),
      ],
    );

    if (isWide) {
      return Card(
        margin: EdgeInsets.zero,
        child: SizedBox(
          width: 350,
          child: columnContent,
        ),
      );
    } else {
      return Card(
        margin: const EdgeInsets.symmetric(vertical: 8.0),
        child: columnContent,
      );
    }
  }

  Widget _buildDepartureCard(Departure departure, {bool isGrouped = false}) {
    final textTheme = Theme.of(context).textTheme;
    final scheduledTime = _formatTime(departure.scheduledTime);
    final realtime = _formatTime(departure.realtimeTime);
    final isCancelled = departure.status == 'CANCELLED';

    Widget timeWidget;
    Color timeColor = textTheme.bodyMedium?.color ?? Colors.white;

    if (isCancelled) {
      timeWidget = Text(
        scheduledTime,
        style: textTheme.titleMedium?.copyWith(
          decoration: TextDecoration.lineThrough,
          color: Colors.red,
        ),
      );
    } else if (realtime != "--:--") {
      if (realtime == scheduledTime) {
        timeColor = Colors.green; // On time
        timeWidget = Text(realtime, style: textTheme.titleMedium?.copyWith(color: timeColor));
      } else {
        try {
          final sched = DateFormat.Hm().parse(scheduledTime);
          final real = DateFormat.Hm().parse(realtime);
          timeColor = real.isAfter(sched) ? Colors.red : Colors.green;
        } catch (e) {
          timeColor = Colors.red;
        }

        timeWidget = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              scheduledTime,
              style: textTheme.bodyMedium?.copyWith(
                decoration: TextDecoration.lineThrough,
              ),
            ),
            Text(
              realtime,
              style: textTheme.titleMedium?.copyWith(color: timeColor),
            ),
          ],
        );
      }
    } else {
      timeWidget = Text(scheduledTime, style: textTheme.titleMedium);
    }

    Widget platformWidget;
    if (isCancelled) {
      platformWidget = const SizedBox.shrink();
    } else if (departure.serviceType?.trim().toUpperCase() == "BUS") {
      platformWidget = const Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.directions_bus),
          Text("Bus", style: TextStyle(fontSize: 12)),
        ],
      );
    } else if (isGrouped) {
      platformWidget = (departure.status != null && departure.status!.isNotEmpty)
          ? _buildStatusTag(departure.status!, isGrouped: isGrouped)
          : const SizedBox.shrink();
    } else {
      platformWidget = Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text("Plat", style: textTheme.bodySmall),
          departure.platformChanged
              ? BlinkingWidget(
                  child: Text(
                    (departure.platform == null || departure.platform!.isEmpty)
                        ? "TBC"
                        : departure.platform!,
                    style: textTheme.titleLarge?.copyWith(color: Colors.orange, fontWeight: FontWeight.bold),
                  ),
                )
              : Text(
                  (departure.platform == null || departure.platform!.isEmpty)
                      ? "TBC"
                      : departure.platform!,
                  style: textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                ),
        ],
      );
    }

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
      child: InkWell(
        onTap: () => _onDepartureTapped(departure),
        child: Padding(
          padding: const EdgeInsets.all(12.0),
          child: Row(
            children: [
              SizedBox(width: 50, child: timeWidget),
              const VerticalDivider(),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      departure.destination,
                      style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    if (isCancelled) ...[
                      if (departure.cancelReasonShortText != null &&
                          departure.cancelReasonShortText!.isNotEmpty)
                        Text(
                          getFormattedCancellationReason(departure.cancelReasonShortText!),
                          style: textTheme.bodySmall?.copyWith(color: Colors.red, fontStyle: FontStyle.italic),
                          overflow: TextOverflow.ellipsis,
                          maxLines: 2,
                        ),
                      if (!isGrouped) ...[
                        const SizedBox(height: 4),
                        _buildStatusTag(departure.status!),
                      ]
                    ] else ...[
                      Text(
                        departure.operatorName ?? 'Unknown Operator',
                        style: textTheme.bodySmall,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (!isGrouped && departure.status != null && departure.status!.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        _buildStatusTag(departure.status!, isGrouped: isGrouped),
                      ],
                    ]
                  ],
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(width: 50, child: Center(child: platformWidget)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatusTag(String status, {bool isGrouped = false}) {
    Color tagColor;
    String statusText = _formatStatusText(status, isGrouped: isGrouped);

    switch (status) {
      case "LATE":
      case "EARLY":
      case "ON TIME":
        return const SizedBox.shrink();
      case "CANCELLED":
        tagColor = Colors.red;
        break;
      case "AT_PLAT":
        tagColor = Colors.blue;
        break;
      default: // APPR_STAT, APPR_PLAT, etc.
        tagColor = Colors.orange;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: tagColor.withAlpha(50),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: tagColor, width: 1),
      ),
      child: Text(
        statusText,
        style: TextStyle(
          color: tagColor,
          fontWeight: FontWeight.bold,
          fontSize: 10,
        ),
        textAlign: TextAlign.center, // Center the text
      ),
    );
  }
}
