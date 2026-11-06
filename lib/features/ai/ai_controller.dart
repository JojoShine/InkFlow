import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import '../works/work_models.dart';
import 'ai_client.dart';
import 'ai_context.dart';
import 'ai_credentials.dart';
import 'ai_settings.dart';
import 'ai_settings_store.dart';
import 'ai_conversation_store.dart';

class AiTurn {
  AiTurn({
    required this.question,
    this.attachment,
    this.purpose = AiPurpose.organize,
    String? id,
  }) : id = id ?? newId();
  final String id, question;
  final AiAttachment? attachment;
  final AiPurpose purpose;
  String answer = '', state = 'pending';
  final DateTime createdAt = DateTime.now();
  Map<String, dynamic> toJson() => {
    'id': id,
    'question': question,
    'purpose': purpose.name,
    'attachment': attachment?.toJson(),
    'answer': answer,
    'state': state,
    'createdAt': createdAt.toUtc().toIso8601String(),
  };
  factory AiTurn.fromJson(Map<String, dynamic> j) {
    final turn = AiTurn(
      question: j['question'] as String,
      purpose: AiPurpose.values.byName(j['purpose'] as String? ?? 'organize'),
      id: j['id'] as String?,
      attachment: j['attachment'] == null
          ? null
          : AiAttachment.fromJson(
              Map<String, dynamic>.from(j['attachment'] as Map),
            ),
    );
    turn.answer = j['answer'] as String;
    turn.state = j['state'] as String;
    return turn;
  }
}

class AiController extends ChangeNotifier {
  AiController(Directory root, {AiCredentials? credentials, AiClient? client})
    : credentials = credentials ?? PlatformAiCredentials(),
      client = client ?? AiClient(),
      settingsStore = AiSettingsStore(root),
      conversationStore = AiConversationStore(root);
  final AiCredentials credentials;
  final AiClient client;
  final AiSettingsStore settingsStore;
  final AiConversationStore conversationStore;
  final configurations = <AiProvider, AiSettings>{};
  AiProvider? activeProvider;
  AiSettings? get settings => configurations[activeProvider];
  String? workKey, failure;
  final turns = <AiTurn>[];
  String draft = '';
  AiPurpose purpose = AiPurpose.organize;
  AiAttachment? attachment;
  bool processing = false,
      saveFailed = false,
      _disposed = false,
      _discardSave = false,
      _storageBlocked = false;
  String? _boundConnection;
  Map<String, dynamic>? _boundSettings;
  int _generation = 0;
  int _activationGeneration = 0;
  bool loadingConversation = false;
  AiRequest? _request;
  StreamSubscription<AiEvent>? _subscription;
  Timer? _saveTimer;
  bool get busy => _request != null || _sending || loadingConversation;
  bool _sending = false;
  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> initialize() async {
    try {
      final result = await settingsStore.load();
      activeProvider = result.$1;
      configurations.addAll(result.$2);
    } catch (_) {
      failure = 'AI 设置读取失败，原文件已保留，请重新配置';
    }
    _notify();
  }

  Future<void> configure(AiSettings next, {String? key}) async {
    next.validate();
    if (busy) throw const FormatException('请先停止当前回复');
    if (key != null && key.trim().isNotEmpty) {
      if (key.trim().length > 2560) throw const FormatException('API Key 过长');
      await credentials.write(next.credentialId, key.trim());
    } else if (await credentials.read(next.credentialId) == null) {
      throw const FormatException('请填写此地址的 API Key');
    }
    final values = {...configurations, next.provider: next};
    await settingsStore.save(next.provider, values);
    configurations
      ..clear()
      ..addAll(values);
    activeProvider = next.provider;
    failure = null;
    _notify();
  }

  Future<void> deleteKey(AiSettings target) async {
    await credentials.delete(target.credentialId);
    _notify();
  }

  void cancelActivation() {
    _activationGeneration++;
    if (loadingConversation) {
      _generation++;
      loadingConversation = false;
      _notify();
    }
  }

