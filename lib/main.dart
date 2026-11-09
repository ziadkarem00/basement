import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'config.dart';
import 'navigation.dart';
import 'theme.dart';
import 'src/rust/api/simple.dart';
import 'src/rust/frb_generated.dart';
import 'widgets/private_text_field.dart';

String _cachedDeviceId = '';
Future<String> _getDeviceId() async {
  if (_cachedDeviceId.isNotEmpty) return _cachedDeviceId;
  try {
    final file = File('${Directory.systemTemp.path}/basement_device_id.txt');
    if (await file.exists()) {
      final id = (await file.readAsString()).trim();
      if (id.isNotEmpty) {
        _cachedDeviceId = id;
        return _cachedDeviceId;
      }
    }
    final newId = '${DateTime.now().millisecondsSinceEpoch}_${Random().nextInt(1000000)}';
    await file.writeAsString(newId);
    _cachedDeviceId = newId;
    return _cachedDeviceId;
  } catch (_) {
    if (_cachedDeviceId.isEmpty) {
      _cachedDeviceId = '${DateTime.now().millisecondsSinceEpoch}_${Random().nextInt(1000000)}';
    }
    return _cachedDeviceId;
  }
}

Future<void> main() async {
  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();
    FlutterError.onError = (FlutterErrorDetails details) {
      FlutterError.presentError(details);
    };
    ErrorWidget.builder = (FlutterErrorDetails details) {
      return Scaffold(
        backgroundColor: AppTheme.background,
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Something went wrong',
                style: TextStyle(color: AppTheme.text, fontSize: 16),
              ),
              const SizedBox(height: 16),
              OutlinedButton(
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  side: const BorderSide(color: Colors.white38),
                  shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
                ),
                onPressed: () => goHome(),
                child: const Text('GO HOME', style: TextStyle(letterSpacing: 1.5)),
              ),
            ],
          ),
        ),
      );
    };
    homeScreenBuilder = () => const HomeScreen();
    await RustLib.init();
    runApp(const BasementApp());
  }, (error, stack) {
    debugPrint('Uncaught async error: $error\n$stack');
  });
}

class BasementApp extends StatelessWidget {
  const BasementApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: navigatorKey,
      scaffoldMessengerKey: scaffoldMessengerKey,
      title: 'Basement',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: AppTheme.background,
        canvasColor: AppTheme.background,
        dialogTheme: const DialogThemeData(backgroundColor: Color(0xFF111111)),
        colorScheme: const ColorScheme.dark(
          surface: AppTheme.background,
          primary: Colors.white,
          onPrimary: Colors.black,
          onSurface: Colors.white,
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: AppTheme.background,
          foregroundColor: Colors.white,
          elevation: 0,
          centerTitle: true,
          titleTextStyle: TextStyle(
            color: Colors.white,
            fontSize: 17,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.5,
          ),
        ),
        textTheme: const TextTheme(
          bodyLarge: TextStyle(color: AppTheme.text),
          bodyMedium: TextStyle(color: AppTheme.text),
        ),
        snackBarTheme: const SnackBarThemeData(
          backgroundColor: Color(0xFF222222),
          contentTextStyle: TextStyle(color: AppTheme.text),
        ),
      ),
      home: const HomeScreen(),
    );
  }
}

// ==========================================
// 1. HOME SCREEN
// ==========================================
class HomeScreen extends StatefulWidget {
  final String? snackbarMessage;
  const HomeScreen({super.key, this.snackbarMessage});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  @override
  void initState() {
    super.initState();
    if (widget.snackbarMessage != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(widget.snackbarMessage!),
            backgroundColor: const Color(0xFF222222),
            duration: const Duration(seconds: 3),
          ),
        );
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text(
                  'BASEMENT',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 6,
                  ),
                ),
                const SizedBox(height: 64),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: const BorderSide(color: Colors.white, width: 1.5),
                      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
                    ),
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const CreateRoomScreen()),
                      );
                    },
                    child: const Text('CREATE ROOM', style: TextStyle(letterSpacing: 2, fontWeight: FontWeight.bold)),
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: const BorderSide(color: Colors.white, width: 1.5),
                      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
                    ),
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const EnterRoomScreen()),
                      );
                    },
                    child: const Text('ENTER ROOM', style: TextStyle(letterSpacing: 2, fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ==========================================
// 2. CREATE ROOM SCREEN
// ==========================================
class CreateRoomScreen extends StatefulWidget {
  const CreateRoomScreen({super.key});

  @override
  State<CreateRoomScreen> createState() => _CreateRoomScreenState();
}

class _CreateRoomScreenState extends State<CreateRoomScreen> {
  final TextEditingController _nameController = TextEditingController();
  final FocusNode _nameFocus = FocusNode();

  String? _cleanedName;
  String? _generatedCode;
  String? _myId;
  WebSocketChannel? _activeChannel;
  String _errorMessage = '';

  @override
  void dispose() {
    _nameController.dispose();
    _nameFocus.dispose();
    _activeChannel?.sink.close();
    super.dispose();
  }

  Future<void> _onCreateNext() async {
    final raw = _nameController.text;
    final cleaned = cleanName(input: raw);

    if (cleaned == null || cleaned.isEmpty) {
      setState(() {
        _errorMessage = 'Name is required';
      });
      return;
    }

    setState(() {
      _errorMessage = '';
      _cleanedName = cleaned;
      _generatedCode = generateRoomCode();
    });

    final code = _generatedCode!;
    final name = _cleanedName!;
    final myId = 'id_${Random().nextInt(10000000)}';
    _myId = myId;

    final deviceId = await _getDeviceId();
    final url = '$serverWsUrl/room/$code/ws?name=${Uri.encodeComponent(name)}&id=${Uri.encodeComponent(myId)}&deviceId=${Uri.encodeComponent(deviceId)}&platform=app&create=1';
    _activeChannel = WebSocketChannel.connect(Uri.parse(url));
  }

  void _copyCode() {
    if (_generatedCode == null) return;
    Clipboard.setData(ClipboardData(text: _generatedCode!));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Copied')),
    );
  }

  void _copyInviteLink() {
    if (_generatedCode == null) return;
    Clipboard.setData(ClipboardData(text: '$WEB_URL/#$_generatedCode'));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Copied')),
    );
  }

  Future<void> _handleLeaveCreator() async {
    if (_generatedCode == null) {
      goHome();
      return;
    }

    final close = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF111111),
        title: const Text(
          'Close the basement? This removes everyone and deletes all messages.',
          style: TextStyle(color: Colors.white, fontSize: 16),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('CANCEL', style: TextStyle(color: Colors.grey)),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('CLOSE', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (close == true) {
      try {
        _activeChannel?.sink.add(jsonEncode({'type': 'leave'}));
      } catch (_) {}
      await Future.delayed(const Duration(milliseconds: 300));
      try {
        _activeChannel?.sink.close(4000, "Left");
      } catch (_) {}
      _activeChannel = null;
      goHome();
    }
  }

  void _goToChat() {
    if (_activeChannel == null || _generatedCode == null || _cleanedName == null || _myId == null) {
      return;
    }

    final channel = _activeChannel!;
    final code = _generatedCode!;
    final name = _cleanedName!;
    final myId = _myId!;

    _activeChannel = null;

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => ChatRoomScreen(
          roomCode: code,
          initialChannel: channel,
          name: name,
          myId: myId,
          isHost: true,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        _handleLeaveCreator();
      },
      child: Scaffold(
        backgroundColor: AppTheme.background,
        appBar: AppBar(
          title: const Text('CREATE ROOM'),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.white),
            onPressed: _handleLeaveCreator,
          ),
        ),
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 32.0),
              child: _generatedCode == null ? _buildNameStep() : _buildCodeStep(),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNameStep() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        PrivateTextField(
          key: const ValueKey('create_name_field'),
          controller: _nameController,
          focusNode: _nameFocus,
          maxLength: 20,
          keyboardType: TextInputType.name,
          textCapitalization: TextCapitalization.words,
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.white, fontSize: 18),
          cursorColor: Colors.white,
          decoration: const InputDecoration(
            hintText: 'Your name',
            hintStyle: TextStyle(color: Colors.grey),
            counterText: '',
            contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            enabledBorder: OutlineInputBorder(
              borderSide: BorderSide(color: Colors.white30),
              borderRadius: BorderRadius.zero,
            ),
            focusedBorder: OutlineInputBorder(
              borderSide: BorderSide(color: Colors.white),
              borderRadius: BorderRadius.zero,
            ),
          ),
          onSubmitted: (_) => _onCreateNext(),
        ),
        if (_errorMessage.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            _errorMessage,
            style: const TextStyle(color: Colors.redAccent, fontSize: 13),
          ),
        ],
        const SizedBox(height: 24),
        SizedBox(
          width: double.infinity,
          height: 52,
          child: OutlinedButton(
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.white,
              side: const BorderSide(color: Colors.white, width: 1.5),
              shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
            ),
            onPressed: _onCreateNext,
            child: const Text('CREATE', style: TextStyle(letterSpacing: 2, fontWeight: FontWeight.bold)),
          ),
        ),
      ],
    );
  }

  Widget _buildCodeStep() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          _generatedCode!,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 48,
            fontWeight: FontWeight.bold,
            letterSpacing: 8,
          ),
        ),
        const SizedBox(height: 32),
        SizedBox(
          width: double.infinity,
          height: 48,
          child: OutlinedButton(
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.white,
              side: const BorderSide(color: Colors.white38),
              shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
            ),
            onPressed: _copyCode,
            child: const Text('COPY CODE', style: TextStyle(letterSpacing: 1.2)),
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          height: 48,
          child: OutlinedButton(
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.white,
              side: const BorderSide(color: Colors.white38),
              shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
            ),
            onPressed: _copyInviteLink,
            child: const Text('COPY INVITE LINK', style: TextStyle(letterSpacing: 1.2)),
          ),
        ),
        const SizedBox(height: 24),
        SizedBox(
          width: double.infinity,
          height: 52,
          child: OutlinedButton(
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.white,
              side: const BorderSide(color: Colors.white, width: 1.5),
              shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
            ),
            onPressed: _goToChat,
            child: const Text('NEXT', style: TextStyle(letterSpacing: 2, fontWeight: FontWeight.bold)),
          ),
        ),
      ],
    );
  }
}

