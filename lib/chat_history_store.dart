import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ChatMessageRecord {
  final String nodeId;
  final String text;
  final bool isMe;
  final bool isSystem;
  final int timestampMs;

  // Порядок появления сообщения в чате
  final int orderIndex;

  // Время, когда сообщение было впервые показано в приложении
  final int displayTimestampMs;

  final int? msgId;
  final String? sourceIp;
  final String? deliveryState;

  const ChatMessageRecord({
    required this.nodeId,
    required this.text,
    required this.isMe,
    required this.timestampMs,
    this.orderIndex = 0,
    int? displayTimestampMs,
    this.isSystem = false,
    this.msgId,
    this.sourceIp,
    this.deliveryState,
  }) : displayTimestampMs = displayTimestampMs ?? timestampMs;

  ChatMessageRecord copyWith({
    String? nodeId,
    String? text,
    bool? isMe,
    bool? isSystem,
    int? timestampMs,
    int? orderIndex,
    int? displayTimestampMs,
    int? msgId,
    String? sourceIp,
    String? deliveryState,
  }) {
    return ChatMessageRecord(
      nodeId: nodeId ?? this.nodeId,
      text: text ?? this.text,
      isMe: isMe ?? this.isMe,
      isSystem: isSystem ?? this.isSystem,
      timestampMs: timestampMs ?? this.timestampMs,
      orderIndex: orderIndex ?? this.orderIndex,
      displayTimestampMs: displayTimestampMs ?? this.displayTimestampMs,
      msgId: msgId ?? this.msgId,
      sourceIp: sourceIp ?? this.sourceIp,
      deliveryState: deliveryState ?? this.deliveryState,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'nodeId': nodeId,
      'text': text,
      'isMe': isMe,
      'isSystem': isSystem,
      'timestampMs': timestampMs,
      'orderIndex': orderIndex,
      'displayTimestampMs': displayTimestampMs,
      'msgId': msgId,
      'sourceIp': sourceIp,
      'deliveryState': deliveryState,
    };
  }

  factory ChatMessageRecord.fromJson(Map<String, dynamic> json) {
    final timestampMs = (json['timestampMs'] is int)
        ? json['timestampMs'] as int
        : int.tryParse((json['timestampMs'] ?? '0').toString()) ?? 0;

    final orderIndex = (json['orderIndex'] is int)
        ? json['orderIndex'] as int
        : int.tryParse((json['orderIndex'] ?? '0').toString()) ?? 0;

    final displayTimestampMs = (json['displayTimestampMs'] is int)
        ? json['displayTimestampMs'] as int
        : int.tryParse((json['displayTimestampMs'] ?? '0').toString()) ?? 0;

    return ChatMessageRecord(
      nodeId: (json['nodeId'] ?? '').toString(),
      text: (json['text'] ?? '').toString(),
      isMe: json['isMe'] == true,
      isSystem: json['isSystem'] == true,
      timestampMs: timestampMs,
      orderIndex: orderIndex,
      displayTimestampMs: displayTimestampMs > 0
          ? displayTimestampMs
          : timestampMs,
      msgId: json['msgId'] == null
          ? null
          : (json['msgId'] is int
                ? json['msgId'] as int
                : int.tryParse(json['msgId'].toString())),
      sourceIp: json['sourceIp']?.toString(),
      deliveryState: json['deliveryState']?.toString(),
    );
  }

  String dedupeKey() {
    return '${msgId ?? -1}|$nodeId|$isMe|$isSystem';
  }
}

class ChatThreadRecord {
  final String nodeId;
  final List<ChatMessageRecord> messages;

  ChatThreadRecord({required this.nodeId, List<ChatMessageRecord>? messages})
    : messages = messages ?? [];

  Map<String, dynamic> toJson() {
    return {
      'nodeId': nodeId,
      'messages': messages.map((m) => m.toJson()).toList(),
    };
  }

  factory ChatThreadRecord.fromJson(Map<String, dynamic> json) {
    final rawMessages = json['messages'];
    final messages = <ChatMessageRecord>[];

    if (rawMessages is List) {
      for (final item in rawMessages) {
        if (item is Map<String, dynamic>) {
          messages.add(ChatMessageRecord.fromJson(item));
        } else if (item is Map) {
          messages.add(
            ChatMessageRecord.fromJson(Map<String, dynamic>.from(item)),
          );
        }
      }
    }

    return ChatThreadRecord(
      nodeId: (json['nodeId'] ?? '').toString(),
      messages: messages,
    );
  }
}

