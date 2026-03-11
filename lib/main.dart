import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:convert';
import 'dart:async';
import 'dart:math' as math;
import 'package:http/http.dart' as http;

void main() {
  runApp(const MyApp());
}

class GamingColors {
  static const Color bg = Color(0xFF05050A);
  static const Color surface = Color(0xFF0F0F1E);
  static const Color primary = Color(0xFF80D8FF); // Mentora Light Blue
  static const Color secondary = Color(0xFF0091EA); // Mentora Deep Blue
  static const Color accent = Color(0xFF8338EC); // Deep Purple
  static const Color success = Color(0xFF3A86FF); // Bright Blue
  static const Color textMain = Color(0xFFE0E0E0);
  static const Color textDim = Color(0xFF6B6B7B);
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MENTORA',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: GamingColors.bg,
        colorScheme: ColorScheme.fromSeed(
          seedColor: GamingColors.primary,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
        fontFamily: 'Resist Mono',
      ),
      home: const ChatScreen(),
    );
  }
}

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final List<Map<String, String>> _messages = [];
  List<Map<String, String>> _conversationHistory = [];
  bool _isLoading = false;

  final String apiUrl = "https://chatbot-ai-7034.onrender.com/chat";

  Future<void> sendMessage(String message) async {
    if (message.trim().isEmpty) return;

    final userMessage = {"role": "user", "content": message};

    setState(() {
      _messages.add(userMessage);
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
        _conversationHistory = List<Map<String, String>>.from(
          data["conversation_history"].map(
            (e) => Map<String, String>.from(e),
          ),
        );
        setState(() {
          _messages.add({"role": "assistant", "content": reply});
          _isLoading = false;
        });
      } else {
        _handleError("[SYSTEM_ERROR] :: UPLINK_FAILURE");
      }
    } catch (e) {
      _handleError("[TIMEOUT] :: RECONNECTING_TO_GRID...");
    }

    _scrollToBottom();
  }

  void _handleError(String errorMsg) {
    setState(() {
      _messages.add({"role": "assistant", "content": errorMsg});
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
            duration: const Duration(milliseconds: 200),
            curve: Curves.fastOutSlowIn,
          );
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(100),
        child: Container(
          decoration: BoxDecoration(
            color: GamingColors.surface,
            border: const Border(
              bottom: BorderSide(color: GamingColors.primary, width: 2),
            ),
            boxShadow: [
              BoxShadow(
                color: GamingColors.primary.withOpacity(0.1),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              child: Row(
                children: [
                  const SizedBox(
                    width: 60,
                    height: 60,
                    child: CustomPaint(
                      painter: MentoraLogoPainter(),
                    ),
                  ),
                  const SizedBox(width: 15),
                  Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "MENTORA",
                        style: TextStyle(
                          color: GamingColors.primary,
                          fontWeight: FontWeight.bold,
                          fontSize: 24,
                          letterSpacing: 4,
                          fontFamily: 'Resist Mono', // Keeping requested font or fallback
                        ),
                      ),
                      Text(
                        "INTELLIGENCE OS",
                        style: TextStyle(
                          color: GamingColors.textDim,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.5,
                        ),
                      ),
                    ],
                  ),
                  const Spacer(),
                ],
              ),
            ),
          ),
        ),
      ),
      body: Stack(
        children: [
          Positioned.fill(
            child: CustomPaint(
              painter: GridPainter(),
            ),
          ),
          Column(
            children: [
              Expanded(
                child: _messages.isEmpty
                    ? const EmptyState()
                    : ListView.builder(
                        controller: _scrollController,
                        padding: const EdgeInsets.all(20),
                        itemCount: _messages.length,
                        itemBuilder: (context, index) {
                          return MessageBubble(msg: _messages[index]);
                        },
                      ),
              ),
              _buildInput(),
            ],
          ),
          if (_isLoading)
            const Center(
              child: InnovativeLoading(),
            ),
        ],
      ),
    );
  }

  Widget _buildInput() {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 30),
      decoration: BoxDecoration(
        color: GamingColors.surface,
        border: const Border(
          top: BorderSide(color: GamingColors.primary, width: 1),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 15),
              decoration: BoxDecoration(
                color: GamingColors.bg,
                border: Border.all(color: GamingColors.primary.withOpacity(0.5)),
              ),
              child: TextField(
                controller: _controller,
                autofocus: true,
                style: const TextStyle(color: GamingColors.primary),
                decoration: const InputDecoration(
                  hintText: ">> TYPE_COMMAND...",
                  hintStyle: TextStyle(color: GamingColors.textDim, fontSize: 12),
                  border: InputBorder.none,
                ),
                onSubmitted: sendMessage,
              ),
            ),
          ),
          const SizedBox(width: 10),
          GestureDetector(
            onTap: () => sendMessage(_controller.text),
            child: Container(
              height: 48,
              width: 60,
              decoration: BoxDecoration(
                color: GamingColors.primary,
                boxShadow: [
                  BoxShadow(
                    color: GamingColors.primary.withOpacity(0.5),
                    blurRadius: 10,
                  ),
                ],
              ),
              child: const Icon(Icons.keyboard_double_arrow_right, color: Colors.black),
            ),
          ),
        ],
      ),
    );
  }
}

class MessageBubble extends StatelessWidget {
  final Map<String, String> msg;
  const MessageBubble({super.key, required this.msg});

