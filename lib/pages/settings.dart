import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../widgets/dialog.dart' as util;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_background_geolocation/flutter_background_geolocation.dart' as bg;


const INPUT_TYPE_SELECT = "select";
const INPUT_TYPE_TOGGLE = "toggle";
const INPUT_TYPE_TEXT   = "text";
const INPUT_TYPE_DESCRIPTION   = "description";

class SettingsView extends StatefulWidget {
  @override
  State createState() => _SettingsViewState();
}

class _SettingsViewState extends State<SettingsView> {
  bg.State _state;
  Future<SharedPreferences> _prefs = SharedPreferences.getInstance();

  // Categorized field-lists.
  List<Map> _applicationSettings = [];
  Map<String, dynamic> _values = {
    "enableTracking": false,
    "enablePublicData": false,
  };

  void initState() {
    super.initState();
    PLUGIN_SETTINGS['common'].forEach((Map item) {
      _applicationSettings.add(item);
    });

    initPlatformState();
  }

  void initPlatformState() async {
    bg.BackgroundGeolocation.state.then((bg.State state) {
      setState(() {
        _state = state;
        _values["enableTracking"] = _state.enabled;
      });
    });
    bg.BackgroundGeolocation.onEnabledChange((bool enabled) {
      setState(() {
        _values["enableTracking"] = enabled;
      });
    });
    SharedPreferences prefs = await _prefs;
    setState(() {
      _values["enablePublicData"] = prefs.getBool("enablePublicData") ?? false;
    });

  }

  @override
  Widget build(BuildContext context) {
    if (_state == null) {
      return new Scaffold(
        body: new Text('Loading...')
      );
    }
    
    return new Container(
      child: new CustomScrollView(
        slivers: <Widget>[

          _buildList(_applicationSettings),
        ],
      )
    );
  }

  Widget _buildList(List<Map> list) {
    return new SliverFixedExtentList(
      delegate: SliverChildBuilderDelegate((BuildContext context, int index) {
        return _buildField(list[index]);
      }, childCount: list.length),
      itemExtent: 80.0,
    );
  }

  Widget _buildField(Map<String, Object> setting) {
    String name = setting['name'];
    String inputType = setting['inputType'];
    print('[buildField] - $name: $inputType');
    Widget field;
    switch(inputType) {
      case INPUT_TYPE_TOGGLE:
        field = _buildSwitchField(setting);
        break;
      case INPUT_TYPE_DESCRIPTION:
        field = _buildDescriptionField(setting);
        break;
      default:
        field = new Text('field: $name - Unsupported inputType: $inputType');
        break;
    }
    return field;
  }

  Widget _buildDescriptionField(Map<String, Object> setting) {
    return InputDecorator(
        decoration: InputDecoration(
          contentPadding: EdgeInsets.only(top:0.0, left:10.0, bottom:0.0),
          labelStyle: TextStyle(color: Colors.blue),
          //labelText: name
        ),
        child: Text(setting["text"], style: TextStyle(color: Colors.blue, fontSize: 15.0))
    );
  }
  

  Widget _buildSwitchField(Map<String, Object> setting) {
    String name = setting['name'];
    bool value = _values[name];
    return InputDecorator(
        decoration: InputDecoration(
          contentPadding: EdgeInsets.only(top:0.0, left:10.0, bottom:0.0),
          labelStyle: TextStyle(color: Colors.blue),
          //labelText: name
        ),
        child: Row(
            children: <Widget>[
              Expanded(flex: 3, child: _buildLabel(name)),
              Expanded(
                  flex: 1,
                  child: Column(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: <Widget>[
                        Switch(value: value, onChanged: _createSwitchChangeHandler(name))
                      ]
                  )
              )
            ]
        )
    );
  }


  Text _buildLabel(String label) {
    return Text(label, style: TextStyle(color: Colors.blue, fontSize: 15.0));
  }

  Function(bool) _createSwitchChangeHandler(String field) {
    return (bool value) async {
      if(field == "enableTracking") {
        _onToggleEnableTracking(value);
      } else {
        final SharedPreferences prefs = await _prefs;
        setState(() {
          _values[field] = value;
          prefs.setBool(field, value);
        });
      }
    };
  }

  void _onToggleEnableTracking(enabled) async {
    bg.BackgroundGeolocation.playSound(util.Dialog.getSoundId("BUTTON_CLICK"));
    if (enabled) {
      dynamic callback = (bg.State state) {
        print('[start] success: $state');
        setState(() {
          _values["enableTracking"] = state.enabled;
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
          _values["enableTracking"] = state.enabled;
        });
      };
      bg.BackgroundGeolocation.stop().then(callback);
    }
  }
}

///
/// SIMPLE Hash of most of the plugin's available settings.
///
const PLUGIN_SETTINGS = {
  'common': [
    {'name': 'enableTracking', 'group': 'application', 'dataType': 'boolean', 'inputType': 'toggle', 'values': [true, false], 'defaultValue': true},
    {'name': 'enablePublicData', 'group': 'application', 'dataType': 'boolean', 'inputType': 'toggle', 'values': [true, false], 'defaultValue': false},
  ],
};

// [
//     {'name': 'Enable Tracking', 'dataType': 'boolean', 'inputType': 'toggle', 'values': [true, false], 'defaultValue': false},
//     {'name': 'Enable Tracking Desc', 'text': 'Enable this option will allow tracking your location and travel history', 'inputType': 'description'},
//     {'name': 'Enable Public Data','dataType': 'boolean', 'inputType': 'toggle', 'values': [true, false], 'defaultValue': false},
//     {'name': 'Enable Public Data Desc', 'text': 'Enable this option will sync public data about public cases maintained by Johns Hopkins CSSE', 'inputType': 'description'},
//   ]