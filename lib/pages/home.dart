import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:location/location.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong/latlong.dart';
import '../widgets/drawer.dart';
import 'package:flutter_background_geolocation/flutter_background_geolocation.dart' as bg;

class HomePage extends StatefulWidget {
  static const String route = '/';

  @override
  _HomePage createState() => _HomePage();
}

class _HomePage extends State<HomePage> {

  LocationData _currentLocation;
  MapController _mapController;

  PermissionStatus _permission = PermissionStatus.DENIED;

  String _serviceError = '';

  final Location _locationService = Location();

  @override
  void initState() {
    super.initState();
    _mapController = MapController();
    initLocationService();
    _initPlatformState();
  }
  Future<Null> _initPlatformState() async {
    print('[onLocation] registering onLocation');
    bg.BackgroundGeolocation.onLocation((bg.Location location) {
      print('[onLocation] $location');
    });
    
    bg.BackgroundGeolocation.ready(bg.Config(
      enableHeadless: true,    
      stopOnTerminate: false,  
      startOnBoot: true,
      heartbeatInterval: 60
    ));
    bg.BackgroundGeolocation.onHeartbeat((bg.HeartbeatEvent event) {
      print('[onHeartbeat] ${event}');
    
      // You could request a new location if you wish.
      bg.BackgroundGeolocation.getCurrentPosition(
        samples: 1,
      persist: true
      ).then((bg.Location location) {
        print('[getCurrentPosition] ${location}');
      });
    });
  }

  void initLocationService() async {
    await _locationService.changeSettings(
      accuracy: LocationAccuracy.HIGH,
      interval: 1000,
    );

    LocationData location;
    bool serviceEnabled;
    bool serviceRequestResult;

    try {
      serviceEnabled = await _locationService.serviceEnabled();

      if (serviceEnabled) {
        _permission = await _locationService.requestPermission();

        if (_permission == PermissionStatus.GRANTED) {
          location = await _locationService.getLocation();
          _currentLocation = location;
          moveToCurrentLatLng(zoom: 11.0);
          // _locationService.onLocationChanged().listen((LocationData result) async {
          //   if (mounted) {
          //     setState(() {
          //       _currentLocation = result;
          //       moveToCurrentLatLng(zoom: 13.0);
          //     });
          //   }
          // });
        }
      } else {
        serviceRequestResult = await _locationService.requestService();
        if(serviceRequestResult){
          initLocationService();
          return;
        }
      }
    } on PlatformException catch (e) {
      print(e);
      if (e.code == 'PERMISSION_DENIED') {
        _serviceError = e.message;
      } else if (e.code == 'SERVICE_STATUS_ERROR') {
        _serviceError = e.message;
      }
      location = null;
    }
  }

  void moveToCurrentLatLng({double zoom=0}) {
    if(zoom == 0){
      zoom = _mapController.zoom;
    }
    _mapController.move(LatLng(_currentLocation.latitude, _currentLocation.longitude), zoom);
  }

   @override
  Widget build(BuildContext context) {
    LatLng currentLatLng;

    // Until currentLocation is initially updated, Widget can locate to 0, 0
    // by default or store previous location value to show.
    if (_currentLocation != null) {
      currentLatLng = LatLng(_currentLocation.latitude, _currentLocation.longitude);
    } else {
      currentLatLng = LatLng(41.15, -96.50); // United States
    }

    var markers = <Marker>[
      Marker(
        width: 20.0,
        height: 20.0,
        point: currentLatLng,
        builder: (ctx) => Container(
          child: FlutterLogo(
            colors: Colors.blue,
            key: ObjectKey(Colors.blue),
          ),
        ),
      ),
    ];

    return Scaffold(
      appBar: AppBar(title: Text('Covid-19 Tracker')),
      drawer: buildDrawer(context, HomePage.route),
      body: Padding(
        padding: EdgeInsets.all(8.0),
        child: Column(
          children: [
            Padding(
              padding: EdgeInsets.only(top: 8.0, bottom: 8.0),
              child: _serviceError.isEmpty ?
                Text('This is a map that is showing '
                  '(${currentLatLng.latitude}, ${currentLatLng.longitude}).') :
                Text('Error occured while acquiring location. Error Message : '
                    '$_serviceError'),
            ),
            Flexible(
              child: FlutterMap(
                mapController: _mapController,
                options: MapOptions(
                  center: LatLng(currentLatLng.latitude, currentLatLng.longitude),
                  zoom: 4.0,
                ),
                layers: [
                  TileLayerOptions(
                    urlTemplate:
                    'https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png',
                    subdomains: ['a', 'b', 'c'],
                    // For example purposes. It is recommended to use
                    // TileProvider with a caching and retry strategy, like
                    // NetworkTileProvider or CachedNetworkTileProvider
                    tileProvider: NonCachingNetworkTileProvider(),
                  ),
                  MarkerLayerOptions(markers: markers)
                ],
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
          onPressed: () => moveToCurrentLatLng(),
          child: Icon(Icons.location_on),
      ),
    );
  }
}
