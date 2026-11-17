import 'package:flutter/material.dart';
import '../models.dart';

class SettingsScreen extends StatefulWidget {
  final ModemSettings settings;
  final Future<void> Function(ModemSettings) onSave;
  const SettingsScreen({super.key, required this.settings, required this.onSave});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late TextEditingController _port;
  late TextEditingController _ussd;
  late String _charset;
  late String _storage;

  @override
  void initState() {
    super.initState();
    _port = TextEditingController(text: widget.settings.port);
    _ussd = TextEditingController(text: widget.settings.ussdCode);
    _charset = widget.settings.charset;
    _storage = widget.settings.smsStorage;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Настройки')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: ListView(
          children: [
            TextField(
              controller: _port,
              decoration: const InputDecoration(
                labelText: 'COM-порт (AT)',
                hintText: 'COM40',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _ussd,
              decoration: const InputDecoration(
                labelText: 'USSD-код оператора',
                hintText: '*100#',
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: _charset,
              decoration: const InputDecoration(labelText: 'Кодировка'),
              items: const [
                DropdownMenuItem(value: 'UCS2', child: Text('UCS2 (рекомендуется)')),
                DropdownMenuItem(value: 'GSM', child: Text('GSM')),
              ],
              onChanged: (v) => setState(() => _charset = v!),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: _storage,
              decoration: const InputDecoration(labelText: 'Память SMS'),
              items: const [
                DropdownMenuItem(value: 'ME', child: Text('Модем (ME)')),
                DropdownMenuItem(value: 'SM', child: Text('SIM (SM)')),
              ],
              onChanged: (v) => setState(() => _storage = v!),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () async {
                await widget.onSave(ModemSettings(
                  port: _port.text.trim(),
                  ussdCode: _ussd.text.trim(),
                  charset: _charset,
                  smsStorage: _storage,
                ));
                if (mounted) Navigator.pop(context);
              },
              child: const Text('Сохранить'),
            ),
          ],
        ),
      ),
    );
  }
}
