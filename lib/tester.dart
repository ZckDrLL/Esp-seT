// lib/tester.dart
import 'package:flutter/material.dart';

/// Простая глобальная нотация режима разработчика.
/// Используем ValueNotifier чтобы UI могла легко подписываться на изменения.
final ValueNotifier<bool> devMode = ValueNotifier<bool>(false);

/// Примерный ответ / статус (используется, когда devMode == true)
Map<String, dynamic> sampleMasterInfo() {
  return {
    "masterKnown": true,
    "isConnected": true,
    "hasData": false,
    "receivedData": "none",
    "foundSlaveMac": "AA:BB:CC:DD:EE:01",
    "slaveCount": 1,
    "slaves": ["AA:BB:CC:DD:EE:01"]
  };
}

/// Симуляция отправки — возвращаем "успешно" строкой, без фактического HTTP.
Future<String> simulateSend(String what) async {
  await Future.delayed(const Duration(milliseconds: 250));
  return "Отправлено в режиме разработчика";
}
