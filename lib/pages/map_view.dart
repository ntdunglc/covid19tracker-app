import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:collection';
import 'dart:math';
import 'package:flutter_background_geolocation/flutter_background_geolocation.dart' as bg;
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map/plugin_api.dart';
import 'package:latlong/latlong.dart';
import 'package:http/http.dart' as http;
import 'package:csv/csv.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sliding_up_panel/sliding_up_panel.dart';
import '../widgets/dialog.dart' as util;
import '../shared_events.dart';

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
  EventStore eventStore = EventStore.instance();

  bg.Location _stationaryLocation;

  List<CircleMarker> _currentPosition = [];
  List<LatLng> _polyline = [];
  List<CircleMarker> _locations = [];
  List<CircleMarker> _stopLocations = [];
  List<Polyline> _motionChangePolylines = [];

  List<Marker> _caseLocations = [];
  List<Marker> _caseInfoWindows = [];

  
  List<CircleMarker> _historyLocations = [];

  LatLng _center = new LatLng(41.15, -96.50); // US
  MapController _mapController;
  MapOptions _mapOptions;
  bool _enablePublicData = false;
  final double _initFabHeight = 100.0;
  double _panelHeightOpen;
  double _panelHeightClosed = 75.0;
  double _fabHeight = 100.0;

  static int timeBlock = 24; // hours
  static int minDays = 14; // days
  double _timeSliderMaxValue = timeBlock * 60.0;
  double _timeSliderValue = timeBlock * 60.0;
  double _timeSliderLastValue = timeBlock * 60.0;

  double _daySliderMaxValue = 24.0  * minDays / timeBlock; // default last 30 days
  double _daySliderValue = 24.0 * minDays / timeBlock ;

  Event _prevEvent;

  DateTime _timestampSlider; //this value is combination of both timeslider and dayslider
  double _sliderWidth;

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
            _mapController.move(ll, 14.0);
          }).catchError((error) {
          });
        }
      });
    });

    DateTime today = new DateTime.now();
    eventStore.load(today.subtract(new Duration(days: 30)));
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

  // Manually fetch the current position.
  void _onClickGetCurrentPosition() async {
    // if(!_enabled) {
    //   util.Dialog.alert(context, 'Location tracking is disable', 'Please enable tracking in settings page and allow the app to use location service all the time');
    // }

    // force tracking, we know there is user interaction
    bg.BackgroundGeolocation.changePace(true).then((bool isMoving) { 
      print('[changePace] success $isMoving');
    }).catchError((e) {
      print('[changePace] ERROR: ' + e.code.toString());
    });
  }

  
  void _onTimeStampSliderChange(DateTime dt) async {
    int idx = lowerBound(eventStore.events, dt);
    if(idx == eventStore.events.length) {
      idx = eventStore.events.length - 1;
    }
    Event event = eventStore.events[idx];
    LatLng ll = new LatLng(event.lat, event.lng);
    setState(() {
      _prevEvent = event;
      _historyLocations = [
        CircleMarker(
          point: ll,
          color: Colors.purple,
          radius: 5.0
        )
      ];
    });
  }

  int lowerBound(List<Event> events, DateTime dt) {
    String dts = dt.toUtc().toIso8601String();
    int min = 0;
    int max = events.length;
    while (min < max) {
      int mid = min + ((max - min) >> 1);
      var element = events[mid];
      int comp = element.timestamp.compareTo(dts);
      if (comp > 0) { // event are sorted DESC, so switch the comparison
        min = mid + 1;
      } else {
        max = mid;
      }
    }
    return min;
  }

  void _onDateTimeSliderChange(double daySliderValue, double timeSliderValue) {
    setState(() {
      DateTime today = new DateTime.now();
      int hoursAgo = (_daySliderMaxValue - _daySliderValue).round() * timeBlock; // 1 min step
      int minutesAgo = (_timeSliderMaxValue - _timeSliderValue).round(); // 1 min step
      _timestampSlider = today.subtract(new Duration(minutes: minutesAgo, hours: hoursAgo));
      _onTimeStampSliderChange(_timestampSlider);
    });
  }

  void _onAddThisLocation(){

  }

  void _onAddPreviousLocation(){
    
  }

  void _onAddManually(){
    
  }

  @override
  Widget build(BuildContext context){
    _panelHeightOpen = MediaQuery.of(context).size.height * .50;
    _sliderWidth = MediaQuery.of(context).size.width * .70;

    return Material(
      child: Stack(
        alignment: Alignment.topCenter,
        children: <Widget>[

          SlidingUpPanel(
            maxHeight: _panelHeightOpen,
            minHeight: _panelHeightClosed,
            parallaxEnabled: true,
            parallaxOffset: .5,
            body: _body(),
            panelBuilder: (sc) => _panel(sc),
            borderRadius: BorderRadius.only(topLeft: Radius.circular(18.0), topRight: Radius.circular(18.0)),
            onPanelSlide: (double pos) => setState((){
              _fabHeight = pos * (_panelHeightOpen - _panelHeightClosed) + _initFabHeight;
            }),
          ),

          // the fab
          Positioned(
            width: MediaQuery.of(context).size.width * .20,
            right: 20.0,
            bottom: _fabHeight,
            child: FloatingActionButton(
              child: Icon(
                Icons.gps_fixed,
                color: Theme.of(context).primaryColor,
              ),
              onPressed: _onClickGetCurrentPosition,
              backgroundColor: Colors.white,
            ),
          ),
          Positioned(
            left: 20.0,	
            width: _sliderWidth,
            bottom: _fabHeight - 20,
            child: Column(
              // alignment: Alignment.topCenter,
              children: <Widget>[ 
                Slider(	
                  value: _timeSliderValue,
                  min: 0.0,
                  max: _timeSliderMaxValue,
                  divisions: _timeSliderMaxValue.round(), 
                  label: '${_timestampSlider!=null?_timestampSlider.toString().split(".")[0]:""}',	
                  inactiveColor: Colors.black,
                  onChanged: (double value) {
                    _timeSliderValue = value;
                    // if(_timeSliderLastValue != _timeSliderValue) {
                    //   if(_timeSliderValue == 0 && _daySliderValue > 0) {
                    //     _timeSliderValue = _timeSliderMaxValue;
                    //     _daySliderValue -= 1;
                    //   } else if (_timeSliderValue == _timeSliderMaxValue && _daySliderValue < _daySliderMaxValue) {
                    //     _timeSliderValue = 0;
                    //     _daySliderValue += 1;
                    //   }
                    // }
                    // _timeSliderLastValue = _timeSliderValue;
                    _onDateTimeSliderChange(_daySliderMaxValue, value);
                  },
                ),
                Slider(	
                  value: _daySliderValue,
                  min: 0.0,
                  max: _daySliderMaxValue,
                  divisions: _daySliderMaxValue.round(), 
                  label: '${_timestampSlider.toString().split(".")[0]}',	
                  inactiveColor: Colors.black,
                  onChanged: (double value) {
                    _daySliderValue = value;
                    _onDateTimeSliderChange(value, _timeSliderValue);
                  },
                ),
              ]
            ),
          ),
        ],
      ),
    );
  }

  Widget _body(){
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
        new CircleLayerOptions(circles: _historyLocations),
      ],
    );
  }
  Widget _panel(ScrollController sc){
    return MediaQuery.removePadding(
      context: context,
      removeTop: true,
      child: ListView(
        controller: sc,
        children: <Widget>[
          SizedBox(height: 12.0,),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Container(
                width: 30,
                height: 5,
                decoration: BoxDecoration(
                color: Colors.grey[300],
                  borderRadius: BorderRadius.all(Radius.circular(12.0))
                ),
              ),
            ],
          ),

          SizedBox(height: 12.0,),

          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              InkWell(
                // When the user taps the button, show a snackbar.
                onTap: () {
                  util.Dialog.alert(context, 'OKAY', 'Please enable tracking in settings page and allow the app to use location service all the time');
                },
                child: Container(
                  // padding: EdgeInsets.all(12.0),
                  child: Text(
                      "Travel History",
                      style: TextStyle(
                        fontWeight: FontWeight.normal,
                        fontSize: 24.0,
                      ),
                    ),
                ),
              ),
            ],
          ),

          SizedBox(height: 36.0,),
          
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: <Widget>[
                // Icons.gps_fixed,
                // color: Theme.of(context).primaryColor,
              _button("Add this location", Icons.gps_fixed, Colors.blue, _onAddThisLocation),
              _button("Add previous", Icons.gps_fixed, Colors.purple, _onAddPreviousLocation),
              _button("Add manually", Icons.add, Colors.amber, _onAddManually),
              // _button("Events", Icons.event, Colors.amber),
              // _button("More", Icons.more_horiz, Colors.green),
            ],
          ),

        ],
      )
    );
  }

  Widget _button(String label, IconData icon, Color color, onPressed){
    return Column(
      children: <Widget>[
        Container(
          padding: const EdgeInsets.all(16.0),
          child: IconButton(
            icon: Icon(icon, color: Colors.white),
            tooltip: 'Increase volume by 10',
            onPressed: onPressed,
          ),
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            boxShadow: [BoxShadow(
              color: Color.fromRGBO(0, 0, 0, 0.15),
              blurRadius: 8.0,
            )]
          ),
        ),

        SizedBox(height: 12.0,),

        Text(label),
      ],

    );
  }
}