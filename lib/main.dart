import 'package:flutter/material.dart';
import 'esp32_manager.dart';
import 'web_version_page.dart';
import 'master_info_page.dart';
import 'tester.dart';
import 'widgets/icon_toggle_switch.dart';

void main() {
  runApp(const Esp32NatRouterApp());
}

class Esp32NatRouterApp extends StatelessWidget {
  const Esp32NatRouterApp({super.key});

  @override
  Widget build(BuildContext context) {
    const Color brandBlue = Color(0xFF32E3FE); // ваш синий

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        // общий primary (опционально)
        primaryColor: brandBlue,

        // Настройки выделения и каретки
        textSelectionTheme: TextSelectionThemeData(
          cursorColor: brandBlue,                 // цвет каретки (палочка)
          selectionColor: brandBlue.withValues(), // заливка выделенного текста
          selectionHandleColor: const Color(0xDF6EADFF),        // цвет "капли" (handles)
        ),
        // Если хотите, можно также настроить colorScheme для кнопок тулбара коп/вставить
        colorScheme: ColorScheme.fromSwatch().copyWith(primary: const Color(0xFF5EA1D4)),
      ),
      home: HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final Esp32Manager esp32Manager = Esp32Manager(serverUrl: 'http://192.168.4.1');

  bool isChecking = false;
  bool serverAvailable = false;
  String statusText = 'Сервер не проверен';

  TextEditingController apSsidController = TextEditingController();
  TextEditingController apPasswordController = TextEditingController();
  TextEditingController ssidController = TextEditingController();
  TextEditingController passwordController = TextEditingController();
  // Контрол для ввода IP (например "192.168.4.1")
  late TextEditingController ipController;

  @override
  void initState() {
    super.initState();
    // Инициализируем контрол для IP — извлекаем host без http://
    ipController = TextEditingController(text: _extractHost(esp32Manager.serverUrl));
  }

  @override
  void dispose() {
    // освобождаем ipController + уже существующие контроллеры (если у вас их ещё не деспозят)
    ipController.dispose();
    apSsidController.dispose();
    apPasswordController.dispose();
    ssidController.dispose();
    passwordController.dispose();
    super.dispose();
  }

  // Вспомогательная функция: забирает host из 'http://192.168.4.1' -> '192.168.4.1'
  String _extractHost(String url) {
    return url.replaceFirst(RegExp(r'^https?://'), '');
  }

  // Проверка доступности сервера
  Future<void> checkServer() async {
    setState(() {
      isChecking = true;
      statusText = 'Проверка сервера...';
      serverAvailable = false;
    });

    final available = await esp32Manager.checkServer();

    if (!mounted) return;
    setState(() {
      serverAvailable = available;
      statusText = available ? '' : 'Сервер недоступен';
      isChecking = false;
    });
  }

