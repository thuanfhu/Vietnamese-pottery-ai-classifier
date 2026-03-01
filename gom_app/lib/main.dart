import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:image_picker/image_picker.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF1A3C5E),
          brightness: Brightness.light,
        ),
        useMaterial3: true,
        fontFamily: 'Roboto',
      ),
      home: const HomeScreen(),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({Key? key}) : super(key: key);

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  static const String _baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://localhost:8000',
  );

  // Application color palette
  static const _navy = Color(0xFF1A3C5E);
  static const _teal = Color(0xFF0E8C7E);
  static const _navyLight = Color(0xFFE8EFF6);
  static const _bg = Color(0xFFF4F7FB);
  static const _brown = _navy;
  static const _brownLight = _navyLight;

  List<dynamic> potteryList = [];
  bool isLoading = true;
  bool isUploading = false;
  // Tracks which TADP agent is currently active (0 = idle, 1-4 = active step)
  int _debateStep = 0;
  Uint8List? _previewBytes;
  String? _previewName;
  Map<String, dynamic>? _lastResult;
  String? _errorMessage;
  final ImagePicker _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    fetchPotteries();
  }

  Future<void> fetchPotteries() async {
    setState(() => isLoading = true);
    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/api/potteries'),
        headers: {'Accept': 'application/json'},
      );
      if (response.statusCode == 200) {
        setState(() => potteryList = jsonDecode(response.body));
      }
    } catch (e) {
      debugPrint('Fetch error: $e');
    } finally {
      setState(() => isLoading = false);
    }
  }

  Future<void> pickImage() async {
    final XFile? image = await _picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
    );
    if (image == null) return;
    final bytes = await image.readAsBytes();
    setState(() {
      _previewBytes = bytes;
      _previewName = image.name;
      _lastResult = null;
      _errorMessage = null;
      _debateStep = 0;
    });
  }

  Future<void> uploadImage() async {
    if (_previewBytes == null || _previewName == null) return;

    setState(() {
      isUploading = true;
      _debateStep = 1;
      _lastResult = null;
      _errorMessage = null;
    });

    // Advance the visible debate step indicator every 40 seconds as a progress hint
    final stepTimer = Stream.periodic(const Duration(seconds: 40), (i) => i + 2)
        .take(3)
        .listen((step) {
      if (mounted && isUploading) setState(() => _debateStep = step);
    });

    try {
      final request = http.MultipartRequest(
        'POST',
        Uri.parse('$_baseUrl/api/upload'),
      );
      request.headers['Accept'] = 'application/json';
      request.files.add(
        http.MultipartFile.fromBytes(
          'image',
          _previewBytes!,
          filename: _previewName!,
          contentType: MediaType.parse('image/jpeg'),
        ),
      );

      final streamed = await request.send();
      final response = await http.Response.fromStream(streamed);
      final body = jsonDecode(response.body);

      if (response.statusCode == 200) {
        setState(() => _lastResult = body['data']);
        await fetchPotteries();
      } else {
        setState(() => _errorMessage = body['message'] ?? 'Unknown error');
      }
    } catch (e) {
      setState(() => _errorMessage = 'Connection error: $e');
    } finally {
      await stepTimer.cancel();
      setState(() {
        isUploading = false;
        _debateStep = 0;
      });
    }
  }

  // Proxies image paths through the API to ensure CORS middleware is applied
  String _imageUrl(String path) => '$_baseUrl/api/img/$path';

  Future<void> deletePottery(int id) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete record'),
        content: const Text('Remove this prediction from history?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      final response = await http.delete(
        Uri.parse('$_baseUrl/api/potteries/$id'),
        headers: {'Accept': 'application/json'},
      );
      if (response.statusCode == 200) {
        setState(() {
          potteryList.removeWhere((e) => e['id'] == id);
        });
      }
    } catch (e) {
      debugPrint('Delete error: $e');
    }
  }

  double _confidenceValue(dynamic v) => v == null ? 0.0 : (v as num).toDouble();

  Color _confidenceColor(double v) {
    if (v >= 0.85) return Colors.green;
    if (v >= 0.65) return Colors.orange;
    return Colors.red;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _navy,
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Row(
          children: [
            Icon(Icons.emoji_nature_rounded, size: 22),
            SizedBox(width: 10),
            Text(
              'Pottery Classification',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                letterSpacing: 0.6,
                fontSize: 18,
              ),
            ),
          ],
        ),
        actions: const [],
      ),
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Left panel: image picker and upload controls
          Flexible(
            flex: 2,
            child: Container(
              decoration: const BoxDecoration(color: _bg),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Card(
                  elevation: 2,
                  shadowColor: _navy.withValues(alpha: 0.18),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18),
                    side: BorderSide(
                      color: _navy.withValues(alpha: 0.35),
                      width: 1.5,
                    ),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Container(
                        decoration: const BoxDecoration(color: _navy),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 14,
                        ),
                        child: const Row(
                          children: [
                            Icon(
                              Icons.upload_rounded,
                              color: Colors.white70,
                              size: 18,
                            ),
                            SizedBox(width: 8),
                            Text(
                              'Upload & Classify',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                                letterSpacing: 0.3,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: GestureDetector(
                          onTap: isUploading ? null : pickImage,
                          child: Container(
                            color: const Color(0xFFF0F4F8),
                            child: _previewBytes != null
                                ? Stack(
                                    fit: StackFit.expand,
                                    alignment: Alignment.center,
                                    children: [
                                      Image.memory(
                                        _previewBytes!,
                                        fit: BoxFit.contain,
                                      ),
                                      if (isUploading)
                                        Container(
                                          color: Colors.black54,
                                          child: Center(
                                            child: _TadpLoadingOverlay(
                                              activeStep: _debateStep,
                                            ),
                                          ),
                                        ),
                                      if (!isUploading)
                                        Positioned(
                                          bottom: 8,
                                          right: 8,
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 10,
                                              vertical: 4,
                                            ),
                                            decoration: BoxDecoration(
                                              color: Colors.black54,
                                              borderRadius:
                                                  BorderRadius.circular(20),
                                            ),
                                            child: const Text(
                                              'Tap to change',
                                              style: TextStyle(
                                                color: Colors.white,
                                                fontSize: 11,
                                              ),
                                            ),
                                          ),
                                        ),
                                    ],
                                  )
                                : Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(
                                        Icons.add_photo_alternate_outlined,
                                        size: 60,
                                        color: _brown.withValues(alpha: 0.35),
                                      ),
                                      const SizedBox(height: 10),
                                      Text(
                                        'Tap to choose an image',
                                        style: TextStyle(
                                          fontSize: 14,
                                          color: _brown.withValues(alpha: 0.55),
                                        ),
                                      ),
                                    ],
                                  ),
                          ),
                        ),
                      ),
                      Container(
                        color: _navyLight,
                        padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.hub_rounded,
                              size: 15,
                              color: _teal,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: RichText(
                                text: const TextSpan(
                                  style: TextStyle(fontSize: 11, color: _navy),
                                  children: [
                                    TextSpan(
                                      text: 'TADP Pipeline  ',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w800,
                                        color: _teal,
                                        letterSpacing: 0.4,
                                      ),
                                    ),
                                    TextSpan(
                                      text:
                                          'Gemini 2.5 → GPT-4o mini → Grok 4 → Hội đồng',
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (_errorMessage != null)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.red.shade50,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.red.shade200),
                            ),
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.error_outline,
                                  size: 16,
                                  color: Colors.red,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    _errorMessage!,
                                    style: const TextStyle(
                                      color: Colors.red,
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      Padding(
                        padding: const EdgeInsets.all(14),
                        child: Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: isUploading ? null : pickImage,
                                icon: const Icon(
                                  Icons.photo_library_outlined,
                                  size: 16,
                                ),
                                label: const Text(
                                  'Choose',
                                  style: TextStyle(fontSize: 13),
                                ),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: _navy,
                                  side: BorderSide(
                                    color: _navy.withValues(alpha: 0.5),
                                  ),
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 13,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: FilledButton.icon(
                                onPressed:
                                    (_previewBytes == null || isUploading)
                                        ? null
                                        : uploadImage,
                                icon: isUploading
                                    ? const SizedBox(
                                        width: 16,
                                        height: 16,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: Colors.white,
                                        ),
                                      )
                                    : const Icon(Icons.auto_awesome, size: 16),
                                label: Text(
                                  isUploading ? 'Classifying…' : 'Classify',
                                  style: const TextStyle(fontSize: 13),
                                ),
                                style: FilledButton.styleFrom(
                                  backgroundColor: _teal,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 13,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          // Right panel: prediction history list
          Flexible(
            flex: 3,
            child: Container(
              color: _bg,
              padding: const EdgeInsets.all(16),
              child: Card(
                elevation: 2,
                shadowColor: _navy.withValues(alpha: 0.18),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                  side: BorderSide(
                    color: _navy.withValues(alpha: 0.35),
                    width: 1.5,
                  ),
                ),
                clipBehavior: Clip.antiAlias,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(
                      color: _navy,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 14,
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.history_rounded,
                            color: Colors.white70,
                            size: 18,
                          ),
                          const SizedBox(width: 8),
                          const Text(
                            'History',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                              letterSpacing: 0.3,
                            ),
                          ),
                          const SizedBox(width: 8),
                          if (!isLoading)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 7,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(
                                '${potteryList.length}',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          const Spacer(),
                          Tooltip(
                            message: 'Refresh',
                            child: InkWell(
                              borderRadius: BorderRadius.circular(8),
                              onTap: isLoading ? null : fetchPotteries,
                              child: Padding(
                                padding: const EdgeInsets.all(4),
                                child: isLoading
                                    ? const SizedBox(
                                        width: 16,
                                        height: 16,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: Colors.white70,
                                        ),
                                      )
                                    : const Icon(
                                        Icons.refresh_rounded,
                                        color: Colors.white70,
                                        size: 18,
                                      ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (_lastResult != null)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                        child: _buildResultCard(_lastResult!),
                      ),
                    Expanded(
                      child: isLoading
                          ? const Center(
                              child: CircularProgressIndicator(color: _teal),
                            )
                          : potteryList.isEmpty
                              ? Center(
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Icons.image_search,
                                        size: 56,
                                        color: _navy.withValues(alpha: 0.2),
                                      ),
                                      const SizedBox(height: 12),
                                      Text(
                                        'No records yet',
                                        style: TextStyle(
                                          fontSize: 15,
                                          color: _navy.withValues(alpha: 0.4),
                                        ),
                                      ),
                                    ],
                                  ),
                                )
                              : ListView.builder(
                                  padding:
                                      const EdgeInsets.fromLTRB(10, 8, 10, 12),
                                  itemCount: potteryList.length,
                                  itemBuilder: (context, index) {
                                    final item = potteryList[
                                        potteryList.length - 1 - index];
                                    return _buildHistoryItem(item);
                                  },
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

  Widget _buildResultCard(Map<String, dynamic> result) {
    final model = (result['ai_model'] as String?) ?? 'TADP';
    final rawText = (result['raw_text'] as String? ?? '').trim();
    final label = result['predicted_label'] ?? 'Unknown';
    final debateTrail =
        (result['debate_trail'] as List?)?.cast<Map<String, dynamic>>();
    // Delegate to the animated debate result card when a full debate trail is available
    if (label != 'not_pottery' &&
        debateTrail != null &&
        debateTrail.isNotEmpty) {
      return _DebateResultCard(result: result);
    }

    if (label == 'not_pottery') {
      return Container(
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFFB71C1C), Color(0xFF7B1FA2)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: Colors.red.withValues(alpha: 0.3),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _resultHeader(model, Icons.hide_image_rounded),
            const SizedBox(height: 14),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.warning_rounded,
                  color: Colors.amber,
                  size: 24,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Không phải gốm',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      if (rawText.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        _TypewriterText(
                          text: rawText,
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 13,
                            height: 1.6,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      );
    }

    final conf = _confidenceValue(result['confidence']);
    final confColor = _confidenceColor(conf);

    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF0E8C7E), Color(0xFF1A3C5E)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: _teal.withValues(alpha: 0.3),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _resultHeader(model, Icons.check_circle_rounded),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.3,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: confColor,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '${(conf * 100).toStringAsFixed(1)}%',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: conf,
              backgroundColor: Colors.white24,
              valueColor: AlwaysStoppedAnimation(confColor),
              minHeight: 6,
            ),
          ),
          if (rawText.isNotEmpty) ...[
            const SizedBox(height: 14),
            const Divider(color: Colors.white24, height: 1),
            const SizedBox(height: 12),
            _TypewriterText(
              text: rawText,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                height: 1.7,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _resultHeader(String model, IconData icon) {
    return Row(
      children: [
        Icon(icon, color: Colors.white70, size: 15),
        const SizedBox(width: 6),
        const Text(
          'Kết quả phân tích',
          style: TextStyle(
            color: Colors.white70,
            fontSize: 11,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.5,
          ),
        ),
        const Spacer(),
        if (model.isNotEmpty)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              model,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildHistoryItem(Map<String, dynamic> item) {
    final conf = _confidenceValue(item['confidence']);
    final confColor = _confidenceColor(conf);
    final imgUrl =
        item['image_path'] != null ? _imageUrl(item['image_path']) : null;
    final rawAnswer = (item['raw_answer'] as String? ?? '').trim();
    final label = item['predicted_label'] ?? 'Unknown';
    final isNotPottery = label == 'not_pottery';
    final forgeryRisk = item['forgery_risk'] as String?;
    final debateTrail =
        (item['debate_trail'] as List?)?.cast<Map<String, dynamic>>();
    final hasExpand =
        rawAnswer.isNotEmpty || (debateTrail?.isNotEmpty ?? false);

    final thumbnail = Container(
      width: 80,
      height: 80,
      color: _navyLight,
      child: imgUrl != null
          ? Image.network(
              imgUrl,
              fit: BoxFit.contain,
              errorBuilder: (_, __, ___) => Icon(
                Icons.broken_image_outlined,
                color: _navy.withValues(alpha: 0.4),
              ),
            )
          : Icon(Icons.image_outlined, color: _navy.withValues(alpha: 0.4)),
    );

    final infoSection = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  isNotPottery ? 'Không phải gốm' : label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: isNotPottery ? Colors.red.shade700 : _navy,
                  ),
                ),
              ),
              if (forgeryRisk != null && forgeryRisk != 'không áp dụng') ...[
                const SizedBox(width: 4),
                _ForgeryRiskBadge(risk: forgeryRisk, compact: true),
              ],
              const SizedBox(width: 4),
              if (item['ai_model'] != null)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 5,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: _teal.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(5),
                  ),
                  child: Text(
                    item['ai_model'],
                    style: TextStyle(
                      fontSize: 9,
                      color: _teal,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              SizedBox(
                width: 28,
                height: 28,
                child: IconButton(
                  padding: EdgeInsets.zero,
                  tooltip: 'Delete',
                  icon: Icon(
                    Icons.delete_outline_rounded,
                    size: 16,
                    color: Colors.red.withValues(alpha: 0.7),
                  ),
                  onPressed: () => deletePottery(item['id'] as int),
                ),
              ),
            ],
          ),
          if (!isNotPottery) ...[
            const SizedBox(height: 4),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: conf,
                backgroundColor: _navyLight,
                valueColor: AlwaysStoppedAnimation(confColor),
                minHeight: 5,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              '${(conf * 100).toStringAsFixed(1)}% confidence',
              style: TextStyle(
                fontSize: 10,
                color: confColor,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ],
      ),
    );

    return Card(
      elevation: 1,
      margin: const EdgeInsets.symmetric(vertical: 4),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      clipBehavior: Clip.antiAlias,
      child: hasExpand
          ? Theme(
              data: Theme.of(
                context,
              ).copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                tilePadding: EdgeInsets.zero,
                childrenPadding: EdgeInsets.zero,
                trailing: Icon(
                  Icons.expand_more_rounded,
                  size: 18,
                  color: _navy.withValues(alpha: 0.45),
                ),
                title: Row(
                  children: [
                    thumbnail,
                    Expanded(child: infoSection),
                  ],
                ),
                children: [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.fromLTRB(14, 4, 14, 14),
                    color: _navyLight.withValues(alpha: 0.5),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Divider(height: 12),
                        Row(
                          children: [
                            Icon(
                              Icons.forum_rounded,
                              size: 12,
                              color: _navy.withValues(alpha: 0.5),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              'Phán quyết cuối cùng',
                              style: TextStyle(
                                fontSize: 10,
                                color: _navy.withValues(alpha: 0.5),
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.4,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        if (rawAnswer.isNotEmpty)
                          Text(
                            rawAnswer,
                            style: TextStyle(
                              fontSize: 12,
                              color: _navy.withValues(alpha: 0.85),
                              height: 1.6,
                            ),
                          ),
                        if (debateTrail != null && debateTrail.isNotEmpty) ...[
                          const SizedBox(height: 12),
                          const Divider(height: 1),
                          const SizedBox(height: 8),
                          Text(
                            'Nhật ký tranh luận TADP',
                            style: TextStyle(
                              fontSize: 10,
                              color: _navy.withValues(alpha: 0.5),
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.4,
                            ),
                          ),
                          const SizedBox(height: 8),
                          ...debateTrail.map(
                            (step) => _HistoryDebateStep(step: step),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            )
          : Row(
              children: [
                thumbnail,
                Expanded(child: infoSection),
              ],
            ),
    );
  }
}

class _DebateResultCard extends StatefulWidget {
  final Map<String, dynamic> result;
  const _DebateResultCard({required this.result});

  @override
  State<_DebateResultCard> createState() => _DebateResultCardState();
}

class _DebateResultCardState extends State<_DebateResultCard>
    with TickerProviderStateMixin {
  static const _colors = [
    Color(0xFF1565C0),
    Color(0xFFE65100),
    Color(0xFFC62828),
    Color(0xFF1B5E20),
  ];
  static const _icons = [
    Icons.visibility_rounded,
    Icons.history_edu_rounded,
    Icons.psychology_alt_rounded,
    Icons.gavel_rounded,
  ];

  int _visibleSteps = 0;
  bool _showVerdict = false;
  final List<AnimationController> _slideCtrl = [];
  final List<Animation<Offset>> _slideAnim = [];

  @override
  void initState() {
    super.initState();
    final trail = (widget.result['debate_trail'] as List? ?? [])
        .cast<Map<String, dynamic>>();
    for (int i = 0; i < trail.length; i++) {
      final ctrl = AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 450),
      );
      _slideCtrl.add(ctrl);
      _slideAnim.add(
        Tween<Offset>(begin: const Offset(-0.3, 0), end: Offset.zero)
            .animate(CurvedAnimation(parent: ctrl, curve: Curves.easeOut)),
      );
    }
    _startReveal(trail.length);
  }

  void _startReveal(int total) {
    for (int i = 0; i < total; i++) {
      Future.delayed(Duration(milliseconds: 400 + i * 900), () {
        if (!mounted) return;
        setState(() => _visibleSteps = i + 1);
        _slideCtrl[i].forward();
      });
    }
    Future.delayed(Duration(milliseconds: 400 + total * 900 + 600), () {
      if (mounted) setState(() => _showVerdict = true);
    });
  }

  @override
  void dispose() {
    for (final c in _slideCtrl) c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final trail = (widget.result['debate_trail'] as List? ?? [])
        .cast<Map<String, dynamic>>();
    final label = widget.result['predicted_label'] ?? '';
    final conf = (widget.result['confidence'] as num?)?.toDouble() ?? 0.0;
    final forgeryRisk = widget.result['forgery_risk'] as String? ?? '';
    final confColor = conf >= 0.85
        ? Colors.green.shade400
        : conf >= 0.65
            ? Colors.orange
            : Colors.red;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ...List.generate(trail.length.clamp(0, _visibleSteps), (i) {
          final step = trail[i];
          final color = _colors[i % _colors.length];
          final icon = _icons[i % _icons.length];
          return SlideTransition(
            position: _slideAnim[i],
            child: AnimatedOpacity(
              opacity: _visibleSteps > i ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 400),
              child: _AgentStepCard(
                step: step,
                color: color,
                icon: icon,
              ),
            ),
          );
        }),
        AnimatedOpacity(
          opacity: _showVerdict ? 1.0 : 0.0,
          duration: const Duration(milliseconds: 600),
          child: AnimatedSlide(
            offset: _showVerdict ? Offset.zero : const Offset(0, 0.2),
            duration: const Duration(milliseconds: 500),
            curve: Curves.easeOut,
            child: Container(
              margin: const EdgeInsets.only(top: 10),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF0E8C7E), Color(0xFF1A3C5E)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(14),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF0E8C7E).withValues(alpha: 0.35),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.gavel_rounded,
                          color: Colors.white70, size: 15),
                      const SizedBox(width: 6),
                      const Expanded(
                        child: Text('PHÁN QUYẾT CUỐI CÙNG – HỘI ĐỒNG TADP',
                            style: TextStyle(
                                color: Colors.white70,
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.8)),
                      ),
                      if (forgeryRisk.isNotEmpty)
                        _ForgeryRiskBadge(risk: forgeryRisk, compact: false),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(
                        child: Text(label,
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 22,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 0.3)),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                            color: confColor,
                            borderRadius: BorderRadius.circular(20)),
                        child: Text(
                          '${(conf * 100).toStringAsFixed(1)}%',
                          style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 13),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: LinearProgressIndicator(
                      value: conf,
                      backgroundColor: Colors.white24,
                      valueColor: AlwaysStoppedAnimation(confColor),
                      minHeight: 6,
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Divider(color: Colors.white24, height: 1),
                  const SizedBox(height: 10),
                  _TypewriterText(
                    text: (widget.result['raw_text'] as String? ?? '').trim(),
                    style: const TextStyle(
                        color: Colors.white, fontSize: 13, height: 1.7),
                    charDelay: const Duration(milliseconds: 18),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _AgentStepCard extends StatelessWidget {
  final Map<String, dynamic> step;
  final Color color;
  final IconData icon;

  const _AgentStepCard({
    required this.step,
    required this.color,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final agent = step['agent'] as String? ?? '';
    final model = step['model'] as String? ?? '';
    final role = step['role'] as String? ?? '';
    final content = step['content'] as String? ?? '';
    final stepNum = step['step'] as int? ?? 0;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border(
          left: BorderSide(color: color, width: 3.5),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Text('$stepNum',
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.bold)),
                ),
              ),
              const SizedBox(width: 8),
              Icon(icon, size: 13, color: color),
              const SizedBox(width: 5),
              Expanded(
                child: Text(agent,
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: color)),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(5),
                ),
                child: Text(model,
                    style: TextStyle(
                        fontSize: 9,
                        color: color,
                        fontWeight: FontWeight.w700)),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(role,
              style: TextStyle(
                  fontSize: 10,
                  color: color.withValues(alpha: 0.75),
                  fontStyle: FontStyle.italic)),
          const SizedBox(height: 6),
          _TypewriterText(
            text: content,
            style: TextStyle(
                fontSize: 12,
                color: const Color(0xFF1A3C5E).withValues(alpha: 0.85),
                height: 1.6),
            charDelay: const Duration(milliseconds: 12),
          ),
        ],
      ),
    );
  }
}

class _ForgeryRiskBadge extends StatelessWidget {
  final String risk;
  final bool compact;
  const _ForgeryRiskBadge({required this.risk, required this.compact});

  Color _riskColor() {
    switch (risk.toLowerCase()) {
      case 'rất thấp':
        return Colors.green.shade600;
      case 'thấp':
        return Colors.lightGreen.shade700;
      case 'trung bình':
        return Colors.orange.shade700;
      case 'cao':
        return Colors.deepOrange;
      case 'rất cao':
        return Colors.red.shade800;
      default:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = _riskColor();
    return Container(
      padding: EdgeInsets.symmetric(
          horizontal: compact ? 5 : 8, vertical: compact ? 2 : 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.security_rounded, size: compact ? 9 : 11, color: color),
          const SizedBox(width: 3),
          Text(
            compact ? risk : 'Giả cổ: $risk',
            style: TextStyle(
                fontSize: compact ? 9 : 10,
                color: color,
                fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

class _HistoryDebateStep extends StatelessWidget {
  final Map<String, dynamic> step;
  const _HistoryDebateStep({required this.step});

  static const _borderColors = [
    Color(0xFF1565C0),
    Color(0xFFE65100),
    Color(0xFFC62828),
    Color(0xFF1B5E20),
  ];

  @override
  Widget build(BuildContext context) {
    final stepNum = (step['step'] as int?) ?? 1;
    final agent = step['agent'] as String? ?? '';
    final model = step['model'] as String? ?? '';
    final content = step['content'] as String? ?? '';
    final idx = (stepNum - 1).clamp(0, _borderColors.length - 1);
    final color = _borderColors[idx];

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        border: Border(left: BorderSide(color: color, width: 3)),
        color: color.withValues(alpha: 0.04),
        borderRadius: const BorderRadius.only(
          topRight: Radius.circular(6),
          bottomRight: Radius.circular(6),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('$stepNum. $agent',
                  style: TextStyle(
                      fontSize: 10, fontWeight: FontWeight.w800, color: color)),
              const Spacer(),
              Text(model,
                  style: TextStyle(
                      fontSize: 9,
                      color: color.withValues(alpha: 0.7),
                      fontStyle: FontStyle.italic)),
            ],
          ),
          const SizedBox(height: 3),
          Text(content,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontSize: 11,
                  color: const Color(0xFF1A3C5E).withValues(alpha: 0.75),
                  height: 1.5)),
        ],
      ),
    );
  }
}

class _TadpLoadingOverlay extends StatefulWidget {
  // Active step index passed from the parent upload state (1-4)
  final int activeStep;
  const _TadpLoadingOverlay({required this.activeStep});

  @override
  State<_TadpLoadingOverlay> createState() => _TadpLoadingOverlayState();
}

class _TadpLoadingOverlayState extends State<_TadpLoadingOverlay>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  static const _agents = [
    ('Quan sát viên', Icons.visibility_rounded, Color(0xFF1565C0)),
    ('Sử gia', Icons.history_edu_rounded, Color(0xFFE65100)),
    ('Hoài nghi', Icons.psychology_alt_rounded, Color(0xFFC62828)),
    ('Hội đồng', Icons.gavel_rounded, Color(0xFF1B5E20)),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('TADP đang tranh luận…',
              style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                  letterSpacing: 0.4)),
          const SizedBox(height: 14),
          ..._agents.asMap().entries.map((e) {
            final idx = e.key;
            final agent = e.value;
            final isActive = idx + 1 == widget.activeStep;
            final isDone = idx + 1 < widget.activeStep;
            return AnimatedBuilder(
              animation: _pulse,
              builder: (_, __) {
                final opacity = isActive
                    ? 0.5 + _pulse.value * 0.5
                    : isDone
                        ? 1.0
                        : 0.3;
                return Opacity(
                  opacity: opacity,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      children: [
                        Container(
                          width: 28,
                          height: 28,
                          decoration: BoxDecoration(
                            color:
                                isDone || isActive ? agent.$3 : Colors.white24,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(agent.$2,
                              size: 14,
                              color: isDone || isActive
                                  ? Colors.white
                                  : Colors.white38),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(agent.$1,
                              style: TextStyle(
                                  color: isDone
                                      ? Colors.white
                                      : isActive
                                          ? agent.$3.withValues(alpha: 0.9)
                                          : Colors.white38,
                                  fontSize: 12,
                                  fontWeight: isActive
                                      ? FontWeight.w700
                                      : FontWeight.normal)),
                        ),
                        Icon(
                          isDone
                              ? Icons.check_circle_rounded
                              : isActive
                                  ? Icons.pending_rounded
                                  : Icons.radio_button_unchecked_rounded,
                          size: 14,
                          color: isDone
                              ? Colors.green.shade400
                              : isActive
                                  ? Colors.amber
                                  : Colors.white24,
                        ),
                      ],
                    ),
                  ),
                );
              },
            );
          }),
        ],
      ),
    );
  }
}

class _TypewriterText extends StatefulWidget {
  final String text;
  final TextStyle? style;

  final Duration charDelay;

  const _TypewriterText({
    required this.text,
    this.style,
    this.charDelay = const Duration(milliseconds: 20),
  });

  @override
  State<_TypewriterText> createState() => _TypewriterTextState();
}

class _TypewriterTextState extends State<_TypewriterText>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<int> _charCount;

  @override
  void initState() {
    super.initState();
    _startAnimation(widget.text);
  }

  @override
  void didUpdateWidget(_TypewriterText old) {
    super.didUpdateWidget(old);
    if (old.text != widget.text) {
      _ctrl.dispose();
      _startAnimation(widget.text);
    }
  }

  void _startAnimation(String text) {
    final length = text.length.clamp(1, 10000);
    _ctrl = AnimationController(
      vsync: this,
      duration: widget.charDelay * length,
    );
    _charCount = IntTween(
      begin: 0,
      end: text.length,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.linear));
    _ctrl.forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _charCount,
      builder: (_, __) =>
          Text(widget.text.substring(0, _charCount.value), style: widget.style),
    );
  }
}
