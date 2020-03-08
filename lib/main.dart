import 'package:flutter/material.dart';
import './pages/home.dart';
import './pages/my_health.dart';
import 'package:flutter_background_geolocation/flutter_background_geolocation.dart' as bg;

void main() {
  runApp(MyApp());
  bg.BackgroundGeolocation.registerHeadlessTask(headlessTask);
}

class MyApp extends StatelessWidget {
  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Covid-19 Tracker',
      // theme: ThemeData(
      //   // This is the theme of your application.
      //   //
      //   // Try running your application with "flutter run". You'll see the
      //   // application has a blue toolbar. Then, without quitting the app, try
      //   // changing the primarySwatch below to Colors.green and then invoke
      //   // "hot reload" (press "r" in the console where you ran "flutter run",
      //   // or simply save your changes to "hot reload" in a Flutter IDE).
      //   // Notice that the counter didn't reset back to zero; the application
      //   // is not restarted.
      //   primarySwatch: Colors.blue,
      // ),
      home: HomePage(),
      routes: <String, WidgetBuilder>{
        MyHealthPage.route: (context) => MyHealthPage(),
      },
    );
  }
}


void headlessTask(bg.HeadlessEvent headlessEvent) async {
  print('[BackgroundGeolocation HeadlessTask]: $headlessEvent');
  // Implement a 'case' for only those events you're interested in.
  switch(headlessEvent.name) {
    case bg.Event.TERMINATE:
      bg.State state = headlessEvent.event;
      print('- State: $state');
      break;
    case bg.Event.HEARTBEAT:
      bg.HeartbeatEvent event = headlessEvent.event;
      print('- HeartbeatEvent: $event');
      break;
    case bg.Event.LOCATION:
      bg.Location location = headlessEvent.event;
      print('- Location: $location');
      break;
    case bg.Event.MOTIONCHANGE:
      bg.Location location = headlessEvent.event;
      print('- Location: $location');
      break;
    case bg.Event.GEOFENCE:
      bg.GeofenceEvent geofenceEvent = headlessEvent.event;
      print('- GeofenceEvent: $geofenceEvent');
      break;
    case bg.Event.GEOFENCESCHANGE:
      bg.GeofencesChangeEvent event = headlessEvent.event;
      print('- GeofencesChangeEvent: $event');
      break;
    case bg.Event.SCHEDULE:
      bg.State state = headlessEvent.event;
      print('- State: $state');
      break;
    case bg.Event.ACTIVITYCHANGE:
      bg.ActivityChangeEvent event = headlessEvent.event;
      print('ActivityChangeEvent: $event');
      break;
    case bg.Event.HTTP:
      bg.HttpEvent response = headlessEvent.event;
      print('HttpEvent: $response');
      break;
    case bg.Event.POWERSAVECHANGE:
      bool enabled = headlessEvent.event;
      print('ProviderChangeEvent: $enabled');
      break;
    case bg.Event.CONNECTIVITYCHANGE:
      bg.ConnectivityChangeEvent event = headlessEvent.event;
      print('ConnectivityChangeEvent: $event');
      break;
    case bg.Event.ENABLEDCHANGE:
      bool enabled = headlessEvent.event;
      print('EnabledChangeEvent: $enabled');
      break;
  }
}