  // Упаковка отображения результата в диалог с возможностью копирования
  Future<void> _showResultDialog(String title, String message) async {
    if (!mounted) return;
    await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(title),
        content: SelectableText(message),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('OK')),
        ],
      ),
    );
  }

  // Открытие меню настроек
  void openSettingsMenu() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        titlePadding: EdgeInsets.zero,
        title: ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
          child: Container(
            height: 56,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              color: const Color(0xFF6BEBFF),
            ),
            child: Row(
              children: [
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert, color: Colors.white),
                onSelected: (value) async {
                  if (value == 'reboot') {
                    final ok = await showDialog<bool>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: const Text('Перезагрузить контроллер?'),
                        content: const Text('Вы уверены, что хотите перезагрузить контроллер?'),
                        actions: [
                          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Отмена')),
                          TextButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Перезагрузить')),
                        ],
                      ),
                    );
                    if (ok == true) {
                      final res = await esp32Manager.rebootController();
                      await _showResultDialog('Результат', res);
                    }
                    return;
                  } else if (value == 'reset') {
                    final ok = await showDialog<bool>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: const Text('Сброс параметров'),
                        content: const Text('Это действие обнулит все сетевые параметры и перезагрузит устройство. Продолжить?'),
                        actions: [
                          TextButton(onPressed: () => Navigator.of(ctx).pop(false),  child: const Text('Отмена')),
                          TextButton(onPressed: () => Navigator.of(ctx).pop(true),  child: const Text('Сбросить')),
                        ],
                      ),
                    );
                    if (ok == true) {
                      final res = await esp32Manager.resetParameters();
                      await _showResultDialog('Результат', res);
                    }
                    return;
} else if (value == 'web') {
  if (devMode.value) {
    // В режиме разработчика — недоступно
    await _showResultDialog('Недоступно', 'Веб-версия недоступна в режиме разработчика');
    return;
  }
  if (!mounted) return;
  Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => WebVersionPage(
        url: esp32Manager.serverUrl,
      ),
    ),
  );
  return;
} else if (value == 'master_info') {
                    if (!mounted) return;
                    Navigator.of(context).pop(); // закрыть диалог настроек
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => MasterInfoPage(manager: esp32Manager)),
                    );
                    return;
                  }
                },
                // itemBuilder формирует список пунктов условно — показываем master_info только если host == 192.168.4.1
                itemBuilder: (ctx) {
                  // получаем host (без схемы); _extractHost доступен в State
                  final String host = _extractHost(esp32Manager.serverUrl);
                  final bool showMasterInfo = (host == '192.168.4.1') || devMode.value;

                  final List<PopupMenuEntry<String>> items = [];

                  if (showMasterInfo) {
                    items.add(
                      PopupMenuItem<String>(
                        value: 'master_info',
                        child: Text('Инфо мастера', style: TextStyle(color: Colors.grey[700])),
                      ),
                    );
                  }

                  items.addAll([
                    PopupMenuItem<String>(
                      value: 'reboot',
                      child: Text('Перезагрузить контроллер', style: TextStyle(color: Colors.grey[700])),
                    ),
                    PopupMenuItem<String>(
                      value: 'reset',
                      child: Text('Сбросить параметры', style: TextStyle(color: Colors.grey[700])),
                    ),
                    PopupMenuItem<String>(
                      value: 'web',
                      child: Text('Веб-версия', style: TextStyle(color: Colors.grey[700])),
                    ),
                  ]);

                  return items;
                },
              ),
                const Expanded(
                  child: Center(
                    child: Text(
                      "Настройка сети",
                      style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, size: 20, color: Colors.white),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),
        ),
      contentPadding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      content: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.60,
          maxWidth: MediaQuery.of(context).size.width * 0.95,
        ),
        // ---- Заменили Scrollbar на RawScrollbar с белым thumb ----
        child: RawScrollbar(
          padding: const EdgeInsets.only(right: -10),

          thumbVisibility: true,
          // Цвет полосы прокрутки (белый)
          thumbColor: Colors.white,
          // Толщина полосы (подберите под дизайн)
          thickness: 2.0,
          // Сглаженные края
          radius: const Radius.circular(6),
          // Плавное перехватывание ввода при прокрутке
          interactive: true,
          
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // AP группа
                Align(alignment: Alignment.centerLeft, child: Text('AP SSID', style: TextStyle(color: Colors.grey[700]))),
                const SizedBox(height: 6),
                TextField(
                  controller: apSsidController,
                  cursorColor: Colors.blue, 
                  style: TextStyle(color: Colors.grey[700]),            // <-- цвет текста
                  decoration: InputDecoration(
                    hintText: 'AP SSID',
                    hintStyle: TextStyle(color: Colors.grey[500]),      // <-- цвет placeholder
                    filled: true,
                    fillColor: const Color(0xFFF7FBFF),

                      // Линия под полем (не в фокусе)
                    enabledBorder: const UnderlineInputBorder(
                    borderSide: BorderSide(color: Color(0xFF1A73BD)),
                    ),

                      // Линия под полем (в фокусе)
                    focusedBorder: const UnderlineInputBorder(
                    borderSide: BorderSide(color: Color(0xFF2196F3), width: 2),
                    ),
                    ),
                  ),

                const SizedBox(height: 12),
                Align(alignment: Alignment.centerLeft, child: Text('AP Password', style: TextStyle(color: Colors.grey[700]))),
                const SizedBox(height: 6),
                TextField(
                  controller: apPasswordController,
                  cursorColor: Colors.blue, 
                  style: TextStyle(color: Colors.grey[700]),            // <-- цвет текста
                  decoration: InputDecoration(
                    hintText: 'AP Password',
                    hintStyle: TextStyle(color: Colors.grey[500]),      // <-- цвет placeholder
                    filled: true,
                    fillColor: const Color(0xFFF7FBFF),

                          // Линия под полем (не в фокусе)
                    enabledBorder: const UnderlineInputBorder(
                    borderSide: BorderSide(color: Color(0xFF1A73BD)),
                    ),

                      // Линия под полем (в фокусе)
                    focusedBorder: const UnderlineInputBorder(
                    borderSide: BorderSide(color: Color(0xFF2196F3), width: 2),
                    ),
                    ),
                  ),

                const SizedBox(height: 10),

                // Кнопка отправки AP
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () async {
                          final ok = await showDialog<bool>(
                            context: context,
                            builder: (ctx) => AlertDialog(
                              title: const Text('Отправить AP-параметры?'),
                              content: const Text('Отправить AP SSID и AP Password на устройство?'),
                              actions: [
                                TextButton(onPressed: () => Navigator.of(ctx).pop(false),  child: const Text('Отмена')),
                                TextButton(onPressed: () => Navigator.of(ctx).pop(true),  child: const Text('Отправить')),
                              ],
                            ),
                          );
                          if (ok == true) {
                            final res = await esp32Manager.sendApSettings(
                              apSsid: apSsidController.text,
                              apPassword: apPasswordController.text,
                            );
                            await _showResultDialog('Результат', res);
                          }
                        },
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.white, foregroundColor: const Color(0xFF32E3FE)),
                        child: const Text('Отправить AP'),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 18),

                // STA группа
                Align(alignment: Alignment.centerLeft, child: Text('STA SSID', style: TextStyle(color: Colors.grey[700]))),
                const SizedBox(height: 6),
                TextField(
                  controller: ssidController,
                  cursorColor: Colors.blue, 
                  style: TextStyle(color: Colors.grey[700]),            // <-- цвет текста
                  decoration: InputDecoration(
                    hintText: 'STA SSID',
                    hintStyle: TextStyle(color: Colors.grey[500]),      // <-- цвет placeholder
                    filled: true,
                    fillColor: const Color(0xFFF7FBFF),

                          // Линия под полем (не в фокусе)
                    enabledBorder: const UnderlineInputBorder(
                    borderSide: BorderSide(color: Color(0xFF1A73BD)),
                    ),

                      // Линия под полем (в фокусе)
                    focusedBorder: const UnderlineInputBorder(
                    borderSide: BorderSide(color: Color(0xFF2196F3), width: 2),
                    ),
                    ),
                  ),
                const SizedBox(height: 12),
                Align(alignment: Alignment.centerLeft, child: Text('STA Password', style: TextStyle(color: Colors.grey[700]))),
                const SizedBox(height: 6),
                TextField(
                  controller: passwordController,
                  cursorColor: Colors.blue, 
                  style: TextStyle(color: Colors.grey[700]),            // <-- цвет текста
                  decoration: InputDecoration(
                    hintText: 'STA Password',
                    hintStyle: TextStyle(color: Colors.grey[500]),      // <-- цвет placeholder
                    filled: true,
                    fillColor: const Color(0xFFF7FBFF),

                          // Линия под полем (не в фокусе)
                    enabledBorder: const UnderlineInputBorder(
                    borderSide: BorderSide(color: Color(0xFF1A73BD)),
                    ),

                      // Линия под полем (в фокусе)
                    focusedBorder: const UnderlineInputBorder(
                    borderSide: BorderSide(color: Color(0xFF2196F3), width: 2),
                    ),
                    ),
                  ),

                const SizedBox(height: 10),

                // Кнопка отправки STA
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton(
                       onPressed: () async {
                        final ssidValue = ssidController.text.trim();
                        if (ssidValue.isEmpty) {
                          if (!mounted) return;
                          await showDialog(
                            context: context,
                            builder: (ctx) => AlertDialog(
                              title: const Text('Пустой SSID'),
                              content: const Text('Поле STA SSID не должно быть пустым.'),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.of(ctx).pop(),
                                  style: TextButton.styleFrom(foregroundColor: Colors.blue),
                                  child: const Text('OK'),
                                ),
                              ],
                            ),
                          );
                          return;
                        }

                        final ok = await showDialog<bool>(
                          context: context,
                          builder: (ctx) => AlertDialog(
                            title: const Text('Отправить STA-параметры?'),
                            content: const Text('Отправить STA SSID и STA Password на устройство?'),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.of(ctx).pop(false),
                                style: TextButton.styleFrom(foregroundColor: Colors.blue),
                                child: const Text('Отмена'),
                              ),
                              TextButton(
                                onPressed: () => Navigator.of(ctx).pop(true),
                                style: TextButton.styleFrom(foregroundColor: Colors.blue),
                                child: const Text('Отправить'),
                              ),
                            ],
                          ),
                        );

                        if (ok != true) return;
                        if (!mounted) return;

                        // spinner
                        showDialog(
                          context: context,
                          barrierDismissible: false,
                          builder: (_) => const Center(child: CircularProgressIndicator()),
                        );

                        final res = await esp32Manager.sendStaSettings(
                          ssid: ssidValue,
                          password: passwordController.text,
                        );

                        if (!mounted) return;

                        Navigator.of(context).pop(); // закрываем spinner
                        await _showResultDialog('Результат', res);
                      },
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.white, foregroundColor: const Color(0xFF32E3FE)),
                        child: const Text('Отправить STA'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
      )
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
appBar: AppBar(
  title: const Text('ESP32 MANAGER'),
  backgroundColor: const Color(0xFF6BEBFF),
  foregroundColor: const Color(0xFFFFFFFF),
  centerTitle: true,
  actions: [
    IconButton(
      icon: const Icon(Icons.settings),
      onPressed: () {
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const SettingsPage()),
        );
      },
      tooltip: 'Настройки',
    ),
  ],
),
      body: RefreshIndicator(
        onRefresh: checkServer,
        color: const Color(0xFF6BEBFF),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: ListView(
            children: [
              ValueListenableBuilder<bool>(
                valueListenable: devMode,
                builder: (ctx, dev, _) {
                  if (!serverAvailable && !dev) return const SizedBox.shrink();
                  return SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: openSettingsMenu,
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.white, foregroundColor: const Color(0xFF32E3FE)),
                      child: const Text('Настроить ESP'),
                    ),
                  );
                },
              ),
              const SizedBox(height: 30),
             // --- Поле ввода IP (широкое) и кнопка "Задать адрес" под ним ---
