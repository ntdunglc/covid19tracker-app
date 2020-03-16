import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter_background_geolocation/flutter_background_geolocation.dart' as bg;
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map/plugin_api.dart';
import 'package:latlong/latlong.dart';
import 'package:http/http.dart' as http;
import 'package:csv/csv.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sliding_up_panel/sliding_up_panel.dart';
import 'package:flip_card/flip_card.dart';
import 'package:flutter_form_builder/flutter_form_builder.dart';
import 'package:intl/intl.dart';
import 'package:timeago/timeago.dart' as timeago;
import 'package:duration/duration.dart' as duration;
import 'package:flutter_firebase_ui/flutter_firebase_ui.dart';
import 'package:firebase_auth/firebase_auth.dart';
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
  bool _enabled;

  bg.Location _stationaryLocation;

  List<CircleMarker> _currentPosition = [];
  List<LatLng> _polyline = [];
  List<CircleMarker> _locations = [];
  List<CircleMarker> _stopLocations = [];
  List<Polyline> _motionChangePolylines = [];

  List<Marker> _caseLocations = [];
  List<Marker> _caseInfoWindows = [];

  
  List<CircleMarker> _historyLocations = [];
  List<Marker> _addLocationsFormMarker = [];

  LatLng _center = new LatLng(41.15, -96.50); // US
  MapController _mapController;
  MapOptions _mapOptions;

  PanelController _slideUpPc = new PanelController();
  GlobalKey<FlipCardState> _addLocationFlipCard = GlobalKey<FlipCardState>();
  final GlobalKey<FormBuilderState> _locationHistoryFormKey = GlobalKey<FormBuilderState>();

  bool _enablePublicData = false;
  final double _initFabHeight = 100.0;
  double _panelHeightOpen;
  double _panelHeightClosed = 75.0;
  double _fabHeight = 100.0;

  static int timeBlock = 24; // hours
  static int minDays = 14; // days
  double _timeSliderMaxValue = timeBlock * 60.0;
  double _timeSliderValue = timeBlock * 60.0;
  // double _timeSliderLastValue = timeBlock * 60.0;
  double _sliderWidth;

  double _daySliderMaxValue = 24.0  * minDays / timeBlock; // default last 30 days
  double _daySliderValue = 24.0 * minDays / timeBlock ;

  LatLng _currentLatLng;
  Event _prevEvent;

  DateTime _timestampSlider; //this value is combination of both timeslider and dayslider
 
  Map<String, dynamic> _locationHistoryFormControllers = {
    'startTime': TextEditingController(text: ""),
    'endTime': TextEditingController(text: ""),
    "name": TextEditingController(text: ""),
    "description": TextEditingController(text: ""),
    "latlng": TextEditingController(text: ""),
  };

  HistoricalLocation _editingLocation;
  
  final FirebaseAuth _auth = FirebaseAuth.instance;
  StreamSubscription<FirebaseUser> _listener;
  FirebaseUser _currentUser;


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
        onLongPress: _onSelectMarkerManually
    );
    _mapController = new MapController();

    bg.BackgroundGeolocation.onLocation(_onLocation);
    bg.BackgroundGeolocation.onMotionChange(_onMotionChange);
    bg.BackgroundGeolocation.onEnabledChange(_onEnabledChange);
    bg.BackgroundGeolocation.state.then((bg.State state) {
      setState(() {
        _enabled = state.enabled;
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
    eventStore.loadHistoricalLocations();

    _checkCurrentUser();
  }

  @override
  void dispose() {
    _listener.cancel();
    super.dispose();
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
    _enabled = enabled;
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
    _currentLatLng = ll;
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
    if(!_enabled) {
      util.Dialog.alert(context, 'Location tracking is disable', 'Please enable tracking in settings page and allow the app to use location service all the time');
    }

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

  void _askEnableTracking() {
    util.Dialog.alert(context, 'Location tracking is disable', 'Please enable tracking in settings page and allow the app to use location service all the time');
  }

  void _onAddThisLocation() async {
    if(!_enabled || _currentLatLng == null) {
      _askEnableTracking();
      return;
    }
    _onSelectMarkerManually(_currentLatLng);
    _locationHistoryFormControllers["endTime"].text = _dateTimeToFormValue(DateTime.now());
    _onPopupAddLocation();
    _geocodingLocation(_currentLatLng);
  }

  // void _geocodingLocation(LatLng ll) async{
  //   var response = await http.get("http://photon.komoot.de/reverse?lat=${ll.latitude}&lon=${ll.longitude}");
  //   if (response.statusCode == 200) {
  //     Map<dynamic, dynamic> properties = json.decode(response.body)["features"][0]["properties"];
  //     String name = "${properties['name']!=null ? properties['name']+", " : ""}${properties['housenumber']!=null ? properties['housenumber']+" " : ""}${properties['street']!=null ? properties['street']+", " : ""}${properties['state']!=null ? properties['state']+" " : ""}${properties['postcode']!=null ? properties['postcode']: ""}";
  //     _locationHistoryFormControllers["name"].text = name;
  //   } else {
  //     throw Exception('Failed to load album');
  //   }
  // }
  void _geocodingLocation(LatLng ll) async{
    var response = await http.get("http://3.226.73.226:8000/geolocation/${ll.latitude}/${ll.longitude}");
    if (response.statusCode == 200) {
      String name = json.decode(response.body)["name"];
      _locationHistoryFormControllers["name"].text = name;
    } else {
      throw Exception('Failed to load album');
    }
  }

  void _onAddPreviousLocation(){
    if(!_enabled) {
      _askEnableTracking();
      return;
    }
    String message;
    Event event = _prevEvent;
    if(event == null){
      if(eventStore.events.length == 0){
        print("no events");
        util.Dialog.alert(context, 'No history events', 'Please enable tracking in settings page and wait for locations to be recorded to use this feature'); // this should not happen
        return;
      } else {
        print("eventStore.events.length ${eventStore.events.length}");
        event = eventStore.events[eventStore.events.length - 1];
        message = "TIme slider is not used, using latest known location as historical location";
      }
    }
    LatLng ll = new LatLng(event.lat, event.lng);
    DateTime dt = DateTime.parse(event.timestamp);
    _onSelectMarkerManually(ll);
    _locationHistoryFormControllers["endTime"].text = _dateTimeToFormValue(dt);
    _onPopupAddLocation();
  }

  void _onAddManually(){
    _onPopupAddLocation();
  }

  void _onUpdateHistoricalLocation(HistoricalLocation l){
    _editingLocation = l;
    _onPopupAddLocation();
  }

  void _onSelectMarkerManually(LatLng latLng) {
    print(latLng);
    if(latLng == null) {
     _locationHistoryFormControllers["latlng"].text = "";
     setState(() {
       _addLocationsFormMarker = [];
     });
    } else{
      _onPopupAddLocation();
      _geocodingLocation(latLng);
     _locationHistoryFormControllers["latlng"].text = _latlngToFormValue(latLng);
     setState(() {
       _addLocationsFormMarker = [
         Marker(
            height: 24,
            width: 24,
            point: latLng,
            builder: (ctx) => Icon(
              Icons.flag,
              color: Colors.red,
              size: 30.0,
            )
        )
       ];
     });
    } 
  }

  void _onPopupAddLocation(){
    if(_addLocationFlipCard.currentState.isFront) {
      _addLocationFlipCard.currentState.toggleCard();
    }
    _slideUpPc.open();
  }

  String _dateTimeToFormValue(DateTime dt) {
    return dt != null? dt.toString().split(".")[0]: "";
  }
  String _latlngToFormValue(LatLng ll) {
    return "${ll.latitude},${ll.longitude}";
  }

  void _clearHistoricalLocationForm() {
    _locationHistoryFormControllers.forEach((field, controller) => controller.text = "");
    _locationHistoryFormControllers["startTime"].text = _dateTimeToFormValue(DateTime.now());
    _locationHistoryFormControllers["endTime"].text = _dateTimeToFormValue(DateTime.now());
    _onSelectMarkerManually(null);
  }

  Future _insertHistoricalLocation() async{
    print(_locationHistoryFormKey.currentState.value);
    String latlng = _locationHistoryFormKey.currentState.value["latlng"];
    double lat = double.parse(latlng.split(",")[0]);
    double lng = double.parse(latlng.split(",")[1]);
    DateTime startTime = _locationHistoryFormKey.currentState.value["startTime"];
    DateTime endTime = _locationHistoryFormKey.currentState.value["endTime"];
    HistoricalLocation location = HistoricalLocation(
      _locationHistoryFormKey.currentState.value["name"],
      lat,
      lng,
      toEventDateTimeFormat(startTime),
      toEventDateTimeFormat(endTime),
      _locationHistoryFormKey.currentState.value["description"],
    );
    await eventStore.insertHistoricalLocation(location);
    await eventStore.loadHistoricalLocations();
    _clearHistoricalLocationForm();
    setState(() {
      
    });
    if(!_addLocationFlipCard.currentState.isFront) {
      _addLocationFlipCard.currentState.toggleCard();
    }
  }

  void _updateHistoricalLocation() async {
    String latlng = _locationHistoryFormKey.currentState.value["latlng"];
    double lat = double.parse(latlng.split(",")[0]);
    double lng = double.parse(latlng.split(",")[1]);
    DateTime startTime = _locationHistoryFormKey.currentState.value["startTime"];
    DateTime endTime = _locationHistoryFormKey.currentState.value["endTime"];
    HistoricalLocation location = HistoricalLocation(
      _locationHistoryFormKey.currentState.value["name"],
      lat,
      lng,
      toEventDateTimeFormat(startTime),
      toEventDateTimeFormat(endTime),
      _locationHistoryFormKey.currentState.value["description"],
    );
    await eventStore.updateHistoricalLocation(_editingLocation.id, location);
    await eventStore.loadHistoricalLocations();
    _clearHistoricalLocationForm();
    setState(() {
      
    });
    if(!_addLocationFlipCard.currentState.isFront) {
      _addLocationFlipCard.currentState.toggleCard();
    }
  }

  void _deleteHistoricalLocation() async {
    await eventStore.deleteHistoricalLocation(_editingLocation.id);
    await eventStore.loadHistoricalLocations();
    setState(() {
      
    });
  }

  void _onReportTravelHistory () {
    showDialog(
        context: context,
        builder: (BuildContext context) {
          return AlertDialog(
            content: _loginForm(),
          );
        });
  }

  @override
  Widget _loginForm() {
    if (_currentUser == null) {
      return new SignInScreen(
        title: "Bienvenue",
        header: new Padding(
          padding: const EdgeInsets.symmetric(vertical: 16.0),
          child: new Padding(
            padding: const EdgeInsets.all(16.0),
            child: new Text("Demo"),
          ),
        ),
        providers: [
          ProvidersTypes.google,
          ProvidersTypes.facebook,
          ProvidersTypes.twitter,
          ProvidersTypes.email
        ],
        twitterConsumerKey: "",
        twitterConsumerSecret: "",
      );
    } else {
      return new Text("success!");
    }
  }

  void _checkCurrentUser() async {
    _currentUser = await _auth.currentUser();
    _currentUser?.getIdToken(refresh: true);

    _listener = _auth.onAuthStateChanged.listen((FirebaseUser user) {
      setState(() {
        _currentUser = user;
      });
    });
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
            controller: _slideUpPc,
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
                  label: '${_dateTimeToFormValue(_timestampSlider)}',	
                  inactiveColor: Colors.black,
                  onChanged: (double value) {
                    _timeSliderValue = value;
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
        new MarkerLayerOptions(markers: _addLocationsFormMarker),
        
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
              Container(
                  // padding: EdgeInsets.all(12.0),
                  child: InkWell(
                    onTap: () {
                      setState(() {
                        if(_slideUpPc.isPanelOpen){
                          _slideUpPc.close();
                        } else {
                          _slideUpPc.open();
                        }
                      });
                    },
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

          SizedBox(height: 18.0,),
          FlipCard(
            key: _addLocationFlipCard,
            flipOnTouch: false,
            front: Container(
              child: _historicalLocationList(),
            ),
            back: _locationHistoryForm(),
          ),

        ],
      )
    );
  }
  
  Widget _historicalLocationList() {
    print(eventStore.historicalLocations);
    return Column(
      children: <Widget>[
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: <Widget>[
            _button("Add current", Icons.gps_fixed, Colors.blue, _onAddThisLocation),
            _button("Add previous", Icons.gps_fixed, Colors.purple, _onAddPreviousLocation),
            _button("Add manually", Icons.add, Colors.amber, _onAddManually),
            _button("I'm sick", Icons.report, Colors.red, _onReportTravelHistory),
          ],
        ),
        SizedBox(height: 18.0,),
        ListView.separated(
          shrinkWrap: true,
          physics: ClampingScrollPhysics(),
          padding: const EdgeInsets.all(0.0),
          separatorBuilder: (context, index) {
            return Divider();
          },
          itemCount: eventStore.historicalLocations.length,
          itemBuilder: /*1*/ (context, index) {
            final location = eventStore.historicalLocations[index];
            DateTime s = DateTime.parse(location.startTime);
            DateTime e = DateTime.parse(location.endTime);
            Duration difference = e.difference(s);
            String formattedTime = timeago.format(s) + " - for " + duration.printDuration(difference);
            if(location.description.isNotEmpty) {
              formattedTime +=  "\n" + location.description;
            }
            print("difference $s $e ${location.startTime} ${location.endTime} $difference");
            return ListTile(
              title: Text(location.name),
              subtitle: Text(formattedTime),
              trailing: Icon(Icons.keyboard_arrow_right),
              onTap: () {
                _editingLocation = location;
                _locationHistoryFormControllers["name"].text = _editingLocation.name;
                _locationHistoryFormControllers["startTime"].text = _dateTimeToFormValue(DateTime.parse(_editingLocation.startTime).toLocal());
                _locationHistoryFormControllers["endTime"].text = _dateTimeToFormValue(DateTime.parse(_editingLocation.endTime).toLocal());
                _locationHistoryFormControllers["description"].text = _editingLocation.description;
                _locationHistoryFormControllers["latlng"].text = "${_editingLocation.lat},${_editingLocation.lng}";
                _onPopupAddLocation();
              },
            );
          }
        )
      ],
    );
  }

  Widget _locationHistoryForm(){
    Widget addButton = _editingLocation == null? RaisedButton(
      child: Text("Add Location"),
      textColor: Colors.white,
      color: Colors.blue,
      onPressed: () {
        if (_locationHistoryFormKey.currentState.saveAndValidate()) {
          _insertHistoricalLocation();
          _addLocationFlipCard.currentState.toggleCard();
          _editingLocation = null;
        }
      },
    ): Container();
    Widget updateButton = _editingLocation != null? RaisedButton(
      child: Text("Update"),
      textColor: Colors.white,
      color: Colors.blue,
      onPressed: () {
        if (_locationHistoryFormKey.currentState.saveAndValidate()) {
          _updateHistoricalLocation();
          _addLocationFlipCard.currentState.toggleCard();
          _editingLocation = null;
        }
      },
    ): Container();
    Widget deleteButton = _editingLocation != null? MaterialButton(
      child: Text("Delete"),
      onPressed: () {
        util.Dialog.confirm(context, "Confirm", "Delete this location?", (bool confirm) {
          if (!confirm) { return; }
          _deleteHistoricalLocation();
          _addLocationFlipCard.currentState.toggleCard();
          _editingLocation = null;
        });
      },
    ): Container();
    return Container(
      padding: const EdgeInsets.all(8.0),
      child: Column(
        children: <Widget>[
          Row(
            children: <Widget>[
              addButton,
              updateButton,
              MaterialButton(
                child: Text("Clear"),
                onPressed: () {
                  _clearHistoricalLocationForm();
                },
              ),
              deleteButton,
              MaterialButton(
                child: Text("Close"),
                onPressed: () {
                  // _locationHistoryFormKey.currentState.reset();
                  _addLocationFlipCard.currentState.toggleCard();
                  _editingLocation = null;
                },
              ),
            ],
          ),
          Container(
            padding: const EdgeInsets.all(8.0),
            child: FormBuilder(
              key: _locationHistoryFormKey,
              initialValue: {
                "name": "test location", // TODO: remove
                "description": "test description", // TODO: remove
                'startTime': DateTime.now(),
                'endTime': DateTime.now(),
              },
              autovalidate: true,
              child: Column(
                children: <Widget>[
                  FormBuilderTextField(
                    controller: _locationHistoryFormControllers["name"],
                    attribute: "name",
                    decoration: InputDecoration(labelText: "Name"),
                    maxLines: 1,
                    validators: [
                      FormBuilderValidators.required(),
                      FormBuilderValidators.minLength(3)
                    ],
                  ),
                  FormBuilderDateTimePicker(
                    controller: _locationHistoryFormControllers["startTime"],
                    attribute: "startTime",
                    inputType: InputType.both,
                    format: DateFormat("yyyy-MM-dd HH:mm:ss"),
                    decoration:InputDecoration(labelText: "Start Time"),
                    validators: [
                      FormBuilderValidators.required(),
                    ],
                    lastDate: DateTime.now(),
                  ),
                  FormBuilderDateTimePicker(
                    controller: _locationHistoryFormControllers["endTime"],
                    attribute: "endTime",
                    inputType: InputType.both,
                    format: DateFormat("yyyy-MM-dd HH:mm:ss"),
                    decoration: InputDecoration(labelText: "End Time"),
                    validators: [
                      FormBuilderValidators.required(),
                    ],
                    lastDate: DateTime.now(),
                  ),
                  FormBuilderTextField(
                    controller: _locationHistoryFormControllers["description"],
                    attribute: "description",
                    decoration: InputDecoration(labelText: "Note"),
                    maxLines: 2,
                  ),
                  FormBuilderTextField(
                    controller: _locationHistoryFormControllers["latlng"],
                    attribute: "latlng",
                    decoration: InputDecoration(
                      labelText: "Location"
                      ),
                    maxLines: 1,
                    readOnly: true,
                    validators: [
                      FormBuilderValidators.required(),
                    ],
                  ),
                  Text("Tip: Press and hold on map to change location"),
                ]
              )
            )
          )
        ]
      )
    );
  }

  Widget _button(String label, IconData icon, Color color, onPressed){
    return Column(
      children: <Widget>[
        Container(
          padding: const EdgeInsets.all(4.0),
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