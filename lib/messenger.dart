import 'dart:async';
import 'package:flutter/material.dart';
import 'backendmess.dart';
import 'esp32_manager.dart';
import 'chat_history_store.dart';
import 'tester.dart';

class MessengerPage extends StatefulWidget {
  final Esp32Manager manager;

  const MessengerPage({super.key, required this.manager});

  @override
  State<MessengerPage> createState() => _MessengerPageState();
}

class _MessengerPageState extends State<MessengerPage> {
  final BackendMessBuilder _backendBuilder = BackendMessBuilder();

  bool loading = true;
  String? error;
  String? _selfNodeId;
  late String _serverIp;
  List<_ChatItem> chats = [];

  @override
  void initState() {
    super.initState();
    _serverIp = widget.manager.serverIp;
    _loadChats();
  }

  Future<void> _loadChats() async {
    setState(() {
      loading = true;
      error = null;
    });

    try {
      // всегда берем актуальный IP, а не старый кешированный
      _serverIp = widget.manager.serverIp;

      final info = await widget.manager.fetchMasterInfo();

      String normalize(dynamic raw) {
        final s = (raw ?? '').toString().trim();
        return s;
      }

      final String? selfNodeId = normalize(info['selfNodeId']).isEmpty
          ? null
          : normalize(info['selfNodeId']);

      await ChatHistoryStore.instance.ensureLoaded(_serverIp);

      try {
        final snapshot = await widget.manager.fetchChatSnapshot();
        if (snapshot != null) {
          await ChatHistoryStore.instance.mergeRemoteSnapshot(
            _serverIp,
            snapshot,
          );

          await widget.manager.ackChatSnapshot(snapshot);
        }
      } catch (_) {}

      final Set<String> seenNodeIds = <String>{};
      final Set<String> availableNowNodeIds = <String>{};
      final List<_ChatItem> loaded = [];

      void addChat(
        String nodeId, {
        bool isMaster = false,
        String? subtitle,
        bool isAvailableNow = false,
      }) {
        final cleanId = normalize(nodeId);
        if (cleanId.isEmpty) return;
        if (selfNodeId != null && cleanId == selfNodeId) return;
        if (seenNodeIds.contains(cleanId)) return;

        seenNodeIds.add(cleanId);

        if (isAvailableNow) {
          availableNowNodeIds.add(cleanId);
        }

        final cachedCount = ChatHistoryStore.instance.messageCount(
          _serverIp,
          cleanId,
        );
        loaded.add(
          _ChatItem(
            nodeId: cleanId,
            title: cleanId,
            subtitle:
                subtitle ??
                (cachedCount > 0
                    ? 'История сохранена ($cachedCount)'
                    : (isMaster ? 'Мастер' : 'Доступный контроллер')),
            isMaster: isMaster,
          ),
        );
      }

      // 1) мастер по прямому полю
      final String masterNodeId = normalize(info['masterNodeId']);
      if (masterNodeId.isNotEmpty) {
        addChat(
          masterNodeId,
          isMaster: true,
          subtitle: 'Мастер',
          isAvailableNow: true,
        );
      }

      // 2) известные nodeId
      final dynamic knownNodeIds = info['knownNodeIds'];
      if (knownNodeIds is List) {
        for (final item in knownNodeIds) {
          final nodeId = normalize(item);
          if (nodeId.isEmpty) continue;
          addChat(
            nodeId,
            isMaster: nodeId.startsWith('M_'),
            subtitle: nodeId.startsWith('M_')
                ? 'Мастер'
                : 'Доступный контроллер',
            isAvailableNow: true,
          );
        }
      }

      // 3) knownNodes
      final dynamic knownNodes = info['knownNodes'];
      if (knownNodes is List) {
        for (final item in knownNodes) {
          if (item is! Map) continue;

          final nodeId = normalize(item['nodeId']);
          if (nodeId.isEmpty) continue;

          final bool isMaster =
              item['isMaster'] == true ||
              normalize(item['role']).toUpperCase() == 'MASTER' ||
              nodeId.startsWith('M_');

          addChat(
            nodeId,
            isMaster: isMaster,
            subtitle: isMaster ? 'Мастер' : 'Доступный контроллер',
            isAvailableNow: true,
          );
        }
      }

      // 4) кеш по текущему IP
      final cachedDialogs = ChatHistoryStore.instance.dialogIds(_serverIp);
      for (final nodeId in cachedDialogs) {
        addChat(
          nodeId,
          isMaster: nodeId.startsWith('M_'),
          subtitle: 'История по IP',
        );
      }

      if (devMode.value && loaded.isEmpty) {
        addChat(
          'M_R2-D2',
          isMaster: true,
          subtitle: 'Мастер',
          isAvailableNow: true,
        );
        addChat(
          'R2-D3_A',
          isMaster: false,
          subtitle: 'Доступный контроллер',
          isAvailableNow: true,
        );
      }

      if (loaded.isEmpty) {
        loaded.add(
          const _ChatItem(
            nodeId: '',
            title: 'Нет доступных контроллеров',
            subtitle: 'Подождите обнаружения узлов',
            isMaster: false,
          ),
        );
      }

      loaded.sort((a, b) {
        if (a.isMaster != b.isMaster) {
          return a.isMaster ? -1 : 1;
        }
        return a.nodeId.toLowerCase().compareTo(b.nodeId.toLowerCase());
      });

      if (!mounted) return;
      setState(() {
        _selfNodeId = selfNodeId;
        chats = loaded;
        loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        error = 'Связь с ESP32 не установлена';
        loading = false;
      });
    }
  }

