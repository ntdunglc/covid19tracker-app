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
  @override
  String toString() {
      return toMap().toString();
  }
}

class HistoricalLocation {
  int id;
  String name;
  double lat;
  double lng;
  String startTime;
  String endTime;
  String description;
  HistoricalLocation(this.name,this.lat, this.lng, this.startTime,  this.endTime,  this.description);

  HistoricalLocation.fromMap(Map map) {
    id = map["id"] as int;
    name = map["name"] as String;
    lat = map["lat"] as double;
    lng = map["lng"] as double;
    startTime = map["startTime"] as String;
    endTime = map["endTime"] as String;
    description = map["description"] as String;
  }
    /// Convert to a record.
  Map<String, dynamic> toMap() {
    var map = <String, dynamic>{
      "name": name,
      "lat": lat,
      "lng": lng,
      "startTime": startTime,
      "endTime": endTime,
      "description": description,
    };
    return map;
  }    
  @override
  String toString() {
      return toMap().toString();
  }
}

class EventStore {
  Database db;
  List<Event> events = [];
  List<HistoricalLocation> historicalLocations = [];
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
    db = await openDatabase(ENV.DB_PATH, version: 2,
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
      },
      onUpgrade: (Database db, int oldVersion, int newVersion) async{
        if(newVersion == 2) {
          await db.execute('''
            create table HistoricalLocations ( 
              id integer primary key autoincrement, 
              name TEXT not null,
              lat double,
              lng double,
              startTime TEXT not null,
              endTime TEXT not null,
              description TEXT not null)
            ''');
        }
      });
      // await db.delete("HistoricalLocations");
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
    List<Map> maps = await db.query("LocationEvents",
      columns: ["timestamp", "eventType", "lat", "lng", "content"],
      where: 'timestamp > ?',
      whereArgs: [lastTimestampStr],
      orderBy: "timestamp DESC"
    );
    events = maps.map((m) => Event.fromMap(m)).toList();
    return events;
  }

  void insertHistoricalLocation(HistoricalLocation location) async {
    print(location);
    historicalLocations.insert(0, location);
    if(db == null) {
      await open();
    }
    location.id = await db.insert("HistoricalLocations", location.toMap());
  }

  Future<List<HistoricalLocation>> loadHistoricalLocations() async {
    print("[EventStore] loadHistoricalLocations");
    if(db == null) {
      await open();
    }
    List<Map> maps = await db.query("HistoricalLocations",
      orderBy: "startTime DESC"
    );
    historicalLocations = maps.map((m) => HistoricalLocation.fromMap(m)).toList();
    print("[EventStore] loadHistoricalLocations ${historicalLocations.length}");
    return historicalLocations;
  }

  
  void updateHistoricalLocation(int id, HistoricalLocation location) async {
    if(db == null) {
      await open();
    }
    await db.update(
      "HistoricalLocations", 
      location.toMap(),
      where: 'id = ?', 
      whereArgs: [id],
    );
  }

  
  void deleteHistoricalLocation(int id) async {
    if(db == null) {
      await open();
    }
    await db.delete(
      "HistoricalLocations", 
      where: 'id = ?', 
      whereArgs: [id],
    );
  }

  


}

