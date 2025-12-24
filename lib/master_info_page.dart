import 'package:flutter/material.dart';
import 'esp32_manager.dart';

class MasterInfoPage extends StatefulWidget {
  final Esp32Manager manager;
  const MasterInfoPage({super.key, required this.manager});

  @override
  State<MasterInfoPage> createState() => _MasterInfoPageState();
}

class _MasterInfoPageState extends State<MasterInfoPage> {
  Map<String, dynamic>? info;
  String? error;
  bool loading = true;

  // Новые контроллеры для UI (MAC вместо SSID)
  late TextEditingController slaveMacController;
  late TextEditingController slaveIpController;

  @override
  void initState() {
    super.initState();
    slaveMacController = TextEditingController();
    slaveIpController = TextEditingController();
    _load();
  }

  @override
  void dispose() {
    slaveMacController.dispose();
    slaveIpController.dispose();
    super.dispose();
  }

Future<void> _load() async {
  setState(() {
    loading = true;
    error = null;
  });

  Map<String, dynamic>? fetched;
  Object? caughtError;

  try {
    fetched = await widget.manager.fetchMasterInfo();
  } catch (e) {
    caughtError = e;
  }

  // После await: проверяем mounted один раз и обновляем состояние атомарно
  if (!mounted) return;

  setState(() {
    if (fetched != null) {
      info = fetched;
      error = null;
    } else {
      // если был error — превратим его в строку
      info = null;
      error = caughtError?.toString();
    }
    loading = false;
  });
}

  // Проверка IPv4 (строгая: каждый октет 0..255)
  bool _isValidIPv4(String ip) {
    final parts = ip.split('.');
    if (parts.length != 4) return false;
    for (final p in parts) {
      final n = int.tryParse(p);
      if (n == null) return false;
      if (n < 0 || n > 255) return false;
    }
    return true;
  }

  // Показ диалога с копируемым текстом
  Future<void> _showResultDialog(String title, String message) async {
    if (!mounted) return;
    await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(title),
        content: SizedBox(
          width: double.maxFinite,
          child: SelectableText(message),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('OK')),
        ],
      ),
    );
  }

  // Диалог подтверждения
  Future<bool> _confirm(String title, String text) async {
    if (!mounted) return false;
    final res = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(text),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Отмена')),
          TextButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Продолжить')),
        ],
      ),
    );
    return res == true;
  }

  // Выполнение назначения IP: вызывает assignSlaveIp у менеджера
// helper: строгая проверка MAC в формате AA:BB:CC:DD:EE:FF
  // Проверка MAC (принимает AA:BB:CC:DD:EE:FF или AABBCCDDEEFF)
  bool _isValidMac(String mac) {
    final macClean = mac.replaceAll(RegExp(r'[^A-Fa-f0-9]'), '');
    if (macClean.length != 12) return false;
    return RegExp(r'^[A-Fa-f0-9]{12}$').hasMatch(macClean);
  }