Column(
  crossAxisAlignment: CrossAxisAlignment.stretch,
  children: [
Column(
  crossAxisAlignment: CrossAxisAlignment.center,
  children: [
    // Надпись над полем (выровнена по центру)
    Text(
      'IP устройства',
      textAlign: TextAlign.center,
      style: TextStyle(
        color: Colors.grey,
        fontSize: 14,
        fontWeight: FontWeight.w600,
      ),
    ),

    const SizedBox(height: 8),

    // Само поле ввода (узкое и по центру)
    Align(
      alignment: Alignment.center,
      child: SizedBox(
        width: 330,
        child: TextField(
          controller: ipController,
          keyboardType: TextInputType.number,
          textAlign: TextAlign.center,
          decoration: InputDecoration(
            // label убран (метка над полем теперь отдельным Text)
            hintText: '192.168.x.x',
            hintStyle: TextStyle(color: Colors.grey[500]),
            isDense: true,
            filled: true,
            fillColor: const Color(0xFFF7FBFF),
            enabledBorder: const UnderlineInputBorder(
              borderSide: BorderSide(color: Color(0xFFBDBDBD)),
            ),
            focusedBorder: const UnderlineInputBorder(
              borderSide: BorderSide(color: Color(0xFF2196F3), width: 2),
            ),
            contentPadding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
          ),
        ),
      ),
    ),
  ],
),
const SizedBox(height: 8),
    SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: isChecking
            ? null
            : () async {
                final ip = ipController.text.trim();
                // простая валидация формата IPv4 (0-255 не проверяется строго)
                final ipRegex = RegExp(r'^(?:\d{1,3}\.){3}\d{1,3}$');
                if (!ipRegex.hasMatch(ip)) {
                  if (!mounted) return;
                  await showDialog(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: const Text('Неверный IP'),
                      content: const Text('Введите корректный IP в формате 192.168.x.x'),
                      actions: [
                        TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('OK')),
                      ],
                    ),
                  );
                  return;
                }

                final newUrl = 'http://$ip';

                // Показываем проверку
                setState(() {
                  isChecking = true;
                  statusText = 'Проверка сервера...';
                  serverAvailable = false;
                });

                // Устанавливаем новый URL и проверяем сервер
                esp32Manager.setServerUrl(newUrl);
                final available = await esp32Manager.checkServer();

                if (!mounted) return;
                setState(() {
                  serverAvailable = available;
                  statusText = available ? '' : 'Сервер недоступен';
                  isChecking = false;
                });
              },
        child: const Padding(
          padding: EdgeInsets.symmetric(vertical: 12),
          child: Text('Задать адрес'),
        ),
      ),
    ),
    const SizedBox(height: 12),
  ],
),
 // --- конец блока IP ---

              if (!isChecking && statusText.isNotEmpty)
                Center(child: Text(statusText, style: const TextStyle(fontSize: 18, color: Colors.grey))),
              const SizedBox(height: 250),
              if (isChecking)
                const Center(child: CircularProgressIndicator(valueColor: AlwaysStoppedAnimation<Color>(Color(0xC86BEBFF)))),
            ],
          ),
        ),
      ),
    );
  }
}

