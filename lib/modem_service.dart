import 'dart:async';
import 'dart:convert';
import 'package:platform_serial/platform_serial.dart';
import 'models.dart';

class ModemService {
  final SerialManager _manager = SerialManager();
  SerialPort? _port;
  String? _openPortName;

  // Очередь полученных строк (кто первый ждет — тот и забирает)
  final List<String> _lineBuffer = [];
  final List<Completer<String>> _lineWaiters = [];
  bool _reading = false;

  // URC-события (незапрошенные уведомления модема)
  final StreamController<String> _urcController = StreamController.broadcast();
  Stream<String> get urcStream => _urcController.stream;

  // Лог AT
  final StreamController<LogEntry> _logController = StreamController.broadcast();
  Stream<LogEntry> get logStream => _logController.stream;

  bool get isOpen => _port != null;
  String? get portName => _openPortName;

  void _log(String dir, String text) => _logController.add(LogEntry(dir, text));

  // ---------------- Открытие / закрытие ----------------
  Future<void> open(String portName) async {
    await close();
    _port = await _manager.openPort(portName, baudRate: 115200, dataBits: 8);
    _openPortName = portName;
    _startReader();
    await initModem();
  }

  Future<void> close() async {
    _reading = false;
    await Future.delayed(const Duration(milliseconds: 250));
    if (_openPortName != null) {
      try {
        await _manager.closePort(_openPortName!);
      } catch (_) {}
    }
    _port = null;
    _openPortName = null;
    _lineBuffer.clear();
    for (final w in _lineWaiters) {
      if (!w.isCompleted) w.complete('');
    }
    _lineWaiters.clear();
  }

  // ---------------- Фоновый читатель ----------------
  void _startReader() {
    if (_reading) return;
    _reading = true;
    _readerLoop();
  }

  Future<void> _readerLoop() async {
    while (_reading && _port != null) {
      try {
        final raw = await _port!.readUntil(
          '\n',
          timeout: const Duration(milliseconds: 200),
        );
        final line = raw.toString().trim();
        if (line.isNotEmpty) {
          _log('<<', line);
          _dispatchLine(line);
        }
      } catch (_) {
        // таймаут — продолжаем
      }
    }
  }

  void _dispatchLine(String line) {
    // URC: +CMTI, +CUSD (неожидаемый), RING, +CREG, и т.д.
    final isUrc = line.startsWith('+CMTI:') ||
        line.startsWith('+CMT:') ||
        line.startsWith('+CUSD:') ||
        line.startsWith('+CREG:') ||
        line.startsWith('+CGREG:') ||
        line == 'RING' ||
        line.startsWith('+CLIP:');

    if (isUrc && _lineWaiters.isEmpty) {
      _urcController.add(line);
      return;
    }

    if (_lineWaiters.isNotEmpty) {
      final w = _lineWaiters.removeAt(0);
      if (!w.isCompleted) w.complete(line);
    } else {
      _lineBuffer.add(line);
    }
  }

  Future<String> _readLine({Duration timeout = const Duration(seconds: 3)}) {
    if (_lineBuffer.isNotEmpty) {
      return Future.value(_lineBuffer.removeAt(0));
    }
    final c = Completer<String>();
    _lineWaiters.add(c);
    return c.future.timeout(timeout, onTimeout: () {
      _lineWaiters.remove(c);
      return '';
    });
  }

