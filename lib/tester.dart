// lib/tester.dart
import 'package:flutter/material.dart';

/// Простая глобальная нотация режима разработчика.
/// Используем ValueNotifier чтобы UI могла легко подписываться на изменения.
final ValueNotifier<bool> devMode = ValueNotifier<bool>(false);

/// Примерный ответ / статус (используется, когда devMode == true)
Map<String, dynamic> sampleMasterInfo() {
  return {
    "selfNodeId": "APP_DEV",
    "masterKnown": true,
    "isConnected": true,
    "hasData": false,
    "receivedData": "none",
    "foundSlaveMac": "AA:BB:CC:DD:EE:01",
    "slaveCount": 2,
    "masterNodeId": "M_DEV-01",
    "knownNodeIds": ["M_DEV-01", "S_DEV-01", "S_DEV-02"],
    "knownNodes": [
      {
        "nodeId": "M_DEV-01",
        "role": "MASTER",
        "isMaster": true,
      },
      {
        "nodeId": "S_DEV-01",
        "role": "SLAVE",
        "isMaster": false,
      },
      {
        "nodeId": "S_DEV-02",
        "role": "SLAVE",
        "isMaster": false,
      },
    ],
    "slaves": ["AA:BB:CC:DD:EE:01", "AA:BB:CC:DD:EE:02"],
  };
}

/// Симуляция отправки — возвращаем "успешно" строкой, без фактического HTTP.
Future<String> simulateSend(String what) async {
  await Future.delayed(const Duration(milliseconds: 250));
  return "Отправлено в режиме разработчика";
}
