import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:geolocator/geolocator.dart';
import '../models/station.dart';
import '../models/departure.dart';
import '../services/live_activity_service.dart';
import '../widgets/settings_dialog.dart';
import 'departure_screen.dart';
import 'service_detail_screen.dart';

class StationListScreen extends StatefulWidget {
  const StationListScreen({super.key});

  @override
  State<StationListScreen> createState() => _StationListScreenState();
}

class _StationListScreenState extends State<StationListScreen> {
  String _statusMessage = "Loading station data...";
  List<Station> _allStations = [];
  List<Station> _nearbyStations = [];
  bool _isLoading = true;

  bool _isSearching = false;
  final TextEditingController _searchController = TextEditingController();
  List<Station> _searchResults = [];

  @override
  void initState() {
    super.initState();
    _loadAllStationsAndFindNearby();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadAllStationsAndFindNearby() async {
    await _loadAllStations();
    await _findNearbyStations();
  }

  Future<void> _loadAllStations() async {
    try {
      final String response =
      await rootBundle.loadString('assets/stations.json');
      final List<dynamic> data = json.decode(response);
      _allStations = data.map((stationJson) {
        return Station.fromJson(stationJson as Map<String, dynamic>);
      }).toList();
      setState(() {
        _statusMessage = "Getting your location...";
      });
    } catch (e) {
      setState(() {
        _statusMessage = "Error loading station data.";
        _isLoading = false;
      });
    }
  }

  Future<void> _findNearbyStations() async {
    setState(() {
      _isLoading = true;
      _statusMessage = "Getting your location...";
      _nearbyStations = [];
    });

    try {
      final position = await _determinePosition();
      setState(() {
        _statusMessage = "Finding nearby stations...";
      });

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
        _statusMessage =
        _nearbyStations.isEmpty ? "No stations found nearby." : "";
      });
    } catch (e) {
      setState(() {
        _statusMessage = "Error: ${e.toString()}";
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

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
        return Future.error('Location permissions are denied.');
      }
    }

    if (permission == LocationPermission.deniedForever) {
      return Future.error(
          'Location permissions are permanently denied; cannot request permissions.');
    }

    // Try last known position first for quick responsiveness
    try {
      final lastKnown = await Geolocator.getLastKnownPosition();
      if (lastKnown != null) {
        return lastKnown;
      }
    } catch (_) {
      // If last known position fails, continue to get current position
    }

    return await Geolocator.getCurrentPosition(
      timeLimit: const Duration(seconds: 10),
    );
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

  void _onStationTapped(Station station) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => DepartureScreen(station: station),
      ),
    );
  }

  AppBar _buildAppBar() {
    return AppBar(
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
          : const Text("GapMinder"),
      actions: _isSearching
          ? [
        IconButton(
          icon: const Icon(Icons.clear),
          onPressed: () {
            _searchController.clear();
            _filterStations('');
            setState(() {
              _isSearching = false;
              _searchResults = [];
            });
          },
        )
      ]
          : [
        ListenableBuilder(
          listenable: LiveActivityService(),
          builder: (context, _) {
            final starred = LiveActivityService().starredServices;
            if (starred.isEmpty) return const SizedBox.shrink();
            return IconButton(
              icon: Badge(
                label: Text('${starred.length}'),
                child: const Icon(Icons.star, color: Colors.amber),
              ),
              tooltip: 'View Starred Live Activities',
              onPressed: () => _showStarredModal(context),
            );
          },
        ),
        IconButton(
          icon: const Icon(Icons.search),
          onPressed: () {
            setState(() {
              _isSearching = true;
            });
          },
        ),
        IconButton(
          icon: const Icon(Icons.refresh),
          onPressed: _findNearbyStations,
          tooltip: 'Refresh Nearby Stations',
        ),
        IconButton(
          icon: const Icon(Icons.settings),
          onPressed: () => showSettingsDialog(context),
          tooltip: 'Settings',
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
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
    );
  }

  Widget _buildContent() {
    if (_isSearching) {
      return _buildStationsList("Search Results", stations: _searchResults);
    } else if (_nearbyStations.isNotEmpty) {
      return _buildStationsList("Nearby Stations");
    } else {
      return const SizedBox.shrink();
    }
  }

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
                  onTap: () => _onStationTapped(station),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  void _showStarredModal(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.5,
          maxChildSize: 0.8,
          minChildSize: 0.3,
          builder: (context, scrollController) {
            return ListenableBuilder(
              listenable: LiveActivityService(),
              builder: (context, _) {
                final service = LiveActivityService();
                final starredList = service.starredServices.values.toList();
                return Container(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: const [
                              Icon(Icons.star, color: Colors.amber),
                              SizedBox(width: 8),
                              Text(
                                "Starred Live Activities",
                                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                              ),
                            ],
                          ),
                          if (starredList.isNotEmpty)
                            TextButton(
                              onPressed: () async {
                                await service.clearAll();
                                if (context.mounted) Navigator.pop(context);
                              },
                              child: const Text("Clear All"),
                            ),
                        ],
                      ),
                      const Divider(),
                      if (starredList.isEmpty)
                        const Padding(
                          padding: EdgeInsets.all(32.0),
                          child: Center(
                            child: Text(
                              "No active starred services.\nStar a service from departures to track it as a Live Activity!",
                              textAlign: TextAlign.center,
                              style: TextStyle(color: Colors.grey),
                            ),
                          ),
                        )
                      else
                        Expanded(
                          child: ListView.builder(
                            controller: scrollController,
                            itemCount: starredList.length,
                            itemBuilder: (context, index) {
                              final item = starredList[index];
                              final uid = item['serviceUid'] ?? '';
                              final runDate = item['runDate'] ?? '';
                              final dest = item['destination'] ?? 'Unknown';
                              final time = item['scheduledTime'] ?? '';
                              final realtime = item['realtimeTime'] ?? '';
                              final plat = item['platform'] ?? '';
                              final stationName = item['stationName'] ?? '';
                              final crs = item['stationCrs'] ?? 'LBG';
                              final status = item['status'] ?? '';

                              return Card(
                                margin: const EdgeInsets.symmetric(vertical: 4.0),
                                child: ListTile(
                                  leading: const Icon(Icons.star, color: Colors.amber),
                                  title: Text(
                                    "$time to $dest",
                                    style: const TextStyle(fontWeight: FontWeight.bold),
                                  ),
                                  subtitle: Text(
                                    "${stationName.isNotEmpty ? '$stationName | ' : ''}Plat ${plat.isNotEmpty ? plat : 'TBC'} ${status.isNotEmpty ? '($status)' : ''}",
                                  ),
                                  trailing: IconButton(
                                    icon: const Icon(Icons.remove_circle_outline, color: Colors.red),
                                    tooltip: 'Remove Live Activity',
                                    onPressed: () async {
                                      await service.unstarService(uid, runDate);
                                    },
                                  ),
                                  onTap: () {
                                    Navigator.pop(context);
                                    final dep = Departure(
                                      serviceUid: uid,
                                      runDate: runDate,
                                      scheduledTime: time,
                                      realtimeTime: realtime,
                                      platform: plat,
                                      operatorName: item['operator'],
                                      destination: dest,
                                      origin: item['origin'],
                                      platformChanged: false,
                                      status: status,
                                      serviceType: 'train',
                                    );
                                    final station = Station(
                                      crsCode: crs,
                                      name: stationName.isNotEmpty ? stationName : 'Station',
                                      latitude: 0,
                                      longitude: 0,
                                    );
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (context) => ServiceDetailScreen(
                                          station: station,
                                          departure: dep,
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              );
                            },
                          ),
                        ),
                    ],
                  ),
                );
              },
            );
          },
        );
      },
    );
  }
}
