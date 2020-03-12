import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:math';
import 'package:flutter_background_geolocation/flutter_background_geolocation.dart' as bg;
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map/plugin_api.dart';
import 'package:latlong/latlong.dart';
import 'package:http/http.dart' as http;
import 'package:csv/csv.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
  Future<SharedPreferences> _prefs = SharedPreferences.getInstance();

  bg.Location _stationaryLocation;

  List<CircleMarker> _currentPosition = [];
  List<LatLng> _polyline = [];
  List<CircleMarker> _locations = [];
  List<CircleMarker> _stopLocations = [];
  List<Polyline> _motionChangePolylines = [];

  List<Marker> _caseLocations = [];
  List<Marker> _caseInfoWindows = [];

  LatLng _center = new LatLng(41.15, -96.50); // US
  MapController _mapController;
  MapOptions _mapOptions;
  bool _enablePublicData = false;

  @override
  void initState() {
    super.initState();
    refreshhGithubData();

    // currently I dont have a good way to sync with setting in shared_preferences...
    // so polling it for now
    Timer.periodic(new Duration(seconds: 5), (timer) {
      refreshhGithubData();
    });
    _mapOptions = new MapOptions(
        onPositionChanged: _onPositionChanged,
        center: _center,
        zoom: 4.0,
    );
    _mapController = new MapController();

    bg.BackgroundGeolocation.onLocation(_onLocation);
    bg.BackgroundGeolocation.onMotionChange(_onMotionChange);
    bg.BackgroundGeolocation.onEnabledChange(_onEnabledChange);
    bg.BackgroundGeolocation.state.then((bg.State state) {
      setState(() {
        if(state.enabled){
          bg.BackgroundGeolocation.getCurrentPosition(
            maximumAge: 86400000,   // 1d is okay, this is just for default view
          ).then((bg.Location location) {
            // force set zoom on startup
            LatLng ll = new LatLng(location.coords.latitude, location.coords.longitude);
            _mapController.move(ll, 10.0);
          }).catchError((error) {
          });
        }
      });
    });
  }

  void refreshhGithubData() async {
    SharedPreferences prefs = await _prefs;
    _enablePublicData = prefs.getBool("enablePublicData");
    if(!_enablePublicData) {
      if(_caseLocations.isNotEmpty){
        setState(() {
          _caseLocations = [];
          _caseInfoWindows = [];
        });
      }
      return;
    }
    if(_caseLocations.isNotEmpty){ // if data already loaded, do nothing
      return;
    }

    DateTime today = new DateTime.now();
    
    for(var i=0; i<7; i+=1) {
      DateTime queryDate = today;
      if(i > 0) {
        queryDate = today.subtract(new Duration(days: i));
      }
      String dateSlug ="${queryDate.month.toString().padLeft(2,'0')}-${queryDate.day.toString().padLeft(2,'0')}-${queryDate.year.toString()}";
      String covid19GithubUrl = 'https://raw.githubusercontent.com/CSSEGISandData/COVID-19/master/csse_covid_19_data/csse_covid_19_daily_reports/$dateSlug.csv';
      var response = await http.get(covid19GithubUrl);
      if(response.statusCode != 200) {
        continue;
      }
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
          double minRadius = 15.0; // ~ 1 case
          double maxRadius = 25;   // 1 mil cases, log(1e6) = 6
          double radius = minRadius + min(6, log(c.confirmed - c.deaths - c.recovered)) * maxRadius / 6;
          _caseLocations.add(Marker(
              height: radius,
              width: radius,
              point: ll,
              builder: (ctx) => new GestureDetector(
                onTap: (){
                  _onSelectCaseMarker(ll, "${c.locationName}\n${c.confirmed} Confirmed\n${c.deaths} Deaths\n${c.recovered} Recovered");
                },
              child: new Container(
                height: radius,
                width: radius,
                decoration: new BoxDecoration(
                  color: Colors.red.withOpacity(0.5),
                  shape: BoxShape.circle,
                ),
              ),
            )
          ));
        });
      });
      break; // no need to go to older date
    }
  }

  void _onSelectCaseMarker(LatLng ll, String description) {
    setState(() {
      _caseInfoWindows = [
        Marker(
            point: ll,
            height: 80,
            width: 200,
            builder: (ctx) => new Container(
              child: Padding(
                padding: EdgeInsets.all(5.0),
                child: Text(description),
              ),
              decoration: new BoxDecoration(
                color: Colors.white,
                shape: BoxShape.rectangle,
                border: Border.all(width: 1.0, color: Color(0xAAAAAAAA))
              ),
            )
          )
      ];
    });
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
        new MarkerLayerOptions(markers: _caseLocations),
        new MarkerLayerOptions(markers: _caseInfoWindows),
      ],
    );
  }
}