// ==========================================
// 3. ENTER ROOM SCREEN
// ==========================================
class EnterRoomScreen extends StatefulWidget {
  const EnterRoomScreen({super.key});

  @override
  State<EnterRoomScreen> createState() => _EnterRoomScreenState();
}

class _EnterRoomScreenState extends State<EnterRoomScreen> {
  final TextEditingController _codeController = TextEditingController();
  final FocusNode _codeFocus = FocusNode();

  final TextEditingController _nameController = TextEditingController();
  final FocusNode _nameFocus = FocusNode();

  String? _verifiedCode;
  String _errorMessage = '';
  bool _isLoading = false;

  @override
  void dispose() {
    _codeController.dispose();
    _codeFocus.dispose();
    _nameController.dispose();
    _nameFocus.dispose();
    super.dispose();
  }

  Future<void> _checkCode() async {
    final code = _codeController.text.trim();
    if (!isValidCode(input: code)) {
      setState(() {
        _errorMessage = 'Wrong code';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });

    try {
      final res = await http.get(Uri.parse('$serverBaseUrl/room/$code/exists'));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        if (data['exists'] == true) {
          setState(() {
            _verifiedCode = code;
            _errorMessage = '';
          });
          return;
        }
      }
      setState(() {
        _errorMessage = 'Wrong code';
      });
    } catch (_) {
      setState(() {
        _errorMessage = 'Connection error';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _joinRoom() async {
    final raw = _nameController.text;
    final cleaned = cleanName(input: raw);

    if (cleaned == null || cleaned.isEmpty) {
      setState(() {
        _errorMessage = 'Name is required';
      });
      return;
    }

    final code = _verifiedCode!;
    final name = cleaned;
    final myId = 'id_${Random().nextInt(10000000)}';

    final deviceId = await _getDeviceId();
    final url = '$serverWsUrl/room/$code/ws?name=${Uri.encodeComponent(name)}&id=${Uri.encodeComponent(myId)}&deviceId=${Uri.encodeComponent(deviceId)}&platform=app';
    final channel = WebSocketChannel.connect(Uri.parse(url));

    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => ChatRoomScreen(
          roomCode: code,
          initialChannel: channel,
          name: name,
          myId: myId,
          isHost: false,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isCodeStep = _verifiedCode == null;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (!isCodeStep) {
          setState(() {
            _verifiedCode = null;
            _errorMessage = '';
          });
        } else {
          goHome();
        }
      },
      child: Scaffold(
        backgroundColor: AppTheme.background,
        appBar: AppBar(
          title: const Text('ENTER ROOM'),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.white),
            onPressed: () {
              if (!isCodeStep) {
                setState(() {
                  _verifiedCode = null;
                  _errorMessage = '';
                });
              } else {
                goHome();
              }
            },
          ),
        ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 32.0),
            child: isCodeStep ? _buildCodeStep() : _buildNameStep(),
          ),
        ),
      ),
    ),
  );
}

  Widget _buildCodeStep() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        PrivateTextField(
          key: const ValueKey('enter_code_field'),
          controller: _codeController,
          focusNode: _codeFocus,
          maxLength: 5,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.white, fontSize: 24, letterSpacing: 4),
          cursorColor: Colors.white,
          decoration: const InputDecoration(
            hintText: '5-digit code',
            hintStyle: TextStyle(color: Colors.grey, fontSize: 18, letterSpacing: 0),
            counterText: '',
            contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            enabledBorder: OutlineInputBorder(
              borderSide: BorderSide(color: Colors.white30),
              borderRadius: BorderRadius.zero,
            ),
            focusedBorder: OutlineInputBorder(
              borderSide: BorderSide(color: Colors.white),
              borderRadius: BorderRadius.zero,
            ),
          ),
          onSubmitted: (_) => _checkCode(),
        ),
        if (_errorMessage.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            _errorMessage,
            style: const TextStyle(color: Colors.redAccent, fontSize: 13),
          ),
        ],
        const SizedBox(height: 24),
        SizedBox(
          width: double.infinity,
          height: 52,
          child: OutlinedButton(
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.white,
              side: const BorderSide(color: Colors.white, width: 1.5),
              shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
            ),
            onPressed: _isLoading ? null : _checkCode,
            child: _isLoading
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                : const Text('NEXT', style: TextStyle(letterSpacing: 2, fontWeight: FontWeight.bold)),
          ),
        ),
      ],
    );
  }

  Widget _buildNameStep() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        PrivateTextField(
          key: const ValueKey('enter_name_field'),
          controller: _nameController,
          focusNode: _nameFocus,
          maxLength: 20,
          keyboardType: TextInputType.name,
          textCapitalization: TextCapitalization.words,
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.white, fontSize: 18),
          cursorColor: Colors.white,
          decoration: const InputDecoration(
            hintText: 'Your name',
            hintStyle: TextStyle(color: Colors.grey),
            counterText: '',
            contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            enabledBorder: OutlineInputBorder(
              borderSide: BorderSide(color: Colors.white30),
              borderRadius: BorderRadius.zero,
            ),
            focusedBorder: OutlineInputBorder(
              borderSide: BorderSide(color: Colors.white),
              borderRadius: BorderRadius.zero,
            ),
          ),
          onSubmitted: (_) => _joinRoom(),
        ),
        if (_errorMessage.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            _errorMessage,
            style: const TextStyle(color: Colors.redAccent, fontSize: 13),
          ),
        ],
        const SizedBox(height: 24),
        SizedBox(
          width: double.infinity,
          height: 52,
          child: OutlinedButton(
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.white,
              side: const BorderSide(color: Colors.white, width: 1.5),
              shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
            ),
            onPressed: _joinRoom,
            child: const Text('JOIN', style: TextStyle(letterSpacing: 2, fontWeight: FontWeight.bold)),
          ),
        ),
      ],
    );
  }
}

