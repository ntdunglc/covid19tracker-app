import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_background_geolocation/flutter_background_geolocation.dart' as bg;
import 'package:background_fetch/background_fetch.dart';
import 'package:http/http.dart' as http;

// import '../app.dart';
import '../config/env.dart';
import 'map_view.dart';
import 'event_list.dart';
import '../widgets/dialog.dart' as util;
// import './util/test.dart';

import '../shared_events.dart';

// For pretty-printing location JSON
JsonEncoder encoder = new JsonEncoder.withIndent("     ");

/// The main home-screen of the AdvancedApp.  Builds the Scaffold of the App.
///
class HomePage extends StatefulWidget {
  @override
  State createState() => HomePageState();
}

class HomePageState extends State<HomePage> with TickerProviderStateMixin<HomePage>, WidgetsBindingObserver {
  Future<SharedPreferences> _prefs = SharedPreferences.getInstance();
  TabController _tabController;

  bool _isMoving;
  bool _enabled;
  String _motionActivity;

  List<Event> events = [];

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addObserver(this);

    _isMoving = false;
    _enabled = false;
    _motionActivity = 'UNKNOWN';

    _tabController = TabController(
        length: 2,
        initialIndex: 0,
        vsync: this
    );
    _tabController.addListener(_handleTabChange);

