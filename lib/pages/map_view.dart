import 'package:flutter/material.dart';
import 'package:flutter_background_geolocation/flutter_background_geolocation.dart' as bg;
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map/plugin_api.dart';
import 'package:latlong/latlong.dart';
import 'package:http/http.dart' as http;
import 'package:csv/csv.dart';

var covid19_github_url = 'https://raw.githubusercontent.com/CSSEGISandData/COVID-19/master/csse_covid_19_data/csse_covid_19_daily_reports/03-09-2020.csv';
class GithubCaseEvent {
  String locationName;
  String timestamp;
  int confirmed;
  int deaths;
  int recovered;
  double lat;
  double lng;
  GithubCaseEvent(this.locationName, this.timestamp, this.confirmed, this.deaths, this.recovered, this.lat, this.lng);
}

class MapView extends StatefulWidget {
  @override
  State createState() => MapViewState();
}

class MapViewState extends State<MapView> with AutomaticKeepAliveClientMixin<MapView> {
  @override
  bool get wantKeepAlive { return true; }

  bg.Location _stationaryLocation;

  List<CircleMarker> _currentPosition = [];
  List<LatLng> _polyline = [];
  List<CircleMarker> _locations = [];
  List<CircleMarker> _stopLocations = [];
  List<Polyline> _motionChangePolylines = [];

  List<CircleMarker> _caseLocations = [];

  LatLng _center = new LatLng(41.15, -96.50); // US
  MapController _mapController;
  MapOptions _mapOptions;

  @override
  void initState() {
    super.initState();
    fetchGithubData();
    _mapOptions = new MapOptions(
        onPositionChanged: _onPositionChanged,
        center: _center,
        zoom: 4.0,
    );
    _mapController = new MapController();

    bg.BackgroundGeolocation.onLocation(_onLocation);
    bg.BackgroundGeolocation.onMotionChange(_onMotionChange);
    bg.BackgroundGeolocation.onEnabledChange(_onEnabledChange);
    bg.BackgroundGeolocation.getCurrentPosition(
      maximumAge: 86400000,   // 1d is okay, this is just for default view
    ).then((bg.Location location) {
      // force set zoom on startup
      LatLng ll = new LatLng(location.coords.latitude, location.coords.longitude);
      _mapController.move(ll, 10.0);
      print('[getCurrentPosition] - $location');
    }).catchError((error) {
      print('[getCurrentPosition] ERROR: $error');
    });
  }

  void fetchGithubData() async {
    var response = await http.get(covid19_github_url);
    if(response.statusCode == 200) {
      List<List<dynamic>> rowsAsListOfValues = const CsvToListConverter().convert(response.body.replaceAll("\n", "\r\n"));
      print("rowsAsListOfValues ${rowsAsListOfValues.length}");
      List<GithubCaseEvent> cases = rowsAsListOfValues.map((columns) {
        try{
          String locationName = columns[1];
          if(columns[0].toString().isNotEmpty){
            locationName = [columns[0], columns[1]].join(", ");
          }
          return GithubCaseEvent(locationName, columns[2], columns[3], columns[4], columns[5], columns[6], columns[7]);   
        } catch (error) {
          print(error);
          return null;
        }
      })
      .where((c) => c != null)
      .toList();
      setState(() {
        cases.forEach((c) {
          LatLng ll = new LatLng(c.lat, c.lng);
          _caseLocations.add(CircleMarker(
            point: ll,
            color: Colors.red.withOpacity(0.5),
            radius: 5, // c.deaths * 1.0
          ));
        });
      });
      
    }
  }

  void _onEnabledChange(bool enabled) {
    if (!enabled) {
      _locations.clear();
      _polyline.clear();
      _stopLocations.clear();
      _motionChangePolylines.clear();
    }
  }

  void _onMotionChange(bg.Location location) async {
    LatLng ll = new LatLng(location.coords.latitude, location.coords.longitude);

    _updateCurrentPositionMarker(ll);

    _mapController.move(ll, _mapController.zoom);

    if (location.isMoving) {
      if (_stationaryLocation == null) {
        _stationaryLocation = location;
      }
      // Add previous stationaryLocation as a small red stop-circle.
      _stopLocations.add(_buildStopCircleMarker(_stationaryLocation));
      // Create the green motionchange polyline to show where tracking engaged from.
      _motionChangePolylines.add(_buildMotionChangePolyline(_stationaryLocation, location));
    } else {
      // Save a reference to the location where we became stationary.
      _stationaryLocation = location;
    }
  }

  void _onLocation(bg.Location location) {
    LatLng ll = new LatLng(location.coords.latitude, location.coords.longitude);
    _mapController.move(ll, _mapController.zoom);

    _updateCurrentPositionMarker(ll);

    if (location.sample) { return; }

    // Add a point to the tracking polyline.
    _polyline.add(ll);
    // Add a marker for the recorded location.
    _locations.add(CircleMarker(
      point: ll,
      color: Colors.black,
      radius: 5.0
    ));

    _locations.add(CircleMarker(
        point: ll,
        color: Colors.blue,
        radius: 4.0
    ));
  }

  /// Update Big Blue current position dot.
  void _updateCurrentPositionMarker(LatLng ll) {
    _currentPosition.clear();

    // White background
    _currentPosition.add(CircleMarker(
        point: ll,
        color: Colors.white,
        radius: 10
    ));
    // Blue foreground
    _currentPosition.add(CircleMarker(
        point: ll,
        color: Colors.blue,
        radius: 7
    ));
  }

  Polyline _buildMotionChangePolyline(bg.Location from, bg.Location to) {
    return new Polyline(
      points: [
        LatLng(from.coords.latitude, from.coords.longitude),
        LatLng(to.coords.latitude, to.coords.longitude)
      ],
      strokeWidth: 10.0,
      color: Color.fromRGBO(22, 190, 66, 0.7)
    );
  }


  CircleMarker _buildStopCircleMarker(bg.Location location) {
    return new CircleMarker(
        point: LatLng(location.coords.latitude, location.coords.longitude),
        color: Color.fromRGBO(200, 0, 0, 0.3),
        useRadiusInMeter: false,
        radius: 20
    );
  }
  
  void _onPositionChanged(MapPosition pos, bool hasGesture) {
    _mapOptions.crs.scale(_mapController.zoom);
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return FlutterMap(
      mapController: _mapController,
      options: _mapOptions,
      layers: [
        new TileLayerOptions(
          urlTemplate: "https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png",
          subdomains: ['a', 'b', 'c']
        ),
        new PolylineLayerOptions(
          polylines: [
            new Polyline(
                points: _polyline,
                strokeWidth: 10.0,
                color: Color.fromRGBO(0, 179, 253, 0.8),
            ),
          ],
        ),
        // disable these options for now
        // // Polyline joining last stationary location to motionchange:true location.
        // new PolylineLayerOptions(polylines: _motionChangePolylines),
        // // Recorded locations.
        // new CircleLayerOptions(circles: _locations),
        // // Small, red circles showing where motionchange:false events fired.
        // new CircleLayerOptions(circles: _stopLocations),
        new CircleLayerOptions(circles: _currentPosition),
        new CircleLayerOptions(circles: _caseLocations),
      ],
    );
  }
}