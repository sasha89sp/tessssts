import 'package:flutter/material.dart';
import 'screens/home_screen.dart';

void main() => runApp(const App());

class App extends StatelessWidget {
  const App({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Huawei E173 Manager',
        theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.blue),
        home: const HomeScreen(),
      );
}
