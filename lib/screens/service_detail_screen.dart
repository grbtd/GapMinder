import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../api/realtime_trains_service.dart';
import '../helpers/text_formatter.dart';
import '../models/station.dart';
import '../models/departure.dart';
import '../models/service_detail.dart';
import '../widgets/countdown_timer.dart';
import '../widgets/app_lifecycle_observer.dart';

class ServiceDetailScreen extends StatefulWidget {
  final Station station;
  final Departure departure;

  const ServiceDetailScreen({
    super.key,
    required this.station,
    required this.departure,
  });

  @override
  State<ServiceDetailScreen> createState() => _ServiceDetailScreenState();
}

class _ServiceDetailScreenState extends State<ServiceDetailScreen> {
  final RealtimeTrainsService _apiService = RealtimeTrainsService();
  final GlobalKey<CountdownTimerState> _countdownKey = GlobalKey<CountdownTimerState>();

  final ScrollController _scrollController = ScrollController();
  final GlobalKey _selectedStationKey = GlobalKey();

  ServiceDetail? _serviceDetail;
  String? _error;
  bool _isLoading = true;
  Timer? _refreshTimer;
  int _trainPositionIndex = -1;
  List<DateTime?> _locationTimestamps = [];

  @override
  void initState() {
    super.initState();
    _fetchServiceDetails();
    if (widget.departure.status != 'CANCELLED') {
      _startAutoRefresh();
    }
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  void _handleAppResumed() {
    if (widget.departure.status == 'CANCELLED') {
      return;
    }
    _fetchServiceDetails(isRefresh: true);
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
      _fetchServiceDetails(isRefresh: true);
    });
  }

  Future<void> _fetchServiceDetails({bool isRefresh = false}) async {
    if (!mounted) return;

    if (!isRefresh) {
      setState(() {
        _isLoading = true;
        _error = null;
      });
    }

    try {
      final serviceDetail = await _apiService.fetchServiceDetails(
        widget.departure.serviceUid,
        widget.departure.runDate,
      );
      if (!mounted) return;

      _processServiceData(serviceDetail);

      if (!isRefresh) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_selectedStationKey.currentContext != null) {
            Scrollable.ensureVisible(
              _selectedStationKey.currentContext!,
              duration: const Duration(milliseconds: 500),
              curve: Curves.easeInOut,
              alignment: 0.1,
            );
          }
        });
      }

    } catch (e) {
      if (!mounted) return;
      if (!isRefresh || _serviceDetail == null) {
        setState(() {
          _error = "Failed to load service details: ${e.toString()}";
          _isLoading = false;
        });
      }
    }
    _countdownKey.currentState?.reset();
  }

  void _processServiceData(ServiceDetail service) {
    List<DateTime?> timestamps = [];
    if (service.runDate != null) {
      try {
        DateTime currentDate = DateFormat("yyyy-MM-dd").parse(service.runDate!);
        int lastHour = -1;

        for (var loc in service.locations) {
          // Use the most relevant time available to establish the chronological timeline
          String? orderingTimeStr = loc.realtimeDeparture ?? loc.gbttBookedDeparture ?? loc.realtimeArrival ?? loc.gbttBookedArrival;
          
          DateTime? stopTime;
          if (orderingTimeStr != null && orderingTimeStr.length == 4) {
             try {
               int h = int.parse(orderingTimeStr.substring(0, 2));
               int m = int.parse(orderingTimeStr.substring(2, 4));
               
               // Detect day wrapping: if hour jumps backward significantly (e.g. 23 -> 00)
               if (lastHour != -1) {
                  if (h < lastHour && (lastHour - h) > 12) {
                     currentDate = currentDate.add(const Duration(days: 1));
                  }
               }
               lastHour = h;
               stopTime = DateTime(currentDate.year, currentDate.month, currentDate.day, h, m);
             } catch (_) {
               // parse error
             }
          }
          timestamps.add(stopTime);
        }
      } catch (e) {
        // fallback
      }
    }
    
    // Ensure list size matches locations
    while (timestamps.length < service.locations.length) {
      timestamps.add(null);
    }

    setState(() {
      _serviceDetail = service;
      _locationTimestamps = timestamps;
      _trainPositionIndex = _findTrainPositionIndex(service);
      _isLoading = false;
      _error = null;
    });
  }

  String _formatTime(String? time) {
    if (time == null || time.length != 4) return "--:--";
    try {
      return "${time.substring(0, 2)}:${time.substring(2, 4)}";
    } catch (e) {
      return "--:--";
    }
  }

  int _findTrainPositionIndex(ServiceDetail? service) {
    if (service == null) return -1;

    int locationIndex = service.locations.indexWhere(
            (loc) => (loc.serviceLocation ?? '').isNotEmpty && loc.serviceLocation != "AT_PLAT"
    );
    if (locationIndex != -1) return locationIndex;

    int lastDepartedIndex = -1;
    final now = DateTime.now();

    for (int i = 0; i < _locationTimestamps.length; i++) {
      final ts = _locationTimestamps[i];
      if (ts != null) {
        // If the calculated timestamp (which accounts for day wrap) is in the past
        if (ts.isBefore(now)) {
          lastDepartedIndex = i;
        } else {
          // Assuming sorted list, once we hit a future time, we stop
          break;
        }
      }
    }
    return lastDepartedIndex;
  }

  @override
  Widget build(BuildContext context) {
    Widget titleWidget = Text(widget.departure.destination);
    if (_serviceDetail != null) {
      final originTime = _formatTime(_serviceDetail!.originTime);
      titleWidget = FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(
          "$originTime from ${_serviceDetail!.origin} to ${_serviceDetail!.destination}",
        ),
      );
    } else if (_isLoading) {
      titleWidget = Text("Loading service...");
    }

    return AppLifecycleObserver(
      onResumed: _handleAppResumed,
      child: Scaffold(
        appBar: AppBar(
          title: titleWidget,
          actions: [
            if (widget.departure.status != 'CANCELLED')
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: CountdownTimer(
                  key: _countdownKey,
                  onRefresh: () => _fetchServiceDetails(isRefresh: true),
                ),
              ),
          ],
        ),
        body: _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading && _serviceDetail == null) {
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

    if (_serviceDetail == null) {
      return const Center(child: Text("No service details found."));
    }

    return _buildServiceDetailView(_serviceDetail!);
  }

  Widget _buildServiceDetailView(ServiceDetail service) {
    final theme = Theme.of(context);
    final isCancelled = widget.departure.status == 'CANCELLED';

    String article = "A";
    if (service.atocName.isNotEmpty) {
      String firstLetter = service.atocName.substring(0, 1).toLowerCase();
      if (['a', 'e', 'i', 'o', 'u'].contains(firstLetter)) {
        article = "An";
      }
    }

    return ListView.builder(
      controller: _scrollController,
      itemCount: service.locations.length + 1, // +1 for the header
      itemBuilder: (context, index) {
        if (index == 0) {
          // Build the header
          return Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              children: [
                Text(
                  "Head Code: ${service.trainIdentity}",
                  style: theme.textTheme.headlineSmall,
                ),
                const SizedBox(height: 8),
                Text(
                  "$article ${service.atocName} service to ${service.destination} from ${service.origin}",
                  style: theme.textTheme.bodyLarge,
                  textAlign: TextAlign.center,
                ),
                if (isCancelled) ...[
                  const SizedBox(height: 16),
                  Text(
                    "Service Cancelled",
                    style: theme.textTheme.titleLarge?.copyWith(color: Colors.red, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    getFormattedCancellationReason(widget.departure.cancelReasonLongText ?? widget.departure.cancelReasonShortText),
                    style: theme.textTheme.bodyMedium?.copyWith(fontStyle: FontStyle.italic),
                    textAlign: TextAlign.center,
                  ),
                ]
              ],
            ),
          );
        }

        final locationIndex = index - 1;
        final location = service.locations[locationIndex];
        final isSelectedStation = location.crs == widget.station.crsCode;
        final isFinalDestination = locationIndex == service.locations.length - 1;
        final isFirstStation = locationIndex == 0;

        final bool isTrainInTransitHere = _trainPositionIndex == locationIndex &&
            locationIndex < service.locations.length - 1;

        return Column(
          children: [
            _buildTimelineStop(
              location,
              locationIndex,
              isSelectedStation,
              isFinalDestination,
              isFirstStation,
              isCancelled,
              key: isSelectedStation ? _selectedStationKey : null,
            ),
            if (isTrainInTransitHere && !isCancelled)
              _buildInTransitView(service.locations[_trainPositionIndex]),
          ],
        );
      },
    );
  }

  Widget _buildInTransitView(CallingPoint lastDepartedStation) {
    final theme = Theme.of(context);
    String lateness = "On time";
    Color latenessColor = Colors.green;

    final latenessInMinutes = lastDepartedStation.departureLateness;
    if (latenessInMinutes > 0) {
      lateness = "$latenessInMinutes min late";
      latenessColor = Colors.red;
    } else if (latenessInMinutes < 0) {
      lateness = "${latenessInMinutes.abs()} min early";
      latenessColor = Colors.green;
    }

    return IntrinsicHeight(
      child: Row(
        children: [
          SizedBox(
            width: 80,
            child: Center(
              child: Container(
                width: 2,
                color: theme.colorScheme.primary.withOpacity(0.5),
              ),
            ),
          ),
          Expanded(
            child: Row(
              children: [
                Icon(Icons.train, color: theme.colorScheme.primary, size: 20),
                const SizedBox(width: 8),
                Text("In transit", style: theme.textTheme.bodyMedium?.copyWith(
                    fontStyle: FontStyle.italic,
                    color: theme.colorScheme.primary
                )),
                const SizedBox(width: 16),
                Text(lateness, style: theme.textTheme.bodyMedium?.copyWith(
                    color: latenessColor,
                    fontStyle: FontStyle.italic
                )),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTimelineStop(CallingPoint location, int index, bool isSelectedStation, bool isFinalDestination, bool isFirstStation, bool isCancelled, {Key? key}) {
    final theme = Theme.of(context);
    final isAtPlatform = location.serviceLocation == "AT_PLAT";
    final isApproaching = location.serviceLocation == "APPR_STAT" || location.serviceLocation == "APPR_PLAT";

    bool hasDeparted = false;
    if (!isCancelled) {
      if (index < _locationTimestamps.length) {
        final ts = _locationTimestamps[index];
        if (ts != null && ts.isBefore(DateTime.now())) {
           hasDeparted = true;
        }
      }
    }

    final hasArrived = !isCancelled && (location.realtimeArrival?.isNotEmpty ?? false);

    Color circleColor = (hasDeparted || isCancelled)
        ? Colors.grey
        : theme.colorScheme.primary;

    IconData circleIcon;
    if (isCancelled) {
      circleIcon = Icons.cancel;
    } else if (isSelectedStation) {
      circleIcon = Icons.location_pin;
    } else if (isAtPlatform) {
      circleIcon = Icons.train;
    } else if (hasDeparted) {
      circleIcon = Icons.check_circle;
    } else if (isFinalDestination) {
      circleIcon = Icons.flag;
    } else {
      circleIcon = Icons.circle;
    }
    
    Color topSegmentColor = (isFirstStation)
        ? Colors.transparent
        : ((hasDeparted || hasArrived || isCancelled)
            ? Colors.grey
            : theme.colorScheme.primary.withOpacity(0.5));

    Color bottomSegmentColor = (isFinalDestination)
        ? Colors.transparent
        : ((hasDeparted || isCancelled)
            ? Colors.grey
            : theme.colorScheme.primary.withOpacity(0.5));

    return IntrinsicHeight(
      key: key,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Timeline CustomPaint
          SizedBox(
            width: 80,
            child: CustomPaint(
               painter: _TimelinePainter(
                 topColor: topSegmentColor,
                 bottomColor: bottomSegmentColor,
                 iconTop: 20.0,
                 iconSize: 24.0,
               ),
               child: Align(
                 alignment: Alignment.topCenter,
                 child: Padding(
                   padding: const EdgeInsets.only(top: 20.0),
                   child: Icon(circleIcon, color: circleColor, size: 24),
                 ),
               ),
            ),
          ),

          // Stop Details
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 16.0, horizontal: 16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    location.locationName ?? 'Unknown Station',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: isSelectedStation ? FontWeight.bold : FontWeight.normal,
                      color: isCancelled ? Colors.grey : null,
                    ),
                  ),
                  const SizedBox(height: 4),
                  if (location.platform != null && location.platform!.isNotEmpty)
                    Text(
                        "Platform: ${location.platform}",
                        style: theme.textTheme.bodySmall?.copyWith(color: isCancelled ? Colors.grey : null)
                    ),
                  const SizedBox(height: 4),
                  _buildStopTimes(location, isCancelled),
                  if (isAtPlatform && !isCancelled)
                    _buildStatusTag("AT PLATFORM", Colors.blue),
                  if (isApproaching && !isCancelled)
                    _buildStatusTag("APPROACHING", Colors.orange),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStopTimes(CallingPoint location, bool isCancelled) {
    final theme = Theme.of(context);
    final scheduledArrival = _formatTime(location.gbttBookedArrival);
    final realtimeArrival = _formatTime(location.realtimeArrival);
    final scheduledDeparture = _formatTime(location.gbttBookedDeparture);
    final realtimeDeparture = _formatTime(location.realtimeDeparture);

    if (isCancelled) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (scheduledArrival != "--:--")
            Text(
              "$scheduledArrival (Arr)",
              style: theme.textTheme.bodyMedium?.copyWith(
                color: Colors.grey,
                decoration: TextDecoration.lineThrough,
              ),
            ),
          if (scheduledDeparture != "--:--")
            Text(
              "$scheduledDeparture (Dep)",
              style: theme.textTheme.bodyMedium?.copyWith(
                color: Colors.grey,
                decoration: TextDecoration.lineThrough,
              ),
            ),
        ],
      );
    }

    String arrivalText = scheduledArrival;
    String departureText = scheduledDeparture;
    Color arrivalColor = theme.textTheme.bodyMedium?.color ?? Colors.white;
    Color departureColor = theme.textTheme.bodyMedium?.color ?? Colors.white;

    Color getColor(String sched, String real) {
      if (real == sched) return Colors.green;
      try {
        final s = DateFormat.Hm().parse(sched);
        final r = DateFormat.Hm().parse(real);
        int diff = r.difference(s).inMinutes;
        if (diff < -720) diff += 1440;
        else if (diff > 720) diff -= 1440;
        return diff > 0 ? Colors.red : Colors.green;
      } catch (e) {
        return Colors.red;
      }
    }

    if (realtimeArrival != "--:--") {
      arrivalColor = getColor(scheduledArrival, realtimeArrival);
    }
    if (realtimeDeparture != "--:--") {
      departureColor = getColor(scheduledDeparture, realtimeDeparture);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (scheduledArrival != "--:--" || realtimeArrival != "--:--")
          Row(
            children: [
              if (realtimeArrival != "--:--")
                Text(
                  realtimeArrival,
                  style: theme.textTheme.bodyMedium?.copyWith(color: arrivalColor, fontWeight: FontWeight.bold),
                ),
              if (realtimeArrival != "--:--" && scheduledArrival != realtimeArrival)
                Padding(
                  padding: const EdgeInsets.only(left: 8.0),
                  child: Text(
                    arrivalText,
                    style: theme.textTheme.bodySmall?.copyWith(decoration: TextDecoration.lineThrough),
                  ),
                ),
              if (realtimeArrival == "--:--")
                Text(arrivalText, style: theme.textTheme.bodyMedium),
              Text(" (Arr)", style: theme.textTheme.bodySmall),
            ],
          ),

        if (scheduledDeparture != "--:--" || realtimeDeparture != "--:--")
          Row(
            children: [
              if (realtimeDeparture != "--:--")
                Text(
                  realtimeDeparture,
                  style: theme.textTheme.bodyMedium?.copyWith(color: departureColor, fontWeight: FontWeight.bold),
                ),
              if (realtimeDeparture != "--:--" && scheduledDeparture != realtimeDeparture)
                Padding(
                  padding: const EdgeInsets.only(left: 8.0),
                  child: Text(
                    departureText,
                    style: theme.textTheme.bodySmall?.copyWith(decoration: TextDecoration.lineThrough),
                  ),
                ),
              if (realtimeDeparture == "--:--")
                Text(departureText, style: theme.textTheme.bodyMedium),
              Text(" (Dep)", style: theme.textTheme.bodySmall),
            ],
          ),
      ],
    );
  }

  Widget _buildStatusTag(String status, Color color) {
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.2),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color, width: 1),
      ),
      child: Text(
        status,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.bold,
          fontSize: 10,
        ),
      ),
    );
  }
}

class _TimelinePainter extends CustomPainter {
  final Color topColor;
  final Color bottomColor;
  final double iconTop;
  final double iconSize;

  _TimelinePainter({
    required this.topColor,
    required this.bottomColor,
    required this.iconTop,
    required this.iconSize,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke;

    final centerX = size.width / 2;

    // Draw top line (from 0 to top of icon)
    if (topColor != Colors.transparent) {
      paint.color = topColor;
      canvas.drawLine(
        Offset(centerX, 0),
        Offset(centerX, iconTop),
        paint,
      );
    }

    // Draw bottom line (from bottom of icon to end)
    if (bottomColor != Colors.transparent) {
      paint.color = bottomColor;
      canvas.drawLine(
        Offset(centerX, iconTop + iconSize),
        Offset(centerX, size.height),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _TimelinePainter oldDelegate) {
    return oldDelegate.topColor != topColor ||
        oldDelegate.bottomColor != bottomColor ||
        oldDelegate.iconTop != iconTop ||
        oldDelegate.iconSize != iconSize;
  }
}