  Future<void> activateWork(String? key, {bool Function()? isCurrent}) async {
    if (key == workKey) {
      cancelActivation();
      return;
    }
    final activation = ++_activationGeneration;
    bool current() =>
        !_disposed &&
        activation == _activationGeneration &&
        (isCurrent?.call() ?? true);
    await stop();
    if (!current()) return;
    if (saveFailed && !_discardSave) {
      throw const FormatException('当前对话尚未保存，请重试后再切换作品');
    }
    final generation = ++_generation;
    loadingConversation = true;
    _notify();
    final nextTurns = <AiTurn>[];
    String? nextConnection, nextFailure;
    Map<String, dynamic>? nextSettings;
    var blocked = false;
    if (key != null) {
      try {
        final value = await conversationStore.load(key);
        if (!current() || generation != _generation) {
          if (activation == _activationGeneration) {
            loadingConversation = false;
            _notify();
          }
          return;
        }
        if (value != null) {
          for (final t in value['turns'] as List) {
            nextTurns.add(AiTurn.fromJson(Map<String, dynamic>.from(t as Map)));
          }
          nextConnection = value['connectionId'] as String?;
          nextSettings = value['connection'] as Map<String, dynamic>?;
        }
      } catch (_) {
        if (!current() || generation != _generation) return;
        nextTurns.clear();
        blocked = true;
        nextFailure = '本机对话读取失败，原文件已保留。请检查文件后重试';
      }
    }
    if (!current() || generation != _generation) {
      if (activation == _activationGeneration) {
        loadingConversation = false;
        _notify();
      }
      return;
    }
    workKey = key;
    turns
      ..clear()
      ..addAll(nextTurns);
    draft = '';
    attachment = null;
    failure = nextFailure;
    _boundConnection = nextConnection;
    _boundSettings = nextSettings;
    _storageBlocked = blocked;
    loadingConversation = false;
    _notify();
  }

  bool get needsNewConversation =>
      turns.isNotEmpty &&
      settings != null &&
      _boundConnection != settings!.connectionId;
  Future<void> newConversation() async {
    if (loadingConversation) throw const FormatException('本机对话正在加载，请稍后再试');
    if (_storageBlocked) throw const FormatException('请先处理本机对话文件读取失败，原文件已保留');
    await stop();
    _generation++;
    turns.clear();
    draft = '';
    attachment = null;
    _boundConnection = null;
    _boundSettings = null;
    failure = null;
    await _persist();
    _notify();
  }

  Future<void> send(
    String question, {
    AiPurpose? purpose,
    AiAttachment? attachment,
  }) => _send(
    question,
    purpose: purpose,
    attachment: attachment ?? this.attachment,
  );
  Future<void> _send(
    String question, {
    AiPurpose? purpose,
    AiAttachment? attachment,
    AiTurn? replacing,
  }) async {
    if (busy) return;
    final config = settings, key = workKey;
    if (config == null || key == null) {
      failure = '请先打开作品并配置 AI';
      _notify();
      return;
    }
    if (_storageBlocked) {
      _notify();
      return;
    }
    if (needsNewConversation) {
      failure = '连接配置已变化，请先开启新对话';
      _notify();
      return;
    }
    final selectedPurpose = purpose ?? this.purpose,
        selectedAttachment = attachment;
    if (selectedAttachment != null && selectedAttachment.workKey != key) {
      failure = '附加内容属于其他作品，请重新附加';
      _notify();
      return;
    }

    if (selectedPurpose != AiPurpose.organize &&
        selectedAttachment == null &&
        question.trim() == selectedPurpose.draft) {
      failure = '请先附加正文或在输入框粘贴需要分析的内容';
      _notify();
      return;
    }
    final generation = ++_generation;
    _sending = true;
    failure = null;
    _notify();
    try {
      final history = <AiChatMessage>[
        for (final t in turns.where((t) => t.state == 'completed')) ...[
          AiChatMessage(
            'user',
            questionWithAttachment(t.question, t.attachment),
          ),
          AiChatMessage('assistant', t.answer),
        ],
      ];
      final messages = buildAiMessages(
        purpose: selectedPurpose,
        completedHistory: history,
        question: question,
        attachment: selectedAttachment,
      );
      final apiKey = await credentials.read(config.credentialId);
      if (generation != _generation || _disposed) return;
      if (apiKey == null || apiKey.isEmpty) {
        throw const FormatException('请先配置此服务的 API Key');
      }
      final turn = AiTurn(
        question: question,
        attachment: selectedAttachment,
        id: replacing?.id,
        purpose: selectedPurpose,
      );
      final replacedIndex = replacing == null ? -1 : turns.indexOf(replacing);
      if (replacedIndex >= 0) {
        turn.answer = replacing!.answer;
        turns[replacedIndex] = turn;
      } else {
        turns.add(turn);
      }
      _boundConnection = config.connectionId;
      _boundSettings = config.toJson();
      if (!await _persist()) {
        if (replacedIndex >= 0) {
          turns[replacedIndex] = replacing!;
        } else {
          turn.state = 'failed';
        }
        return;
      }
      if (generation != _generation || _disposed) return;
      if (replacing == null) {
        draft = '';
        this.attachment = null;
      }
      final request = client.start(config, apiKey, messages);
      _request = request;
      turn.state = 'receiving';
      bool newText = false;
      _subscription = request.events.listen(
        (event) {
          if (_disposed || generation != _generation) return;
          switch (event) {
            case AiTextDelta(:final text):
              if (replacing != null && !newText) turn.answer = '';
              newText = true;
              turn.answer += text;
              processing = false;
              _scheduleSave();
            case AiProcessing():
              processing = true;
            case AiFinished(:final reason):
              turn.state = reason == 'stop' ? 'completed' : 'interrupted';
              if (reason != 'stop') {
                failure =
                    '回复未完整完成（${reason == 'length' ? '达到长度上限' : '模型未完成文本回复'}）';
              }
              _finish();
            case AiFailed(:final message):
              turn.state = 'failed';
              failure = message;
              _finish();
          }
          _notify();
        },
        onError: (Object _) {
          if (generation == _generation) {
            turn.state = 'failed';
            failure = '回复连接中断，已有内容已保留';
            _finish();
          }
        },
        onDone: () {
          if (generation == _generation && turn.state == 'receiving') {
            turn.state = 'interrupted';
            failure = '回复连接中断，已有内容已保留';
            _finish();
          }
        },
      );
    } on FormatException catch (error) {
      if (generation == _generation) failure = error.message.toString();
    } catch (_) {
      if (generation == _generation) failure = '无法读取已保存的密钥或保存对话，请重试';
    } finally {
      if (generation == _generation) _sending = false;
      _notify();
    }
  }