class ChatHistoryStore extends ChangeNotifier {
  ChatHistoryStore._();

  static final ChatHistoryStore instance = ChatHistoryStore._();

  final Map<String, Map<String, ChatThreadRecord>> _cacheByIp = {};
  final Set<String> _loadedIps = {};

  SharedPreferences? _prefs;

  String _storageKey(String ip) => 'chat_history_ip_${ip.replaceAll(':', '_')}';

  int _nextOrderIndex(ChatThreadRecord thread) {
    var maxIndex = 0;
    for (final msg in thread.messages) {
      if (msg.orderIndex > maxIndex) {
        maxIndex = msg.orderIndex;
      }
    }
    return maxIndex + 1;
  }

  void _normalizeThreadOrder(ChatThreadRecord thread) {
    var next = 1;
    for (var i = 0; i < thread.messages.length; i++) {
      final current = thread.messages[i];
      if (current.orderIndex <= 0) {
        thread.messages[i] = current.copyWith(orderIndex: next);
        next++;
      } else {
        final candidate = current.orderIndex + 1;
        if (candidate > next) {
          next = candidate;
        }
      }
    }
  }

  void _upsertThreadMessage(
    Map<String, ChatThreadRecord> perIp,
    ChatMessageRecord message,
  ) {
    final thread = perIp.putIfAbsent(
      message.nodeId,
      () => ChatThreadRecord(nodeId: message.nodeId),
    );

    final exactKey = message.dedupeKey();
    final exactExists = thread.messages.any((m) => m.dedupeKey() == exactKey);
    if (exactExists) {
      return;
    }

    var incoming = message;
    if (incoming.orderIndex <= 0) {
      incoming = incoming.copyWith(orderIndex: _nextOrderIndex(thread));
    }

    if (incoming.msgId != null) {
      final idx = thread.messages.indexWhere((m) => m.msgId == incoming.msgId);
      if (idx >= 0) {
        final existing = thread.messages[idx];

        thread.messages[idx] = existing.copyWith(
          text: existing.text.isNotEmpty ? existing.text : incoming.text,
          isMe: existing.isMe,
          isSystem: existing.isSystem,
          timestampMs: existing.timestampMs != 0
              ? existing.timestampMs
              : incoming.timestampMs,
          orderIndex: existing.orderIndex > 0
              ? existing.orderIndex
              : incoming.orderIndex,
          msgId: existing.msgId ?? incoming.msgId,
          sourceIp: existing.sourceIp ?? incoming.sourceIp,
          deliveryState: incoming.deliveryState ?? existing.deliveryState,
        );
        return;
      }
    }

    thread.messages.add(incoming);
  }

  Future<SharedPreferences> _getPrefs() async {
    _prefs ??= await SharedPreferences.getInstance();
    return _prefs!;
  }

