import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../api/realtime_trains_service.dart';
import '../helpers/preferences_service.dart';
import '../helpers/text_formatter.dart';
import '../models/station.dart';
import '../models/departure.dart';
import '../models/service_detail.dart';
import '../widgets/countdown_timer.dart';
import '../widgets/app_lifecycle_observer.dart';
import '../widgets/blinking_widget.dart';
import '../widgets/rate_limit_card.dart';
import '../widgets/settings_dialog.dart';

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
  final PreferencesService _prefs = PreferencesService();
  final GlobalKey<CountdownTimerState> _countdownKey = GlobalKey<CountdownTimerState>();

  final ScrollController _scrollController = ScrollController();
  final GlobalKey _selectedStationKey = GlobalKey();
  final GlobalKey _trainPositionKey = GlobalKey();
  final GlobalKey _inTransitKey = GlobalKey();

  ServiceDetail? _serviceDetail;
  String? _error;
  bool _isLoading = true;
  Timer? _refreshTimer;
  int _trainPositionIndex = -1;
  List<DateTime?> _locationTimestamps = [];

  @override
  void initState() {
    super.initState();
    _prefs.addListener(_onPrefsChanged);
    _fetchServiceDetails();
    if (widget.departure.status != 'CANCELLED') {
      _startAutoRefresh();
    }
  }

  @override
  void dispose() {
    _prefs.removeListener(_onPrefsChanged);
    _refreshTimer?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  void _onPrefsChanged() {
    if (!mounted) return;
    setState(() {});
  }

  void _handleAppResumed() {
    if (!mounted || !(ModalRoute.of(context)?.isCurrent ?? true)) return;
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
      if (ModalRoute.of(context)?.isCurrent ?? true) {
        _fetchServiceDetails(isRefresh: true);
      }
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
        forceRefresh: isRefresh,
      );
      if (!mounted) return;

      _processServiceData(serviceDetail);

      if (!isRefresh) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          final hasInTransitCtx = _inTransitKey.currentContext != null;
          final hasTrainPosCtx = _trainPositionKey.currentContext != null;
          final hasSelectedStationCtx = _selectedStationKey.currentContext != null;

          final targetContext = _inTransitKey.currentContext ??
              _trainPositionKey.currentContext ??
              _selectedStationKey.currentContext;

          debugPrint('[ServiceDetailScreen] postFrameCallback scroll target evaluation:');
          debugPrint('  - _inTransitKey present: $hasInTransitCtx');
          debugPrint('  - _trainPositionKey present: $hasTrainPosCtx');
          debugPrint('  - _selectedStationKey present: $hasSelectedStationCtx');
          debugPrint('  - Selected targetContext: ${targetContext != null ? "FOUND" : "NULL"}');

          if (targetContext != null) {
            Scrollable.ensureVisible(
              targetContext,
              duration: const Duration(milliseconds: 500),
              curve: Curves.easeInOut,
              alignment: 0.15,
            );
          }
        });
      }

    } on RateLimitException catch (_) {
      if (!mounted) return;
      _countdownKey.currentState?.stop();
      setState(() {
        _isLoading = false;
      });
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
          String? orderingTimeStr = loc.realtimeDeparture ?? loc.gbttBookedDeparture ?? loc.realtimeArrival ?? loc.gbttBookedArrival;
          
          DateTime? stopTime;
          if (orderingTimeStr != null && orderingTimeStr.length == 4) {
             try {
               int h = int.parse(orderingTimeStr.substring(0, 2));
               int m = int.parse(orderingTimeStr.substring(2, 4));
               
               if (lastHour != -1) {
                  if (h < lastHour && (lastHour - h) > 12) {
                     currentDate = currentDate.add(const Duration(days: 1));
                  }
               }
               lastHour = h;
               stopTime = DateTime(currentDate.year, currentDate.month, currentDate.day, h, m);
             } catch (_) {
             }
          }
          timestamps.add(stopTime);
        }
      } catch (_) {
        // Ignore date parse errors
      }
    }
    
    while (timestamps.length < service.locations.length) {
      timestamps.add(null);
    }

    debugPrint('[ServiceDetailScreen] Processed service data:');
    debugPrint('  - trainIdentity (Headcode): "${service.trainIdentity}"');
    debugPrint('  - serviceUid: "${service.serviceUid}"');
    debugPrint('  - total locations: ${service.locations.length}');

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

  int _findTrainPositionIndexForLocations(List<CallingPoint> locations) {
    if (locations.isEmpty) return -1;

    int explicitStatusIndex = locations.indexWhere((loc) {
      final status = (loc.serviceLocation ?? '').toUpperCase();
      return status == 'AT_PLAT' ||
          status == 'AT_PLATFORM' ||
          status == 'APPR_PLAT' ||
          status == 'APPR_STAT' ||
          status == 'APPROACHING';
    });
    if (explicitStatusIndex != -1) {
      debugPrint('[ServiceDetailScreen] _findTrainPositionIndex -> Explicit platform status at index $explicitStatusIndex (${locations[explicitStatusIndex].locationName}, status: ${locations[explicitStatusIndex].serviceLocation})');
      return explicitStatusIndex;
    }

    int lastActualIndex = -1;
    for (int i = 0; i < locations.length; i++) {
      if (locations[i].hasActualReport) {
        lastActualIndex = i;
      }
    }
    if (lastActualIndex != -1) {
      debugPrint('[ServiceDetailScreen] _findTrainPositionIndex -> Last actual report at index $lastActualIndex (${locations[lastActualIndex].locationName})');
      return lastActualIndex;
    }

    int lastDepartedIndex = -1;
    final now = DateTime.now();
    for (int i = 0; i < _locationTimestamps.length && i < locations.length; i++) {
      final ts = _locationTimestamps[i];
      if (ts != null && ts.isBefore(now)) {
        lastDepartedIndex = i;
      } else if (ts != null) {
        break;
      }
    }
    final resultIdx = lastDepartedIndex != -1 ? lastDepartedIndex : 0;
    debugPrint('[ServiceDetailScreen] _findTrainPositionIndex -> Timestamp check index $resultIdx (${locations[resultIdx].locationName})');
    return resultIdx;
  }

  int _findTrainPositionIndex(ServiceDetail? service) {
    if (service == null) return -1;
    return _findTrainPositionIndexForLocations(service.locations);
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
            IconButton(
              icon: const Icon(Icons.settings),
              tooltip: 'Settings',
              onPressed: () => showSettingsDialog(context),
            ),
            if (widget.departure.status != 'CANCELLED')
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 16.0),
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

    if (_apiService.isRateLimited) {
      return Column(
        children: [
          RateLimitCard(
            resetTime: _apiService.rateLimitResetTime!,
            onRetry: () => _fetchServiceDetails(isRefresh: true),
          ),
          if (_serviceDetail != null)
            Expanded(child: _buildServiceDetailView(_serviceDetail!)),
        ],
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

    final displayLocations = _prefs.isNerdMode
        ? service.locations
        : service.locations.where((loc) => loc.serviceLocation != 'PASS').toList();
    final activeTrainIdx = _findTrainPositionIndexForLocations(displayLocations);

    String serviceText = "";
    if (service.stockBranding != null && service.stockBranding!.isNotEmpty) {
      serviceText = "${formatOperatorStockService(service.atocName, service.stockBranding)} to ${service.destination} from ${service.origin}";
    } else {
      String article = "A";
      if (service.atocName.isNotEmpty) {
        String firstLetter = service.atocName.substring(0, 1).toLowerCase();
        if (['a', 'e', 'i', 'o', 'u', 'l'].contains(firstLetter)) {
          article = "An";
        }
      }
      serviceText = "$article ${service.atocName} service to ${service.destination} from ${service.origin}";
    }

    if (service.coachCount != null && service.coachCount! > 0) {
      serviceText += ", formed of ${service.coachCount} coaches";
    }

    return ListView.builder(
      controller: _scrollController,
      cacheExtent: 20000.0,
      itemCount: displayLocations.length + 1, // +1 for the header
      itemBuilder: (context, index) {
        if (index == 0) {
          return Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              children: [
                if (_prefs.isNerdMode && service.trainIdentity.isNotEmpty) ...[
                  Text(
                    "Head Code: ${service.trainIdentity}",
                    style: theme.textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 8),
                ],
                Text(
                  serviceText,
                  style: theme.textTheme.bodyLarge,
                  textAlign: TextAlign.center,
                ),
                if (_prefs.isNerdMode) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.amber.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.amber, width: 1),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.psychology, size: 16, color: Colors.amber),
                        SizedBox(width: 6),
                        Text(
                          "Nerd Mode Active 🤓",
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.amber),
                        ),
                      ],
                    ),
                  ),
                ],
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
        final location = displayLocations[locationIndex];
        final isSelectedStation = location.crs == widget.station.crsCode;
        final isFinalDestination = locationIndex == displayLocations.length - 1;
        final isFirstStation = locationIndex == 0;

        final currentLocation = displayLocations[activeTrainIdx];
        final currentStatus = (currentLocation.serviceLocation ?? '').toUpperCase();
        final bool isAtOrApproachingPlatform = currentStatus == 'AT_PLAT' ||
            currentStatus == 'AT_PLATFORM' ||
            currentStatus == 'APPR_PLAT' ||
            currentStatus == 'APPR_STAT' ||
            currentStatus == 'APPROACHING';
        final bool hasDepartedOrigin = activeTrainIdx > 0 || currentLocation.hasActualReport;

        final bool isTrainInTransitHere = activeTrainIdx == locationIndex &&
            locationIndex < displayLocations.length - 1 &&
            !isAtOrApproachingPlatform &&
            hasDepartedOrigin;

        Key? itemKey;
        if (locationIndex == activeTrainIdx) {
          itemKey = _trainPositionKey;
        } else if (isSelectedStation) {
          itemKey = _selectedStationKey;
        }

        return Column(
          children: [
            _buildTimelineStop(
              location,
              locationIndex,
              isSelectedStation,
              isFinalDestination,
              isFirstStation,
              isCancelled,
              key: itemKey,
            ),
            if (isTrainInTransitHere && !isCancelled)
              _buildInTransitView(
                displayLocations[activeTrainIdx],
                key: _inTransitKey,
              ),
          ],
        );
      },
    );
  }

  Widget _buildInTransitView(CallingPoint lastDepartedStation, {Key? key}) {
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
      key: key,
      child: Row(
        children: [
          SizedBox(
            width: 80,
            child: Center(
              child: Container(
                width: 2,
                color: theme.colorScheme.primary.withValues(alpha: 0.5),
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
    final isAtPlatform = location.serviceLocation == "AT_PLAT" || location.serviceLocation == "AT_PLATFORM";
    final isApproaching = location.serviceLocation == "APPR_STAT" || location.serviceLocation == "APPR_PLAT" || location.serviceLocation == "APPROACHING";

    bool hasDeparted = false;
    if (!isCancelled) {
      if (location.hasActualReport || index <= _trainPositionIndex) {
        hasDeparted = true;
      }
    }

    final hasArrived = !isCancelled && (location.realtimeArrival?.isNotEmpty ?? false);

    int? prevCoachCount;
    if (_serviceDetail != null) {
      final displayLocations = _prefs.isNerdMode
          ? _serviceDetail!.locations
          : _serviceDetail!.locations.where((loc) => loc.serviceLocation != 'PASS').toList();
      for (int i = index - 1; i >= 0; i--) {
        if (displayLocations[i].coachCount != null) {
          prevCoachCount = displayLocations[i].coachCount;
          break;
        }
      }
    }

    Widget? formationWidget;
    if (location.coachCount != null) {
      if (prevCoachCount != null && location.coachCount! > prevCoachCount) {
        final diff = location.coachCount! - prevCoachCount;
        formationWidget = _buildFormationTag(
          "${location.coachCount} Coaches (+$diff attached)",
          Icons.trending_up,
          Colors.green,
        );
      } else if (prevCoachCount != null && location.coachCount! < prevCoachCount) {
        final diff = prevCoachCount - location.coachCount!;
        formationWidget = _buildFormationTag(
          "${location.coachCount} Coaches (-$diff detached)",
          Icons.trending_down,
          Colors.orange,
        );
      } else if (prevCoachCount == null || isFirstStation) {
        formationWidget = _buildFormationTag(
          "${location.coachCount} Coaches",
          Icons.train,
          theme.colorScheme.secondary,
        );
      }
    }

    Color circleColor = (hasDeparted || isCancelled)
        ? Colors.grey
        : theme.colorScheme.primary;

    final bool isPassPoint = location.serviceLocation == 'PASS';

    IconData circleIcon;
    if (isCancelled) {
      circleIcon = Icons.cancel;
    } else if (isPassPoint) {
      circleIcon = hasDeparted ? Icons.fast_forward : Icons.fast_forward_outlined;
    } else if (isSelectedStation) {
      circleIcon = Icons.location_pin;
    } else if (isAtPlatform) {
      circleIcon = Icons.train;
    } else if (hasDeparted) {
      circleIcon = Icons.check_circle;
    } else if (isFinalDestination) {
      circleIcon = hasDeparted ? Icons.flag : Icons.outlined_flag;
    } else {
      circleIcon = Icons.circle_outlined;
    }
    
    Color topSegmentColor = (isFirstStation)
        ? Colors.transparent
        : ((hasDeparted || hasArrived || isCancelled)
            ? Colors.grey
            : theme.colorScheme.primary.withValues(alpha: 0.5));

    Color bottomSegmentColor = (isFinalDestination)
        ? Colors.transparent
        : ((hasDeparted || isCancelled)
            ? Colors.grey
            : theme.colorScheme.primary.withValues(alpha: 0.5));

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
                    location.platformChanged
                        ? BlinkingWidget(
                            child: Text(
                              "Platform: ${location.platform}",
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: isCancelled ? Colors.grey : Colors.orange,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          )
                        : Text(
                            "Platform: ${location.platform}",
                            style: theme.textTheme.bodySmall?.copyWith(color: isCancelled ? Colors.grey : null),
                          ),
                  const SizedBox(height: 4),
                  _buildStopTimes(location, isCancelled),
                  if (formationWidget != null && !isCancelled)
                    formationWidget,
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
    final isPass = location.serviceLocation == 'PASS';

    final scheduledArrival = _formatTime(location.gbttBookedArrival);
    final realtimeArrival = _formatTime(location.realtimeArrival);
    final scheduledDeparture = _formatTime(location.gbttBookedDeparture);
    final realtimeDeparture = _formatTime(location.realtimeDeparture);

    Color getColor(String sched, String real) {
      if (real == sched) return Colors.green;
      try {
        final s = DateFormat.Hm().parse(sched);
        final r = DateFormat.Hm().parse(real);
        int diff = r.difference(s).inMinutes;
        if (diff < -720) {
          diff += 1440;
        } else if (diff > 720) {
          diff -= 1440;
        }
        return diff > 0 ? Colors.red : Colors.green;
      } catch (e) {
        return Colors.red;
      }
    }

    if (isCancelled) {
      final timeToShow = isPass
          ? (scheduledDeparture != "--:--" ? scheduledDeparture : scheduledArrival)
          : scheduledDeparture;
      return Text(
        isPass ? "$timeToShow (Pass)" : "$timeToShow (Cancelled)",
        style: theme.textTheme.bodyMedium?.copyWith(
          color: Colors.grey,
          decoration: TextDecoration.lineThrough,
        ),
      );
    }

    // 1. Handle PASS point display
    if (isPass) {
      final sched = scheduledDeparture != "--:--" ? scheduledDeparture : scheduledArrival;
      final real = realtimeDeparture != "--:--" ? realtimeDeparture : realtimeArrival;

      Color passColor = theme.textTheme.bodyMedium?.color ?? Colors.white;
      if (real != "--:--" && sched != "--:--") {
        passColor = getColor(sched, real);
      }

      return Row(
        children: [
          if (real != "--:--")
            Text(
              real,
              style: theme.textTheme.bodyMedium?.copyWith(color: passColor, fontWeight: FontWeight.bold),
            ),
          if (real != "--:--" && sched != "--:--" && sched != real)
            Padding(
              padding: const EdgeInsets.only(left: 8.0),
              child: Text(
                sched,
                style: theme.textTheme.bodySmall?.copyWith(decoration: TextDecoration.lineThrough),
              ),
            ),
          if (real == "--:--" && sched != "--:--")
            Text(sched, style: theme.textTheme.bodyMedium),
          Text(" (Pass)", style: theme.textTheme.bodySmall?.copyWith(fontStyle: FontStyle.italic)),
        ],
      );
    }

    // 2. Handle CALL / STOP points
    final hasArr = scheduledArrival != "--:--" || realtimeArrival != "--:--";
    final hasDep = scheduledDeparture != "--:--" || realtimeDeparture != "--:--";
    final isSameTime = (scheduledArrival == scheduledDeparture) && (realtimeArrival == realtimeDeparture);

    if (hasArr && hasDep && !isSameTime) {
      Color arrivalColor = theme.textTheme.bodyMedium?.color ?? Colors.white;
      Color departureColor = theme.textTheme.bodyMedium?.color ?? Colors.white;

      if (realtimeArrival != "--:--" && scheduledArrival != "--:--") {
        arrivalColor = getColor(scheduledArrival, realtimeArrival);
      }
      if (realtimeDeparture != "--:--" && scheduledDeparture != "--:--") {
        departureColor = getColor(scheduledDeparture, realtimeDeparture);
      }

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (realtimeArrival != "--:--")
                Text(
                  realtimeArrival,
                  style: theme.textTheme.bodyMedium?.copyWith(color: arrivalColor, fontWeight: FontWeight.bold),
                ),
              if (realtimeArrival != "--:--" && scheduledArrival != "--:--" && scheduledArrival != realtimeArrival)
                Padding(
                  padding: const EdgeInsets.only(left: 8.0),
                  child: Text(
                    scheduledArrival,
                    style: theme.textTheme.bodySmall?.copyWith(decoration: TextDecoration.lineThrough),
                  ),
                ),
              if (realtimeArrival == "--:--")
                Text(scheduledArrival, style: theme.textTheme.bodyMedium),
              Text(" (Arr)", style: theme.textTheme.bodySmall),
            ],
          ),
          const SizedBox(height: 2),
          Row(
            children: [
              if (realtimeDeparture != "--:--")
                Text(
                  realtimeDeparture,
                  style: theme.textTheme.bodyMedium?.copyWith(color: departureColor, fontWeight: FontWeight.bold),
                ),
              if (realtimeDeparture != "--:--" && scheduledDeparture != "--:--" && scheduledDeparture != realtimeDeparture)
                Padding(
                  padding: const EdgeInsets.only(left: 8.0),
                  child: Text(
                    scheduledDeparture,
                    style: theme.textTheme.bodySmall?.copyWith(decoration: TextDecoration.lineThrough),
                  ),
                ),
              if (realtimeDeparture == "--:--")
                Text(scheduledDeparture, style: theme.textTheme.bodyMedium),
              Text(" (Dep)", style: theme.textTheme.bodySmall),
            ],
          ),
        ],
      );
    } else {
      final sched = hasDep ? scheduledDeparture : scheduledArrival;
      final real = hasDep ? realtimeDeparture : realtimeArrival;
      final label = (hasArr && !hasDep) ? " (Arr)" : "";

      Color timeColor = theme.textTheme.bodyMedium?.color ?? Colors.white;
      if (real != "--:--" && sched != "--:--") {
        timeColor = getColor(sched, real);
      }

      return Row(
        children: [
          if (real != "--:--")
            Text(
              real,
              style: theme.textTheme.bodyMedium?.copyWith(color: timeColor, fontWeight: FontWeight.bold),
            ),
          if (real != "--:--" && sched != "--:--" && sched != real)
            Padding(
              padding: const EdgeInsets.only(left: 8.0),
              child: Text(
                sched,
                style: theme.textTheme.bodySmall?.copyWith(decoration: TextDecoration.lineThrough),
              ),
            ),
          if (real == "--:--" && sched != "--:--")
            Text(sched, style: theme.textTheme.bodyMedium),
          if (label.isNotEmpty) Text(label, style: theme.textTheme.bodySmall),
        ],
      );
    }
  }

  Widget _buildStatusTag(String status, Color color) {
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.2),
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

  Widget _buildFormationTag(String text, IconData icon, Color color) {
    return Container(
      margin: const EdgeInsets.only(top: 6),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.5), width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Text(
            text,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
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