// ==========================================
// 4. CHAT ROOM SCREEN
// ==========================================
enum MessageStatus { sending, sent, failed }

class ReplyQuoteModel {
  final String id;
  final String name;
  final String preview;

  ReplyQuoteModel({required this.id, required this.name, required this.preview});

  factory ReplyQuoteModel.fromJson(Map<String, dynamic> json) {
    return ReplyQuoteModel(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      preview: json['preview'] as String? ?? '',
    );
  }
}

class ChatMessageItem {
  String id;
  final String? clientId;
  final String kind;
  final String name;
  bool isMine;
  final String? platform;
  String? text;
  String? image;
  Uint8List? bytes;
  ReplyQuoteModel? reply;
  bool isDeleted;
  bool viewOnce;
  bool opened;
  List<String> openedBy;
  bool consumed;
  bool slowDown;
  int ts;
  MessageStatus status;

  ChatMessageItem({
    required this.id,
    this.clientId,
    required this.kind,
    required this.name,
    required this.isMine,
    this.platform,
    this.text,
    this.image,
    this.bytes,
    this.reply,
    this.isDeleted = false,
    this.viewOnce = false,
    this.opened = false,
    List<String>? openedBy,
    this.consumed = false,
    this.slowDown = false,
    required this.ts,
    required this.status,
  }) : openedBy = openedBy ?? [];
}

class ChatRoomScreen extends StatefulWidget {
  final String roomCode;
  final WebSocketChannel initialChannel;
  final String name;
  final String myId;
  final bool isHost;

  const ChatRoomScreen({
    super.key,
    required this.roomCode,
    required this.initialChannel,
    required this.name,
    required this.myId,
    required this.isHost,
  });

  @override
  State<ChatRoomScreen> createState() => _ChatRoomScreenState();
}

class _ChatRoomScreenState extends State<ChatRoomScreen> with WidgetsBindingObserver {
  WebSocketChannel? _channel;
  StreamSubscription? _subscription;

  final TextEditingController _textController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final List<ChatMessageItem> _messages = [];

  late String _assignedId;
  late String _myName;

  List<Map<String, dynamic>> _onlineMembers = [];

  bool _isReconnecting = false;
  Timer? _reconnectTimer;
  DateTime? _reconnectStartTime;
  bool _leftDeliberately = false;

  final Map<String, Timer> _pendingEchoTimers = {};
  final Map<String, String> _pendingImagePayloads = {};
  ReplyQuoteModel? _replyingTo;

  // View once state: every image is view once
  DateTime _lastImageSendTime = DateTime.fromMillisecondsSinceEpoch(0);

  // Vibration state
  bool _vibrationEnabled = true;
  DateTime _lastVibrateTime = DateTime.fromMillisecondsSinceEpoch(0);
  bool _inHistory = false;
  bool _isAppInBackground = false;

  // Unread divider state
  String? _lastReadId;
  int _unreadCount = 0;
  Timer? _dividerDismissTimer;

  // Active view-once dialog controller for immediate background wiping
  BuildContext? _viewOnceViewerContext;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    activeRoomCleanup = _cleanupState;
    _assignedId = widget.myId;
    _myName = widget.name;
    _attachChannel(widget.initialChannel);

