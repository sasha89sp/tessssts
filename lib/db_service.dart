import 'package:hive_flutter/hive_flutter.dart';
import 'package:path_provider/path_provider.dart';
import 'models.dart';

class DbService {
  static late Box _box;

  static Future<void> init() async {
    final dir = await getApplicationDocumentsDirectory();
    Hive.init(dir.path);
    _box = await Hive.openBox('sms_history');
  }

  static Future<void> saveSms(SmsMessage msg) async {
    // Ключ = дата + отправитель (чтобы не дублировать)
    await _box.put('${msg.date}_${msg.from}', msg.toJson());
  }

  static List<SmsMessage> getAllSms() {
    return _box.values
        .map((e) => SmsMessage.fromJson(e as Map<dynamic, dynamic>))
        .toList()
      ..sort((a, b) => b.date.compareTo(a.date));
  }

  static Future<void> clearHistory() async {
    await _box.clear();
  }
}
