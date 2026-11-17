class SmsMessage {
  final int index;
  final String status;
  final String from;
  final String date;
  final String text;

  SmsMessage({
    required this.index,
    required this.status,
    required this.from,
    required this.date,
    required this.text,
  });

  Map<String, dynamic> toJson() => {
        'index': index,
        'status': status,
        'from': from,
        'date': date,
        'text': text,
      };

  factory SmsMessage.fromJson(Map<dynamic, dynamic> json) => SmsMessage(
        index: json['index'] ?? 0,
        status: json['status'] ?? '',
        from: json['from'] ?? '',
        date: json['date'] ?? '',
        text: json['text'] ?? '',
      );
}

class ModemSettings {
  String port;
  String ussdCode;
  String charset; // 'UCS2' | 'GSM'
  String smsStorage; // 'ME' | 'SM'
  bool isDarkMode;

  ModemSettings({
    this.port = 'COM40',
    this.ussdCode = '*100#',
    this.charset = 'UCS2',
    this.smsStorage = 'ME',
    this.isDarkMode = false,
  });
}

class LogEntry {
  final DateTime time;
  final String direction; // '>>' отправлено, '<<' получено, '!!' ошибка
  final String text;
  LogEntry(this.direction, this.text) : time = DateTime.now();

  @override
  String toString() {
    final t = '${time.hour.toString().padLeft(2, '0')}:'
        '${time.minute.toString().padLeft(2, '0')}:'
        '${time.second.toString().padLeft(2, '0')}';
    return '[$t] $direction $text';
  }
}
