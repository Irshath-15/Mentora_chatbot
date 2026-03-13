import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:convert';
import 'dart:async';
import 'dart:math' as math;
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:typed_data';

void main() {
  runApp(const MyApp());
}

// ─── COLOR PALETTE ───────────────────────────────────────────────
class CyberColors {
  static const Color bg         = Color(0xFF05050A);
  static const Color surface    = Color(0xFF0A0A14);
  static const Color surfaceAlt = Color(0xFF0F0F1E);
  static const Color primary    = Color(0xFF00F5FF);
  static const Color secondary  = Color(0xFFFF2D78);
  static const Color accent     = Color(0xFFBF00FF);
  static const Color yellow     = Color(0xFFFFE600);
  static const Color textMain   = Color(0xFFE0E0FF);
  static const Color textDim    = Color(0xFF4A4A6A);
}

// ─── CHAT SESSION MODEL ──────────────────────────────────────────
class ChatSession {
  final String id;
  final String title;
  final DateTime createdAt;
  final List<Map<String, String>> messages;

  ChatSession({
    required this.id,
    required this.title,
    required this.createdAt,
    required this.messages,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'createdAt': createdAt.toIso8601String(),
    'messages': messages,
  };

  factory ChatSession.fromJson(Map<String, dynamic> json) => ChatSession(
    id: json['id'],
    title: json['title'],
    createdAt: DateTime.parse(json['createdAt']),
    messages: List<Map<String, String>>.from(
      json['messages'].map((e) => Map<String, String>.from(e)),
    ),
  );
}

// ─── APP ─────────────────────────────────────────────────────────
class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MENTORA',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: CyberColors.bg,
        colorScheme: ColorScheme.fromSeed(
          seedColor: CyberColors.primary,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: const ChatScreen(),
    );
  }
}