  @override
  Widget build(BuildContext context) {
    final bool isUser = msg["role"] == "user";
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          Text(
            isUser ? ">> USER" : "<< MENTORA",
            style: TextStyle(
              color: isUser ? GamingColors.secondary : GamingColors.primary,
              fontSize: 10,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.5,
            ),
          ),
          const SizedBox(height: 4),
          Container(
            padding: const EdgeInsets.all(12),
            constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.85),
            decoration: BoxDecoration(
              color: GamingColors.surface.withOpacity(0.8),
              border: Border(
                left: isUser ? BorderSide.none : const BorderSide(color: GamingColors.primary, width: 2),
                right: isUser ? const BorderSide(color: GamingColors.secondary, width: 2) : BorderSide.none,
              ),
            ),
            child: Text(
              msg["content"]!,
              style: const TextStyle(
                color: GamingColors.textMain,
                fontSize: 14,
                height: 1.3,
              ),
            ),
          ),
          if (!isUser) ...[
            const SizedBox(height: 4),
            GestureDetector(
              onTap: () {
                Clipboard.setData(ClipboardData(text: msg["content"]!));
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: const Text("DATA_COPIED"),
                    backgroundColor: GamingColors.primary,
                    behavior: SnackBarBehavior.floating,
                    duration: const Duration(seconds: 1),
                  ),
                );
              },
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.copy_rounded, size: 12, color: GamingColors.textDim),
                  const SizedBox(width: 4),
                  Text(
                    "COPY",
                    style: TextStyle(
                      color: GamingColors.textDim,
                      fontSize: 8,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class InnovativeLoading extends StatefulWidget {
  const InnovativeLoading({super.key});

  @override
  State<InnovativeLoading> createState() => _InnovativeLoadingState();
}

class _InnovativeLoadingState extends State<InnovativeLoading> with TickerProviderStateMixin {
  late AnimationController _rotationController;
  late AnimationController _beforeRotationController;

  @override
  void initState() {
    super.initState();
    _rotationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    )..repeat();

    _beforeRotationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    )..repeat();
  }

  @override
  void dispose() {
    _rotationController.dispose();
    _beforeRotationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 70,
      height: 70,
      child: RotationTransition(
        turns: _rotationController,
        child: Stack(
          alignment: Alignment.center,
          children: [
            CustomPaint(
              size: const Size(70, 70),
              painter: LoaderPainter(),
            ),
            Positioned(
              bottom: 16,
              child: RotationTransition(
                turns: _beforeRotationController,
                alignment: const Alignment(0, 3.5),
                child: Container(
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(
                    color: GamingColors.accent,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class LoaderPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final centerPaint = Paint()..color = GamingColors.primary;
    canvas.drawCircle(Offset(size.width / 2, size.height / 2), 8, centerPaint);

    final bottomPaint = Paint()..color = GamingColors.secondary;
    canvas.drawCircle(Offset(size.width / 2, size.height - 6), 6, bottomPaint);
  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) => false;
}

class MentoraLogoPainter extends CustomPainter {
  const MentoraLogoPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final scale = size.width / 100;

    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3 * scale
      ..strokeCap = StrokeCap.round
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [GamingColors.primary, GamingColors.secondary],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));

    final detailPaint = Paint()
      ..style = PaintingStyle.fill
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [GamingColors.primary, GamingColors.secondary],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));

    for (int i = 0; i < 5; i++) {
      final double angle = (i * 72 * math.pi / 180) - (math.pi / 2);
      
      canvas.save();
      canvas.translate(center.dx, center.dy);
      canvas.rotate(angle);

      // Draw central petal loop
      final Path petal = Path();
      petal.moveTo(0, 0);
      petal.cubicTo(
        10 * scale, -20 * scale, 
        25 * scale, -10 * scale, 
        8 * scale, 4 * scale
      );
      canvas.drawPath(petal, paint);

      // Draw segmented tail
      for (int j = 1; j <= 4; j++) {
        double dist = (22 + j * 10) * scale;
        double segmentAngle = -0.3 + (j * 0.08); // Trailing curve
        double x = math.cos(segmentAngle) * dist;
        double y = math.sin(segmentAngle) * dist;
        
        canvas.save();
        canvas.translate(x, y);
        canvas.rotate(segmentAngle + math.pi/2);
        
        final double rectWidth = (7 - j) * scale;
        final double rectHeight = (12 - j) * scale;
        
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromCenter(center: Offset.zero, width: rectWidth, height: rectHeight),
            Radius.circular(3 * scale),
          ),
          detailPaint,
        );
        canvas.restore();
      }

      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) => false;
}

class EmptyState extends StatelessWidget {
  const EmptyState({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const SizedBox(
            width: 120,
            height: 120,
            child: CustomPaint(
              painter: MentoraLogoPainter(),
            ),
          ),
          const SizedBox(height: 30),
          const Text(
            "MENTORA",
            style: TextStyle(
              color: GamingColors.primary,
              fontSize: 36,
              fontWeight: FontWeight.bold,
              letterSpacing: 12,
            ),
          ),
          Text(
            "AI_CONNECTED",
            style: TextStyle(
              color: GamingColors.textDim.withOpacity(0.5),
              fontSize: 12,
              letterSpacing: 4,
            ),
          ),
        ],
      ),
    );
  }
}

class GridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = GamingColors.primary.withOpacity(0.04)
      ..strokeWidth = 1;

    for (double i = 0; i < size.width; i += 40) {
      canvas.drawLine(Offset(i, 0), Offset(i, size.height), paint);
    }
    for (double i = 0; i < size.height; i += 40) {
      canvas.drawLine(Offset(0, i), Offset(size.width, i), paint);
    }
  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) => false;
}
