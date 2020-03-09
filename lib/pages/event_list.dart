import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../shared_events.dart';

/// Renders a simple list of [BackgroundGeolocation] events.  Fetches its data from [SharedEvents] (which is an [InheritedWidget].
///
class EventList extends StatefulWidget {
  @override
  State createState() => EventListState();
}

class EventListState extends State<EventList> with AutomaticKeepAliveClientMixin<EventList> {
  Future<SharedPreferences> _prefs = SharedPreferences.getInstance();
  final isSelected = <bool>[true, false, false];

  @override
  bool get wantKeepAlive {
    return true;
  }

  @override
  void initState() {
    super.initState();
    initPlatformState();
  }

  void initPlatformState() async {
    SharedPreferences prefs = await _prefs;
    int timestampFilter = prefs.getInt("timestampFilter") ?? 0;
    loadEvents(timestampFilter);
  }

  void loadEvents(idx) async {
    setState(() {
      for (int indexBtn = 0;indexBtn < isSelected.length;indexBtn++) {
        if (indexBtn == idx) {
          isSelected[indexBtn] = true;
        } else {
          isSelected[indexBtn] = false;
        }
      }
    });
    final eventStore = EventStore.instance();
    DateTime today = new DateTime.now();
    DateTime filterTimeStamp;
    switch (idx) {
      case 0:
        // filterTimeStamp = today.subtract(new Duration(hours: 24));
        filterTimeStamp = today.subtract(new Duration(minutes: 30));
        break;
      case 1:
        filterTimeStamp = today.subtract(new Duration(days: 7));
        break;
      case 2:
        filterTimeStamp = today.subtract(new Duration(days: 30));
        break;
      default:
    }
    eventStore.load(filterTimeStamp).then((events) {
      setState(() {//trigger redraw, need to find a better way
      });
    });
    final SharedPreferences prefs = await _prefs;
    prefs.setInt("timestampFilter", idx);
  }

  @override
  Widget build(BuildContext context) {

    // Fetch SharedEvents for events data.
    final eventStore = EventStore.instance();
    
    return Container(
        //color: Color.fromRGBO(20, 20, 20, 1.0),
        color: Colors.white,
        padding: EdgeInsets.all(5.0),
        child: 
          Column(
          children: <Widget>[
            ToggleButtons(
              children: [
                Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Text('Last 24 Hours'),
                ),
                Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Text('Last 7 Days'),
                ),
                Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Text('Last 30 Days'),
                ),
              ],
              onPressed: (index) {
                setState(() {
                  loadEvents(index);
                });
              },
              isSelected: isSelected,
            ),
            Text("Showing ${eventStore.events.length} events"),
            Expanded(
              child: ListView.builder(
              padding: const EdgeInsets.all(0.0),
              itemCount: eventStore.events.length,
              itemBuilder: /*1*/ (context, index) {
                final event = eventStore.events[index];
                return ListTile(
                  title: Text("${event.timestamp},${event.lat},${event.lng},${event.eventType}"),
                );
              })
            )
        ]),
    );
  }
}