    _scrollController.addListener(_onScroll);
  }

  void _cleanupState() {
    _leftDeliberately = true;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _dividerDismissTimer?.cancel();
    _dividerDismissTimer = null;
    for (final t in _pendingEchoTimers.values) {
      t.cancel();
    }
    _pendingEchoTimers.clear();
    _pendingImagePayloads.clear();
    _subscription?.cancel();
    _subscription = null;
    try {
      _channel?.sink.close(4000, "Left");
    } catch (_) {}
    _channel = null;
    _messages.clear();
    _onlineMembers.clear();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _scrollController.removeListener(_onScroll);
    _cleanupState();
    _textController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    if (_scrollController.offset <= 40.0) {
      if (_unreadCount > 0) {
        setState(() {
          _unreadCount = 0;
          _lastReadId = _messages.isNotEmpty ? _messages.first.id : null;
        });
        _dividerDismissTimer?.cancel();
        _dividerDismissTimer = Timer(const Duration(seconds: 3), () {
          if (mounted) setState(() {});
        });
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.hidden) {
      _isAppInBackground = true;
      // Close any active view-once viewer immediately
      if (_viewOnceViewerContext != null && Navigator.of(_viewOnceViewerContext!).canPop()) {
        Navigator.of(_viewOnceViewerContext!).pop();
        _viewOnceViewerContext = null;
      }
    } else if (state == AppLifecycleState.resumed) {
      _isAppInBackground = false;
      if (!_leftDeliberately) {
        _checkSafetyNet();
      }
    }
  }

  Future<void> _checkSafetyNet() async {
    try {
      final res = await http.get(Uri.parse('$serverBaseUrl/room/${widget.roomCode}/exists'));
      if (res.statusCode == 403) {
        goHome(message: 'You were kicked from the basement');
        return;
      }
      if (res.statusCode == 404 || (res.statusCode == 200 && jsonDecode(res.body)['exists'] == false)) {
        goHome(message: 'The basement was closed');
        return;
      }
    } catch (_) {}
  }

  void _attachChannel(WebSocketChannel channel) {
    _channel = channel;
    _subscription?.cancel();
    _subscription = channel.stream.listen(
      _onMessageReceived,
      onDone: _onSocketDone,
      onError: (err) => _onSocketDone(),
      cancelOnError: true,
    );
  }

  void _onMessageReceived(dynamic data) {
    if (data is! String) return;

    try {
      final parsed = jsonDecode(data);
      if (parsed is! Map<String, dynamic>) return;

      final type = parsed['type'];

      if (type == 'room_closed') {
        final by = parsed['by'] as String? ?? 'Host';
        goHome(message: '$by closed the basement');
        return;
      }

      if (type == 'kicked') {
        goHome(message: 'You were kicked from the basement');
        return;
      }

      if (type == 'welcome') {
        final id = parsed['id'] as String?;
        final name = parsed['name'] as String?;
        if (id != null && id.isNotEmpty) _assignedId = id;
        if (name != null && name.isNotEmpty) {
          setState(() {
            _myName = name;
          });
        }
        return;
      }

      if (type == 'history_start') {
        _inHistory = true;
        setState(() {
          _messages.removeWhere((m) => m.status == MessageStatus.sent);
        });
        return;
      }

      if (type == 'history_end') {
        _inHistory = false;
        setState(() {
          if (_messages.isNotEmpty) {
            _lastReadId = _messages.first.id;
          }
        });
        return;
      }

      if (type == 'members') {
        final list = parsed['list'] as List<dynamic>? ?? [];
        setState(() {
          _onlineMembers = list.map((e) => e as Map<String, dynamic>).toList();
        });
        return;
      }

      // View data arrived (View once photo bytes)
      if (type == 'view_data') {
        final viewId = parsed['id'] as String? ?? '';
        final imgB64 = parsed['image'] as String? ?? '';
        _displayViewOncePhoto(viewId, imgB64);
        return;
      }

      // Viewed broadcast
      if (type == 'viewed') {
        final vId = parsed['id'] as String? ?? '';
        final vName = parsed['name'] as String? ?? '';
        final vMemberId = parsed['memberId'] as String? ?? '';
        setState(() {
          for (final m in _messages) {
            if (m.id == vId) {
              if (!m.openedBy.contains(vName)) {
                m.openedBy.add(vName);
              }
              if (vMemberId == _assignedId) {
                m.opened = true;
              }
            }
          }
        });
        return;
      }

      // Deleted event
      if (type == 'deleted') {
        final deletedId = parsed['id'] as String? ?? '';
        setState(() {
          for (final m in _messages) {
            if (m.id == deletedId) {
              m.isDeleted = true;
              m.text = null;
              m.bytes = null;
              m.reply = null;
            }
            if (m.reply?.id == deletedId) {
              m.reply = ReplyQuoteModel(id: deletedId, name: m.reply!.name, preview: 'Message deleted');
            }
          }
          if (_replyingTo?.id == deletedId) {
            _replyingTo = null;
          }
        });
        return;
      }

      if (type == 'msg') {
        final id = parsed['id'] as String? ?? '';
        final clientId = parsed['clientId'] as String?;
        final kind = parsed['kind'] as String? ?? 'text';
        final name = parsed['name'] as String? ?? '';
        final isMine = parsed['mine'] == true; // PROTOCOL CHANGE: Decided by server!
        final platform = parsed['platform'] as String?;
        final text = parsed['text'] as String?;
        final isDeleted = parsed['deleted'] == true;
        final viewOnce = (kind == 'image' || parsed['viewOnce'] == true);
        final opened = parsed['opened'] == true;
        final consumed = parsed['consumed'] == true;
        final openedBy = (parsed['openedBy'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [];
        final ts = parsed['ts'] as int? ?? DateTime.now().millisecondsSinceEpoch;

        // Vibration for new message from others in foreground
        if (!_inHistory && kind != 'system' && !isMine && !_isAppInBackground && _vibrationEnabled) {
          final now = DateTime.now();
          if (now.difference(_lastVibrateTime).inMilliseconds >= 1500) {
            _lastVibrateTime = now;
            HapticFeedback.lightImpact();
          }
        }

        ReplyQuoteModel? reply;
        if (parsed['reply'] is Map<String, dynamic>) {
          reply = ReplyQuoteModel.fromJson(parsed['reply'] as Map<String, dynamic>);
        }

        if (clientId != null && _pendingEchoTimers.containsKey(clientId)) {
          _pendingEchoTimers[clientId]?.cancel();
          _pendingEchoTimers.remove(clientId);
          _pendingImagePayloads.remove(clientId);
        }

        if (clientId != null) {
          final idx = _messages.indexWhere((m) => m.clientId == clientId);
          if (idx != -1) {
            setState(() {
              final existing = _messages[idx];
              existing.id = id;
              existing.isMine = isMine;
              existing.status = MessageStatus.sent;
              existing.ts = ts;
              existing.isDeleted = isDeleted;
              existing.viewOnce = viewOnce;
              existing.opened = opened;
              existing.consumed = consumed;
              existing.openedBy = openedBy;
              if (isDeleted) {
                existing.text = null;
                existing.bytes = null;
                existing.reply = null;
              }
            });
            return;
          }
        }

        if (_messages.any((m) => m.id == id)) {
          return;
        }

        final newMsg = ChatMessageItem(
          id: id,
          clientId: clientId,
          kind: kind,
          name: name,
          isMine: isMine,
          platform: platform,
          text: isDeleted ? null : text,
          reply: isDeleted ? null : reply,
          isDeleted: isDeleted,
          viewOnce: viewOnce,
          opened: opened,
          consumed: consumed,
          openedBy: openedBy,
          ts: ts,
          status: MessageStatus.sent,
        );

        // Update unread logic for messages from others
        if (!_inHistory && kind != 'system' && !isMine && !isDeleted) {
          if (_scrollController.hasClients && _scrollController.offset > 40.0) {
            _unreadCount++;
          } else {
            _lastReadId = id;
          }
        }

        setState(() {
          _messages.insert(0, newMsg);
        });
        return;
      }

      if (type == 'error') {
        final clientId = parsed['clientId'] as String?;
        final reason = parsed['reason'] as String? ?? 'Error';
        if (clientId != null) {
          _pendingEchoTimers[clientId]?.cancel();
          _pendingEchoTimers.remove(clientId);
          final idx = _messages.indexWhere((m) => m.clientId == clientId);
          if (idx != -1) {
            setState(() {
              _messages[idx].status = MessageStatus.failed;
              if (reason == 'slow_down') {
                _messages[idx].slowDown = true;
              }
            });
          }
        }
        if (reason == 'slow_down') {
          _showSnackbar('Slow down');
        } else {
          _showSnackbar(reason);
        }
        return;
      }
    } catch (_) {}
  }

  void _onSocketDone() {
    if (_leftDeliberately) return;
    final closeCode = _channel?.closeCode;
    if (closeCode == 4001) {
      goHome(message: 'The basement was closed');
      return;
    }
    if (closeCode == 4002) {
      goHome(message: 'You were kicked from the basement');
      return;
    }
    _startReconnecting();
  }

  void _startReconnecting() {
    if (_isReconnecting) return;

    setState(() {
      _isReconnecting = true;
    });

    _reconnectStartTime = DateTime.now();
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer.periodic(const Duration(seconds: 3), (timer) async {
      if (_leftDeliberately) {
        timer.cancel();
        return;
      }

      final elapsed = DateTime.now().difference(_reconnectStartTime!);
      if (elapsed > const Duration(minutes: 2)) {
        timer.cancel();
        goHome(message: 'Disconnected');
        return;
      }

      try {
        final checkRes = await http.get(Uri.parse('$serverBaseUrl/room/${widget.roomCode}/exists'));
        if (checkRes.statusCode == 403) {
          timer.cancel();
          goHome(message: 'You were kicked from the basement');
          return;
        }
        if (checkRes.statusCode != 200 || jsonDecode(checkRes.body)['exists'] == false) {
          timer.cancel();
          goHome(message: 'The basement was closed');
          return;
        }
      } catch (_) {}

      final deviceId = await _getDeviceId();
      final url = '$serverWsUrl/room/${widget.roomCode}/ws?name=${Uri.encodeComponent(_myName)}&id=${Uri.encodeComponent(_assignedId)}&deviceId=${Uri.encodeComponent(deviceId)}&platform=app${widget.isHost ? '&create=1' : ''}';
      try {
        final newChannel = WebSocketChannel.connect(Uri.parse(url));
        _attachChannel(newChannel);
        timer.cancel();
        _reconnectTimer = null;
        if (mounted) {
          setState(() {
            _isReconnecting = false;
          });
        }
        _resendPendingMessages();
      } catch (_) {}
    });
  }

  void _resendPendingMessages() {
    for (final m in _messages) {
      // Do NOT auto-resend slowDown errors
      if ((m.status == MessageStatus.sending || m.status == MessageStatus.failed) && !m.slowDown) {
        final cached = _pendingImagePayloads[m.clientId];
        _dispatchMessage(m, base64Override: cached);
      }
    }
  }

  void _sendText() {
    final text = _textController.text.trim();
    if (text.isEmpty) return;

    final clientId = 'c_${DateTime.now().millisecondsSinceEpoch}_${Random().nextInt(10000)}';
    final replyTo = _replyingTo;

    final item = ChatMessageItem(
      id: clientId,
      clientId: clientId,
      kind: 'text',
      name: _myName,
      isMine: true,
      platform: 'app',
      text: text,
      reply: replyTo,
      ts: DateTime.now().millisecondsSinceEpoch,
      status: MessageStatus.sending,
    );

    setState(() {
      _messages.insert(0, item);
      _replyingTo = null;
    });
    _textController.clear();
    _scrollToBottom();

    _dispatchMessage(item);
  }

  Future<void> _pickAndSendImage() async {
    final now = DateTime.now();
    if (now.difference(_lastImageSendTime).inSeconds < 3) {
      _showSnackbar('Wait a moment');
      return;
    }

    if (_onlineMembers.length <= 1) {
      _showSnackbar('No one else is here');
      return;
    }

    final picker = ImagePicker();
    final file = await picker.pickImage(source: ImageSource.gallery);
    if (file == null) return;

    _lastImageSendTime = DateTime.now();

    final bytes = await file.readAsBytes();

    if (bytes.length >= 3 && bytes[0] == 0x47 && bytes[1] == 0x49 && bytes[2] == 0x46) {
      _showSnackbar('GIFs not allowed');
      return;
    }

    String compressedBase64;
    try {
      compressedBase64 = await processImage(bytes: bytes);
    } catch (e) {
      if (e.toString().contains('isGif')) {
        _showSnackbar('GIFs not allowed');
      } else if (e.toString().contains('tooBig')) {
        _showSnackbar('Image too big');
      } else {
        _showSnackbar("Can't use this image");
      }
      return;
    }

    final clientId = 'c_${DateTime.now().millisecondsSinceEpoch}_${Random().nextInt(10000)}';
    final replyTo = _replyingTo;

    // ITEM 1: Every photo is view-once
    final item = ChatMessageItem(
      id: clientId,
      clientId: clientId,
      kind: 'image',
      name: _myName,
      isMine: true,
      platform: 'app',
      reply: replyTo,
      viewOnce: true,
      ts: DateTime.now().millisecondsSinceEpoch,
      status: MessageStatus.sending,
    );

    _pendingImagePayloads[clientId] = compressedBase64;

    setState(() {
      _messages.insert(0, item);
      _replyingTo = null;
    });
    _scrollToBottom();

    _dispatchMessage(item, base64Override: compressedBase64);
  }

  void _dispatchMessage(ChatMessageItem item, {String? base64Override}) {
    if (_channel == null) {
      setState(() {
        item.status = MessageStatus.failed;
      });
      return;
    }

    final payload = <String, dynamic>{
      'type': item.kind,
      'clientId': item.clientId,
    };
    if (item.kind == 'text') payload['text'] = item.text;
    if (item.kind == 'image') {
      payload['image'] = base64Override ?? _pendingImagePayloads[item.clientId] ?? item.image;
      payload['viewOnce'] = true;
    }
    if (item.reply != null) payload['replyTo'] = item.reply!.id;

    try {
      _channel!.sink.add(jsonEncode(payload));
      setState(() {
        item.status = MessageStatus.sending;
        item.slowDown = false;
      });

      _pendingEchoTimers[item.clientId!]?.cancel();
      _pendingEchoTimers[item.clientId!] = Timer(const Duration(seconds: 10), () {
        if (mounted && item.status == MessageStatus.sending) {
          setState(() {
            item.status = MessageStatus.failed;
          });
        }
      });
    } catch (_) {
      setState(() {
        item.status = MessageStatus.failed;
      });
    }
  }

  void _retryMessage(ChatMessageItem item) {
    setState(() {
      item.status = MessageStatus.sending;
      item.slowDown = false;
      item.ts = DateTime.now().millisecondsSinceEpoch;
    });
    final cached = _pendingImagePayloads[item.clientId];
    _dispatchMessage(item, base64Override: cached);
  }

  void _requestViewOnce(String msgId) {
    if (_channel == null) {
      _showSnackbar('Photo no longer available');
      return;
    }
    try {
      _channel!.sink.add(jsonEncode({'type': 'view', 'id': msgId}));
    } catch (_) {
      _showSnackbar('Photo no longer available');
    }
  }

  void _displayViewOncePhoto(String msgId, String b64) {
    Uint8List? rawBytes;
    try {
      rawBytes = base64Decode(b64);
    } catch (_) {
      rawBytes = null;
    }

    if (rawBytes == null) {
      _showSnackbar('Photo no longer available');
      return;
    }

    setState(() {
      for (final m in _messages) {
        if (m.id == msgId) {
          m.opened = true;
        }
      }
    });

    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (dialogCtx) {
        _viewOnceViewerContext = dialogCtx;
        return Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(
            backgroundColor: Colors.black,
            leading: IconButton(
              icon: const Icon(Icons.close, color: Colors.white),
              onPressed: () => Navigator.of(dialogCtx).pop(),
            ),
          ),
          body: Center(
            child: InteractiveViewer(
              minScale: 0.8,
              maxScale: 4.0,
              child: Image.memory(
                rawBytes!,
                fit: BoxFit.contain,
              ),
            ),
          ),
        );
      },
    ).then((_) {
      _viewOnceViewerContext = null;
      rawBytes = null; // Wipe bytes from memory immediately
      if (mounted) setState(() {});
    });
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        0.0,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    }
  }

  void _scrollToMessage(String msgId) {
    final idx = _messages.indexWhere((m) => m.id == msgId);
    if (idx != -1 && _scrollController.hasClients) {
      final targetOffset = idx * 60.0;
      _scrollController.animateTo(
        targetOffset.clamp(0.0, _scrollController.position.maxScrollExtent),
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  void _startReply(ChatMessageItem msg) {
    if (msg.viewOnce) return;
    setState(() {
      _replyingTo = ReplyQuoteModel(
        id: msg.id,
        name: msg.name,
        preview: msg.kind == 'image' ? 'Photo' : (msg.text != null && msg.text!.length > 80 ? msg.text!.substring(0, 80) : (msg.text ?? '')),
      );
    });
  }

  void _confirmDeleteMessage(ChatMessageItem msg) {
    final isMine = msg.isMine;
    final titleText = isMine
        ? 'Delete this message for everyone?'
        : 'Delete ${msg.name}\'s message for everyone?';

    showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF111111),
        title: Text(titleText, style: const TextStyle(color: Colors.white, fontSize: 16)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('CANCEL', style: TextStyle(color: Colors.grey)),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('DELETE', style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    ).then((confirmed) {
      if (confirmed == true) {
        if (msg.status == MessageStatus.sending || msg.status == MessageStatus.failed) {
          setState(() {
            _messages.removeWhere((m) => m.id == msg.id || m.clientId == msg.clientId);
          });
          return;
        }

        if (msg.id.startsWith('c_')) {
          _showSnackbar('Wait for it to be sent');
          return;
        }

        try {
          _channel?.sink.add(jsonEncode({'type': 'delete', 'id': msg.id}));
        } catch (_) {
          _showSnackbar('Failed to delete message');
        }
      }
    });
  }

  void _confirmKickMember(String memberId, String memberName) {
    showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF111111),
        title: Text('Kick $memberName? They can\'t come back to this room.', style: const TextStyle(color: Colors.white, fontSize: 16)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('CANCEL', style: TextStyle(color: Colors.grey)),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('KICK', style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    ).then((confirmed) {
      if (confirmed == true) {
        try {
          _channel?.sink.add(jsonEncode({'type': 'kick', 'id': memberId}));
        } catch (_) {}
      }
    });
  }

  void _confirmKickMemberByName(String memberName) {
    final member = _onlineMembers.firstWhere(
      (m) => m['name'] == memberName,
      orElse: () => <String, dynamic>{},
    );
    if (member.isNotEmpty && member['id'] != null) {
      _confirmKickMember(member['id'] as String, memberName);
    }
  }

  void _openActionMenu(ChatMessageItem msg) {
    final isMine = msg.isMine;
    final isPhoto = msg.kind == 'image' || msg.viewOnce;
    final canReply = !isPhoto && !msg.isDeleted && msg.status == MessageStatus.sent && msg.kind != 'system';
    final canCopy = !isPhoto && !msg.isDeleted && msg.kind == 'text' && msg.text != null && msg.text!.isNotEmpty;

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF111111),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
      builder: (ctx) {
        return SafeArea(
          child: Wrap(
            children: [
              if (canReply)
                ListTile(
                  leading: const Icon(Icons.reply, color: Colors.white),
                  title: const Text('Reply', style: TextStyle(color: Colors.white)),
                  onTap: () {
                    Navigator.of(ctx).pop();
                    _startReply(msg);
                  },
                ),
              if (canCopy)
                ListTile(
                  leading: const Icon(Icons.copy, color: Colors.white),
                  title: const Text('Copy text', style: TextStyle(color: Colors.white)),
                  onTap: () {
                    Navigator.of(ctx).pop();
                    Clipboard.setData(ClipboardData(text: msg.text ?? ''));
                    _showSnackbar('Copied');
                  },
                ),
              if ((isMine || widget.isHost) && !msg.isDeleted)
                ListTile(
                  leading: const Icon(Icons.delete_outline, color: Colors.redAccent),
                  title: const Text('Delete', style: TextStyle(color: Colors.redAccent)),
                  onTap: () {
                    Navigator.of(ctx).pop();
                    _confirmDeleteMessage(msg);
                  },
                ),
              if (widget.isHost && !isMine)
                ListTile(
                  leading: const Icon(Icons.person_remove_outlined, color: Colors.redAccent),
                  title: Text('Kick ${msg.name}', style: const TextStyle(color: Colors.redAccent)),
                  onTap: () {
                    Navigator.of(ctx).pop();
                    _confirmKickMemberByName(msg.name);
                  },
                ),
            ],
          ),
        );
      },
    );
  }

  void _openMembersSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF111111),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (bottomSheetCtx, setSheetState) {
            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'ONLINE IN BASEMENT',
                      style: TextStyle(color: Colors.grey, fontSize: 13, fontWeight: FontWeight.bold, letterSpacing: 1.2),
                    ),
                    const SizedBox(height: 16),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 200),
                      child: ListView.builder(
                        shrinkWrap: true,
                        itemCount: _onlineMembers.length,
                        itemBuilder: (context, idx) {
                          final m = _onlineMembers[idx];
                          final name = m['name'] as String? ?? '';
                          final isHost = m['host'] == true;
                          final platform = m['platform'] as String? ?? 'web';
                          final isMe = name == _myName;

                          var label = name;
                          if (isHost) label += ' (host)';
                          if (isMe) label += ' (you)';

                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 6),
                            child: Row(
                              children: [
                                Text(
                                  label,
                                  style: const TextStyle(color: Colors.white, fontSize: 15),
                                ),
                                const SizedBox(width: 6),
                                Icon(
                                  platform == 'app' ? Icons.smartphone : Icons.language,
                                  size: 13,
                                  color: Colors.grey,
                                ),
                                const Spacer(),
                                if (widget.isHost && !isMe)
                                  TextButton(
                                    style: TextButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                      minimumSize: Size.zero,
                                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                    ),
                                    onPressed: () {
                                      Navigator.of(ctx).pop();
                                      _confirmKickMember(m['id'] as String, name);
                                    },
                                    child: const Text('KICK', style: TextStyle(color: Colors.redAccent, fontSize: 12, fontWeight: FontWeight.bold)),
                                  ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 12),
                    // Vibration toggle
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Vibration', style: TextStyle(color: Colors.white, fontSize: 15)),
                        Switch(
                          value: _vibrationEnabled,
                          activeThumbColor: Colors.white,
                          onChanged: (val) {
                            setSheetState(() {
                              _vibrationEnabled = val;
                            });
                            setState(() {
                              _vibrationEnabled = val;
                            });
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.white,
                          side: const BorderSide(color: Colors.white38),
                          shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
                        ),
                        onPressed: () {
                          Clipboard.setData(ClipboardData(text: widget.roomCode));
                          Navigator.pop(ctx);
                          _showSnackbar('Copied');
                        },
                        child: const Text('COPY CODE', style: TextStyle(letterSpacing: 1.2)),
                      ),
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.white,
                          side: const BorderSide(color: Colors.white38),
                          shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
                        ),
                        onPressed: () {
                          Clipboard.setData(ClipboardData(text: '$WEB_URL/#${widget.roomCode}'));
                          Navigator.pop(ctx);
                          _showSnackbar('Copied');
                        },
                        child: const Text('COPY INVITE LINK', style: TextStyle(letterSpacing: 1.2)),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _handleLeave() async {
    final titleText = widget.isHost
        ? 'Close the basement? This removes everyone and deletes all messages.'
        : 'Leave the basement? Messages will be gone.';
    final buttonText = widget.isHost ? 'CLOSE' : 'LEAVE';

    final leave = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF111111),
        title: Text(
          titleText,
          style: const TextStyle(color: Colors.white, fontSize: 16),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('CANCEL', style: TextStyle(color: Colors.grey)),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(buttonText, style: const TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (leave == true) {
      _leftDeliberately = true;
      try {
        _channel?.sink.add(jsonEncode({'type': 'leave'}));
      } catch (_) {}
      await Future.delayed(const Duration(milliseconds: 300));
      goHome();
    }
  }

  void _showSnackbar(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: const Color(0xFF222222),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  String _formatHHmm(int ts) {
    final dt = DateTime.fromMillisecondsSinceEpoch(ts);
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  @override
  Widget build(BuildContext context) {
    final onlineCount = _onlineMembers.length;

    // Check if unread divider should be shown
    int firstUnreadIndex = -1;
    if (_unreadCount > 0 && _lastReadId != null) {
      final lastReadIdx = _messages.indexWhere((m) => m.id == _lastReadId);
      if (lastReadIdx != -1) {
        // In reverse list, newer messages have smaller indices (< lastReadIdx)
        for (int i = lastReadIdx - 1; i >= 0; i--) {
          final m = _messages[i];
          if (!m.isMine && m.kind != 'system' && !m.isDeleted) {
            firstUnreadIndex = i;
          }
        }
      }
    }

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        _handleLeave();
      },
      child: Scaffold(
        backgroundColor: AppTheme.background,
        appBar: AppBar(
          title: GestureDetector(
            onTap: _openMembersSheet,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(widget.roomCode),
                const SizedBox(width: 6),
                Text(
                  '· $onlineCount online',
                  style: const TextStyle(
                    color: AppTheme.subtext,
                    fontSize: 13,
                    fontWeight: FontWeight.normal,
                    letterSpacing: 0,
                  ),
                ),
              ],
            ),
          ),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.white),
            onPressed: _handleLeave,
          ),
        ),
        body: SafeArea(
          child: Stack(
            children: [
              Column(
                children: [
                  if (_isReconnecting)
                    Container(
                      width: double.infinity,
                      color: const Color(0xFF1A1A1A),
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: const Text(
                        'Reconnecting...',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.grey, fontSize: 12),
                      ),
                    ),
                  Expanded(
                    child: ListView.builder(
                      key: const ValueKey('chat_list'),
                      reverse: true,
                      controller: _scrollController,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      itemCount: _messages.length,
                      itemBuilder: (context, index) {
                        final msg = _messages[index];
                        final showDivider = index == firstUnreadIndex;

                        return KeyedSubtree(
                          key: ValueKey(msg.clientId ?? msg.id),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              _buildMessageRow(msg),
                              if (showDivider)
                                Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 8),
                                  child: Row(
                                    children: [
                                      const Expanded(child: Divider(color: Colors.white24)),
                                      Padding(
                                        padding: const EdgeInsets.symmetric(horizontal: 8),
                                        child: Text(
                                          '$_unreadCount new messages',
                                          style: const TextStyle(color: Colors.grey, fontSize: 12),
                                        ),
                                      ),
                                      const Expanded(child: Divider(color: Colors.white24)),
                                    ],
                                  ),
                                ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                  if (_replyingTo != null) _buildReplyBar(),
                  _buildInputBar(),
                ],
              ),
              // Floating Unread Pill
              if (_unreadCount > 0)
                Positioned(
                  bottom: 70,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: GestureDetector(
                      onTap: _scrollToBottom,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                        decoration: BoxDecoration(
                          color: const Color(0xFF222222),
                          border: Border.all(color: Colors.white30),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Text(
                          '↓ $_unreadCount new',
                          style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildReplyBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: const BoxDecoration(
        color: Color(0xFF111111),
        border: Border(
          left: BorderSide(color: Colors.white, width: 3),
          top: BorderSide(color: Color(0xFF222222)),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Replying to ${_replyingTo!.name}',
                  style: const TextStyle(color: Colors.grey, fontSize: 12, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 2),
                Text(
                  _replyingTo!.preview,
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, color: Colors.grey, size: 18),
            onPressed: () {
              setState(() {
                _replyingTo = null;
              });
            },
          ),
        ],
      ),
    );
  }

  Widget _buildMessageRow(ChatMessageItem msg) {
    if (msg.kind == 'system') {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Text(
          msg.text ?? '',
          textAlign: TextAlign.center,
          style: const TextStyle(color: AppTheme.subtext, fontSize: 13),
        ),
      );
    }

    // ITEM 2: Layout rule - MY messages aligned to RIGHT, others aligned to LEFT
    final isMe = msg.isMine;
    final align = isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start;
    final timeStr = _formatHHmm(msg.ts);
    final isPhoto = msg.kind == 'image' || msg.viewOnce;
    final canSwipe = !isPhoto && !msg.isDeleted && msg.kind != 'system' && msg.status == MessageStatus.sent;

    return SwipeableMessageWrapper(
      enabled: canSwipe,
      onReplyTriggered: () => _startReply(msg),
      child: GestureDetector(
        onLongPress: () => _openActionMenu(msg),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Column(
            crossAxisAlignment: align,
            children: [
              if (!isMe)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        msg.name,
                        style: const TextStyle(color: AppTheme.subtext, fontSize: 11),
                      ),
                      const SizedBox(width: 4),
                      Icon(
                        msg.platform == 'app' ? Icons.smartphone : Icons.language,
                        size: 12,
                        color: AppTheme.subtext,
                      ),
                    ],
                  ),
                ),
              if (msg.isDeleted)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                  child: const Text(
                    'Message deleted',
                    style: TextStyle(color: AppTheme.subtext, fontSize: 13, fontStyle: FontStyle.italic),
                  ),
                )
              else
                Container(
                  constraints: BoxConstraints(
                    maxWidth: MediaQuery.of(context).size.width * 0.78,
                  ),
                  padding: AppTheme.bubblePadding,
                  decoration: BoxDecoration(
                    color: isMe ? AppTheme.myBubble : AppTheme.othersBubble,
                    borderRadius: isMe ? AppTheme.myBubbleRadius : AppTheme.othersBubbleRadius,
                  ),
                  child: Column(
                    crossAxisAlignment: align,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (msg.reply != null)
                        GestureDetector(
                          onTap: () => _scrollToMessage(msg.reply!.id),
                          child: Container(
                            margin: const EdgeInsets.only(bottom: 6),
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: isMe ? AppTheme.replyMyBg : AppTheme.replyOthersBg,
                              border: const Border(left: BorderSide(color: AppTheme.replyBorder, width: 2.5)),
                              borderRadius: const BorderRadius.all(Radius.circular(4)),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  msg.reply!.name,
                                  style: const TextStyle(color: AppTheme.subtext, fontSize: 11, fontWeight: FontWeight.bold),
                                ),
                                Text(
                                  msg.reply!.preview,
                                  style: const TextStyle(color: AppTheme.text, fontSize: 12),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                        ),
                      if (isPhoto)
                        _buildViewOnceWidget(msg, isMe)
                      else
                        Text(
                          msg.text ?? '',
                          style: const TextStyle(color: AppTheme.text, fontSize: 15),
                        ),
                    ],
                  ),
                ),
              if (!msg.isDeleted)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
                  child: _buildFooter(msg, isMe, timeStr),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildViewOnceWidget(ChatMessageItem msg, bool isMe) {
    if (isMe) {
      final label = msg.openedBy.isNotEmpty
          ? 'Opened by ${msg.openedBy.join(', ')}'
          : 'View once photo';
      return Text(
        label,
        style: const TextStyle(color: AppTheme.subtext, fontSize: 13),
      );
    }

    if (msg.consumed || msg.opened) {
      return const Text(
        'Photo opened',
        style: TextStyle(color: AppTheme.subtext, fontSize: 13),
      );
    }

    return GestureDetector(
      onTap: () => _requestViewOnce(msg.id),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.lock_clock_outlined, size: 16, color: AppTheme.subtext),
          SizedBox(width: 6),
          Text(
            'Photo · tap to view',
            style: TextStyle(color: AppTheme.text, fontSize: 13),
          ),
        ],
      ),
    );
  }

  Widget _buildFooter(ChatMessageItem msg, bool isMe, String timeStr) {
    if (!isMe) {
      return Text(
        timeStr,
        style: const TextStyle(color: AppTheme.subtext, fontSize: 11),
      );
    }

    if (msg.status == MessageStatus.sending) {
      return Text(
        '$timeStr · Sending...',
        style: const TextStyle(color: AppTheme.subtext, fontSize: 11),
      );
    } else if (msg.status == MessageStatus.failed) {
      final failText = msg.slowDown ? 'Slow down · tap to retry' : 'Not sent · tap to retry';
      return GestureDetector(
        onTap: () => _retryMessage(msg),
        child: Text(
          failText,
          style: const TextStyle(color: Colors.redAccent, fontSize: 11, fontWeight: FontWeight.bold),
        ),
      );
    } else {
      return Text(
        '$timeStr · ✓',
        style: const TextStyle(color: AppTheme.subtext, fontSize: 11),
      );
    }
  }

  Widget _buildInputBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      color: Colors.black,
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.add_photo_alternate_outlined, color: Colors.white),
            onPressed: _pickAndSendImage,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: PrivateTextField(
              controller: _textController,
              maxLength: 2000,
              style: const TextStyle(color: Colors.white, fontSize: 15),
              cursorColor: Colors.white,
              decoration: const InputDecoration(
                hintText: 'Message',
                hintStyle: TextStyle(color: Colors.grey),
                counterText: '',
                contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                enabledBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: Colors.white30),
                  borderRadius: BorderRadius.zero,
                ),
                focusedBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: Colors.white),
                  borderRadius: BorderRadius.zero,
                ),
              ),
              onSubmitted: (_) => _sendText(),
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            icon: const Icon(Icons.send, color: Colors.white),
            onPressed: _sendText,
          ),
        ],
      ),
    );
  }
}