// Simple Settings page with Developer Mode switch
// Заменить/вставить этот класс вместо старого SettingsPage
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  // Текст предупреждения (показывается в диалоге при попытке переключить)
  String _devModeDescription(bool enabling) {
    if (enabling) {
      return 'Включение режима разработчика будет\n''имитировать функции, доступные при\n'
             'подключении к контроллеру «мастера»\n\n'
             'включить режим разработчика?';
    } else {
      return 'После выключения, вы снова сможете работать с контроллером.\n\nвыключить режим разработчика?';
    }
  }

// Обработчик запроса на переключение — безопасно использует context только после mounted check.
Future<void> _handleToggleRequest(bool newVal) async {
  // показываем диалог подтверждения и ждём результата
  final bool? confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) {
      return AlertDialog(
        title: Text(newVal ? 'Включить режим «Разработчика»?' : 'Выключить режим «Разработчика»?'),
        content: SingleChildScrollView(child: Text(_devModeDescription(newVal))),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Отмена')),
          TextButton(onPressed: () => Navigator.of(ctx).pop(true), child: Text(newVal ? 'Включить' : 'Выключить')),
        ],
      );
    },
  );

  // обязательно проверить mounted перед использованием context/ScaffoldMessenger/setState
  if (!mounted) return;

  if (confirmed == true) {
    devMode.value = newVal;
    // теперь безопасно используем context
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(newVal ? 'Режим разработчика включён' : 'Режим разработчика выключен')),
    );
    setState(() {}); // при необходимости обновляем UI
  } else {
    // если отмена — ничего не делаем (виджет останется в прежнем положении)
  }
}

  @override
  Widget build(BuildContext context) {
    // Используем ValueListenableBuilder чтобы UI обновлялся при изменении devMode
    return Scaffold(
      appBar: AppBar(
        title: const Text('Настройки'),
        backgroundColor: const Color(0xFF6BEBFF),
        foregroundColor: const Color(0xFFFFFFFF),
      ),
      body: Column(
        children: [
          const SizedBox(height: 8),
          // плитка с одним заголовком и переключателем справа
          ValueListenableBuilder<bool>(
            valueListenable: devMode,
            builder: (ctx, isDev, _) {
              return ListTile(
                title: const Text(
                  'Режим «Разработчика»',
                  // явный стиль чтобы текст был читабелен на белом фоне
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500, color: Colors.black87),
                ),
                // делаем switch заметным: активная полоса - голубая, кружок белый на ней
                trailing: IconToggleSwitch(
                value: isDev, // значение берётся из devMode.value
  onChanged: (newVal) => _handleToggleRequest(newVal),
                  // --- визуальные настройки: подогнанные под ваш скрин ---
                  width: 66,
                  height: 38,
                  activeTrackColor: const Color(0xFFD9F1FF),     // светло-голубой трек ON
                  inactiveTrackColor: const Color(0xFF2F3437),   // тёмный трек OFF
                  activeThumbInner: const Color(0xFF123A52),     // тёмный круг внутри ON
                  inactiveThumbInner: const Color(0xFF2F3437),   // темный круг OFF
                  thumbBorderColorOn: const Color(0xFF9AD1FF),   // border ON (можно скорректировать)
                  thumbBorderColorOff: const Color(0xFF9EA3A6),  // border OFF (светлее)
                  iconColorOn: Colors.white,
                  iconColorOff: Colors.white,
                ),
onTap: () => _handleToggleRequest(!isDev),
              );
            },
          ),
          // поместите этот блок сразу после ListTile с "Режим «Разработчика»"
          Container(
            height: 1.0,
            margin: const EdgeInsets.only(top: 8.0), // небольшой отступ сверху
            decoration: BoxDecoration(
              color: Colors.grey.shade200,            // тонкий, незаметный цвет
            ),
          ),
          // Информация перенесена в диалог — оставим пустое место/или краткую подсказку
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
          ),
        ],
      ),
    );
  }
}
