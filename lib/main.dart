import 'package:flutter/material.dart';
import 'package:local_notifier/local_notifier.dart';
import 'db_service.dart';
import 'screens/home_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await DbService.init();
  await localNotifier.setup(appName: 'Huawei E173 Manager');
  runApp(const App());
}

class App extends StatefulWidget {
  const App({super.key});
  @override
  State<App> createState() => _AppState();
}

class _AppState extends State<App> {
  bool _isDarkMode = false;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Huawei E173 Manager',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: Colors.blue,
        brightness: _isDarkMode ? Brightness.dark : Brightness.light,
      ),
      home: HomeScreen(
        isDarkMode: _isDarkMode,
        onThemeChanged: (v) => setState(() => _isDarkMode = v),
      ),
    );
  }
}