  Future<void> _clearOldChats() async {
    final ip = widget.manager.serverIp;
    if (ip.isEmpty) return;

    final removed = await ChatHistoryStore.instance.clearAllForIp(ip);

    if (!mounted) return;

    await _loadChats();

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          removed > 0 ? 'Очистен кеш чата: $removed чатов' : 'Кеш уже пуст',
        ),
      ),
    );
  }

  void _openChat(_ChatItem item) {
    if (item.nodeId.isEmpty) return;
    if (_selfNodeId != null && item.nodeId == _selfNodeId) return;

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _ChatRoomPage(
          nodeId: item.nodeId,
          selfNodeId: _selfNodeId ?? '',
          serverIp: _serverIp,
          title: item.title,
          subtitle: item.subtitle,
          backendBuilder: _backendBuilder,
          manager: widget.manager,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Мессенджер'),
        backgroundColor: const Color(0xFF579DDA),
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: 'Удалить старые чаты',
            onPressed: _clearOldChats,
          ),
          IconButton(icon: const Icon(Icons.refresh), onPressed: _loadChats),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _loadChats,
        child: loading
            ? const Center(child: CircularProgressIndicator())
            : error != null
            ? ListView(
                children: [
                  const SizedBox(height: 120),
                  Center(child: Text(error ?? 'Связь с ESP32 не установлена')),
                ],
              )
            : ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: chats.length,
                separatorBuilder: (_, _) => const SizedBox(height: 10),
                itemBuilder: (context, index) {
                  final chat = chats[index];

                  if (_selfNodeId != null && chat.nodeId == _selfNodeId) {
                    return const SizedBox.shrink();
                  }

                  return _ChatTile(
                    item: chat,
                    onTap: chat.nodeId.isEmpty ? null : () => _openChat(chat),
                  );
                },
              ),
      ),
    );
  }
}

class _ChatItem {
  final String nodeId;
  final String title;
  final String subtitle;
  final bool isMaster;

  const _ChatItem({
    required this.nodeId,
    required this.title,
    required this.subtitle,
    required this.isMaster,
  });
}

class _ChatTile extends StatelessWidget {
  final _ChatItem item;
  final VoidCallback? onTap;

  const _ChatTile({required this.item, this.onTap});

  @override
  Widget build(BuildContext context) {
    final bool disabled = onTap == null || item.nodeId.isEmpty;

    return Material(
      color: Colors.white,
      elevation: 1,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: ListTile(
          leading: CircleAvatar(
            backgroundColor: disabled
                ? Colors.grey.shade300
                : const Color(0xFF579DDA),
            child: Icon(
              disabled ? Icons.hourglass_empty : Icons.forum,
              color: Colors.white,
            ),
          ),
          title: Text(item.title),
          subtitle: Text(item.subtitle),
          trailing: disabled ? null : const Icon(Icons.chevron_right),
        ),
      ),
    );
  }
}

class _ChatRoomPage extends StatefulWidget {
  final String nodeId;
  final String selfNodeId;
  final String serverIp;
  final String title;
  final String subtitle;
  final BackendMessBuilder backendBuilder;
  final Esp32Manager manager;

  const _ChatRoomPage({
    required this.serverIp,
    required this.nodeId,
    required this.selfNodeId,
    required this.title,
    required this.subtitle,
    required this.backendBuilder,
    required this.manager,
  });

