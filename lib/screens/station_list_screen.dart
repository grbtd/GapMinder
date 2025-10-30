import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:geolocator/geolocator.dart';
import '../models/station.dart';
import 'departure_screen.dart';

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
        return Future.error('Location permissions are denied');
      }
    }

    if (permission == LocationPermission.deniedForever) {
      return Future.error(
          'Location permissions are permanently denied, we cannot request permissions.');
    }
    return await Geolocator.getCurrentPosition();
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
}
