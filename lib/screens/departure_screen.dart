import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../api/realtime_trains_service.dart';
import '../helpers/preferences_service.dart';
import '../helpers/text_formatter.dart';
import '../models/station.dart';
import '../models/departure.dart';
import '../widgets/blinking_widget.dart';
import '../widgets/countdown_timer.dart';
import '../widgets/app_lifecycle_observer.dart';
import 'service_detail_screen.dart';

class DepartureScreen extends StatefulWidget {
  final Station station;

  const DepartureScreen({super.key, required this.station});

  @override
  State<DepartureScreen> createState() => _DepartureScreenState();
}

class _DepartureScreenState extends State<DepartureScreen> {
  final RealtimeTrainsService _apiService = RealtimeTrainsService();
  final PreferencesService _prefs = PreferencesService();
  final GlobalKey<CountdownTimerState> _countdownKey = GlobalKey<CountdownTimerState>();

  List<Departure>? _departures;
  String? _error;
  String? _loadingStatus;
  DateTime? _pivotTime;
  bool _isLoading = true;
  bool _isGroupingByPlatform = false;
  Map<String, List<Departure>> _groupedDepartures = {};
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _prefs.addListener(_onPrefsChanged);
    _loadDepartures();
    _startAutoRefresh();
  }

  @override
  void dispose() {
    _prefs.removeListener(_onPrefsChanged);
    _refreshTimer?.cancel();
    super.dispose();
  }

  void _onPrefsChanged() {
    if (!mounted) return;
    setState(() {});
  }

  void _handleAppResumed() {
    // If the app is resumed, refresh the departures
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

  DateTime? _parseDepartureTime(Departure dep) {
    final timeStr = dep.realtimeTime ?? dep.scheduledTime;
    if (timeStr == null || timeStr.length < 4) return null;
    try {
      final hour = int.parse(timeStr.substring(0, 2));
      final minute = int.parse(timeStr.substring(2, 4));
      final ref = _pivotTime ?? DateTime.now();
      return DateTime(ref.year, ref.month, ref.day, hour, minute);
    } catch (_) {
      return null;
    }
  }

  void _jumpEarlier() {
    final ref = _pivotTime ?? DateTime.now();
    DateTime target = ref.subtract(const Duration(minutes: 20));
    if (_departures != null && _departures!.isNotEmpty) {
      final firstTime = _parseDepartureTime(_departures!.first);
      if (firstTime != null) {
        target = firstTime.subtract(const Duration(minutes: 20));
      }
    }
    setState(() {
      _pivotTime = target;
    });
    _loadDepartures();
  }

  void _jumpLater() {
    final ref = _pivotTime ?? DateTime.now();
    DateTime target = ref.add(const Duration(minutes: 20));
    if (_departures != null && _departures!.isNotEmpty) {
      final lastTime = _parseDepartureTime(_departures!.last);
      if (lastTime != null) {
        target = lastTime.add(const Duration(minutes: 1));
      }
    }
    setState(() {
      _pivotTime = target;
    });
    _loadDepartures();
  }

  void _resetToNow() {
    setState(() {
      _pivotTime = null;
    });
    _loadDepartures();
  }

  Future<void> _loadDepartures({bool isRefresh = false}) async {
    if (!mounted) return;

    // Only show loading spinner on initial load
    if (!isRefresh) {
      setState(() {
        _isLoading = true;
        _loadingStatus = 'Fetching departures...';
        _error = null;
      });
    }

    try {
      final departures = await _apiService.fetchDepartures(
        widget.station.crsCode,
        forceRefresh: isRefresh,
        pivotTime: _pivotTime,
        onProgress: (status) {
          if (mounted && !isRefresh) {
            setState(() {
              _loadingStatus = status;
            });
          }
        },
      );
      if (!mounted) return;

      Map<String, List<Departure>> grouped = {};
      for (var dep in departures) {
        final platformKey = (dep.platform?.isNotEmpty ?? false) ? "Platform ${dep.platform}" : "Platform TBC";
        grouped.putIfAbsent(platformKey, () => []).add(dep);
      }

      setState(() {
        _departures = departures;
        _groupedDepartures = grouped;
        _isLoading = false;
        _loadingStatus = null;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      if (!isRefresh || _departures == null) {
        setState(() {
          _error = "Failed to load departures: ${e.toString()}";
          _isLoading = false;
          _loadingStatus = null;
        });
      }
    }
    _countdownKey.currentState?.reset();
  }

  Widget _buildPivotTimeBanner() {
    final formattedTime = _pivotTime != null ? DateFormat('HH:mm').format(_pivotTime!) : '';
    return Container(
      color: Theme.of(context).colorScheme.primaryContainer,
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      child: Row(
        children: [
          Icon(Icons.schedule, size: 18, color: Theme.of(context).colorScheme.onPrimaryContainer),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              "Viewing departures around $formattedTime",
              style: TextStyle(
                color: Theme.of(context).colorScheme.onPrimaryContainer,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          TextButton.icon(
            onPressed: _isLoading ? null : _resetToNow,
            icon: const Icon(Icons.restore, size: 16),
            label: const Text("Reset to Now"),
          ),
        ],
      ),
    );
  }

  Widget _buildTimeJumpButton({required bool isTop}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 6.0),
      child: OutlinedButton.icon(
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 12.0, horizontal: 16.0),
          minimumSize: const Size.fromHeight(44),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        onPressed: _isLoading ? null : (isTop ? _jumpEarlier : _jumpLater),
        icon: Icon(
          isTop ? Icons.arrow_upward : Icons.arrow_downward,
          size: 18,
        ),
        label: Text(
          isTop ? "Jump to earlier departures" : "Jump to later departures",
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
    );
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
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const CircularProgressIndicator(),
              if (_loadingStatus != null) ...[
                const SizedBox(height: 16),
                Text(
                  _loadingStatus!,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
              ],
            ],
          ),
        ),
      );
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
    final departuresCount = _departures?.length ?? 0;
    final itemCount = departuresCount + 2;

    return LayoutBuilder(builder: (context, constraints) {
      if (constraints.maxWidth > 600) {
        return Column(
          children: [
            if (_pivotTime != null) _buildPivotTimeBanner(),
            _buildTimeJumpButton(isTop: true),
            Expanded(
              child: GridView.builder(
                padding: const EdgeInsets.all(8.0),
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 400.0,
                  mainAxisSpacing: 8.0,
                  crossAxisSpacing: 8.0,
                  childAspectRatio: 3.5,
                ),
                itemCount: departuresCount,
                itemBuilder: (context, index) {
                  return _buildDepartureCard(_departures![index]);
                },
              ),
            ),
            _buildTimeJumpButton(isTop: false),
          ],
        );
      } else {
        return ListView.builder(
          itemCount: itemCount,
          itemBuilder: (context, index) {
            if (index == 0) {
              return Column(
                children: [
                  if (_pivotTime != null) _buildPivotTimeBanner(),
                  _buildTimeJumpButton(isTop: true),
                ],
              );
            }
            if (index == itemCount - 1) {
              return _buildTimeJumpButton(isTop: false);
            }
            return _buildDepartureCard(_departures![index - 1]);
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
          return SingleChildScrollView(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              children: [
                if (_pivotTime != null) _buildPivotTimeBanner(),
                _buildTimeJumpButton(isTop: true),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 16.0,
                  runSpacing: 16.0,
                  children: _groupedDepartures.entries.map((entry) {
                    return _buildPlatformColumn(entry.key, entry.value, isWide: true);
                  }).toList(),
                ),
                const SizedBox(height: 8),
                _buildTimeJumpButton(isTop: false),
              ],
            ),
          );
        } else {
          return ListView(
            padding: const EdgeInsets.all(8.0),
            children: [
              if (_pivotTime != null) _buildPivotTimeBanner(),
              _buildTimeJumpButton(isTop: true),
              ..._groupedDepartures.entries.map((entry) {
                return _buildPlatformColumn(entry.key, entry.value, isWide: false);
              }),
              _buildTimeJumpButton(isTop: false),
            ],
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
          
          int diffMinutes = real.difference(sched).inMinutes;
          // Handle day wrap (e.g. 23:55 sched, 00:05 real)
          if (diffMinutes < -720) {
            diffMinutes += 1440;
          } else if (diffMinutes > 720) {
            diffMinutes -= 1440;
          }
          
          timeColor = diffMinutes > 0 ? Colors.red : Colors.green;
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

    switch (status.toUpperCase()) {
      case "LATE":
      case "EARLY":
      case "ON TIME":
      case "CALL":
      case "STARTS":
      case "TERMINATES":
      case "PASS":
        return const SizedBox.shrink();
      case "CANCELLED":
        tagColor = Colors.red;
        break;
      case "AT_PLAT":
        tagColor = Colors.blue;
        break;
      case "APPR_STAT":
      case "APPR_PLAT":
        tagColor = Colors.orange;
        break;
      default:
        return const SizedBox.shrink();
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
        textAlign: TextAlign.center,
      ),
    );
  }
}
