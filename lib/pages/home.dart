import 'package:flutter/material.dart';
import 'dart:async';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_background_geolocation/flutter_background_geolocation.dart' as bg;
import 'package:flutter/services.dart';

import 'map_view.dart';
import 'event_list.dart';
import 'settings.dart';
import 'about.dart';
import '../shared_events.dart';

/// The main home-screen of the AdvancedApp.  Builds the Scaffold of the App.
///
class HomePage extends StatefulWidget {
  static const String route = '/';

  @override
  State createState() => HomePageState();
}

class HomePageState extends State<HomePage> with TickerProviderStateMixin<HomePage>, WidgetsBindingObserver {
  Future<SharedPreferences> _prefs = SharedPreferences.getInstance();
  TabController _tabController;

  bool _isMoving;
  bool _enabled;
  String _motionActivity;

  EventStore eventStore = EventStore.instance();

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addObserver(this);

    _isMoving = false;
    _enabled = false;
    _motionActivity = 'UNKNOWN';

    _tabController = TabController(
        length: 3,
        initialIndex: 0,
        vsync: this
    );
    _tabController.addListener(_handleTabChange);

    initPlatformState();
  }

  void initPlatformState() async {
    _configureBackgroundGeolocation();
    
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

  void _configureBackgroundGeolocation() async {
    bg.BackgroundGeolocation.onLocation(_onLocation, _onLocationError);
    bg.BackgroundGeolocation.onMotionChange(_onMotionChange);
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
        heartbeatInterval: 300
    )).then((bg.State state) {
      print('[ready] ${state.toMap()}');

      setState(() {
        _enabled = state.enabled;
        _isMoving = state.isMoving;
      });
    }).catchError((error) {
      print('[ready] ERROR: $error');
    });

  }

  void _onClickEnable(enabled) async {
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
  ////
  // Event handlers
  //

  void _onLocation(bg.Location location) {
    print('[${bg.Event.LOCATION}] - $location');

    setState(() {
      if(_enabled) {
        eventStore.insertEvent(Event(location.timestamp, bg.Event.LOCATION, location.coords.latitude, location.coords.longitude, location.toString(compact: true)));
      }
    });
  }

  void _onLocationError(bg.LocationError error) {
    print('[${bg.Event.LOCATION}] ERROR - $error');
    setState(() {
      if(_enabled) {
        eventStore.insertEvent(Event(toEventDateTimeFormat(DateTime.now()), bg.Event.LOCATION + " error", -1, -1, error.toString()));
      }
    });
  }

  void _onMotionChange(bg.Location location) {
    print('[${bg.Event.MOTIONCHANGE}] - $location');
    setState(() {   
      if(_enabled) {
        eventStore.insertEvent(Event(location.timestamp, bg.Event.MOTIONCHANGE, location.coords.latitude, location.coords.longitude, location.toString(compact:true)));
      }
      _isMoving = location.isMoving;
    });
  }

  void _onHeartbeat(bg.HeartbeatEvent event) {
    print('[${bg.Event.HEARTBEAT}] - $event');
    setState(() {
      if(_enabled) {
        eventStore.insertEvent(Event(event.location.timestamp, bg.Event.HEARTBEAT, event.location.coords.latitude, event.location.coords.longitude, event.toString()));
      }
    });
  }

  void _onEnabledChange(bool enabled) {
    print('[${bg.Event.ENABLEDCHANGE}] - $enabled');
    setState(() {
      _enabled = enabled;
      eventStore.insertEvent(Event(toEventDateTimeFormat(DateTime.now()), bg.Event.ENABLEDCHANGE, -1, -1, '[EnabledChangeEvent enabled: $enabled]'));
    });
  }

  void _onClickHelp() async {
    Navigator.pushReplacementNamed(context, AboutPage.route);
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
                Tab(icon: Icon(Icons.list)),
                Tab(icon: Icon(Icons.settings)),
              ]
          )
      ),
      //body: body,
      body: TabBarView(
          controller: _tabController,
          children: [
            MapView(),
            EventList(),
            SettingsView(),
          ],
          physics: new NeverScrollableScrollPhysics()
      ),
      // bottomNavigationBar: BottomAppBar(
      //     child: Container(
      //         padding: const EdgeInsets.only(left: 5.0, right: 5.0),
      //         child: Row(
      //             mainAxisSize: MainAxisSize.max,
      //             mainAxisAlignment: MainAxisAlignment.spaceBetween,
      //             children: <Widget>[
      //               IconButton(
      //                 icon: Icon(Icons.gps_fixed),
      //                 onPressed: _onClickGetCurrentPosition,
      //               ),
      //               IconButton(
      //                 icon: Icon(Icons.share),
      //                 onPressed: _onClickShareLog,
      //               ),
      //             ]
      //         )
      //     )
      // ),
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