// ─── CHAT SCREEN ─────────────────────────────────────────────────
class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _focusNode = FocusNode();
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  List<Map<String, String>> _messages = [];
  List<Map<String, String>> _conversationHistory = [];
  List<ChatSession> _chatSessions = [];
  String? _currentSessionId;

  bool _isLoading = false;
  bool _inputFocused = false;

  final String apiUrl = "https://chatbot-ai-7034.onrender.com/chat";

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(() {
      setState(() => _inputFocused = _focusNode.hasFocus);
    });
    _loadChatSessions();
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  // ─── STORAGE ─────────────────────────────────────────────────
  Future<void> _loadChatSessions() async {
    final prefs = await SharedPreferences.getInstance();
    final data = prefs.getString('chat_sessions');
    if (data != null) {
      final List decoded = jsonDecode(data);
      setState(() {
        _chatSessions = decoded
            .map((e) => ChatSession.fromJson(e))
            .toList()
          ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
      });
    }
  }

  Future<void> _saveChatSessions() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      'chat_sessions',
      jsonEncode(_chatSessions.map((e) => e.toJson()).toList()),
    );
  }

  void _saveCurrentSession() {
    if (_messages.isEmpty) return;

    final title = _messages.first['content']!.length > 35
        ? '${_messages.first['content']!.substring(0, 35)}...'
        : _messages.first['content']!;

    if (_currentSessionId != null) {
      final idx = _chatSessions.indexWhere((s) => s.id == _currentSessionId);
      if (idx != -1) {
        _chatSessions[idx] = ChatSession(
          id: _currentSessionId!,
          title: title,
          createdAt: _chatSessions[idx].createdAt,
          messages: List.from(_messages),
        );
      }
    } else {
      _currentSessionId = DateTime.now().millisecondsSinceEpoch.toString();
      _chatSessions.insert(
        0,
        ChatSession(
          id: _currentSessionId!,
          title: title,
          createdAt: DateTime.now(),
          messages: List.from(_messages),
        ),
      );
    }
    _saveChatSessions();
  }

  void _loadSession(ChatSession session) {
    setState(() {
      _messages = List.from(session.messages);
      _conversationHistory = session.messages
          .map((m) => {'role': m['role']!, 'content': m['content']!})
          .toList();
      _currentSessionId = session.id;
    });
    Navigator.pop(context);
    _scrollToBottom();
  }

  void _startNewChat() {
    setState(() {
      _messages = [];
      _conversationHistory = [];
      _currentSessionId = null;
    });
    Navigator.pop(context);
  }

  void _deleteSession(String id) {
    setState(() {
      _chatSessions.removeWhere((s) => s.id == id);
      if (_currentSessionId == id) {
        _messages = [];
        _conversationHistory = [];
        _currentSessionId = null;
      }
    });
    _saveChatSessions();
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date);
    if (diff.inMinutes < 1) return 'JUST_NOW';
    if (diff.inMinutes < 60) return '${diff.inMinutes}M_AGO';
    if (diff.inHours < 24) return '${diff.inHours}H_AGO';
    if (diff.inDays < 7) return '${diff.inDays}D_AGO';
    return '${date.day}/${date.month}/${date.year}';
  }

  // ─── SEND MESSAGE ─────────────────────────────────────────────
  Future<void> sendMessage(String message) async {
    if (message.trim().isEmpty) return;

    setState(() {
      _messages.add({"role": "user", "content": message});
      _isLoading = true;
    });

    _controller.clear();
    _scrollToBottom(immediate: true);

    try {
      final response = await http.post(
        Uri.parse(apiUrl),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "message": message,
          "conversation_history": _conversationHistory,
        }),
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
  final data = jsonDecode(response.body);
  final reply = data["reply"];
  final imageBase64 = data["image_base64"];

  // If image was generated show it
  if (imageBase64 != null) {
    _stopTypingAnimation();
    setState(() {
      _messages.add({
        "role": "assistant",
        "content": reply,
        "image": imageBase64
      });
      _isLoading = false;
    });
    _saveCurrentSession();
    return;
  }
        _conversationHistory = List<Map<String, String>>.from(
          data["conversation_history"].map((e) => Map<String, String>.from(e)),
        );
        setState(() {
          _messages.add({"role": "assistant", "content": reply});
          _isLoading = false;
        });
        _saveCurrentSession();
      } else {
        _handleError("[SYSTEM_ERROR] :: UPLINK_FAILURE");
      }
    } catch (e) {
      _handleError("[TIMEOUT] :: RECONNECTING_TO_GRID...");
    }

    _scrollToBottom();
  }

  void _handleError(String msg) {
    setState(() {
      _messages.add({"role": "assistant", "content": msg});
      _isLoading = false;
    });
  }

  void _scrollToBottom({bool immediate = false}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        if (immediate) {
          _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
        } else {
          _scrollController.animateTo(
            _scrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 250),
            curve: Curves.fastOutSlowIn,
          );
        }
      }
    });
  }

  // ─── CYBER DRAWER ─────────────────────────────────────────────
  Widget _buildDrawer() {
    return Drawer(
      backgroundColor: CyberColors.bg,
      child: Column(
        children: [
          // Drawer Header
          Container(
            padding: const EdgeInsets.fromLTRB(20, 52, 20, 16),
            decoration: BoxDecoration(
              color: CyberColors.surfaceAlt,
              border: Border(
                bottom: BorderSide(
                  color: CyberColors.primary.withOpacity(0.4),
                  width: 1,
                ),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        border: Border.all(color: CyberColors.primary, width: 2),
                        boxShadow: [
                          BoxShadow(
                            color: CyberColors.primary.withOpacity(0.3),
                            blurRadius: 12,
                          ),
                        ],
                      ),
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          Transform.rotate(
                            angle: math.pi / 4,
                            child: Container(
                              width: 24,
                              height: 24,
                              decoration: BoxDecoration(
                                border: Border.all(
                                  color: CyberColors.primary.withOpacity(0.3),
                                ),
                              ),
                            ),
                          ),
                          const Text(
                            "M",
                            style: TextStyle(
                              color: CyberColors.primary,
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              fontFamily: 'monospace',
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          "MENTORA",
                          style: TextStyle(
                            color: CyberColors.primary,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            fontFamily: 'monospace',
                            letterSpacing: 4,
                          ),
                        ),
                        Text(
                          "CHAT_HISTORY",
                          style: TextStyle(
                            color: CyberColors.textDim,
                            fontSize: 9,
                            fontFamily: 'monospace',
                            letterSpacing: 3,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 14),

                // New Chat Button
                GestureDetector(
                  onTap: _startNewChat,
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    decoration: BoxDecoration(
                      color: CyberColors.primary.withOpacity(0.1),
                      border: Border.all(color: CyberColors.primary),
                      boxShadow: [
                        BoxShadow(
                          color: CyberColors.primary.withOpacity(0.2),
                          blurRadius: 10,
                        ),
                      ],
                    ),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.add, color: CyberColors.primary, size: 14),
                        SizedBox(width: 8),
                        Text(
                          "[ NEW_SESSION ]",
                          style: TextStyle(
                            color: CyberColors.primary,
                            fontSize: 11,
                            fontFamily: 'monospace',
                            letterSpacing: 2,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Recent Label
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
            child: Row(
              children: [
                Container(
                  width: 16,
                  height: 1,
                  color: CyberColors.accent,
                ),
                const SizedBox(width: 8),
                const Text(
                  "RECENT_SESSIONS",
                  style: TextStyle(
                    color: CyberColors.accent,
                    fontSize: 9,
                    fontFamily: 'monospace',
                    letterSpacing: 3,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Container(
                    height: 1,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          CyberColors.accent.withOpacity(0.5),
                          Colors.transparent,
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Sessions List
          Expanded(
            child: _chatSessions.isEmpty
                ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.storage_outlined,
                    color: CyberColors.textDim,
                    size: 36,
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    "NO_SESSIONS_FOUND",
                    style: TextStyle(
                      color: CyberColors.textDim,
                      fontSize: 10,
                      fontFamily: 'monospace',
                      letterSpacing: 2,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    "START A NEW SESSION",
                    style: TextStyle(
                      color: CyberColors.textDim,
                      fontSize: 9,
                      fontFamily: 'monospace',
                      letterSpacing: 2,
                    ),
                  ),
                ],
              ),
            )
                : ListView.builder(
              padding: const EdgeInsets.symmetric(
                  horizontal: 10, vertical: 4),
              itemCount: _chatSessions.length,
              itemBuilder: (context, index) {
                final session = _chatSessions[index];
                final isActive = session.id == _currentSessionId;
                return GestureDetector(
                  onTap: () => _loadSession(session),
                  child: Container(
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: isActive
                          ? CyberColors.primary.withOpacity(0.08)
                          : CyberColors.surfaceAlt,
                      border: Border(
                        left: BorderSide(
                          color: isActive
                              ? CyberColors.primary
                              : CyberColors.accent.withOpacity(0.3),
                          width: 2,
                        ),
                        top: BorderSide(
                          color: isActive
                              ? CyberColors.primary.withOpacity(0.2)
                              : Colors.transparent,
                        ),
                      ),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                session.title.toUpperCase(),
                                style: TextStyle(
                                  color: isActive
                                      ? CyberColors.primary
                                      : CyberColors.textMain,
                                  fontSize: 11,
                                  fontFamily: 'monospace',
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 1,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 4),
                              Text(
                                _formatDate(session.createdAt),
                                style: const TextStyle(
                                  color: CyberColors.textDim,
                                  fontSize: 9,
                                  fontFamily: 'monospace',
                                  letterSpacing: 2,
                                ),
                              ),
                            ],
                          ),
                        ),
                        GestureDetector(
                          onTap: () => _deleteSession(session.id),
                          child: Container(
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              border: Border.all(
                                color: CyberColors.secondary.withOpacity(0.3),
                              ),
                            ),
                            child: const Icon(
                              Icons.delete_outline,
                              color: CyberColors.secondary,
                              size: 14,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),

          // Drawer Footer
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              border: Border(
                top: BorderSide(
                  color: CyberColors.primary.withOpacity(0.2),
                ),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  "SESSIONS::${_chatSessions.length.toString().padLeft(3, '0')}",
                  style: const TextStyle(
                    color: CyberColors.textDim,
                    fontSize: 9,
                    fontFamily: 'monospace',
                    letterSpacing: 2,
                  ),
                ),
                const _BlinkingText(
                  text: "◈ MEMORY_ACTIVE",
                  color: CyberColors.accent,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _scaffoldKey,
      drawer: _buildDrawer(),
      body: Stack(
        children: [
          const Positioned.fill(child: GridBackground()),
          const Positioned.fill(child: ScanlineOverlay()),
          const Positioned.fill(child: CornerAccents()),
          Column(
            children: [
              // Header with menu button
              _buildHeader(),
              Expanded(
                child: _messages.isEmpty
                    ? const EmptyState()
                    : ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.all(20),
                  itemCount: _messages.length + (_isLoading ? 1 : 0),
                  itemBuilder: (context, index) {
                    if (_isLoading && index == _messages.length) {
                      return const CyberLoader();
                    }
                    return MessageBubble(
                      msg: _messages[index],
                      index: index,
                    );
                  },
                ),
              ),
              _buildInputArea(),
            ],
          ),
        ],
      ),
    );
  }

  // ─── HEADER WITH MENU ────────────────────────────────────────
  Widget _buildHeader() {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [CyberColors.surfaceAlt, CyberColors.bg.withOpacity(0)],
        ),
        border: const Border(
          bottom: BorderSide(color: Color(0x3300F5FF), width: 1),
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          child: Row(
            children: [
              // Menu Button
              GestureDetector(
                onTap: () => _scaffoldKey.currentState?.openDrawer(),
                child: Container(
                  width: 40,
                  height: 40,
                  margin: const EdgeInsets.only(right: 12),
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: CyberColors.primary.withOpacity(0.5),
                    ),
                    color: CyberColors.primary.withOpacity(0.05),
                  ),
                  child: const Icon(
                    Icons.menu,
                    color: CyberColors.primary,
                    size: 18,
                  ),
                ),
              ),

              // Logo box
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  border: Border.all(color: CyberColors.primary, width: 2),
                  boxShadow: [
                    BoxShadow(
                      color: CyberColors.primary.withOpacity(0.3),
                      blurRadius: 16,
                    ),
                    BoxShadow(
                      color: CyberColors.primary.withOpacity(0.1),
                      blurRadius: 6,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Transform.rotate(
                      angle: math.pi / 4,
                      child: Container(
                        width: 26,
                        height: 26,
                        decoration: BoxDecoration(
                          border: Border.all(
                            color: CyberColors.primary.withOpacity(0.4),
                            width: 1,
                          ),
                        ),
                      ),
                    ),
                    const Text(
                      "M",
                      style: TextStyle(
                        color: CyberColors.primary,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 14),

              // Title
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const _GlitchText(text: "MENTORA", fontSize: 22),
                  Row(
                    children: [
                      for (final (i, t) in [
                        "INTELLIGENCE",
                        "OS",
                        "v2.4.1"
                      ].indexed) ...[
                        Text(
                          t,
                          style: const TextStyle(
                            color: CyberColors.textDim,
                            fontSize: 8,
                            letterSpacing: 2,
                            fontFamily: 'monospace',
                          ),
                        ),
                        if (i < 2)
                          Container(
                            margin:
                            const EdgeInsets.symmetric(horizontal: 6),
                            width: 1,
                            height: 8,
                            color: CyberColors.textDim.withOpacity(0.4),
                          ),
                      ],
                    ],
                  ),
                ],
              ),
              const Spacer(),

              // New chat icon
              GestureDetector(
                onTap: () {
                  setState(() {
                    _messages = [];
                    _conversationHistory = [];
                    _currentSessionId = null;
                  });
                },
                child: Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: CyberColors.accent.withOpacity(0.5),
                    ),
                    color: CyberColors.accent.withOpacity(0.05),
                  ),
                  child: const Icon(
                    Icons.add,
                    color: CyberColors.accent,
                    size: 16,
                  ),
                ),
              ),

              const SizedBox(width: 8),

              // Status pills
              Wrap(
                spacing: 6,
                children: const [
                  StatusPill(
                      label: "UPLINK",
                      color: CyberColors.primary,
                      blink: true),
                  StatusPill(label: "ENC_256", color: CyberColors.accent),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInputArea() {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [
            CyberColors.surfaceAlt,
            CyberColors.bg.withOpacity(0),
          ],
        ),
        border: Border(
          top: BorderSide(
              color: CyberColors.secondary.withOpacity(0.3), width: 1),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(width: 20, height: 1, color: CyberColors.primary),
              const SizedBox(width: 8),
              const Text(
                "COMMAND_TERMINAL",
                style: TextStyle(
                  color: CyberColors.primary,
                  fontSize: 8,
                  fontFamily: 'monospace',
                  letterSpacing: 3,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Container(
                  height: 1,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        CyberColors.primary.withOpacity(0.5),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              ),
              const Text(
                "ENTER TO SEND",
                style: TextStyle(
                  color: CyberColors.textDim,
                  fontSize: 8,
                  fontFamily: 'monospace',
                  letterSpacing: 2,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Container(
                padding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
                decoration: BoxDecoration(
                  color: CyberColors.primary.withOpacity(0.1),
                  border:
                  Border.all(color: CyberColors.primary.withOpacity(0.4)),
                ),
                child: const Text(
                  "ROOT@MENTORA:~\$",
                  style: TextStyle(
                    color: CyberColors.primary,
                    fontSize: 11,
                    fontFamily: 'monospace',
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  decoration: BoxDecoration(
                    color: CyberColors.bg,
                    border: Border.all(
                      color: _inputFocused
                          ? CyberColors.primary
                          : CyberColors.primary.withOpacity(0.3),
                      width: 1,
                    ),
                    boxShadow: _inputFocused
                        ? [
                      BoxShadow(
                          color: CyberColors.primary.withOpacity(0.2),
                          blurRadius: 14)
                    ]
                        : [],
                  ),
                  child: TextField(
                    controller: _controller,
                    focusNode: _focusNode,
                    style: const TextStyle(
                      color: CyberColors.primary,
                      fontSize: 13,
                      fontFamily: 'monospace',
                    ),
                    cursorColor: CyberColors.primary,
                    decoration: const InputDecoration(
                      hintText: ">> TYPE_COMMAND...",
                      hintStyle: TextStyle(
                        color: CyberColors.textDim,
                        fontSize: 12,
                        fontFamily: 'monospace',
                      ),
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.symmetric(
                          horizontal: 14, vertical: 13),
                    ),
                    onSubmitted: sendMessage,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: () => sendMessage(_controller.text),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  height: 48,
                  width: 64,
                  decoration: BoxDecoration(
                    color: _isLoading
                        ? CyberColors.primary.withOpacity(0.1)
                        : CyberColors.primary.withOpacity(0.15),
                    border: Border.all(
                      color: _isLoading
                          ? CyberColors.textDim
                          : CyberColors.primary,
                    ),
                    boxShadow: _isLoading
                        ? []
                        : [
                      BoxShadow(
                          color: CyberColors.primary.withOpacity(0.35),
                          blurRadius: 12)
                    ],
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.double_arrow_rounded,
                        color: _isLoading
                            ? CyberColors.textDim
                            : CyberColors.primary,
                        size: 18,
                      ),
                      Text(
                        "SEND",
                        style: TextStyle(
                          color: _isLoading
                              ? CyberColors.textDim
                              : CyberColors.primary,
                          fontSize: 7,
                          fontFamily: 'monospace',
                          letterSpacing: 2,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Text(
                "SESSION::XK-${(math.Random().nextInt(9000) + 1000)}",
                style: const TextStyle(
                  color: CyberColors.textDim,
                  fontSize: 8,
                  fontFamily: 'monospace',
                  letterSpacing: 2,
                ),
              ),
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 10),
                width: 1,
                height: 10,
                color: CyberColors.textDim.withOpacity(0.4),
              ),
              Text(
                "MSGS::${_messages.length.toString().padLeft(3, '0')}",
                style: const TextStyle(
                  color: CyberColors.textDim,
                  fontSize: 8,
                  fontFamily: 'monospace',
                  letterSpacing: 2,
                ),
              ),
              const Spacer(),
              const _BlinkingText(
                text: "◈ SECURE_CHANNEL_ACTIVE",
                color: CyberColors.accent,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─── STATUS PILL ─────────────────────────────────────────────────
class StatusPill extends StatelessWidget {
  final String label;
  final Color color;
  final bool blink;

  const StatusPill({
    super.key,
    required this.label,
    required this.color,
    this.blink = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          blink
              ? _BlinkingDot(color: color)
              : Container(
            width: 5,
            height: 5,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              boxShadow: [BoxShadow(color: color, blurRadius: 4)],
            ),
          ),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 8,
              fontFamily: 'monospace',
              letterSpacing: 2,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── MESSAGE BUBBLE ──────────────────────────────────────────────
class MessageBubble extends StatelessWidget {
  final Map<String, String> msg;
  final int index;

  const MessageBubble({super.key, required this.msg, required this.index});

  @override
  Widget build(BuildContext context) {
    final bool isUser = msg["role"] == "user";
    final Color accent =
    isUser ? CyberColors.secondary : CyberColors.primary;

    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment:
        isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!isUser)
                Container(
                  margin: const EdgeInsets.only(right: 6),
                  width: 18,
                  height: 18,
                  decoration: BoxDecoration(
                    border: Border.all(color: CyberColors.primary),
                  ),
                  child: const Center(
                    child: Text(
                      "AI",
                      style: TextStyle(
                        color: CyberColors.primary,
                        fontSize: 7,
                        fontFamily: 'monospace',
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              Text(
                isUser ? "▶ USER_INPUT" : "◀ MENTORA.OS",
                style: TextStyle(
                  color: accent,
                  fontSize: 9,
                  fontFamily: 'monospace',
                  letterSpacing: 2,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 5),
          Stack(
            children: [
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: MediaQuery.of(context).size.width * 0.82,
                ),
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        accent.withOpacity(0.08),
                        CyberColors.surfaceAlt,
                      ],
                    ),
                    border: Border(
                      left: isUser
                          ? BorderSide.none
                          : BorderSide(color: accent, width: 2),
                      right: isUser
                          ? BorderSide(color: accent, width: 2)
                          : BorderSide.none,
                      top: BorderSide(
                          color: accent.withOpacity(0.2), width: 1),
                      bottom: BorderSide(
                          color: accent.withOpacity(0.1), width: 1),
                    ),
                  ),
                  child: Column(
  crossAxisAlignment: CrossAxisAlignment.start,
  children: [
    Text(
      msg["content"]!,
      style: const TextStyle(
        color: CyberColors.textMain,
        fontSize: 13,
        height: 1.6,
        fontFamily: 'monospace',
      ),
    ),
    if (msg["image"] != null) ...[
      const SizedBox(height: 10),
      ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image.memory(
          base64Decode(msg["image"]!),
          fit: BoxFit.cover,
        ),
      ),
    ],
  ],
),
                ),
              ),
              Positioned(
                  top: 0, left: 0, child: _Corner(color: accent)),
              Positioned(
                  top: 0,
                  right: 0,
                  child: _Corner(color: accent, flipH: true)),
              Positioned(
                  bottom: 0,
                  left: 0,
                  child: _Corner(color: accent, flipV: true)),
              Positioned(
                  bottom: 0,
                  right: 0,
                  child: _Corner(color: accent, flipH: true, flipV: true)),
            ],
          ),
          if (!isUser)
            Padding(
              padding: const EdgeInsets.only(top: 5),
              child: GestureDetector(
                onTap: () {
                  Clipboard.setData(
                      ClipboardData(text: msg["content"]!));
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: const Text(
                        "DATA COPIED TO CLIPBOARD",
                        style: TextStyle(
                            fontFamily: 'monospace',
                            letterSpacing: 2,
                            fontSize: 11),
                      ),
                      backgroundColor: CyberColors.primary,
                      behavior: SnackBarBehavior.floating,
                      duration: const Duration(seconds: 1),
                      shape: const RoundedRectangleBorder(
                          borderRadius: BorderRadius.zero),
                    ),
                  );
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    border: Border.all(
                        color: CyberColors.textDim.withOpacity(0.4)),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.copy_rounded,
                          size: 10, color: CyberColors.textDim),
                      SizedBox(width: 4),
                      Text(
                        "⧉ COPY_DATA",
                        style: TextStyle(
                          color: CyberColors.textDim,
                          fontSize: 8,
                          fontFamily: 'monospace',
                          letterSpacing: 2,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ─── CORNER BRACKET ──────────────────────────────────────────────
class _Corner extends StatelessWidget {
  final Color color;
  final bool flipH;
  final bool flipV;

  const _Corner({required this.color, this.flipH = false, this.flipV = false});

  @override
  Widget build(BuildContext context) {
    return Transform.scale(
      scaleX: flipH ? -1 : 1,
      scaleY: flipV ? -1 : 1,
      child: SizedBox(
        width: 10,
        height: 10,
        child: CustomPaint(painter: _CornerPainter(color: color)),
      ),
    );
  }
}

class _CornerPainter extends CustomPainter {
  final Color color;
  const _CornerPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;
    canvas.drawLine(Offset.zero, Offset(size.width, 0), paint);
    canvas.drawLine(Offset.zero, Offset(0, size.height), paint);
  }

  @override
  bool shouldRepaint(_CornerPainter old) => old.color != color;
}

// ─── CYBER LOADER ────────────────────────────────────────────────
class CyberLoader extends StatefulWidget {
  const CyberLoader({super.key});

  @override
  State<CyberLoader> createState() => _CyberLoaderState();
}

class _CyberLoaderState extends State<CyberLoader>
    with TickerProviderStateMixin {
  late AnimationController _spinController;
  late List<AnimationController> _letterControllers;
  final String _text = "PROCESSING";

  @override
  void initState() {
    super.initState();
    _spinController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..repeat();

    _letterControllers = List.generate(_text.length, (i) {
      return AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 600),
      )..repeat(reverse: true);
    });

    for (int i = 0; i < _letterControllers.length; i++) {
      Future.delayed(Duration(milliseconds: i * 80), () {
        if (mounted) _letterControllers[i].forward();
      });
    }
  }

  @override
  void dispose() {
    _spinController.dispose();
    for (final c in _letterControllers) c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "◀ MENTORA.OS",
            style: TextStyle(
              color: CyberColors.primary,
              fontSize: 9,
              fontFamily: 'monospace',
              letterSpacing: 2,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 5),
          Container(
            padding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              border: const Border(
                left: BorderSide(color: CyberColors.primary, width: 2),
                top: BorderSide(color: Color(0x2200F5FF)),
              ),
              color: CyberColors.primary.withOpacity(0.05),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                RotationTransition(
                  turns: _spinController,
                  child: Container(
                    width: 20,
                    height: 20,
                    decoration: BoxDecoration(
                      border: Border.all(
                          color: CyberColors.primary, width: 2),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Container(
                      margin: const EdgeInsets.only(top: 2),
                      decoration: const BoxDecoration(
                        color: CyberColors.primary,
                        borderRadius: BorderRadius.only(
                          topLeft: Radius.circular(8),
                          topRight: Radius.circular(8),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                ...List.generate(_text.length, (i) {
                  return AnimatedBuilder(
                    animation: _letterControllers[i],
                    builder: (_, __) {
                      return Opacity(
                        opacity:
                        0.3 + (_letterControllers[i].value * 0.7),
                        child: Text(
                          _text[i],
                          style: const TextStyle(
                            color: CyberColors.primary,
                            fontSize: 11,
                            fontFamily: 'monospace',
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1,
                          ),
                        ),
                      );
                    },
                  );
                }),
                const SizedBox(width: 4),
                const _BlinkingText(
                    text: "▮",
                    color: CyberColors.accent,
                    fontSize: 11),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── EMPTY STATE ─────────────────────────────────────────────────
class EmptyState extends StatelessWidget {
  const EmptyState({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              border: Border.all(color: CyberColors.primary, width: 2),
              boxShadow: [
                BoxShadow(
                    color: CyberColors.primary.withOpacity(0.3),
                    blurRadius: 30),
              ],
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                Transform.rotate(
                  angle: math.pi / 4,
                  child: Container(
                    width: 50,
                    height: 50,
                    decoration: BoxDecoration(
                      border: Border.all(
                          color: CyberColors.primary.withOpacity(0.3)),
                    ),
                  ),
                ),
                const Text(
                  "M",
                  style: TextStyle(
                    color: CyberColors.primary,
                    fontSize: 30,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'monospace',
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 28),
          const _GlitchText(text: "MENTORA", fontSize: 32),
          const SizedBox(height: 8),
          Text(
            "AI_CONNECTED  ::  AWAITING_INPUT",
            style: TextStyle(
              color: CyberColors.textDim.withOpacity(0.6),
              fontSize: 10,
              letterSpacing: 4,
              fontFamily: 'monospace',
            ),
          ),
          const SizedBox(height: 20),
          const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              StatusPill(
                  label: "UPLINK_ACTIVE",
                  color: CyberColors.primary,
                  blink: true),
              SizedBox(width: 8),
              StatusPill(
                  label: "NEURAL_LINK_READY",
                  color: CyberColors.accent),
            ],
          ),
        ],
      ),
    );
  }
}

// ─── GLITCH TEXT ─────────────────────────────────────────────────
class _GlitchText extends StatefulWidget {
  final String text;
  final double fontSize;

  const _GlitchText({required this.text, this.fontSize = 22});

  @override
  State<_GlitchText> createState() => _GlitchTextState();
}

class _GlitchTextState extends State<_GlitchText>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  bool _showGlitch = false;
  Timer? _glitchTimer;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 100),
    );
    _scheduleGlitch();
  }

  void _scheduleGlitch() {
    _glitchTimer =
        Timer(Duration(milliseconds: 3000 + math.Random().nextInt(4000)),
                () {
              if (!mounted) return;
              setState(() => _showGlitch = true);
              Timer(const Duration(milliseconds: 150), () {
                if (!mounted) return;
                setState(() => _showGlitch = false);
                _scheduleGlitch();
              });
            });
  }

  @override
  void dispose() {
    _controller.dispose();
    _glitchTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Text(
          widget.text,
          style: TextStyle(
            color: CyberColors.primary,
            fontSize: widget.fontSize,
            fontWeight: FontWeight.bold,
            fontFamily: 'monospace',
            letterSpacing: 6,
            shadows: [
              Shadow(
                  color: CyberColors.primary.withOpacity(0.8),
                  blurRadius: 12),
              Shadow(
                  color: CyberColors.primary.withOpacity(0.4),
                  blurRadius: 24),
            ],
          ),
        ),
        if (_showGlitch)
          Transform.translate(
            offset: const Offset(3, -2),
            child: Text(
              widget.text,
              style: TextStyle(
                color: CyberColors.secondary.withOpacity(0.7),
                fontSize: widget.fontSize,
                fontWeight: FontWeight.bold,
                fontFamily: 'monospace',
                letterSpacing: 6,
              ),
            ),
          ),
      ],
    );
  }
}

// ─── BLINKING TEXT ───────────────────────────────────────────────
class _BlinkingText extends StatefulWidget {
  final String text;
  final Color color;
  final double fontSize;

  const _BlinkingText({
    required this.text,
    required this.color,
    this.fontSize = 8,
  });

  @override
  State<_BlinkingText> createState() => _BlinkingTextState();
}

class _BlinkingTextState extends State<_BlinkingText>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _anim = CurvedAnimation(parent: _controller, curve: Curves.easeInOut);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _anim,
      child: Text(
        widget.text,
        style: TextStyle(
          color: widget.color,
          fontSize: widget.fontSize,
          fontFamily: 'monospace',
          letterSpacing: 2,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

// ─── BLINKING DOT ────────────────────────────────────────────────
class _BlinkingDot extends StatefulWidget {
  final Color color;
  const _BlinkingDot({required this.color});

  @override
  State<_BlinkingDot> createState() => _BlinkingDotState();
}

class _BlinkingDotState extends State<_BlinkingDot>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _controller,
      child: Container(
        width: 5,
        height: 5,
        decoration: BoxDecoration(
          color: widget.color,
          shape: BoxShape.circle,
          boxShadow: [BoxShadow(color: widget.color, blurRadius: 4)],
        ),
      ),
    );
  }
}

// ─── GRID BACKGROUND ─────────────────────────────────────────────
class GridBackground extends StatelessWidget {
  const GridBackground({super.key});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(painter: _GridPainter());
  }
}

class _GridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = CyberColors.primary.withOpacity(0.03)
      ..strokeWidth = 1;

    for (double x = 0; x < size.width; x += 40) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (double y = 0; y < size.height; y += 40) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(_GridPainter old) => false;
}

// ─── SCANLINE OVERLAY ────────────────────────────────────────────
class ScanlineOverlay extends StatelessWidget {
  const ScanlineOverlay({super.key});

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: CustomPaint(painter: _ScanlinePainter()),
    );
  }
}

class _ScanlinePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = Colors.black.withOpacity(0.06);
    for (double y = 0; y < size.height; y += 4) {
      canvas.drawRect(Rect.fromLTWH(0, y + 2, size.width, 2), paint);
    }
  }

  @override
  bool shouldRepaint(_ScanlinePainter old) => false;
}

// ─── CORNER ACCENTS ──────────────────────────────────────────────
class CornerAccents extends StatelessWidget {
  const CornerAccents({super.key});

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: CustomPaint(painter: _CornerAccentPainter()),
    );
  }
}

class _CornerAccentPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final cyanPaint = Paint()
      ..shader = LinearGradient(
        colors: [CyberColors.primary, Colors.transparent],
      ).createShader(const Rect.fromLTWH(0, 0, 80, 2))
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    final pinkPaint = Paint()
      ..shader = LinearGradient(
        colors: [Colors.transparent, CyberColors.secondary],
      ).createShader(Rect.fromLTWH(size.width - 80, 0, 80, 2))
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    canvas.drawLine(const Offset(0, 0), const Offset(80, 0), cyanPaint);
    canvas.drawLine(
      const Offset(0, 0),
      const Offset(0, 80),
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [CyberColors.primary, Colors.transparent],
        ).createShader(const Rect.fromLTWH(0, 0, 2, 80))
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke,
    );

    canvas.drawLine(
        Offset(size.width - 80, 0), Offset(size.width, 0), pinkPaint);
    canvas.drawLine(
      Offset(size.width, 0),
      Offset(size.width, 80),
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [CyberColors.secondary, Colors.transparent],
        ).createShader(Rect.fromLTWH(size.width - 2, 0, 2, 80))
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke,
    );
  }

  @override
  bool shouldRepaint(_CornerAccentPainter old) => false;
}