// Выполнение назначения IP: вызывает assignSlaveIp у менеджера (MAC, IP)
Future<void> _assignIp() async {
  final mac = slaveMacController.text.trim();
  final ip = slaveIpController.text.trim();

  if (mac.isEmpty) {
    await _showResultDialog('Ошибка', 'Введите MAC слейва.');
    return;
  }
  if (!_isValidMac(mac)) {
    await _showResultDialog('Ошибка', 'Введите корректный MAC (AA:BB:CC:DD:EE:FF или AABBCCDDEEFF).');
    return;
  }
  if (!_isValidIPv4(ip)) {
    await _showResultDialog('Ошибка', 'Введите корректный IPv4 в формате 192.168.x.x (0-255).');
    return;
  }

  final ok = await _confirm('Подтвердить', 'Назначить IP $ip слейву с MAC "$mac"?\nЭто перезапишет старую привязку и пошлёт команду перезагрузки.');
  if (!ok) return;

  if (!mounted) return; // гарантируем, что виджет ещё в дереве

  // Показать spinner
  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (_) => const Center(child: CircularProgressIndicator()),
  );

  // ВАЖНО: сразу после await нужно проверить mounted перед использованием context
  final result = await widget.manager.assignSlaveIp(slaveMac: mac, slaveIp: ip);

  if (!mounted) {
    // Если виджет уже удалён — больше не пытаемся управлять навигацией/контекстом
    return;
  }

  // Закрываем spinner безопасно
  if (Navigator.canPop(context)) Navigator.of(context).pop();

  await _showResultDialog('Результат', result);

  // Обновляем информацию с мастера (если нужно)
  if (!mounted) return;
  await _load();
}

  // Существующие кнопки: показать список MAC и сообщения
  void _showListDialog(String title, List<String> items) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(title),
        content: SizedBox(
          width: double.maxFinite,
          child: items.isEmpty ? const Text('Нет данных') : SelectableText(items.join('\n')),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Закрыть')),
        ],
      ),
    );
  }

  void _showMessagesDialog(String title, String message) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(title),
        content: SizedBox(width: double.maxFinite, child: SelectableText(message.isEmpty ? 'Сообщений нет' : message)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Закрыть')),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (loading) return const Center(child: CircularProgressIndicator());
    if (error != null) return Center(child: Text('Ошибка: $error'));
    if (info == null) return const Center(child: Text('Нет данных'));

    // Получаем "сырые" MAC из JSON и формируем список STA-MAC (эвристика: STA = AP - 1 по последнему байту)
List<String> normalizeMacList(List<dynamic>? raw) {
  if (raw == null) return <String>[];

  final Set<String> outSet = <String>{}; // уникальные значения

  for (final item in raw) {
    if (item == null) continue;
    String mac = item.toString().trim();

    // Оставляем только hex цифры
    final macClean = mac.replaceAll(RegExp(r'[^A-Fa-f0-9]'), '');
    if (macClean.length != 12) continue;

    try {
      // преобразуем в байты
      final bytes = List<int>.generate(
        6,
        (i) => int.parse(macClean.substring(i * 2, i * 2 + 2), radix: 16),
        growable: false,
      );

      // Эвристика: считаем, что incoming — AP, вычисляем STA = AP - 1 (последний байт - 1)
      final staBytes = List<int>.from(bytes);
      if (staBytes[5] > 0) {
        staBytes[5] = (staBytes[5] - 1) & 0xFF;
      } else {
        // если последний байт == 0 — подстраховка: оставляем как есть
        staBytes[5] = 0;
      }

      // Форматируем MAC в AA:BB:CC:DD:EE:FF верхним регистром
      final staMac = staBytes
          .map((b) => b.toRadixString(16).padLeft(2, '0'))
          .join(':')
          .toUpperCase();

      outSet.add(staMac);
    } catch (_) {
      // пропускаем невалидные
      continue;
    }
  }

  final List<String> out = outSet.toList();
  out.sort(); // детерминированный порядок
  return out;
}

// Вызов: получаем только STA-MAC'и (множество -> список)
final List<String> slaves = normalizeMacList((info!['slaves'] as List<dynamic>? ?? []));

    final int slaveCount = info!['slaveCount'] ?? 0;
    final String receivedData = info!['receivedData'] ?? '';

    // Если поле SSID пусто — попытаться подставить первый найденный SSID для удобства
    if (slaveMacController.text.isEmpty && slaves.isNotEmpty) {
      slaveMacController.text = slaves.first; // info['slaves'] содержит MAC-строки
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Поле SSID
          const Text('MAC подчинённого (целевой):', style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          TextField(
            controller: slaveMacController,
            decoration: InputDecoration(
              hintText: 'Введите MAC слейва (например AA:BB:CC:DD:EE:FF)',
              filled: true,
              fillColor: const Color(0xFFF7FBFF),
              contentPadding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
              enabledBorder: const UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFFBDBDBD))),
              focusedBorder: const UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFF2196F3), width: 2)),
            ),
          ),

          const SizedBox(height: 16),

          // Поле IP
          const Text('Новый IP для подчинённого:', style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          TextField(
            controller: slaveIpController,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              hintText: '192.168.x.x',
              filled: true,
              fillColor: const Color(0xFFF7FBFF),
              contentPadding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
              enabledBorder: const UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFFBDBDBD))),
              focusedBorder: const UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFF2196F3), width: 2)),
            ),
          ),

          const SizedBox(height: 12),

          // Кнопка назначения
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _assignIp,
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF32E3FE), foregroundColor: Colors.white),
              child: const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text('Назначить IP и перезагрузить слейв'),
              ),
            ),
          ),

          const SizedBox(height: 20),

          // Существующие кнопки (MAC, сообщения)
          ElevatedButton.icon(
            icon: const Icon(Icons.memory),
            label: const Text('Показать найденные MAC-адреса'),
            onPressed: () => _showListDialog('Найденные MAC-адреса (STA)', slaves),
          ),
          const SizedBox(height: 12),

          ElevatedButton.icon(
            icon: const Icon(Icons.message),
            label: const Text('Показать сообщения от подчинённых'),
            onPressed: () => _showMessagesDialog('Полученные сообщения', receivedData),
          ),

          const SizedBox(height: 24),

          Center(
            child: Text(
              'Подключено подчинённых: $slaveCount',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.grey),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Информация мастера'),
        backgroundColor: const Color(0xFF6BEBFF),
        foregroundColor: const Color(0xFFFFFFFF),
      ),
      body: _buildBody(),
    );
  }
}