    initPlatformState();
  }

  void initPlatformState() async {
    _configureBackgroundGeolocation();
  }

  void _configureBackgroundGeolocation() async {
    bg.BackgroundGeolocation.onLocation(_onLocation, _onLocationError);
    bg.BackgroundGeolocation.onMotionChange(_onMotionChange);
    bg.BackgroundGeolocation.onActivityChange(_onActivityChange);
    bg.BackgroundGeolocation.onHeartbeat(_onHeartbeat);
    bg.BackgroundGeolocation.onEnabledChange(_onEnabledChange);
    
    bg.BackgroundGeolocation.ready(bg.Config(
        // Logging & Debug
        reset: false,
        debug: true,
        logLevel: bg.Config.LOG_LEVEL_VERBOSE,
        // Geolocation options
        desiredAccuracy: bg.Config.DESIRED_ACCURACY_HIGH,
        distanceFilter: 10.0,
        stopTimeout: 1,
        // HTTP & Persistence
        autoSync: false,
        // Application options
        stopOnTerminate: false,
        startOnBoot: true,
        enableHeadless: true,
        heartbeatInterval: 60
    )).then((bg.State state) {
      print('[ready] ${state.toMap()}');

      setState(() {
        _enabled = state.enabled;
        _isMoving = state.isMoving;
      });
    }).catchError((error) {
      print('[ready] ERROR: $error');
    });

    // Fetch currently selected tab.
    SharedPreferences prefs = await _prefs;
    int tabIndex = prefs.getInt("tabIndex");

    // Which tab to view?  MapView || EventList.   Must wait until after build before switching tab or bad things happen.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (tabIndex != null) {
        _tabController.animateTo(tabIndex);
      }
    });
  }

  void _onClickEnable(enabled) async {
    bg.BackgroundGeolocation.playSound(util.Dialog.getSoundId("BUTTON_CLICK"));
    if (enabled) {
      dynamic callback = (bg.State state) {
        print('[start] success: $state');
        setState(() {
          _enabled = state.enabled;
          _isMoving = state.isMoving;
        });
      };
      bg.State state = await bg.BackgroundGeolocation.state;
      if (state.trackingMode == 1) {
        bg.BackgroundGeolocation.start().then(callback);
      } else {
        bg.BackgroundGeolocation.startGeofences().then(callback);
      }
    } else {
      dynamic callback = (bg.State state) {
        print('[stop] success: $state');
        setState(() {
          _enabled = state.enabled;
          _isMoving = state.isMoving;
        });
      };
      bg.BackgroundGeolocation.stop().then(callback);
    }
  }

  // Manually fetch the current position.
  void _onClickGetCurrentPosition() async {
    bg.BackgroundGeolocation.playSound(util.Dialog.getSoundId("BUTTON_CLICK"));

    bg.BackgroundGeolocation.getCurrentPosition(
        desiredAccuracy: 40, // <-- desire an accuracy of 40 meters or less
        maximumAge: 10000,   // <-- Up to 10s old is fine.
        timeout: 30,         // <-- wait 30s before giving up.
        samples: 3,           // <-- sample just 1 location
        extras: {"getCurrentPosition": true}
    ).then((bg.Location location) {
      print('[getCurrentPosition] - $location');
    }).catchError((error) {
      print('[getCurrentPosition] ERROR: $error');
    });

    // force tracking, we know there is user interaction
    bg.BackgroundGeolocation.changePace(true).then((bool isMoving) { 
      print('[changePace] success $isMoving');
    }).catchError((e) {
      print('[changePace] ERROR: ' + e.code.toString());
    });
  }

  ////
  // Event handlers
  //

  void _onLocation(bg.Location location) {
    print('[${bg.Event.LOCATION}] - $location');

    setState(() {
      events.insert(0, Event(bg.Event.LOCATION, location, location.toString(compact: true)));
    });
  }

  void _onLocationError(bg.LocationError error) {
    print('[${bg.Event.LOCATION}] ERROR - $error');
    setState(() {
      events.insert(0, Event(bg.Event.LOCATION + " error", error, error.toString()));
    });
  }

  void _onMotionChange(bg.Location location) {
    print('[${bg.Event.MOTIONCHANGE}] - $location');
    setState(() {
      events.insert(0, Event(bg.Event.MOTIONCHANGE, location, location.toString(compact:true)));
      _isMoving = location.isMoving;
    });
  }

  void _onActivityChange(bg.ActivityChangeEvent event) {
    print('[${bg.Event.ACTIVITYCHANGE}] - $event');
    setState(() {
      events.insert(0, Event(bg.Event.ACTIVITYCHANGE, event, event.toString()));
      _motionActivity = event.activity;
    });
  }

  void _onHeartbeat(bg.HeartbeatEvent event) {
    print('[${bg.Event.HEARTBEAT}] - $event');
    setState(() {
      events.insert(0, Event(bg.Event.HEARTBEAT, event, event.toString()));
    });
  }

  void _onEnabledChange(bool enabled) {
    print('[${bg.Event.ENABLEDCHANGE}] - $enabled');
    setState(() {
      _enabled = enabled;
      events.clear();
      events.insert(0, Event(bg.Event.ENABLEDCHANGE, enabled, '[EnabledChangeEvent enabled: $enabled]'));
    });
  }

  void _onClickShareLog() async {
    util.Dialog.alert(context, 'Preparing log', 'The log will be processed in the background (it can take some time depending on the size of the log).  Your share screen will launch when ready.');

    bg.Logger.emailLog("").then((bool success) {
      print('[emailLog] success');
    }).catchError((error) {
      util.Dialog.alert(context, 'Email log Error', error.toString());
    });
  }
  void _onClickHelp() async {
  }
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
          title: const Text('COVID-19 Tracker'),
          leading: IconButton(onPressed: _onClickHelp, icon: Icon(Icons.help_outline, color: Colors.black)),
          centerTitle: true,
          backgroundColor: Theme.of(context).bottomAppBarColor,
          brightness: Brightness.light,
          actions: <Widget>[
            Switch(value: _enabled, onChanged: _onClickEnable
            ),
          ],
          bottom: TabBar(
              controller: _tabController,
              indicatorColor: Colors.red,
              tabs: [
                Tab(icon: Icon(Icons.map)),
                Tab(icon: Icon(Icons.list))
              ]
          )
      ),
      //body: body,
      body: SharedEvents(
          events: events,
          child: TabBarView(
              controller: _tabController,
              children: [
                MapView(),
                EventList()
              ],
              physics: new NeverScrollableScrollPhysics()
          )
      ),
      bottomNavigationBar: BottomAppBar(
          child: Container(
              padding: const EdgeInsets.only(left: 5.0, right: 5.0),
              child: Row(
                  mainAxisSize: MainAxisSize.max,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: <Widget>[
                    IconButton(
                      icon: Icon(Icons.gps_fixed),
                      onPressed: _onClickGetCurrentPosition,
                    ),
                    IconButton(
                      icon: Icon(Icons.share),
                      onPressed: _onClickShareLog,
                    ),
                  ]
              )
          )
      ),
    );
  }

  @override
  void dispose() {
    _tabController.removeListener(_handleTabChange);
    _tabController.dispose();
    super.dispose();
  }

  void _handleTabChange() async {
    if (!_tabController.indexIsChanging) { return; }
    final SharedPreferences prefs = await _prefs;
    prefs.setInt("tabIndex", _tabController.index);
  }
}