  @override
  State<_ChatRoomPage> createState() => _ChatRoomPageState();
}

class _ChatRoomPageState extends State<_ChatRoomPage> {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  // Настраиваемые цвета панели ввода сообщения
  static const Color _composerBackgroundColor = Color(0xFFF7F7F7);
  static const Color _composerBorderColor = Color(0xFFE3E3E3);
  static const Color _composerFocusedBorderColor = Color(0xFF2E9BFF);
  static const Color _composerTextColor = Color(0xFF111111);
  static const Color _composerHintColor = Color(0xFF7A7A7A);
  static const Color _composerCursorColor = Color(0xFF2E9BFF);
  static const Color _composerSendButtonColor = Color(0xFF2E9BFF);
  static const Color _composerSendIconColor = Colors.white;

  final List<_MessageBubble> _messages = []; // обычный режим
  final List<_MessageBubble> _devMessages = []; // режим разработчика

  Timer? _pollTimer;
  bool _syncInProgress = false;
  bool _sendInProgress = false;

  List<_MessageBubble> get _visibleMessages =>
      devMode.value ? _devMessages : _messages;

  @override
  void initState() {
    super.initState();
    devMode.addListener(_onDevModeChanged);

    if (devMode.value) {
      _resetDevConversation();
    } else {
      _syncFromServer();
    }

    _pollTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (!devMode.value && !_sendInProgress && !_syncInProgress) {
        _syncFromServer();
      }
    });
  }

  void _onDevModeChanged() {
    if (!mounted) return;

    if (devMode.value) {
      if (_devMessages.isEmpty) {
        _resetDevConversation();
      }
    } else {
      _syncFromServer();
    }

    setState(() {});
    _scrollToBottom();
  }

  void _resetDevConversation() {
    _devMessages
      ..clear()
      ..addAll(_buildDevMockConversation());
    _sortMessages(_devMessages);
  }

  String _formatTime(int timestampMs) {
    final dt = DateTime.fromMillisecondsSinceEpoch(timestampMs).toLocal();
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  String _normalizeState(String? state) {
    return (state ?? '').trim().toLowerCase();
  }

  IconData? _deliveryIcon(String? deliveryState) {
    switch (_normalizeState(deliveryState)) {
      case 'sending':
        return Icons.access_time;
      case 'sent':
      case 'delivered':
      case 'read':
        return Icons.check;
      case 'failed':
        return Icons.error_outline;
      default:
        return null;
    }
  }

  void _sortMessages(List<_MessageBubble> list) {
    list.sort((a, b) {
      final orderCmp = a.orderIndex.compareTo(b.orderIndex);
      if (orderCmp != 0) return orderCmp;

      final timeCmp = a.timestampMs.compareTo(b.timestampMs);
      if (timeCmp != 0) return timeCmp;

      if (a.isSystem != b.isSystem) {
        return a.isSystem ? -1 : 1;
      }

      if (a.isMe != b.isMe) {
        return a.isMe ? 1 : -1;
      }

      return 0;
    });
  }

  int _nextBubbleOrderIndex([List<_MessageBubble>? source]) {
    final list = source ?? _visibleMessages;
    var maxIndex = 0;
    for (final item in list) {
      if (item.orderIndex > maxIndex) {
        maxIndex = item.orderIndex;
      }
    }
    return maxIndex + 1;
  }

  String _bubbleKey(_MessageBubble m) {
    if (m.msgId != null) {
      return 'msg:${m.msgId}|${m.isMe}|${m.isSystem}';
    }
    return 'fallback:${m.orderIndex}|${m.isMe}|${m.isSystem}|${m.text}';
  }

  void _mergeMessages(
    List<_MessageBubble> target,
    List<_MessageBubble> incoming,
  ) {
    final Map<String, _MessageBubble> map = {
      for (final item in target) _bubbleKey(item): item,
    };

    for (final item in incoming) {
      map[_bubbleKey(item)] = item;
    }

    target
      ..clear()
      ..addAll(map.values);

    _sortMessages(target);
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (!_scrollController.hasClients) return;
      _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
    });
  }

  List<_MessageBubble> _buildDevMockConversation() {
    final now = DateTime.now();

    DateTime t(int hour, int minute) {
      return DateTime(now.year, now.month, now.day, hour, minute);
    }

    return [
      _MessageBubble(
        text: 'Йоу, че как, анек гони',
        isMe: false,
        timestampMs: t(17, 59).millisecondsSinceEpoch,
        displayTimestampMs: t(17, 59).millisecondsSinceEpoch,
        orderIndex: 1,
      ),
      _MessageBubble(
        text: 'ну не, не все так просто',
        isMe: true,
        timestampMs: t(18, 0).millisecondsSinceEpoch,
        displayTimestampMs: t(18, 0).millisecondsSinceEpoch,
        orderIndex: 2,
        msgId: 1001,
        deliveryState: 'read',
      ),
      _MessageBubble(
        text: 'а че те?',
        isMe: false,
        timestampMs: t(18, 1).millisecondsSinceEpoch,
        displayTimestampMs: t(18, 1).millisecondsSinceEpoch,
        orderIndex: 3,
      ),
      _MessageBubble(
        text: 'а ничо',
        isMe: true,
        timestampMs: t(18, 3).millisecondsSinceEpoch,
        displayTimestampMs: t(18, 3).millisecondsSinceEpoch,
        orderIndex: 4,
        msgId: 1002,
        deliveryState: 'sent',
      ),
    ];
  }

  Future<void> _syncFromServer() async {
    if (devMode.value || _syncInProgress) {
      return;
    }

    _syncInProgress = true;
    try {
      await ChatHistoryStore.instance.ensureLoaded(widget.serverIp);

      Map<String, dynamic> info = <String, dynamic>{};
      try {
        info = await widget.manager.fetchMasterInfo();
      } catch (_) {}

      await _applyTxCompletionFromStatus(info);

      try {
        final snapshot = await widget.manager.fetchChatSnapshot();
        if (snapshot != null) {
          await ChatHistoryStore.instance.mergeRemoteSnapshot(
            widget.serverIp,
            snapshot,
          );
          await widget.manager.ackChatSnapshot(snapshot);
        }
      } catch (_) {}

      final history = ChatHistoryStore.instance.messages(
        widget.serverIp,
        widget.nodeId,
      );

      final String emptyPlaceholderText =
          'Чат с узлом ${widget.nodeId} открыт.';
      final loaded = <_MessageBubble>[];

      if (history.isEmpty) {
        loaded.add(
          _MessageBubble(
            text: 'Чат с узлом ${widget.nodeId} открыт.',
            isMe: false,
            isSystem: true,
            timestampMs: DateTime.now().millisecondsSinceEpoch,
            orderIndex: 1,
          ),
        );
      } else {
        for (final item in history) {
          loaded.add(
            _MessageBubble(
              text: item.text,
              isMe: item.isMe,
              isSystem: item.isSystem,
              timestampMs: item.timestampMs,
              displayTimestampMs: item.displayTimestampMs,
              orderIndex: item.orderIndex,
              msgId: item.msgId,
              deliveryState: item.deliveryState,
            ),
          );
        }
      }

      _sortMessages(loaded);

      if (!mounted) return;

      final merged = List<_MessageBubble>.from(_messages);

      // Убираем старую заглушку, чтобы она не копилась и не оставалась,
      // когда уже пришли реальные сообщения.
      merged.removeWhere((m) => m.isSystem && m.text == emptyPlaceholderText);

      _mergeMessages(merged, loaded);

      setState(() {
        _messages
          ..clear()
          ..addAll(merged);
      });

      _scrollToBottom();
    } finally {
      _syncInProgress = false;
    }
  }

  void _replaceVisibleMessageState(int msgId, String newState) {
    final list = devMode.value ? _devMessages : _messages;
    final idx = list.lastIndexWhere((m) => m.msgId == msgId);
    if (idx < 0) return;

    list[idx] = list[idx].copyWith(deliveryState: newState);
    _sortMessages(list);

    if (!mounted) return;
    setState(() {});
    _scrollToBottom();
  }

  Future<void> _applyTxCompletionFromStatus(Map<String, dynamic> info) async {
    final bool chatTxPending = info['chatTxPending'] == true;
    final int lastCompletedTxMsgId =
        int.tryParse((info['lastCompletedTxMsgId'] ?? '0').toString()) ?? 0;

    if (chatTxPending || lastCompletedTxMsgId <= 0) {
      return;
    }

    final list = devMode.value ? _devMessages : _messages;
    var changed = false;

    for (var i = 0; i < list.length; i++) {
      final msg = list[i];
      final int? msgId = msg.msgId;

      if (!msg.isMe || msgId == null || msgId > lastCompletedTxMsgId) {
        continue;
      }

      final state = _normalizeState(msg.deliveryState);
      if (state == 'sending' || state == 'sent' || state.isEmpty) {
        list[i] = msg.copyWith(deliveryState: 'delivered');
        changed = true;
      }
    }

    if (!changed) {
      return;
    }

    _sortMessages(list);

    if (!devMode.value) {
      await ChatHistoryStore.instance.updateOutgoingMessagesDeliveryStateUpTo(
        widget.serverIp,
        widget.nodeId,
        lastCompletedTxMsgId,
        'delivered',
      );
    }

    if (!mounted) {
      return;
    }

    setState(() {});
    _scrollToBottom();
  }

  @override
  void dispose() {
    devMode.removeListener(_onDevModeChanged);
    _pollTimer?.cancel();
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _sendMessage() async {
    if (_sendInProgress) return;

    final text = _messageController.text.trim();
    if (text.isEmpty) return;

    _sendInProgress = true;
    try {
      _messageController.clear();
      final sentAt = DateTime.now().millisecondsSinceEpoch;
      final nextOrderIndex = _nextBubbleOrderIndex(_visibleMessages);
      final packet = widget.backendBuilder.buildPacket(
        srcNodeId: widget.selfNodeId.isNotEmpty ? widget.selfNodeId : 'APP',
        dstNodeId: widget.nodeId,
        text: text,
        chunkSize: BackendMessBuilder.defaultChunkSize,
        deliveryMode: BackendMessBuilder.defaultDeliveryMode,
        burstCount: BackendMessBuilder.defaultBurstCount,
        ackWindowMs: BackendMessBuilder.defaultAckWindowMs,
      );

      if (devMode.value) {
        _devMessages.add(
          _MessageBubble(
            text: text,
            isMe: true,
            timestampMs: sentAt,
            orderIndex: _nextBubbleOrderIndex(_devMessages),
            msgId: packet.msgId,
            deliveryState: 'sending',
          ),
        );
        _sortMessages(_devMessages);

        if (!mounted) return;
        setState(() {});
        _scrollToBottom();

        await Future.delayed(const Duration(milliseconds: 450));
        if (!mounted) return;

        _replaceVisibleMessageState(packet.msgId, 'sent');
        return;
      }
      final pendingBubble = _MessageBubble(
        text: text,
        isMe: true,
        timestampMs: sentAt,
        displayTimestampMs: sentAt,
        orderIndex: nextOrderIndex,
        msgId: packet.msgId,
        deliveryState: 'sending',
      );

      if (!mounted) return;
      setState(() {
        _messages.add(pendingBubble);
        _sortMessages(_messages);
      });
      _scrollToBottom();

      await ChatHistoryStore.instance.upsertMessage(
        widget.serverIp,
        ChatMessageRecord(
          nodeId: widget.nodeId,
          text: text,
          isMe: true,
          timestampMs: sentAt,
          msgId: packet.msgId,
          sourceIp: widget.serverIp,
          deliveryState: 'sending',
        ),
      );

      final outcome = await widget.manager.sendChatPacketBundle(packet);

      if (!mounted) return;

      final messenger = ScaffoldMessenger.maybeOf(context);

      if (!mounted) return;

      if (!outcome.success) {
        await ChatHistoryStore.instance.updateMessageDeliveryState(
          widget.serverIp,
          widget.nodeId,
          packet.msgId,
          'failed',
        );
        _replaceVisibleMessageState(packet.msgId, 'failed');

        messenger?.showSnackBar(SnackBar(content: Text(outcome.message)));
      } else {
        // Не переводим в sent сразу.
        // Часы остаются до тех пор, пока сервер не завершит передачу
        // и не примет последний ACK.
        await _syncFromServer();
      }
    } finally {
      _sendInProgress = false;
    }

    if (mounted && !devMode.value) {
      await _syncFromServer();
    }
  }

  @override
  Widget build(BuildContext context) {
    final messages = List<_MessageBubble>.from(_visibleMessages);

    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.title} • ${widget.nodeId}'),
        backgroundColor: const Color(0xFF579DDA),
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            color: Colors.grey.shade100,
            child: Text(
              widget.subtitle,
              style: TextStyle(color: Colors.grey.shade700),
            ),
          ),
          if (devMode.value)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              color: const Color(0xFFFFF3CD),
              child: const Text(
                'Режим разработчика: демонстрационный чат',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              ),
            ),
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.all(12),
              itemCount: messages.length,
              itemBuilder: (context, index) {
                final msg = messages[index];
                final icon = msg.isMe ? _deliveryIcon(msg.deliveryState) : null;

                return KeyedSubtree(
                  key: ValueKey(
                    '${msg.orderIndex}_${msg.msgId ?? 0}_${msg.isMe}_${msg.isSystem}',
                  ),
                  child: Align(
                    alignment: msg.isSystem
                        ? Alignment.center
                        : (msg.isMe
                              ? Alignment.centerRight
                              : Alignment.centerLeft),
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                      constraints: const BoxConstraints(maxWidth: 320),
                      decoration: BoxDecoration(
                        color: msg.isSystem
                            ? Colors.grey.shade300
                            : (msg.isMe
                                  ? const Color(0xFF579DDA)
                                  : Colors.grey.shade200),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: msg.isSystem
                            ? CrossAxisAlignment.center
                            : (msg.isMe
                                  ? CrossAxisAlignment.end
                                  : CrossAxisAlignment.start),
                        children: [
                          Text(
                            msg.text,
                            textAlign: msg.isSystem
                                ? TextAlign.center
                                : (msg.isMe ? TextAlign.right : TextAlign.left),
                            style: TextStyle(
                              color: msg.isSystem
                                  ? Colors.black87
                                  : (msg.isMe ? Colors.white : Colors.black87),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            mainAxisAlignment: msg.isMe
                                ? MainAxisAlignment.end
                                : MainAxisAlignment.start,
                            children: [
                              Text(
                                _formatTime(msg.displayTimestampMs),
                                style: TextStyle(
                                  fontSize: 11,
                                  color: msg.isSystem
                                      ? Colors.black54
                                      : (msg.isMe
                                            ? Colors.white70
                                            : Colors.black54),
                                ),
                              ),
                              if (icon != null) ...[
                                const SizedBox(width: 4),
                                Icon(
                                  icon,
                                  size: 14,
                                  color: msg.isMe
                                      ? Colors.white70
                                      : Colors.black54,
                                ),
                              ],
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
              child: Row(
                children: [
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        color: _composerBackgroundColor,
                        borderRadius: BorderRadius.circular(28),
                        border: Border.all(
                          color: MediaQuery.of(context).viewInsets.bottom > 0
                              ? _composerFocusedBorderColor
                              : _composerBorderColor,
                          width: 1,
                        ),
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: TextField(
                        controller: _messageController,
                        cursorColor: _composerCursorColor,
                        style: const TextStyle(color: _composerTextColor),
                        minLines: 1,
                        maxLines: 4,
                        decoration: InputDecoration(
                          hintText: 'Сообщение',
                          hintStyle: const TextStyle(color: _composerHintColor),
                          border: InputBorder.none,
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(
                            vertical: 14,
                          ),
                        ),
                        onSubmitted: (_) => _sendMessage(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  SizedBox(
                    width: 52,
                    height: 52,
                    child: FloatingActionButton(
                      heroTag: null,
                      backgroundColor: _composerSendButtonColor,
                      foregroundColor: _composerSendIconColor,
                      elevation: 2,
                      onPressed: _sendInProgress ? null : _sendMessage,
                      child: const Icon(Icons.send),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MessageBubble {
  final String text;
  final bool isMe;
  final bool isSystem;
  final int timestampMs;
  final int displayTimestampMs;
  final int orderIndex;
  final int? msgId;
  final String? deliveryState;

  const _MessageBubble({
    required this.text,
    required this.isMe,
    required this.timestampMs,
    int? displayTimestampMs,
    this.orderIndex = 0,
    this.isSystem = false,
    this.msgId,
    this.deliveryState,
  }) : displayTimestampMs = displayTimestampMs ?? timestampMs;

  _MessageBubble copyWith({
    String? text,
    bool? isMe,
    bool? isSystem,
    int? timestampMs,
    int? displayTimestampMs,
    int? orderIndex,
    int? msgId,
    String? deliveryState,
  }) {
    return _MessageBubble(
      text: text ?? this.text,
      isMe: isMe ?? this.isMe,
      isSystem: isSystem ?? this.isSystem,
      timestampMs: timestampMs ?? this.timestampMs,
      displayTimestampMs: displayTimestampMs ?? this.displayTimestampMs,
      orderIndex: orderIndex ?? this.orderIndex,
      msgId: msgId ?? this.msgId,
      deliveryState: deliveryState ?? this.deliveryState,
    );
  }
}
