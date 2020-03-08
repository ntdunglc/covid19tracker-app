import 'package:flutter/material.dart';

import '../pages/home.dart';
import '../pages/my_health.dart';

Drawer buildDrawer(BuildContext context, String currentRoute) {
  return Drawer(
    child: ListView(
      children: <Widget>[
        const DrawerHeader(
          child: Center(
            child: Text('Covid-19 Tracker'),
          ),
        ),
        ListTile(
          title: const Text('Home'),
          selected: currentRoute == HomePage.route,
          onTap: () {
            Navigator.pushReplacementNamed(context, HomePage.route);
          },
        ),
        ListTile(
          title: const Text('My Health'),
          selected: currentRoute == MyHealthPage.route,
          onTap: () {
            Navigator.pushReplacementNamed(context, MyHealthPage.route);
          },
        ),      ],
    ),
  );
}
