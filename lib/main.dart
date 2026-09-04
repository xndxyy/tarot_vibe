import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'service/api_key_store.dart';

void main() {
  runApp(const TarotVibeApp());
}

class TarotVibeApp extends StatelessWidget {
  const TarotVibeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '塔罗 Vibe',
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF0F001F),
        primaryColor: const Color(0xFF8B00FF),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF1F0033),
          elevation: 0,
        ),
      ),
      home: const HomePage(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final TextEditingController _questionController = TextEditingController();
  List<dynamic> tarotDeck = [];
  List<dynamic> drawnCards = [];
  bool isLoading = false;
  String _lastAskedQuestion = '';
  String _canonicalQuestion = '';
  bool _hasDrawn = false;        // 新增：是否已经抽过牌
  String _aiReading = '';
  String? _aiError;
  bool _isAiLoading = false;
  bool _hasUserApiKey = false;
  final Map<String, String> _aiReadingCache = {};
  static const String _builtInApiKey = String.fromEnvironment('DEEPSEEK_API_KEY');

  @override
  void initState() {
    super.initState();
    _loadTarotData();
    _refreshApiKeyState();
  }

  Future<void> _refreshApiKeyState() async {
    final key = (await ApiKeyStore.readDeepSeekKey())?.trim() ?? '';
    if (!mounted) return;
    setState(() {
      _hasUserApiKey = key.isNotEmpty;
    });
  }

  Future<void> _openApiSettings() async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const ApiSettingsPage()),
    );
    if (changed == true) {
      _refreshApiKeyState();
    }
  }

  Future<void> _loadTarotData() async {
    try {
      final data = await rootBundle.loadString('assets/data/tarot.json');
      final List<dynamic> jsonList = json.decode(data);
      if (!mounted) return;
      setState(() {
        tarotDeck = jsonList;
      });
    } catch (e) {
      debugPrint('加载塔罗数据失败: $e');
    }
  }

  String _normalizeQuestion(String input) {
    return input.trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase();
  }

  // 把不同说法归一成更稳定的语义 key，尽量保证同问题同结果
  String _canonicalizeQuestion(String input) {
    var text = _normalizeQuestion(input);
    text = text.replaceAll(
      RegExp('[，。！？、,.!?;:：；"“”\'（）()【】\\[\\]-]'),
      ' ',
    );
    text = text.replaceAll(RegExp(r'\b(请问|想问|我想问|能不能|会不会|是否|一下|一下子|帮我看|帮我)\b'), ' ');

    final topicRules = <String, List<String>>{
      'love': ['恋爱', '感情', '姻缘', '对象', '脱单', '复合', '关系', '桃花'],
      'career': ['工作', '事业', '升职', '跳槽', 'offer', '面试', '职场', '发展'],
      'wealth': ['财运', '钱', '收入', '投资', '奖金', '偏财', '副业'],
      'study': ['学习', '考试', '上岸', '成绩', '考研', '留学'],
      'health': ['健康', '身体', '状态', '睡眠', '焦虑', '压力'],
    };

    String topic = 'general';
    for (final entry in topicRules.entries) {
      if (entry.value.any((kw) => text.contains(kw))) {
        topic = entry.key;
        break;
      }
    }

    final tokens = text
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty && w.length > 1)
        .toSet()
        .toList()
      ..sort();

    return '$topic|${tokens.join('_')}';
  }

  int _stableHash(String text) {
    int hash = 2166136261;
    for (final unit in text.codeUnits) {
      hash ^= unit;
      hash = (hash * 16777619) & 0x7fffffff;
    }
    return hash;
  }

  void _drawCards() {
    final displayQuestion = _questionController.text.trim();
    if (displayQuestion.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请输入你的问题')),
      );
      return;
    }

    setState(() {
      isLoading = true;
      _hasDrawn = false;
      _aiReading = '';
      _aiError = null;
      _isAiLoading = false;
    });

    final canonical = _canonicalizeQuestion(displayQuestion);
    final random = Random(_stableHash(canonical));
    final temp = List<dynamic>.from(tarotDeck)..shuffle(random);

    Future.delayed(const Duration(milliseconds: 800), () {
      if (!mounted) return;
      setState(() {
        drawnCards = temp.take(3).map((card) {
          final bool isReversed = random.nextBool();
          final String fullName = card['name'] ?? '';
          final String chineseName = fullName.split('(')[0].trim();

          return {
            'name': chineseName,
            'image': card['image'],
            'isReversed': isReversed,
            'isRevealed': false,
            'meaning': isReversed
                ? (card['reverseDescription'] ?? '暂无逆位解读')
                : (card['description'] ?? '暂无正位解读'),
          };
        }).toList();

        isLoading = false;
        _lastAskedQuestion = displayQuestion;
        _canonicalQuestion = canonical;
        _hasDrawn = true;           // 标记已抽牌 → 隐藏输入框和按钮
      });
    });
  }

  String _buildDeepSeekPrompt() {
    final List<Map<String, dynamic>> cardsForPrompt = drawnCards
        .asMap()
        .entries
        .map((entry) {
          const positions = ['过去', '现在', '未来'];
          final card = entry.value;
          return {
            'position': positions[entry.key],
            'name': card['name'],
            'orientation': (card['isReversed'] == true) ? '逆位' : '正位',
            'meaning': card['meaning'],
          };
        })
        .toList();

    return '''
你是一位温和、具体、不过度承诺的塔罗咨询师。
请根据用户问题和三张牌，输出以下四部分（中文）：
1) 总览（80-120字）
2) 分牌解读（每张40-80字）
3) 可执行建议（3条）
4) 风险提醒（1条，避免宿命论）

要求：
- 语气真诚、清晰
- 不要给医学/法律确定性结论
- 不要恐吓用户

用户问题：$_lastAskedQuestion
语义归一键：$_canonicalQuestion
抽牌数据：${jsonEncode(cardsForPrompt)}
''';
  }

  Future<void> _generateAiReading() async {
    if (_lastAskedQuestion.isEmpty || drawnCards.isEmpty || _isAiLoading) return;
    if (_aiReadingCache.containsKey(_canonicalQuestion)) {
      setState(() {
        _aiReading = _aiReadingCache[_canonicalQuestion]!;
        _aiError = null;
      });
      return;
    }

    final userApiKey = (await ApiKeyStore.readDeepSeekKey())?.trim() ?? '';
    final apiKey = userApiKey.isNotEmpty ? userApiKey : _builtInApiKey;
    if (apiKey.isEmpty) {
      setState(() {
        _aiError = '未配置 DeepSeek API Key，请先到右上角设置中保存。';
      });
      return;
    }

    setState(() {
      _isAiLoading = true;
      _aiError = null;
    });

    try {
      final response = await http
          .post(
            Uri.parse('https://api.deepseek.com/v1/chat/completions'),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $apiKey',
            },
            body: jsonEncode({
              'model': 'deepseek-chat',
              'temperature': 0.0,
              'messages': [
                {'role': 'system', 'content': '你是专业塔罗咨询师。'},
                {'role': 'user', 'content': _buildDeepSeekPrompt()},
              ],
            }),
          )
          .timeout(const Duration(seconds: 25));

      if (!mounted) return;

      if (response.statusCode != 200) {
        String detail = '';
        try {
          final dynamic errData = jsonDecode(response.body);
          final dynamic msg = errData is Map<String, dynamic>
              ? (errData['error']?['message'] ?? errData['message'])
              : null;
          detail = (msg ?? '').toString().trim();
        } catch (_) {
          detail = '';
        }

        setState(() {
          _aiError = detail.isEmpty
              ? 'AI 解读失败（${response.statusCode}），请稍后重试。'
              : 'AI 解读失败（${response.statusCode}）：$detail';
          _isAiLoading = false;
        });
        return;
      }

      final Map<String, dynamic> data = jsonDecode(response.body);
      final String content =
          (data['choices']?[0]?['message']?['content'] ?? '').toString().trim();

      setState(() {
        _aiReading = content.isEmpty ? 'AI 暂时没有返回内容，请重试一次。' : content;
        _aiReadingCache[_canonicalQuestion] = _aiReading;
        _isAiLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _aiError = '网络或服务异常，暂时无法获取 AI 解读。';
        _isAiLoading = false;
      });
    }
  }

  // 重新占卜（清空结果，显示输入框）
  void _reset() {
    setState(() {
      drawnCards.clear();
      _hasDrawn = false;
      _questionController.clear();
      _aiReading = '';
      _aiError = null;
      _isAiLoading = false;
      _canonicalQuestion = '';
    });
  }

  @override
  void dispose() {
    _questionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('🔮 塔罗 Vibe'),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.key),
            onPressed: _openApiSettings,
            tooltip: 'API 设置',
          ),
          if (_hasDrawn)
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: _reset,
              tooltip: '重新占卜',
            ),
        ],
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF0F001F), Color(0xFF2A004D)],
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            children: [
              // ==================== 输入区域（抽牌后自动隐藏） ====================
              if (!_hasDrawn) ...[
                TextField(
                  controller: _questionController,
                  style: const TextStyle(color: Colors.white, fontSize: 16),
                  decoration: InputDecoration(
                    labelText: '请向宇宙提出你的问题...',
                    labelStyle: const TextStyle(color: Colors.deepPurpleAccent),
                    hintText: '例如：我的下一段恋情在哪？',
                    hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.6)),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: const BorderSide(color: Colors.deepPurple),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: const BorderSide(color: Color(0xFF8B00FF), width: 2),
                    ),
                    filled: true,
                    fillColor: const Color(0xFF1F0033),
                  ),
                  maxLines: 2,
                ),
                const SizedBox(height: 24),

                SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: ElevatedButton(
                    onPressed: isLoading ? null : _drawCards,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF8B00FF),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      elevation: 8,
                    ),
                    child: isLoading
                        ? const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              CircularProgressIndicator(color: Colors.white, strokeWidth: 3),
                              SizedBox(width: 12),
                              Text('正在与宇宙连接...', style: TextStyle(fontSize: 18)),
                            ],
                          )
                        : const Text('🔮 开始占卜',
                            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                  ),
                ),
                const SizedBox(height: 32),
              ],

              // ==================== 结果区域 ====================
              Expanded(
                child: drawnCards.isNotEmpty
                    ? Column(
                        children: [
                          // 显示问题
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                            decoration: BoxDecoration(
                              color: Colors.deepPurple.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              '问题：$_lastAskedQuestion',
                              style: const TextStyle(
                                fontSize: 12,
                                color: Colors.white60,
                                height: 1.25,
                              ),
                              textAlign: TextAlign.left,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(height: 10),
                          if (_aiReading.isEmpty)
                            SizedBox(
                              width: double.infinity,
                              child: OutlinedButton.icon(
                                onPressed: _isAiLoading
                                    ? null
                                    : () {
                                        final hasAnyApiKey =
                                            _hasUserApiKey || _builtInApiKey.isNotEmpty;
                                        if (!hasAnyApiKey) {
                                          _openApiSettings();
                                          return;
                                        }
                                        _generateAiReading();
                                      },
                                icon: _isAiLoading
                                    ? const SizedBox(
                                        width: 16,
                                        height: 16,
                                        child: CircularProgressIndicator(strokeWidth: 2),
                                      )
                                    : Icon(
                                        _hasUserApiKey || _builtInApiKey.isNotEmpty
                                            ? Icons.auto_awesome
                                            : Icons.key,
                                      ),
                                label: Text(
                                  _isAiLoading
                                      ? 'AI 解读生成中...'
                                      : (_hasUserApiKey || _builtInApiKey.isNotEmpty
                                          ? 'AI 深度解读（DeepSeek）'
                                          : '先配置 API Key'),
                                ),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: Colors.deepPurpleAccent,
                                  side: BorderSide(
                                    color: Colors.deepPurpleAccent.withValues(alpha: 0.45),
                                  ),
                                  padding: const EdgeInsets.symmetric(vertical: 12),
                                ),
                              ),
                            ),
                          if (_aiError != null) ...[
                            const SizedBox(height: 10),
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: Colors.red.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(
                                _aiError!,
                                style: const TextStyle(color: Colors.redAccent),
                              ),
                            ),
                          ],
                          const SizedBox(height: 12),
                          if (_aiReading.isNotEmpty) ...[
                            SizedBox(
                              height: 110,
                              child: ListView.separated(
                                scrollDirection: Axis.horizontal,
                                itemCount: drawnCards.length,
                                separatorBuilder: (_, __) => const SizedBox(width: 10),
                                itemBuilder: (context, index) {
                                  final card = drawnCards[index];
                                  return ClipRRect(
                                    borderRadius: BorderRadius.circular(12),
                                    child: Container(
                                      width: 78,
                                      color: const Color(0xFF1F0033),
                                      child: Image.asset(
                                        'assets/images/${card['image']}',
                                        fit: BoxFit.cover,
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ),
                            const SizedBox(height: 10),
                            Expanded(
                              child: Container(
                                width: double.infinity,
                                decoration: BoxDecoration(
                                  color: const Color(0xFF251037),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: Colors.deepPurpleAccent.withValues(alpha: 0.3),
                                  ),
                                ),
                                child: Scrollbar(
                                  thumbVisibility: true,
                                  child: SingleChildScrollView(
                                    padding: const EdgeInsets.all(14),
                                    child: Text(
                                      _aiReading,
                                      style: const TextStyle(height: 1.85, fontSize: 17),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ] else
                            // 卡牌列表（未生成 AI 解读时，保留原本翻牌体验）
                            Expanded(
                              child: ListView.builder(
                                itemCount: drawnCards.length,
                                itemBuilder: (context, index) {
                                  final card = drawnCards[index];
                                  final bool isRevealed = card['isRevealed'] == true;

                                  return Container(
                                    margin: const EdgeInsets.only(bottom: 24),
                                    child: GestureDetector(
                                      onTap: () {
                                        setState(() {
                                          card['isRevealed'] = !isRevealed;
                                        });
                                      },
                                      child: Card(
                                        elevation: 12,
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(20),
                                        ),
                                        color: const Color(0xFF1F0033),
                                        child: AnimatedSwitcher(
                                          duration: const Duration(milliseconds: 400),
                                          child: isRevealed
                                              ? Column(
                                                  key: ValueKey('front_$index'),
                                                  children: [
                                                    const SizedBox(height: 16),
                                                    ClipRRect(
                                                      borderRadius: BorderRadius.circular(16),
                                                      child: Image.asset(
                                                        'assets/images/${card['image']}',
                                                        height: 240,
                                                        fit: BoxFit.contain,
                                                      ),
                                                    ),
                                                    Padding(
                                                      padding: const EdgeInsets.all(20),
                                                      child: Column(
                                                        children: [
                                                          Text(
                                                            card['name'],
                                                            style: const TextStyle(fontSize: 21, fontWeight: FontWeight.bold),
                                                            textAlign: TextAlign.center,
                                                          ),
                                                          const SizedBox(height: 12),
                                                          Text(
                                                            card['isReversed'] ? '逆位 ⚠️' : '正位 ✨',
                                                            style: TextStyle(
                                                              fontSize: 17,
                                                              color: card['isReversed']
                                                                  ? Colors.orangeAccent
                                                                  : Colors.greenAccent,
                                                              fontWeight: FontWeight.w600,
                                                            ),
                                                          ),
                                                          const SizedBox(height: 20),
                                                          Container(
                                                            padding: const EdgeInsets.all(18),
                                                            decoration: BoxDecoration(
                                                              color: const Color(0xFF2D0A4A),
                                                              borderRadius: BorderRadius.circular(16),
                                                              border: Border.all(
                                                                color: Colors.deepPurpleAccent.withValues(alpha: 0.4),
                                                              ),
                                                            ),
                                                            child: Text(
                                                              card['meaning'],
                                                              textAlign: TextAlign.justify,
                                                              style: const TextStyle(
                                                                height: 1.85,
                                                                fontSize: 17,
                                                              ),
                                                            ),
                                                          ),
                                                        ],
                                                      ),
                                                    ),
                                                  ],
                                                )
                                              : Center(
                                                  key: ValueKey('back_$index'),
                                                  child: Padding(
                                                    padding: const EdgeInsets.symmetric(vertical: 100),
                                                    child: Column(
                                                      children: const [
                                                        Icon(Icons.style, size: 85, color: Color(0xFFBB86FC)),
                                                        SizedBox(height: 20),
                                                        Text('点击翻牌', style: TextStyle(fontSize: 21, fontWeight: FontWeight.bold)),
                                                        SizedBox(height: 8),
                                                        Text('查看宇宙指引', style: TextStyle(fontSize: 15, color: Colors.white70)),
                                                      ],
                                                    ),
                                                  ),
                                                ),
                                        ),
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ),
                        ],
                      )
                    : Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.auto_awesome, size: 90, color: Colors.deepPurple.withValues(alpha: 0.4)),
                            const SizedBox(height: 24),
                            const Text(
                              '输入问题后\n点击「开始占卜」',
                              textAlign: TextAlign.center,
                              style: TextStyle(fontSize: 19, color: Colors.white70, height: 1.6),
                            ),
                          ],
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class ApiSettingsPage extends StatefulWidget {
  const ApiSettingsPage({super.key});

  @override
  State<ApiSettingsPage> createState() => _ApiSettingsPageState();
}

class _ApiSettingsPageState extends State<ApiSettingsPage> {
  final TextEditingController _apiKeyController = TextEditingController();
  bool _obscure = true;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _loadCurrentKey();
  }

  Future<void> _loadCurrentKey() async {
    final key = await ApiKeyStore.readDeepSeekKey();
    if (!mounted) return;
    _apiKeyController.text = key ?? '';
  }

  Future<void> _save() async {
    final key = _apiKeyController.text.trim();
    if (key.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请输入 API Key')),
      );
      return;
    }

    setState(() => _isSaving = true);
    await ApiKeyStore.saveDeepSeekKey(key);
    if (!mounted) return;
    setState(() => _isSaving = false);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('API Key 已保存')),
    );
    Navigator.of(context).pop(true);
  }

  Future<void> _clear() async {
    await ApiKeyStore.clearDeepSeekKey();
    if (!mounted) return;
    _apiKeyController.clear();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已清除 API Key')),
    );
    Navigator.of(context).pop(true);
  }

  @override
  void dispose() {
    _apiKeyController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('API 设置'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'DeepSeek API Key',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _apiKeyController,
              obscureText: _obscure,
              decoration: InputDecoration(
                hintText: '请输入 sk- 开头的 API Key',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                suffixIcon: IconButton(
                  icon: Icon(_obscure ? Icons.visibility : Icons.visibility_off),
                  onPressed: () => setState(() => _obscure = !_obscure),
                ),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              '仅保存在当前设备，用于 AI 深度解读。',
              style: TextStyle(color: Colors.white.withValues(alpha: 0.65), fontSize: 12),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _isSaving ? null : _save,
                child: _isSaving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('保存'),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: _clear,
                child: const Text('清除 Key'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}