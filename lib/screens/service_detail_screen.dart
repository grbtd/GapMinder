import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../api/realtime_trains_service.dart';
import '../models/station.dart';
import '../models/departure.dart';
import '../models/service_detail.dart';
import '../widgets/countdown_timer.dart';

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

  @override
  void initState() {
    super.initState();
    _fetchServiceDetails();
    _startAutoRefresh();
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _scrollController.dispose();
    super.dispose();
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

      setState(() {
        _serviceDetail = serviceDetail;
        _trainPositionIndex = _findTrainPositionIndex(serviceDetail);
        _isLoading = false;
      });

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
      setState(() {
        _error = "Failed to load service details: ${e.toString()}";
        _isLoading = false;
      });
    }
    _countdownKey.currentState?.reset();
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

    final runDate = service.runDate;
    if (runDate == null) return -1;

    for (int i = 0; i < service.locations.length; i++) {
      final location = service.locations[i];
      String time = _formatTime(location.realtimeDeparture);
      if (time != "--:--") {
        try {
          final departureTime = DateFormat("yyyy-MM-dd HH:mm").parse("$runDate $time");

          if (departureTime.isBefore(now)) {
            lastDepartedIndex = i;
          } else {
            break;
          }
        } catch (e) {
          // Ignore parsing errors
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

    return Scaffold(
      appBar: AppBar(
        title: titleWidget,
        actions: [
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
              isSelectedStation,
              isFinalDestination,
              isFirstStation,
              key: isSelectedStation ? _selectedStationKey : null,
            ),
            if (isTrainInTransitHere)
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
          Container(
            width: 80,
            alignment: Alignment.center,
            child: SizedBox(
              height: 40,
              child: VerticalDivider(
                thickness: 2,
                color: theme.colorScheme.primary.withOpacity(0.5),
              ),
            ),
          ),
          const SizedBox(width: 16),
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

  Widget _buildTimelineStop(CallingPoint location, bool isSelectedStation, bool isFinalDestination, bool isFirstStation, {Key? key}) {
    final theme = Theme.of(context);
    final isAtPlatform = location.serviceLocation == "AT_PLAT";
    final isApproaching = location.serviceLocation == "APPR_STAT" || location.serviceLocation == "APPR_PLAT";

    bool hasDeparted = false;
    if (location.realtimeDeparture != null && _serviceDetail?.runDate != null) {
      String time = _formatTime(location.realtimeDeparture);
      if (time != "--:--") {
        try {
          final departureTime = DateFormat("yyyy-MM-dd HH:mm").parse("${_serviceDetail!.runDate!} $time");
          if (departureTime.isBefore(DateTime.now())) {
            hasDeparted = true;
          }
        } catch (e) {
          // Ignore parsing errors
        }
      }
    }

    final hasArrived = location.realtimeArrival?.isNotEmpty ?? false;

    Color circleColor = hasDeparted
        ? Colors.grey
        : theme.colorScheme.primary;

    IconData circleIcon;
    if (isSelectedStation) {
      circleIcon = Icons.location_pin;
    } else if (isAtPlatform) {
      circleIcon = Icons.train;
    } else if (hasDeparted) {
      circleIcon = Icons.check_circle;
    } else if (isFinalDestination) {
      circleIcon = Icons.flag;
    } else {
      circleIcon = Icons.circle_outlined;
    }

    return IntrinsicHeight(
      key: key,
      child: Row(
        children: [
          // Timeline and Time
          SizedBox(
            width: 80,
            child: Column(
              children: [
                Container(
                  height: 20,
                  alignment: Alignment.center,
                  child: VerticalDivider(
                    thickness: 2,
                    color: isFirstStation
                        ? Colors.transparent
                        : (hasDeparted || hasArrived)
                        ? Colors.grey
                        : theme.colorScheme.primary.withOpacity(0.5),
                  ),
                ),
                Icon(circleIcon, color: circleColor, size: 24),
                // --- UPDATED LOGIC ---
                // Only draw the bottom divider if it's NOT the final destination
                if (!isFinalDestination)
                  Expanded(
                    child: VerticalDivider(
                      thickness: 2,
                      color: hasDeparted ? Colors.grey : theme.colorScheme.primary.withOpacity(0.5),
                    ),
                  )
                else
                // If it is the final destination, add an empty Expanded to
                // ensure the IntrinsicHeight behaves correctly, but draw no line.
                  const Expanded(child: SizedBox.shrink()),
                // --- END UPDATED LOGIC ---
              ],
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
                    ),
                  ),
                  const SizedBox(height: 4),
                  if (location.platform != null && location.platform!.isNotEmpty)
                    Text(
                        "Platform: ${location.platform}",
                        style: theme.textTheme.bodySmall
                    ),
                  const SizedBox(height: 4),
                  _buildStopTimes(location),
                  if (isAtPlatform)
                    _buildStatusTag("AT PLATFORM", Colors.blue),
                  if (isApproaching)
                    _buildStatusTag("APPROACHING", Colors.orange),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStopTimes(CallingPoint location) {
    final theme = Theme.of(context);
    final scheduledArrival = _formatTime(location.gbttBookedArrival);
    final realtimeArrival = _formatTime(location.realtimeArrival);
    final scheduledDeparture = _formatTime(location.gbttBookedDeparture);
    final realtimeDeparture = _formatTime(location.realtimeDeparture);

    String arrivalText = scheduledArrival;
    String departureText = scheduledDeparture;
    Color arrivalColor = theme.textTheme.bodyMedium?.color ?? Colors.white;
    Color departureColor = theme.textTheme.bodyMedium?.color ?? Colors.white;

    if (realtimeArrival != "--:--") {
      arrivalColor = (realtimeArrival == scheduledArrival) ? Colors.green : Colors.red;
    }
    if (realtimeDeparture != "--:--") {
      departureColor = (realtimeDeparture == scheduledDeparture) ? Colors.green : Colors.red;
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