class SwipeableMessageWrapper extends StatefulWidget {
  final Widget child;
  final bool enabled;
  final VoidCallback onReplyTriggered;

  const SwipeableMessageWrapper({
    super.key,
    required this.child,
    required this.enabled,
    required this.onReplyTriggered,
  });

  @override
  State<SwipeableMessageWrapper> createState() => _SwipeableMessageWrapperState();
}

class _SwipeableMessageWrapperState extends State<SwipeableMessageWrapper> {
  double _dragOffset = 0.0;

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) return widget.child;

    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onHorizontalDragUpdate: (details) {
        if (details.delta.dx > 0 || _dragOffset > 0) {
          setState(() {
            _dragOffset = (_dragOffset + details.delta.dx).clamp(0.0, 64.0);
          });
        }
      },
      onHorizontalDragEnd: (details) {
        if (_dragOffset >= 40.0) {
          widget.onReplyTriggered();
        }
        setState(() {
          _dragOffset = 0.0;
        });
      },
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.centerLeft,
        children: [
          if (_dragOffset > 5.0)
            Positioned(
              left: 4,
              child: Opacity(
                opacity: (_dragOffset / 40.0).clamp(0.0, 1.0),
                child: const Icon(Icons.reply, size: 20, color: Colors.grey),
              ),
            ),
          Transform.translate(
            offset: Offset(_dragOffset, 0),
            child: widget.child,
          ),
        ],
      ),
    );
  }
}
