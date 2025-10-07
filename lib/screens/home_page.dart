import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';

import '../models/station.dart';
import '../models/departure.dart';
import '../models/service_detail.dart';
import '../models/secrets.dart';
import '../widgets/blinking_widget.dart';
import '../widgets/countdown_timer.dart';

// --- Helper function to load credentials from the asset file ---
Future<Secrets> loadSecrets() async {
  final String response = await rootBundle.loadString('assets/secrets.json');
  final data = json.decode(response);
  return Secrets.fromJson(data);
}

// --- Home Page Widget ---
class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  // --- State Variables ---
  String _statusMessage = "Finding nearby stations...";
  List<Station> _allStations = [];
  List<Station> _nearbyStations = [];
  List<Departure> _departures = [];
  bool _isLoading = true;
  Station? _selectedStation;
  ServiceDetail? _selectedService;
  Departure? _tappedDeparture;
  Timer? _refreshTimer;

  bool _isSearching = false;
  final TextEditingController _searchController = TextEditingController();
  List<Station> _searchResults = [];
  final GlobalKey<CountdownTimerState> _countdownKey = GlobalKey();
  bool _groupByPlatform = false;


  // --- initState & dispose ---
  @override
  void initState() {
    super.initState();
    _loadAllStationsAndFindNearby();
  }

  @override
  void dispose() {
    _stopAutoRefresh();
    _searchController.dispose();
    super.dispose();
  }

  // --- UI Build Method ---
  @override
  Widget build(BuildContext context) {
    final bool canPopApp = !(_isSearching || _selectedService != null || _selectedStation != null);

    return PopScope(
      canPop: canPopApp,
      onPopInvoked: (didPop) {
        if (didPop || !mounted) return;
        _handleBackButton();
      },
      child: Scaffold(
        appBar: _buildAppBar(),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                if (_isLoading && _nearbyStations.isEmpty && !_isSearching)
                  Text(
                    _statusMessage,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                const SizedBox(height: 20),
                Expanded(
                  child: _isLoading
                      ? const Center(child: CircularProgressIndicator())
                      : _buildContent(),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  AppBar _buildAppBar() {
    String appBarTitle;
    if (_isSearching) {
      appBarTitle = "Search Stations";
    } else if (_selectedService != null) {
      appBarTitle = "Service Details";
    } else if (_selectedStation != null) {
      appBarTitle = "${_selectedStation!.name} Departures";
    } else {
      appBarTitle = "Nearby Stations";
    }

    return AppBar(
      leading: _isSearching || _selectedStation != null
          ? IconButton(
        icon: const Icon(Icons.arrow_back),
        onPressed: _handleBackButton,
      )
          : null,
      title: _isSearching
          ? TextField(
        controller: _searchController,
        autofocus: true,
        decoration: const InputDecoration(
          hintText: 'Search station name or CRS code...',
          border: InputBorder.none,
        ),
        onChanged: _filterStations,
      )
          : Text(appBarTitle),
      actions: _isSearching
          ? [
        IconButton(
          icon: const Icon(Icons.clear),
          onPressed: () {
            _searchController.clear();
            _filterStations('');
          },
        )
      ]
          : [
        if (!_isLoading)
          IconButton(
            icon: const Icon(Icons.search),
            onPressed: () {
              _stopAutoRefresh();
              setState(() {
                _isSearching = true;
                _selectedStation = null;
                _selectedService = null;
                _departures = [];
              });
            },
          ),
        if (_selectedStation == null && !_isLoading)
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _findNearbyStations,
            tooltip: 'Refresh Stations',
          ),
        if (_selectedStation != null && _selectedService == null && !_isLoading)
          IconButton(
            icon: Icon(_groupByPlatform ? Icons.access_time : Icons.view_module),
            tooltip: _groupByPlatform ? "Sort by Time" : "Group by Platform",
            onPressed: () {
              setState(() {
                _groupByPlatform = !_groupByPlatform;
              });
            },
          ),
        if (_selectedStation != null && !_isLoading)
          Padding(
            padding: const EdgeInsets.only(right: 16.0),
            child: CountdownTimer(
              key: _countdownKey,
              duration: const Duration(seconds: 60),
              onRefresh: () {
                if (_selectedService != null && _tappedDeparture != null) {
                  _fetchServiceDetails(_tappedDeparture!, isAutoRefresh: false);
                } else if (_selectedStation != null) {
                  _fetchDepartures(_selectedStation!, isAutoRefresh: false);
                }
              },
            ),
          ),
      ],
    );
  }

  // --- Builds the main content based on the current state ---
  Widget _buildContent() {
    if (_isSearching) {
      return _buildSearchResultsList();
    }
    if (_selectedService != null) {
      return _buildServiceDetailView();
    } else if (_selectedStation != null) {
      return _buildDeparturesList();
    } else if (_nearbyStations.isNotEmpty) {
      return _buildStationsList("Nearby Stations");
    } else {
      return const SizedBox.shrink();
    }
  }

  // --- Builds the list of nearby or search result stations ---
  Widget _buildStationsList(String title, {List<Station>? stations}) {
    final stationList = stations ?? _nearbyStations;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 8),
        Expanded(
          child: ListView.builder(
            itemCount: stationList.length,
            itemBuilder: (context, index) {
              final station = stationList[index];
              return Card(
                margin: const EdgeInsets.symmetric(vertical: 4.0),
                child: ListTile(
                  title: Text(station.name),
                  subtitle: Text("CRS: ${station.crsCode}"),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    _stopAutoRefresh();
                    setState(() {
                      _isSearching = false;
                      _searchController.clear();
                    });
                    _fetchDepartures(station);
                  },
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildSearchResultsList() {
    return _buildStationsList("Search Results", stations: _searchResults);
  }

  // Extracted the departure card into its own widget builder for clarity
  Widget _buildDepartureCard(Departure departure) {
    final isLate = departure.expectedTime.compareTo(departure.scheduledTime) > 0;
    final showScheduled = departure.expectedTime != departure.scheduledTime;

    Widget trailingWidget;
    if (departure.serviceType == 'bus') {
      trailingWidget = const Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.directions_bus),
          Text("Bus", style: TextStyle(fontSize: 12)),
        ],
      );
    } else {
      trailingWidget = Text(
        "Plat: ${departure.platform}",
        style: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.bold,
          color: departure.platformChanged ? Colors.orange : null,
        ),
      );
      if (departure.platformChanged) {
        trailingWidget = BlinkingWidget(child: trailingWidget);
      }
    }

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 5.0, horizontal: 2.0),
      child: InkWell(
        onTap: () => _fetchServiceDetails(departure),
        child: Padding(
          padding: const EdgeInsets.all(8.0),
          child: Row(
            children: [
              Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(departure.expectedTime, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: isLate ? Colors.redAccent : Colors.lightGreenAccent)),
                  if (showScheduled) Text(departure.scheduledTime, style: const TextStyle(decoration: TextDecoration.lineThrough, fontSize: 12)),
                ],
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text("To: ${departure.destination}", style: Theme.of(context).textTheme.titleMedium),
                    Text("${departure.operatorName} service"),
                    _buildStatusTag(departure.serviceLocation),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              trailingWidget,
            ],
          ),
        ),
      ),
    );
  }

  // This widget now handles both grouped and chronological views, with responsive layouts.
  Widget _buildDeparturesList() {
    if (_isLoading && _departures.isEmpty) return const Center(child: CircularProgressIndicator());
    if (_departures.isEmpty) return const Center(child: Text("No departures found."));

    if (_groupByPlatform) {
      // --- Grouped by Platform View ---
      Map<String, List<Departure>> groupedDepartures = {};
      for (var d in _departures) {
        String key = d.serviceType == 'bus' ? 'Bus Services' : 'Platform ${d.platform}';
        if (groupedDepartures[key] == null) {
          groupedDepartures[key] = [];
        }
        groupedDepartures[key]!.add(d);
      }

      var sortedKeys = groupedDepartures.keys.toList()
        ..sort((a, b) {
          if (a.startsWith('Bus')) return 1;
          if (b.startsWith('Bus')) return -1;
          var numA = int.tryParse(a.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
          var numB = int.tryParse(b.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
          return numA.compareTo(numB);
        });

      return LayoutBuilder(
          builder: (context, constraints) {
            if (constraints.maxWidth > 800) {
              return SingleChildScrollView(
                child: Wrap(
                  spacing: 16.0,
                  runSpacing: 16.0,
                  children: sortedKeys.map((key) {
                    List<Departure> group = groupedDepartures[key]!;
                    return Container(
                      width: 350,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8.0, left: 4.0),
                            child: Text(key, style: Theme.of(context).textTheme.headlineSmall),
                          ),
                          ...group.take(3).map((d) => _buildDepartureCard(d)).toList(),
                        ],
                      ),
                    );
                  }).toList(),
                ),
              );
            } else {
              return ListView.builder(
                itemCount: sortedKeys.length,
                itemBuilder: (context, index) {
                  String key = sortedKeys[index];
                  List<Departure> group = groupedDepartures[key]!;
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(top: 16.0, bottom: 8.0, left: 4.0),
                        child: Text(key, style: Theme.of(context).textTheme.headlineSmall),
                      ),
                      ...group.take(3).map((d) => _buildDepartureCard(d)).toList(),
                    ],
                  );
                },
              );
            }
          }
      );
    } else {
      // --- Chronological View (default) ---
      return LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth > 600) {
            return GridView.builder(
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 450,
                childAspectRatio: 4,
                crossAxisSpacing: 10,
                mainAxisSpacing: 10,
              ),
              itemCount: _departures.length,
              itemBuilder: (context, index) {
                return _buildDepartureCard(_departures[index]);
              },
            );
          } else {
            return ListView.builder(
              itemCount: _departures.length,
              itemBuilder: (context, index) {
                return _buildDepartureCard(_departures[index]);
              },
            );
          }
        },
      );
    }
  }

  // Helper function to get the status text and color from serviceLocation
  Widget _buildStatusTag(String? serviceLocation) {
    String text;
    Color color;

    switch (serviceLocation) {
      case 'APPR_STAT':
        text = 'Approaching Station';
        color = Colors.amber;
        break;
      case 'APPR_PLAT':
        text = 'Approaching Platform';
        color = Colors.orange;
        break;
      case 'AT_PLAT':
        text = 'At Platform';
        color = Colors.cyan;
        break;
      case 'DEP_READY':
        text = 'Ready to Depart';
        color = Colors.lightGreen;
        break;
      default:
        return const SizedBox.shrink();
    }

    return Text(text, style: TextStyle(color: color, fontWeight: FontWeight.bold));
  }

  // Most accurate logic for finding the train's position.
  int _findTrainPositionIndex(ServiceDetail service) {
    final now = DateTime.now();
    int lastDepartedIndex = -1;

    for (int i = 0; i < service.locations.length; i++) {
      final point = service.locations[i];
      if (point.realtimeDeparture != null) {
        try {
          final timeString = point.realtimeDeparture!;
          final fullDateTimeString = "${service.runDate} ${timeString.substring(0, 2)}:${timeString.substring(2, 4)}";
          final departureTime = DateFormat("yyyy-MM-dd HH:mm").parse(fullDateTimeString);

          if (departureTime.isBefore(now)) {
            lastDepartedIndex = i;
          }
        } catch (e) {
          continue;
        }
      }
    }
    return lastDepartedIndex;
  }


  // Builds the detailed view for a single service
  Widget _buildServiceDetailView() {
    if (_isLoading && _selectedService == null) return const Center(child: CircularProgressIndicator());
    if (_selectedService == null) return const Center(child: Text("Could not load service details."));

    final int lastDepartedIndex = _findTrainPositionIndex(_selectedService!);

    String article = "A";
    if (_selectedService!.atocName.isNotEmpty) {
      String firstLetter = _selectedService!.atocName.substring(0, 1).toLowerCase();
      if (['a', 'e', 'i', 'o', 'u'].contains(firstLetter)) {
        article = "An";
      }
    }

    List<Widget> timelineItems = [];
    for (int i = 0; i < _selectedService!.locations.length; i++) {
      final point = _selectedService!.locations[i];
      final isSelectedStation = point.crsCode == _selectedStation?.crsCode;
      final isCancelled = point.isCancelled;

      final displayScheduled = point.scheduledDeparture ?? point.scheduledArrival ?? 'N/A';
      final displayRealtime = point.realtimeDeparture ?? point.realtimeArrival ?? displayScheduled;
      final isLate = displayRealtime.compareTo(displayScheduled) > 0;

      final stationWidget = IntrinsicHeight(
        child: Row(
          children: [
            SizedBox(
              width: 40,
              child: Column(
                children: [
                  Expanded(
                    child: Container(
                      width: 2,
                      color: i == 0 ? Colors.transparent : Colors.grey,
                    ),
                  ),
                  Icon(
                    isSelectedStation ? Icons.location_pin : Icons.circle,
                    size: isSelectedStation ? 24 : 12,
                    color: isSelectedStation ? Colors.blueAccent : Colors.grey,
                  ),
                  Expanded(
                    child: Container(
                      width: 2,
                      color: i == _selectedService!.locations.length - 1 ? Colors.transparent : Colors.grey,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListTile(
                title: Text(point.stationName, style: TextStyle(fontWeight: isSelectedStation ? FontWeight.bold : FontWeight.normal)),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text("Platform: ${point.platform} | Scheduled: $displayScheduled"),
                    if (isCancelled)
                      const Text("Cancelled", style: TextStyle(color: Colors.red))
                    else
                      _buildStatusTag(point.serviceLocation),
                  ],
                ),
                trailing: Text(displayRealtime, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: isLate ? Colors.redAccent : Colors.lightGreenAccent)),
              ),
            ),
          ],
        ),
      );

      timelineItems.add(stationWidget);

      final bool isTrainInTransitHere = i == lastDepartedIndex && i < _selectedService!.locations.length - 1;
      if (isTrainInTransitHere) {
        String delayText = "On time";
        // **REVISED**: Use the direct lateness value from the API for accuracy.
        final lateness = point.departureLateness;
        if (lateness > 0) {
          delayText = "$lateness min late";
        } else if (lateness < 0) {
          delayText = "${lateness.abs()} min early";
        }

        timelineItems.add(
            IntrinsicHeight(
              child: Row(
                children: [
                  SizedBox(
                    width: 40,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Expanded(child: Container(width: 2, color: Colors.grey)),
                        Icon(
                            _selectedService!.serviceType == 'bus' ? Icons.directions_bus : Icons.train,
                            color: Theme.of(context).colorScheme.primary,
                            size: 28
                        ),
                        Expanded(child: Container(width: 2, color: Colors.grey)),
                      ],
                    ),
                  ),
                  Expanded(
                    child: ListTile(
                      title: Text("In Transit", style: TextStyle(fontStyle: FontStyle.italic, color: Colors.grey[400])),
                      trailing: Text(delayText, style: TextStyle(fontStyle: FontStyle.italic, color: Colors.grey[400])),
                    ),
                  ),
                ],
              ),
            )
        );
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Center(
          child: Column(
            children: [
              Text(
                "Head Code: ${_selectedService!.trainIdentity}",
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 4),
              Text(
                "$article ${_selectedService!.atocName} service to ${_selectedService!.destination} from ${_selectedService!.origin}",
                style: Theme.of(context).textTheme.bodyMedium,
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        const Divider(),
        Expanded(
          child: ListView(
            children: timelineItems,
          ),
        ),
      ],
    );
  }

  // --- Auto-Refresh Logic ---
  void _stopAutoRefresh() {
    _refreshTimer?.cancel();
  }

  void _startAutoRefresh() {
    _stopAutoRefresh();
    _countdownKey.currentState?.reset(); // Reset the visual timer
    _refreshTimer = Timer.periodic(const Duration(seconds: 60), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }

      if (_selectedService != null && _tappedDeparture != null) {
        _fetchServiceDetails(_tappedDeparture!, isAutoRefresh: true);
      } else if (_selectedStation != null) {
        _fetchDepartures(_selectedStation!, isAutoRefresh: true);
      }
    });
  }

  // --- Data Fetching & State Logic ---
  Future<void> _loadAllStationsAndFindNearby() async {
    await _loadAllStations();
    await _findNearbyStations();
  }

  Future<void> _loadAllStations() async {
    try {
      final String response = await rootBundle.loadString('assets/stations.json');
      final List<dynamic> data = json.decode(response);

      _allStations = data.map((stationJson) {
        return Station.fromJson(stationJson as Map<String, dynamic>);
      }).toList();
    } catch (e) {
      setState(() { _statusMessage = "Error loading station data."; });
    }
  }

  void _filterStations(String query) {
    if (query.isEmpty) {
      setState(() {
        _searchResults = [];
      });
      return;
    }
    final suggestions = _allStations.where((station) {
      final queryLower = query.toLowerCase();
      final nameLower = station.name.toLowerCase();
      final crsLower = station.crsCode.toLowerCase();
      return nameLower.contains(queryLower) || crsLower.contains(queryLower);
    }).toList();
    setState(() {
      _searchResults = suggestions;
    });
  }

  void _handleBackButton() {
    if (_isSearching) {
      setState(() {
        _isSearching = false;
        _searchController.clear();
        _searchResults = [];
      });
    } else if (_selectedService != null) {
      setState(() {
        _selectedService = null;
        _tappedDeparture = null;
        _startAutoRefresh();
      });
    } else if (_selectedStation != null) {
      _stopAutoRefresh();
      setState(() {
        _selectedStation = null;
        _departures = [];
      });
    }
    // No final else, PopScope handles closing the app
  }

  Future<void> _findNearbyStations() async {
    _stopAutoRefresh();
    setState(() {
      _isLoading = true;
      _statusMessage = "Getting your location...";
      _nearbyStations = [];
      _selectedStation = null;
      _selectedService = null;
    });

    try {
      final position = await _determinePosition();
      setState(() { _statusMessage = "Finding nearby stations..."; });

      for (var station in _allStations) {
        station.distance = Geolocator.distanceBetween(
          position.latitude,
          position.longitude,
          station.latitude,
          station.longitude,
        );
      }

      _allStations.sort((a, b) => a.distance.compareTo(b.distance));

      setState(() {
        _nearbyStations = _allStations.take(20).toList();
        _statusMessage = _nearbyStations.isEmpty
            ? "No stations found nearby."
            : "";
      });

    } catch (e) {
      setState(() { _statusMessage = "Error: ${e.toString()}"; });
    } finally {
      if (mounted) setState(() { _isLoading = false; });
    }
  }

  Future<void> _fetchDepartures(Station station, {bool isAutoRefresh = false}) async {
    if (!isAutoRefresh) {
      setState(() {
        _isLoading = true;
        _selectedStation = station;
        _statusMessage = "Fetching departures for ${station.name}...";
        _departures = [];
      });
    }

    try {
      final secrets = await loadSecrets();
      final username = secrets.username;
      final password = secrets.password;

      final authority = 'api.rtt.io';
      final path = '/api/v1/json/search/${station.crsCode}';
      final url = Uri.https(authority, path);

      final response = await http.get(
        url,
        headers: { 'Authorization': 'Basic ${base64Encode(utf8.encode('$username:$password'))}' },
      );

      if (mounted && response.statusCode == 200) {
        final data = json.decode(response.body);
        final List<dynamic> services = data['services'] ?? [];
        setState(() {
          _departures = services.map((json) => Departure.fromJson(json as Map<String, dynamic>)).toList();
          _statusMessage = _departures.isEmpty ? "No departures found." : "";
        });
      } else if (mounted) {
        setState(() { _statusMessage = 'Error fetching departures: ${response.statusCode}'; });
      }
    } catch (e) {
      if (mounted) setState(() { _statusMessage = "Error: ${e.toString()}"; });
    } finally {
      if (mounted) {
        if (!isAutoRefresh) {
          setState(() { _isLoading = false; });
        }
        _startAutoRefresh();
      }
    }
  }

  Future<void> _fetchServiceDetails(Departure departure, {bool isAutoRefresh = false}) async {
    if (!isAutoRefresh) {
      _stopAutoRefresh();
      setState(() {
        _isLoading = true;
        _statusMessage = "Fetching service details...";
        _tappedDeparture = departure;
      });
    }

    try {
      final secrets = await loadSecrets();
      final username = secrets.username;
      final password = secrets.password;

      final formattedDate = departure.runDate.replaceAll('-', '/');

      final authority = 'api.rtt.io';
      final path = '/api/v1/json/service/${departure.serviceUid}/$formattedDate';
      final url = Uri.https(authority, path);

      final response = await http.get(
        url,
        headers: { 'Authorization': 'Basic ${base64Encode(utf8.encode('$username:$password'))}' },
      );

      if (mounted && response.statusCode == 200) {
        final data = json.decode(response.body);
        setState(() {
          _selectedService = ServiceDetail.fromJson(data);
        });
      } else if (mounted) {
        setState(() {
          _statusMessage = 'Error fetching service details: ${response.statusCode}';
        });
      }

    } catch (e) {
      if (mounted) setState(() { _statusMessage = "Error: ${e.toString()}"; });
    } finally {
      if (mounted) {
        if (!isAutoRefresh) {
          setState(() { _isLoading = false; });
        }
        _startAutoRefresh();
      }
    }
  }

  // --- Logic for getting user's location ---
  Future<Position> _determinePosition() async {
    bool serviceEnabled;
    LocationPermission permission;

    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      return Future.error('Location services are disabled.');
    }

    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        return Future.error('Location permissions are denied');
      }
    }

    if (permission == LocationPermission.deniedForever) {
      return Future.error(
          'Location permissions are permanently denied, we cannot request permissions.');
    }
    return await Geolocator.getCurrentPosition();
  }
}
