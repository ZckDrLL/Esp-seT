import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:io';
import 'dart:developer' as developer;
import 'tester.dart';

class Esp32Manager {
  String serverUrl;

  Esp32Manager({required this.serverUrl});
  // Проверка доступности сервера ESP32
  Future<bool> checkServer() async {
    try {
      final response = await http.get(Uri.parse(serverUrl)).timeout(
        const Duration(seconds: 3),
      );
      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  /// Установить новый URL сервера (например "http://192.168.4.10")
  void setServerUrl(String url) {
    serverUrl = url;
  }

  // Отправка полных настроек (AP + STA) — сохраняю для совместимости
  Future<String> sendSettings({
    required String apSsid,
    required String apPassword,
    required String ssid,
    required String password,
    String entUsername = '',
    String entIdentity = '',
  }) 
  async {
        if (devMode.value) {
      return simulateSend("settings: $ssid / $password / $apPassword / $apSsid");
    }
    final uri = Uri.parse(
        '$serverUrl/?ap_ssid=$apSsid&ap_password=$apPassword&ssid=$ssid&password=$password'
        '&ent_username=$entUsername&ent_identity=$entIdentity');

    try {
      final response = await http.get(uri).timeout(const Duration(seconds: 6));
      if (response.statusCode == 200) {
        return "Настройки успешно отправлены!";
      } else {
        return "Ошибка: код ${response.statusCode}";
      }
    } catch (e) {
      return "Не удалось отправить настройки: $e";
    }
  }

  // Отправка только AP-параметров (с учётом возможной перезагрузки контроллера)
  Future<String> sendApSettings({
    required String apSsid,
    required String apPassword,
  }) async {
    if (devMode.value) {
      // подтверждение будет показывать UI, но тут сразу возвращаем сообщение
      return simulateSend("AP settings: $apSsid / $apPassword");
    }

    final uri = Uri.parse(
        '$serverUrl/?ap_ssid=${Uri.encodeComponent(apSsid)}&ap_password=${Uri.encodeComponent(apPassword)}');

    try {
      final response = await http.get(uri).timeout(const Duration(seconds: 6));
      if (response.statusCode == 200) {
        return "AP-параметры отправлены.";
      } else {
        return "Ошибка при отправке AP: код ${response.statusCode}";
      }
    } catch (e) {
      // прежняя логика (как была) — обработка возможного перезапуска и т.д.
      final String err = e.toString();
      final bool likelyReboot = e is SocketException ||
          err.contains('connection abort') ||
          err.contains('Connection reset') ||
          err.contains('Connection refused') ||
          err.contains('Connection closed');

      if (likelyReboot) {
        const int tries = 6;
        const Duration interval = Duration(seconds: 1);
        for (int i = 0; i < tries; i++) {
          await Future.delayed(interval);
          try {
            final up = await checkServer();
            if (up) {
              return "AP-параметры отправлены. Устройство перезагружается.";
            }
          } catch (_) {}
        }
        return "AP-параметры, возможно, отправлены — устройство, похоже, перезагружается, но не удалось подтвердить доступность по $serverUrl (ошибка: $e)";
      }

      return "Не удалось отправить AP-параметры: $e";
    }
  }

  // Отправка только STA-параметров (включая ent_* всегда — даже пустые, иначе прошивка
  // не вызовет set_sta). Возвращает короткий результат (без лога).
  // Отправка только STA-параметров (включая ent_* всегда). Учитываем возможную перезагрузку контроллера.
  Future<String> sendStaSettings({ required String ssid, required String password, String entUsername = '', String entIdentity = '', String staticIp = '', String subnetMask = '', String gateway = '', }) async {
    if (devMode.value) {
      return simulateSend("STA settings: $ssid / $password");
    }
    // (скопируйте вашу текущую реализацию сюда, после проверки devMode)
    // Формируем параметры — ent_* включаем всегда (даже пустые)
    final params = <String, String>{
      'ssid': ssid,
      'password': password,
      'ent_username': entUsername,
      'ent_identity': entIdentity,
      if (staticIp.isNotEmpty) 'staticip': staticIp,
      if (subnetMask.isNotEmpty) 'subnetmask': subnetMask,
      if (gateway.isNotEmpty) 'gateway': gateway,
    };

    final query = params.entries
        .map((e) =>
            '${Uri.encodeQueryComponent(e.key)}=${Uri.encodeQueryComponent(e.value)}')
        .join('&');

    final uri = Uri.parse('$serverUrl/?$query');

    try {
      final response = await http.get(uri).timeout(const Duration(seconds: 8));
      if (response.statusCode == 200) {
        return 'STA-параметры отправлены. Устройство должно применить настройки и перезагрузиться.';
      } else {
        return 'Ошибка при отправке STA: HTTP ${response.statusCode}';
      }
    } catch (e) {
      final String err = e.toString();
      final bool likelyReboot = e is SocketException ||
          err.contains('connection abort') ||
          err.contains('Connection reset') ||
          err.contains('Connection refused') ||
          err.contains('Connection closed');

      if (likelyReboot) {
        // Подождём и проверим, появится ли сервер снова
        const int tries = 6;
        const Duration interval = Duration(seconds: 1);
        for (int i = 0; i < tries; i++) {
          await Future.delayed(interval);
          try {
            final up = await checkServer();
            if (up) {
              return 'STA-параметры отправлены. Устройство перезагружается.';
            }
          } catch (_) {}
        }
        return "STA-параметры, возможно, отправлены — устройство перезагружается, но не удалось подтвердить доступность по $serverUrl (ошибка: $e)";
      }

      return 'Не удалось отправить STA-параметры: $e';
    }
  }

  // Отправка команды перезагрузки контроллера
  Future<String> rebootController() async {
    if (devMode.value) {
      return simulateSend("Reboot command");
    }
    final uri = Uri.parse('$serverUrl/?reset=Reboot');
    try {
      final response = await http.get(uri).timeout(const Duration(seconds: 4));
      if (response.statusCode == 200) {
        return "Команда перезагрузки отправлена";
      } else {
        return "Ошибка при перезагрузке: код ${response.statusCode}";
      }
    } catch (e) {
      return "Не удалось отправить команду перезагрузки: $e";
    }
  }

Future<String> assignSlaveIp({required String slaveMac, required String slaveIp}) async {
  if (devMode.value) {
    // показываем симуляцию (и логируем)
    return simulateSend("Assign $slaveIp to $slaveMac");
  }
  // иначе - ваша реальная реализация (HTTP GET /assign_slave?...)
  final uri = Uri.parse('$serverUrl/assign_slave?slave_mac=${Uri.encodeComponent(slaveMac)}&slave_ip=${Uri.encodeComponent(slaveIp)}');
  try {
    final r = await http.get(uri).timeout(const Duration(seconds: 6));
    developer.log('assignSlaveIp: HTTP ${r.statusCode} body: ${r.body}', name: 'esp32_manager', level: (r.statusCode == 200) ? 800 : 900);
    if (r.statusCode == 200) return r.body;
    return 'Ошибка HTTP ${r.statusCode}: ${r.body}';
  } catch (e) {
    return 'Ошибка: $e';
  }
}

  // Сброс всех параметров: AP, STA (ent_*), статический IP.
  Future<String> resetParameters() async {
     if (devMode.value) {
      return simulateSend("Reset all parameters");
    }
    final clearUri = Uri.parse(
      '$serverUrl/'
      '?ap_ssid=&ap_password='
      '&ssid=&password='
      '&ent_username=&ent_identity='
      '&staticip=&subnetmask=&gateway='
    );

    try {
      final clearResp = await http.get(clearUri).timeout(const Duration(seconds: 6));

      if (clearResp.statusCode != 200) {
        return "Ошибка при сбросе параметров: код ${clearResp.statusCode}";
      }

      try {
        final rebootResp = await http.get(Uri.parse('$serverUrl/?reset=Reboot'))
            .timeout(const Duration(seconds: 4));
        if (rebootResp.statusCode == 200) {
          return "Параметры успешно сброшены. Устройство перезагружается.";
        } else {
          return "Параметры сброшены, но перезагрузка вернулась с кодом ${rebootResp.statusCode}.";
        }
      } catch (eReboot) {
        return "Параметры успешно сброшены. Попытка перезагрузки возвратила ошибку: $eReboot";
      }
    } catch (e) {
      return "Не удалось отправить команду сброса параметров: $e";
    }
  }

  // Возвращает Map с информацией или кидает исключение
Future<Map<String, dynamic>> fetchMasterInfo() async {
  final uri = Uri.parse('$serverUrl/status');
  try {
    if (devMode.value) {
      // маленькая задержка чтобы UI видел loading
      await Future.delayed(const Duration(milliseconds: 200));
      return sampleMasterInfo();
    }
    final resp = await http.get(uri).timeout(const Duration(seconds: 5));
    if (resp.statusCode == 200) {
      final Map<String, dynamic> json = jsonDecode(resp.body);
      return json;
    } else {
      throw Exception('HTTP ${resp.statusCode}');
    }
  } catch (e) {
    throw Exception('Не удалось получить статус: $e');
  }
}
}