  void _finish() {
    _request = null;
    processing = false;
    _saveTimer?.cancel();
    _saveTimer = null;
    unawaited(_persist());
  }

  void _scheduleSave() {
    _saveTimer ??= Timer(const Duration(seconds: 1), () {
      _saveTimer = null;
      unawaited(_persist());
    });
  }

  Future<bool> _persist() async {
    final key = workKey;
    if (key == null || _storageBlocked) return !_storageBlocked;
    try {
      await conversationStore.save(key, {
        'schemaVersion': 1,
        'connectionId': _boundConnection,
        'connection': _boundSettings,
        'turns': turns.map((t) => t.toJson()).toList(),
      });
      saveFailed = false;
      _discardSave = false;
      return true;
    } catch (_) {
      saveFailed = true;
      failure = '本机对话保存失败，内容仍保留在面板，可重试';
      _notify();
      return false;
    }
  }

  Future<void> retrySave() async {
    await _persist();
    _notify();
  }

  Future<void> retry() async {
    if (turns.isEmpty || busy) return;
    final old = turns.last;
    if (old.state == 'completed') return;
    await _send(
      old.question,
      purpose: old.purpose,
      attachment: old.attachment,
      replacing: old,
    );
  }

  Future<void> stop() => _stop(persist: true);
  Future<void> _stop({required bool persist}) async {
    if (loadingConversation) return;
    _generation++;
    _saveTimer?.cancel();
    _saveTimer = null;
    final request = _request;
    _request = null;
    _sending = false;
    processing = false;
    await _subscription?.cancel();
    _subscription = null;
    await request?.cancel();
    if (turns.isNotEmpty &&
        (turns.last.state == 'receiving' || turns.last.state == 'pending')) {
      turns.last.state = 'stopped';
    }
    if (persist && workKey != null && turns.isNotEmpty) await _persist();
    _notify();
  }

  void discardFailedSave() {
    _discardSave = true;
  }

  Future<bool> prepareToQuit() async {
    if (loadingConversation) {
      cancelActivation();
      return _discardSave || !saveFailed;
    }
    if (_discardSave) {
      await _stop(persist: false);
      return true;
    }
    await stop();
    await conversationStore.flush();
    return !saveFailed;
  }

  @override
  void dispose() {
    _disposed = true;
    _activationGeneration++;
    _generation++;
    _saveTimer?.cancel();
    unawaited(_subscription?.cancel() ?? Future.value());
    unawaited(_request?.cancel() ?? Future.value());
    super.dispose();
  }
}
