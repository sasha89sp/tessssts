import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models.dart';
import '../modem_service.dart';
import 'settings_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with SingleTickerProviderStateMixin {
  final _modem = ModemService();
  final _settings = ModemSettings();

  late TabController _tabs;
  final List<LogEntry> _logs = [];
  final List<SmsMessage> _sms = [];
  StreamSubscription? _urcSub, _logSub;

  String _balance = 'Нажмите «Проверить баланс»';
  String _status = 'Не подключено';
  int? _signal;
  String? _operator;
  bool _busy = false;

  // Поля отправки SMS
  final _toCtrl = TextEditingController();
  final _textCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this);
    _loadSettings();
    _logSub = _modem.logStream.listen((e) {
      if (!mounted) return;
      setState(() {
        _logs.add(e);
        if (_logs.length > 500) _logs.removeAt(0);
      });
    });
    _urcSub = _modem.urcStream.listen((urc) {
      if (urc.startsWith('+CMTI:')) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('📩 Новое SMS')),
          );
        }
      }
    });
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _settings.port = prefs.getString('port') ?? 'COM40';
      _settings.ussdCode = prefs.getString('ussd') ?? '*100#';
      _settings.charset = prefs.getString('charset') ?? 'UCS2';
      _settings.smsStorage = prefs.getString('storage') ?? 'ME';
    });
  }

  Future<void> _saveSettings(ModemSettings s) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('port', s.port);
    await prefs.setString('ussd', s.ussdCode);
    await prefs.setString('charset', s.charset);
    await prefs.setString('storage', s.smsStorage);
    setState(() {
      _settings.port = s.port;
      _settings.ussdCode = s.ussdCode;
      _settings.charset = s.charset;
      _settings.smsStorage = s.smsStorage;
    });
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _connect() => _run(() async {
        await _modem.open(_settings.port);
        setState(() => _status = 'Подключено: ${_settings.port}');
        await _refreshNetwork();
      });

  Future<void> _autoDetect() => _run(() async {
        final p = await _modem.autoDetectPort();
        if (p == null) {
          setState(() => _status = 'AT-порт не найден');
          return;
        }
        _settings.port = p;
        await _saveSettings(_settings);
        await _modem.open(p);
        setState(() => _status = 'Подключено: $p');
        await _refreshNetwork();
      });

  Future<void> _refreshNetwork() async {
    _signal = await _modem.getSignal();
    _operator = await _modem.getOperator();
    if (mounted) setState(() {});
  }

  Future<void> _checkBalance() => _run(() async {
        final r = await _modem.checkBalance(_settings.ussdCode, _settings.charset);
        setState(() => _balance = r);
      });

  Future<void> _loadSms() => _run(() async {
        final list = await _modem.listSms(_settings.smsStorage);
        setState(() {
          _sms
            ..clear()
            ..addAll(list);
        });
      });

  Future<void> _sendSms() => _run(() async {
        if (_toCtrl.text.isEmpty || _textCtrl.text.isEmpty) {
          throw 'Заполните номер и текст';
        }
        await _modem.sendSms(_toCtrl.text.trim(), _textCtrl.text, _settings.charset);
        _textCtrl.clear();
        await _loadSms();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('✅ SMS отправлено')),
        );
      });

  @override
  void dispose() {
    _urcSub?.cancel();
    _logSub?.cancel();
    _tabs.dispose();
    _modem.dispose();
    _toCtrl.dispose();
    _textCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Huawei E173 Manager'),
        bottom: TabBar(
          controller: _tabs,
          tabs: const [
            Tab(icon: Icon(Icons.account_balance_wallet), text: 'Баланс'),
            Tab(icon: Icon(Icons.sms), text: 'SMS'),
            Tab(icon: Icon(Icons.terminal), text: 'Лог / Сеть'),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => SettingsScreen(
                  settings: _settings,
                  onSave: _saveSettings,
                ),
              ),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          _buildStatusBar(),
          if (_busy) const LinearProgressIndicator(),
          Expanded(
            child: TabBarView(
              controller: _tabs,
              children: [
                _tabBalance(),
                _tabSms(),
                _tabLog(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusBar() {
    return Material(
      color: Colors.blueGrey.shade50,
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Row(
          children: [
            Icon(
              _modem.isOpen ? Icons.usb : Icons.usb_off,
              color: _modem.isOpen ? Colors.green : Colors.grey,
            ),
            const SizedBox(width: 8),
            Expanded(child: Text(_status)),
            if (_operator != null)
              Chip(label: Text(_operator!), visualDensity: VisualDensity.compact),
            const SizedBox(width: 4),
            if (_signal != null)
              Text('📶 $_signal/31', style: const TextStyle(fontSize: 12)),
            const SizedBox(width: 8),
            if (!_modem.isOpen)
              ElevatedButton(onPressed: _busy ? null : _connect, child: const Text('Открыть')),
            if (!_modem.isOpen)
              const SizedBox(width: 4),
            if (!_modem.isOpen)
              OutlinedButton(onPressed: _busy ? null : _autoDetect, child: const Text('Авто')),
          ],
        ),
      ),
    );
  }

  Widget _tabBalance() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _busy || !_modem.isOpen ? null : _checkBalance,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Проверить баланс'),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                tooltip: 'Обновить сигнал',
                onPressed: _busy || !_modem.isOpen ? null : () => _run(_refreshNetwork),
                icon: const Icon(Icons.network_check),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text('USSD-код: ${_settings.ussdCode}  (${_settings.charset})',
              style: const TextStyle(color: Colors.grey)),
          const SizedBox(height: 8),
          Expanded(
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey.shade300),
                borderRadius: BorderRadius.circular(8),
              ),
              child: SingleChildScrollView(
                child: SelectableText(
                  _balance,
                  style: const TextStyle(fontSize: 16),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _tabSms() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _toCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Номер',
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton.icon(
                onPressed: _busy || !_modem.isOpen ? null : _sendSms,
                icon: const Icon(Icons.send),
                label: const Text('Отправить'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _textCtrl,
            maxLines: 2,
            decoration: const InputDecoration(
              labelText: 'Текст SMS',
              border: OutlineInputBorder(),
              isDense: true,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              ElevatedButton.icon(
                onPressed: _busy || !_modem.isOpen ? null : _loadSms,
                icon: const Icon(Icons.download),
                label: const Text('Загрузить'),
              ),
              const SizedBox(width: 8),
              TextButton(
                onPressed: _busy || !_modem.isOpen
                    ? null
                    : () => _run(() async {
                          await _modem.deleteSms(0, all: true);
                          await _loadSms();
                        }),
                child: const Text('Удалить все'),
              ),
              const Spacer(),
              Text('Память: ${_settings.smsStorage}',
                  style: const TextStyle(color: Colors.grey, fontSize: 12)),
            ],
          ),
          const Divider(),
          Expanded(
            child: ListView.builder(
              itemCount: _sms.length,
              itemBuilder: (_, i) {
                final m = _sms[i];
                return Card(
                  child: ListTile(
                    title: Text('${m.from} • ${m.date}',
                        style: const TextStyle(fontSize: 13)),
                    subtitle: Text(m.text),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete_outline),
                      onPressed: _busy || !_modem.isOpen
                          ? null
                          : () => _run(() async {
                                await _modem.deleteSms(m.index);
                                await _loadSms();
                              }),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _tabLog() {
    return Container(
      color: Colors.black87,
      padding: const EdgeInsets.all(8),
      child: ListView.builder(
        itemCount: _logs.length,
        itemBuilder: (_, i) {
          final e = _logs[i];
          final color = e.direction == '>>'
              ? Colors.cyanAccent
              : e.direction == '!!'
                  ? Colors.redAccent
                  : Colors.greenAccent;
          return SelectableText(
            e.toString(),
            style: TextStyle(
              fontFamily: 'monospace',
              color: color,
              fontSize: 12,
            ),
          );
        },
      ),
    );
  }
}
