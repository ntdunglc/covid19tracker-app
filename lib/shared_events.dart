import 'package:flutter/material.dart';

/// Simple container class pushed onto ListView
class Event {
  String name;
  dynamic object;
  String content;
  Event(this.name, this.object, this.content);
}

/// Shared data container for all widgets in app.
class SharedEvents extends InheritedWidget {

  final List<Event> events;

  SharedEvents({this.events, child: Widget}):super(child: child);

  static SharedEvents of(BuildContext context) {
    return context.inheritFromWidgetOfExactType(SharedEvents);
  }

  @override
  bool updateShouldNotify(SharedEvents oldWidget) {
    return oldWidget.events.length != events.length;
  }
}