  // ---------------- Отправка AT-команды ----------------
  /// Отправляет команду и собирает ответ до OK/ERROR или до [stopOn].
  Future<List<String>> sendCommand(
    String cmd, {
    Duration timeout = const Duration(seconds: 4),
    String? stopOnPrefix,
  }) async {
    if (_port == null) throw Exception('Порт не открыт');
    _lineBuffer.clear();
    _log('>>', cmd);
    await _port!.writeText('$cmd\r\n');

    final lines = <String>[];
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      final line = await _readLine(timeout: const Duration(milliseconds: 500));
      if (line.isEmpty) continue;
      if (stopOnPrefix != null && line.startsWith(stopOnPrefix)) {
        lines.add(line);
        break;
      }
      if (line == 'OK' || line.startsWith('+CME ERROR') || line == 'ERROR') {
        lines.add(line);
        break;
      }
      lines.add(line);
    }
    return lines;
  }

  // ---------------- Инициализация модема ----------------
  Future<void> initModem() async {
    await sendCommand('AT'); // проверка связи
    await sendCommand('ATE0'); // выключить эхо
    await sendCommand('AT+CMEE=2'); // текстовые ошибки
    await sendCommand('AT+CMGF=1'); // текстовый режим SMS
    await sendCommand('AT+CNMI=2,1,0,0,0'); // URC для новых SMS
  }

  // ---------------- Автоопределение AT-порта ----------------
  Future<String?> autoDetectPort() async {
    final ports = await _manager.getAvailablePorts();
    for (final p in ports) {
      SerialPort? test;
      try {
        test = await _manager.openPort(p.name, baudRate: 115200, dataBits: 8);
        await test.writeText('AT\r\n');
        final resp = await test.readUntil(
          '\n',
          timeout: const Duration(milliseconds: 1500),
        );
        if (resp.toString().contains('OK')) {
          await _manager.closePort(p.name);
          return p.name;
        }
        await _manager.closePort(p.name);
      } catch (_) {
        try {
          await _manager.closePort(p.name);
        } catch (_) {}
      }
    }
    return null;
  }

  // ---------------- Баланс через USSD ----------------
  Future<String> checkBalance(String ussdCode, String charset) async {
    await sendCommand('AT+CSCS="$charset"');

    final toSend = charset == 'UCS2' ? _toUcs2Hex(ussdCode) : ussdCode;
    final response = await sendCommand(
      'AT+CUSD=1,"$toSend",15',
      timeout: const Duration(seconds: 12),
      stopOnPrefix: '+CUSD:',
    );

    final ussdLine = response.firstWhere(
      (l) => l.startsWith('+CUSD:'),
      orElse: () => response.join('\n'),
    );

    if (ussdLine == response.join('\n')) {
      return ussdLine;
    }

    // +CUSD: <status>,"<text>",<dcs>
    final m = RegExp(r'\+CUSD:\s*(\d+)\s*,\s*"([^"]*)"').firstMatch(ussdLine);
    if (m == null) return ussdLine;
    final status = int.parse(m.group(1)!);
    final text = m.group(2)!;
    final decoded = charset == 'UCS2' ? _fromUcs2Hex(text) : text;

    if (status == 1) {
      return 'USSD ждет ответа: $decoded\n(подтвердите ввод дополнительной командой)';
    }
    return decoded;
  }

  // ---------------- SMS ----------------
  Future<List<SmsMessage>> listSms(String storage) async {
    await sendCommand('AT+CPMS="$storage"');
    final lines = await sendCommand(
      'AT+CMGL="ALL"',
      timeout: const Duration(seconds: 8),
    );

    final result = <SmsMessage>[];
    SmsMessage? current;
    for (final line in lines) {
      if (line.startsWith('+CMGL:')) {
        final parts = _splitCsv(line.substring(6));
        if (parts.length >= 2) {
          final idx = int.tryParse(parts[0].trim()) ?? 0;
          final status = parts[1].replaceAll('"', '');
          final from = parts.length > 2 ? parts[2].replaceAll('"', '') : '';
          final date = parts.length > 4 ? parts[4].replaceAll('"', '') : '';
          current = SmsMessage(
            index: idx,
            status: status,
            from: from,
            date: date,
            text: '',
          );
        }
      } else if (current != null &&
          line != 'OK' &&
          !line.startsWith('+CME') &&
          line != 'ERROR') {
        current = SmsMessage(
          index: current.index,
          status: current.status,
          from: current.from,
          date: current.date,
          text: line,
        );
        result.add(current);
        current = null;
      }
    }
    return result;
  }

  Future<void> deleteSms(int index, {bool all = false}) async {
    await sendCommand(all ? 'AT+CMGD=1,4' : 'AT+CMGD=$index');
  }

  Future<void> sendSms(String phone, String text, String charset) async {
    await sendCommand('AT+CSCS="$charset"');
    _log('>>', 'AT+CMGS="$phone"');
    await _port!.writeText('AT+CMGS="$phone"\r\n');

    // Ждем приглашение ">"
    final deadline = DateTime.now().add(const Duration(seconds: 5));
    bool gotPrompt = false;
    while (DateTime.now().isBefore(deadline)) {
      final line = await _readLine(timeout: const Duration(milliseconds: 500));
      if (line.contains('>')) {
        gotPrompt = true;
        break;
      }
      if (line.contains('ERROR')) throw Exception('Модем отверг номер: $line');
    }
    if (!gotPrompt) throw Exception('Нет приглашения ">"');

    final payload = charset == 'UCS2' ? _toUcs2Hex(text) : text;
    await _port!.writeText('$payload\x1A');

    final lines = await sendCommand('');
    if (lines.any((l) => l.startsWith('+CMGS:'))) {
      _log('<<', 'SMS отправлено');
    } else if (lines.any((l) => l.contains('ERROR'))) {
      throw Exception('Ошибка отправки: ${lines.join(' ')}');
    }
  }

  // ---------------- Сеть и сигнал ----------------
  Future<int?> getSignal() async {
    final lines = await sendCommand('AT+CSQ');
    for (final l in lines) {
      final m = RegExp(r'\+CSQ:\s*(\d+)').firstMatch(l);
      if (m != null) return int.tryParse(m.group(1)!);
    }
    return null;
  }

  Future<String?> getOperator() async {
    final lines = await sendCommand('AT+COPS?');
    for (final l in lines) {
      final m = RegExp(r'\+COPS:\s*\d+\s*,\s*\d+\s*,\s*"([^"]*)"').firstMatch(l);
      if (m != null) return m.group(1);
    }
    return null;
  }

  // ---------------- Утилиты кодирования ----------------
  String _toUcs2Hex(String s) {
    final buf = StringBuffer();
    for (final code in s.codeUnits) {
      buf.write(code.toRadixString(16).padLeft(4, '0').toUpperCase());
    }
    return buf.toString();
  }

  String _fromUcs2Hex(String hex) {
    try {
      final bytes = <int>[];
      for (var i = 0; i + 4 <= hex.length; i += 4) {
        final cu = int.parse(hex.substring(i, i + 4), radix: 16);
        bytes.addAll([cu >> 8, cu & 0xFF]);
      }
      return utf8.decode(bytes, allowMalformed: true);
    } catch (_) {
      return hex;
    }
  }

  List<String> _splitCsv(String s) {
    final out = <String>[];
    final buf = StringBuffer();
    bool inQuote = false;
    for (var i = 0; i < s.length; i++) {
      final c = s[i];
      if (c == '"') inQuote = !inQuote;
      if (c == ',' && !inQuote) {
        out.add(buf.toString());
        buf.clear();
      } else {
        buf.write(c);
      }
    }
    out.add(buf.toString());
    return out;
  }

  void dispose() {
    close();
    _urcController.close();
    _logController.close();
  }
}
