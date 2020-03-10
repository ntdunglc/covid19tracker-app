import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';
import './config/env.dart';

String toEventDateTimeFormat(DateTime dt) {
  return dt.toUtc().toString().replaceAll(" ", "T");
}

/// Simple container class pushed onto ListView
class Event {
  int id;
  String timestamp;
  String eventType;
  double lat;
  double lng;
  String content;
  Event(this.timestamp, this.eventType, this.lat, this.lng, this.content);

  Event.fromMap(Map map) {
    id = map["id"] as int;
    timestamp = map["timestamp"] as String;
    eventType = map["eventType"] as String;
    lat = map["lat"] as double;
    lng = map["lng"] as double;
    content = map["content"] as String;
  }
    /// Convert to a record.
  Map<String, dynamic> toMap() {
    var map = <String, dynamic>{
      "timestamp": timestamp,
      "eventType": eventType,
      "lat": lat,
      "lng": lng,
      "content": content,
    };
    return map;
  }
}

class EventStore {
  Database db;
  List<Event> events = [];
  EventStore();

  static EventStore _instance  = EventStore();
  static EventStore instance() {
    return _instance;
  }

  List<Event> get locationEvents {
    return events.where((e) => e.lat != -1).toList();;
  }

  /// Open the database.
  Future open() async {
    print("[EventStore] opening db");
    db = await openDatabase(ENV.DB_PATH, version: 1,
          onCreate: (Database db, int version) async {
        await db.execute('''
          create table LocationEvents ( 
            id integer primary key autoincrement, 
            timestamp TEXT not null,
            eventType TEXT not null,
            lat double,
            lng double,
            content TEXT not null)
          ''');
      });
  }

  void insertEvent(Event event) async {
    // dont store duplicate events to save use storage
    if(events.isNotEmpty && events[0].lat == event.lat && events[0].lng == event.lng){
      return; 
    }
    events.insert(0, event);
    if(db == null) {
      await open();
    }
    event.id = await db.insert("LocationEvents", event.toMap());
  }
  
  Future<List<Event>> load(DateTime lastTimestamp) async {
    print("[EventStore] loading");
    if(db == null) {
      await open();
    }
    String lastTimestampStr = toEventDateTimeFormat(lastTimestamp);
    print("lastTimestamp.toUtc() ${lastTimestamp.toUtc()} $lastTimestampStr");
    List<Map> maps = await db.query("LocationEvents",
      columns: ["timestamp", "eventType", "lat", "lng", "content"],
      where: 'timestamp > ?',
      whereArgs: [lastTimestampStr],
      orderBy: "timestamp DESC"
    );
    print("[EventStore] loaded ${maps.length}");
    events = maps.map((m) => Event.fromMap(m)).toList();
    return events;
  }

}

/// Shared data container for all widgets in app.
class SharedEvents extends InheritedWidget {

  final EventStore eventStore;

  SharedEvents({this.eventStore, child: Widget}):super(child: child);

  static SharedEvents of(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType();
    // return context.inheritFromWidgetOfExactType(SharedEvents);
  }

  @override
  bool updateShouldNotify(SharedEvents oldWidget) {
    return oldWidget.eventStore.events.length != eventStore.events.length;
  }
}