  Future<void> ensureLoaded(String ip) async {
    if (ip.isEmpty) return;
    if (_loadedIps.contains(ip)) return;

    final prefs = await _getPrefs();
    final raw = prefs.getString(_storageKey(ip));

    final perIp = <String, ChatThreadRecord>{};

    if (raw != null && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map<String, dynamic>) {
          final threads = decoded['threads'];
          if (threads is List) {
            for (final item in threads) {
              if (item is Map<String, dynamic>) {
                final thread = ChatThreadRecord.fromJson(item);
                if (thread.nodeId.isNotEmpty) {
                  perIp[thread.nodeId] = thread;
                }
              } else if (item is Map) {
                final thread = ChatThreadRecord.fromJson(
                  Map<String, dynamic>.from(item),
                );
                if (thread.nodeId.isNotEmpty) {
                  perIp[thread.nodeId] = thread;
                }
              }
            }
          }
        }
      } catch (_) {
        // Если кеш повреждён, просто стартуем с пустого состояния
      }
    }

    for (final thread in perIp.values) {
      _normalizeThreadOrder(thread);
    }

    _cacheByIp[ip] = perIp;
    _loadedIps.add(ip);
    notifyListeners();
  }

  Future<void> _save(String ip) async {
    if (ip.isEmpty) return;
    final prefs = await _getPrefs();

    final threads = _cacheByIp[ip]?.values.toList() ?? <ChatThreadRecord>[];
    final payload = {
      'serverIp': ip,
      'threads': threads.map((t) => t.toJson()).toList(),
    };

    await prefs.setString(_storageKey(ip), jsonEncode(payload));
  }

  List<String> dialogIds(String ip) {
    final perIp = _cacheByIp[ip];
    if (perIp == null) return <String>[];
    return perIp.keys.toList()..sort();
  }

  List<ChatMessageRecord> messages(String ip, String nodeId) {
    final perIp = _cacheByIp[ip];
    if (perIp == null) return <ChatMessageRecord>[];

    final list = List<ChatMessageRecord>.from(
      perIp[nodeId]?.messages ?? const <ChatMessageRecord>[],
    );

    list.sort((a, b) {
      final orderCmp = a.orderIndex.compareTo(b.orderIndex);
      if (orderCmp != 0) return orderCmp;
      return a.timestampMs.compareTo(b.timestampMs);
    });
    return list;
  }

  int messageCount(String ip, String nodeId) {
    final perIp = _cacheByIp[ip];
    if (perIp == null) return 0;
    return perIp[nodeId]?.messages.length ?? 0;
  }

  Future<int> clearThreadsExcept(String ip, Set<String> keepNodeIds) async {
    if (ip.isEmpty) return 0;
    await ensureLoaded(ip);

    final perIp = _cacheByIp.putIfAbsent(
      ip,
      () => <String, ChatThreadRecord>{},
    );

    final normalizedKeep = keepNodeIds
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toSet();

    final before = perIp.length;

    perIp.removeWhere((nodeId, _) => !normalizedKeep.contains(nodeId));

    await _save(ip);
    notifyListeners();

    return before - perIp.length;
  }

  Future<int> clearAllForIp(String ip) async {
    if (ip.isEmpty) return 0;
    await ensureLoaded(ip);

    final perIp = _cacheByIp.putIfAbsent(
      ip,
      () => <String, ChatThreadRecord>{},
    );

    final removed = perIp.length;
    perIp.clear();

    await _save(ip);
    notifyListeners();

    return removed;
  }

  Future<void> upsertMessage(String ip, ChatMessageRecord message) async {
    if (ip.isEmpty || message.nodeId.isEmpty) return;
    await ensureLoaded(ip);

    final perIp = _cacheByIp.putIfAbsent(
      ip,
      () => <String, ChatThreadRecord>{},
    );

    _upsertThreadMessage(perIp, message);

    final thread = perIp[message.nodeId];
    if (thread != null) {
      thread.messages.sort((a, b) {
        final orderCmp = a.orderIndex.compareTo(b.orderIndex);
        if (orderCmp != 0) return orderCmp;
        return a.timestampMs.compareTo(b.timestampMs);
      });
    }

    await _save(ip);
    notifyListeners();
  }

  Future<void> updateMessageDeliveryState(
    String ip,
    String nodeId,
    int msgId,
    String deliveryState,
  ) async {
    if (ip.isEmpty || nodeId.isEmpty) return;
    await ensureLoaded(ip);

    final perIp = _cacheByIp.putIfAbsent(
      ip,
      () => <String, ChatThreadRecord>{},
    );

    final thread = perIp.putIfAbsent(
      nodeId,
      () => ChatThreadRecord(nodeId: nodeId),
    );

    final idx = thread.messages.indexWhere((m) => m.msgId == msgId);
    if (idx < 0) return;

    thread.messages[idx] = thread.messages[idx].copyWith(
      deliveryState: deliveryState,
    );

    thread.messages.sort((a, b) {
      final orderCmp = a.orderIndex.compareTo(b.orderIndex);
      if (orderCmp != 0) return orderCmp;
      return a.timestampMs.compareTo(b.timestampMs);
    });
    await _save(ip);
    notifyListeners();
  }

  Future<void> updateOutgoingMessagesDeliveryStateUpTo(
    String ip,
    String nodeId,
    int maxMsgId,
    String deliveryState,
  ) async {
    if (ip.isEmpty || nodeId.isEmpty || maxMsgId <= 0) return;
    await ensureLoaded(ip);

    final perIp = _cacheByIp.putIfAbsent(
      ip,
      () => <String, ChatThreadRecord>{},
    );

    final thread = perIp.putIfAbsent(
      nodeId,
      () => ChatThreadRecord(nodeId: nodeId),
    );

    var changed = false;

    for (var i = 0; i < thread.messages.length; i++) {
      final msg = thread.messages[i];
      final msgId = msg.msgId;

      if (!msg.isMe || msgId == null || msgId > maxMsgId) {
        continue;
      }

      final state = (msg.deliveryState ?? '').trim().toLowerCase();
      if (state == 'sending' || state == 'sent' || state.isEmpty) {
        thread.messages[i] = msg.copyWith(deliveryState: deliveryState);
        changed = true;
      }
    }

    if (!changed) return;

    thread.messages.sort((a, b) {
      final orderCmp = a.orderIndex.compareTo(b.orderIndex);
      if (orderCmp != 0) return orderCmp;
      return a.timestampMs.compareTo(b.timestampMs);
    });

    await _save(ip);
    notifyListeners();
  }

  Future<void> mergeRemoteSnapshot(
    String ip,
    Map<String, dynamic> snapshot,
  ) async {
    if (ip.isEmpty) return;
    await ensureLoaded(ip);

    final perIp = _cacheByIp.putIfAbsent(
      ip,
      () => <String, ChatThreadRecord>{},
    );

    void ingestMessage(Map<String, dynamic> item) {
      final nodeId =
          (item['nodeId'] ??
                  item['peerNodeId'] ??
                  item['dstNodeId'] ??
                  item['srcNodeId'] ??
                  '')
              .toString()
              .trim();

      if (nodeId.isEmpty) return;

      final text = (item['text'] ?? item['message'] ?? item['body'] ?? '')
          .toString();

      if (text.trim().isEmpty) return;

      final isMe = item['isMe'] == true || item['fromMe'] == true;
      final isSystem = item['isSystem'] == true;

      final timestampMs = (item['timestampMs'] is int)
          ? item['timestampMs'] as int
          : int.tryParse(
                  (item['timestampMs'] ?? DateTime.now().millisecondsSinceEpoch)
                      .toString(),
                ) ??
                DateTime.now().millisecondsSinceEpoch;

      final msgId = item['msgId'] == null
          ? null
          : (item['msgId'] is int
                ? item['msgId'] as int
                : int.tryParse(item['msgId'].toString()));

      final record = ChatMessageRecord(
        nodeId: nodeId,
        text: text,
        isMe: isMe,
        isSystem: isSystem,
        timestampMs: timestampMs,
        displayTimestampMs: isMe
            ? timestampMs
            : DateTime.now().millisecondsSinceEpoch,
        msgId: msgId,
        sourceIp: ip,
        deliveryState: item['deliveryState']?.toString(),
      );

      _upsertThreadMessage(perIp, record);
    }

    final messages = snapshot['messages'];
    if (messages is List) {
      for (final item in messages) {
        if (item is Map<String, dynamic>) {
          ingestMessage(item);
        } else if (item is Map) {
          ingestMessage(Map<String, dynamic>.from(item));
        }
      }
    }

    final threads = snapshot['threads'];
    if (threads is List) {
      for (final threadItem in threads) {
        if (threadItem is Map<String, dynamic>) {
          final nodeId = (threadItem['nodeId'] ?? '').toString().trim();
          if (nodeId.isEmpty) continue;
          final rawMsgs = threadItem['messages'];
          if (rawMsgs is List) {
            for (final msg in rawMsgs) {
              if (msg is Map<String, dynamic>) {
                ingestMessage({...msg, 'nodeId': nodeId});
              } else if (msg is Map) {
                ingestMessage({
                  ...Map<String, dynamic>.from(msg),
                  'nodeId': nodeId,
                });
              }
            }
          }
        } else if (threadItem is Map) {
          final map = Map<String, dynamic>.from(threadItem);
          final nodeId = (map['nodeId'] ?? '').toString().trim();
          if (nodeId.isEmpty) continue;
          final rawMsgs = map['messages'];
          if (rawMsgs is List) {
            for (final msg in rawMsgs) {
              if (msg is Map<String, dynamic>) {
                ingestMessage({...msg, 'nodeId': nodeId});
              } else if (msg is Map) {
                ingestMessage({
                  ...Map<String, dynamic>.from(msg),
                  'nodeId': nodeId,
                });
              }
            }
          }
        }
      }
    }

    for (final thread in perIp.values) {
      thread.messages.sort((a, b) {
        final orderCmp = a.orderIndex.compareTo(b.orderIndex);
        if (orderCmp != 0) return orderCmp;
        return a.timestampMs.compareTo(b.timestampMs);
      });
    }

    await _save(ip);
    notifyListeners();
  }
}
