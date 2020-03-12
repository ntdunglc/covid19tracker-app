import 'package:flutter/material.dart';
import 'dart:async';

import 'package:shared_preferences/shared_preferences.dart';

/// The main home-screen of the AdvancedApp.  Builds the Scaffold of the App.
///
class AboutPage extends StatefulWidget {
  static const String route = '/about';

  @override
  State createState() => AboutPageState();
}

class AboutPageState extends State<AboutPage>  {
  Future<SharedPreferences> _prefs = SharedPreferences.getInstance();
  @override
  void initState() {
    super.initState();

    // WidgetsBinding.instance.addObserver(this);

  }

  void _onClickHome() async {
    Navigator.pushReplacementNamed(context, "/");
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
          title: const Text('COVID-19 Tracker'),
          leading: IconButton(onPressed: _onClickHome, icon: Icon(Icons.arrow_back, color: Colors.black)),
          centerTitle: true,
          backgroundColor: Theme.of(context).bottomAppBarColor,
          brightness: Brightness.light,
      ),
      body: SingleChildScrollView(
        scrollDirection: Axis.vertical,
        padding: EdgeInsets.all(8.0),
        child: Column(
          children: [
            Padding(
              padding: EdgeInsets.only(top: 8.0, bottom: 8.0),
              child: Center(
                child: RichText(
                  text: TextSpan(
                    text: 
                      'Help the community, help yourself to fight the virus!\n\n',
                    style: TextStyle(
                      color: Colors.grey[800],
                      fontSize: 20
                    ),
                    children: <TextSpan>[
                      TextSpan(
                        text: 'One of the most effective way to contain the spread of the virus '
                        'is to quarantine sick people and send alerts to people that contracted with them. '
                        'Very often people don\'t know if they were around infected people and have exposure '
                        'to virus already, so they possibly infect their beloved family and friends unintentionally\n\n'
                        'This '
                      ),
                      TextSpan(text: 'local-first, privacy-first', style: TextStyle(fontWeight: FontWeight.bold)),
                      TextSpan(
                        text: ' application help users to self track their travel history in their own phone, share their health status with community, allow users to anonymously publish their travel history so other users can get alerts if they have were at the same time and location.\n\n'
                      ),
                      TextSpan(
                        text: 'Sincerely,\nFrom Dev team'
                      ),
                    ],
                  ),
                ),
              )
            ),
          ],
        ),
      ),
    );
  }

}
