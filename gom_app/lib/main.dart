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

  // ── Colour palette ──────────────────────────────────────────────────
  static const _navy = Color(0xFF1A3C5E); // primary dark
  static const _teal = Color(0xFF0E8C7E); // accent
  static const _navyLight = Color(0xFFE8EFF6); // surface tint
  static const _bg = Color(0xFFF4F7FB); // scaffold bg
  // legacy aliases so nothing else needs changing
  static const _brown = _navy;
  static const _brownLight = _navyLight;

  List<dynamic> potteryList = [];
  bool isLoading = true;
  bool isUploading = false;
  Uint8List? _previewBytes;
  String? _previewName;
  Map<String, dynamic>? _lastResult;
  String? _errorMessage;
  String? _selectedModel;
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
    });
  }

  Future<void> uploadImage() async {
    if (_previewBytes == null || _previewName == null) return;

    setState(() {
      isUploading = true;
      _lastResult = null;
      _errorMessage = null;
    });

    try {
      final request = http.MultipartRequest(
        'POST',
        Uri.parse('$_baseUrl/api/upload'),
      );
      request.headers['Accept'] = 'application/json';
      request.fields['model'] = _selectedModel ?? 'gemini';
      request.files.add(http.MultipartFile.fromBytes(
        'image',
        _previewBytes!,
        filename: _previewName!,
        contentType: MediaType.parse('image/jpeg'),
      ));

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
      setState(() => isUploading = false);
    }
  }

  // Route through Laravel API so HandleCors middleware fires (built-in server serves /storage/* as static files, bypassing all middleware).
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
                  fontSize: 18),
            ),
          ],
        ),
        actions: const [],
      ),
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ─── LEFT PANEL 40% ────────────────────────────────────────────
          Flexible(
            flex: 2,
            child: Container(
              decoration: const BoxDecoration(
                color: _bg,
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Card(
                  elevation: 2,
                  shadowColor: _navy.withValues(alpha: 0.18),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                      side: BorderSide(
                          color: _navy.withValues(alpha: 0.35), width: 1.5)),
                  clipBehavior: Clip.antiAlias,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // ── Header ──
                      Container(
                        decoration: const BoxDecoration(
                          color: _navy,
                        ),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 14),
                        child: const Row(
                          children: [
                            Icon(Icons.upload_rounded,
                                color: Colors.white70, size: 18),
                            SizedBox(width: 8),
                            Text(
                              'Upload & Classify',
                              style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white,
                                  letterSpacing: 0.3),
                            ),
                          ],
                        ),
                      ),

                      // ── Image preview ──
                      Expanded(
                        child: GestureDetector(
                          onTap: (_selectedModel == null || isUploading)
                              ? null
                              : pickImage,
                          child: Container(
                            color: const Color(0xFFF0F4F8),
                            child: _previewBytes != null
                                ? Stack(
                                    fit: StackFit.expand,
                                    alignment: Alignment.center,
                                    children: [
                                      // BoxFit.contain → never crops/distorts
                                      Image.memory(
                                        _previewBytes!,
                                        fit: BoxFit.contain,
                                      ),
                                      if (isUploading)
                                        Container(
                                          color: Colors.black45,
                                          child: const Center(
                                            child: Column(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                CircularProgressIndicator(
                                                    color: Colors.white),
                                                SizedBox(height: 12),
                                                Text('Analyzing...',
                                                    style: TextStyle(
                                                        color: Colors.white,
                                                        fontWeight:
                                                            FontWeight.w600)),
                                              ],
                                            ),
                                          ),
                                        ),
                                      if (!isUploading)
                                        Positioned(
                                          bottom: 8,
                                          right: 8,
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 10, vertical: 4),
                                            decoration: BoxDecoration(
                                              color: Colors.black54,
                                              borderRadius:
                                                  BorderRadius.circular(20),
                                            ),
                                            child: const Text('Tap to change',
                                                style: TextStyle(
                                                    color: Colors.white,
                                                    fontSize: 11)),
                                          ),
                                        ),
                                    ],
                                  )
                                : Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(Icons.add_photo_alternate_outlined,
                                          size: 60,
                                          color:
                                              _brown.withValues(alpha: 0.35)),
                                      const SizedBox(height: 10),
                                      Text(
                                        _selectedModel == null
                                            ? 'Select a model first'
                                            : 'Tap to choose an image',
                                        style: TextStyle(
                                            fontSize: 14,
                                            color:
                                                _brown.withValues(alpha: 0.55)),
                                      ),
                                    ],
                                  ),
                          ),
                        ),
                      ),

                      // ── Model selector ──
                      Container(
                        color: _navyLight,
                        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Icon(Icons.psychology_rounded,
                                    size: 14, color: _navy),
                                const SizedBox(width: 6),
                                const Text('AI Model',
                                    style: TextStyle(
                                        fontSize: 11,
                                        color: _navy,
                                        fontWeight: FontWeight.w800,
                                        letterSpacing: 0.6)),
                              ],
                            ),
                            const SizedBox(height: 8),
                            SegmentedButton<String>(
                              segments: const [
                                ButtonSegment(
                                  value: 'gemini',
                                  icon: Icon(Icons.flash_on_rounded, size: 13),
                                  label: Text('Gemini 2.5',
                                      style: TextStyle(fontSize: 11)),
                                ),
                                ButtonSegment(
                                  value: 'gemini3',
                                  icon: Icon(Icons.auto_awesome, size: 13),
                                  label: Text('Gemini 3',
                                      style: TextStyle(fontSize: 11)),
                                ),
                                ButtonSegment(
                                  value: 'gemini_lite',
                                  icon: Icon(Icons.bolt_rounded, size: 13),
                                  label: Text('Flash Lite',
                                      style: TextStyle(fontSize: 11)),
                                ),
                                ButtonSegment(
                                  value: 'llama4',
                                  icon:
                                      Icon(Icons.visibility_rounded, size: 13),
                                  label: Text('Llama 4',
                                      style: TextStyle(fontSize: 11)),
                                ),
                              ],
                              selected: _selectedModel != null
                                  ? {_selectedModel!}
                                  : {},
                              emptySelectionAllowed: true,
                              showSelectedIcon: false,
                              onSelectionChanged: isUploading
                                  ? null
                                  : (v) => setState(() {
                                        _selectedModel =
                                            v.isEmpty ? null : v.first;
                                        _lastResult = null;
                                        _errorMessage = null;
                                      }),
                              style: SegmentedButton.styleFrom(
                                backgroundColor: Colors.white,
                                selectedBackgroundColor: _teal,
                                selectedForegroundColor: Colors.white,
                                foregroundColor: _navy,
                                side: BorderSide(
                                    color: _navy.withValues(alpha: 0.2)),
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 4, vertical: 10),
                              ),
                            ),
                          ],
                        ),
                      ),

                      // ── Error ──
                      if (_errorMessage != null)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 8),
                            decoration: BoxDecoration(
                              color: Colors.red.shade50,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.red.shade200),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.error_outline,
                                    size: 16, color: Colors.red),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(_errorMessage!,
                                      style: const TextStyle(
                                          color: Colors.red, fontSize: 12)),
                                ),
                              ],
                            ),
                          ),
                        ),

                      // ── Buttons ──
                      Padding(
                        padding: const EdgeInsets.all(14),
                        child: Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed:
                                    (_selectedModel == null || isUploading)
                                        ? null
                                        : pickImage,
                                icon: const Icon(Icons.photo_library_outlined,
                                    size: 16),
                                label: const Text('Choose',
                                    style: TextStyle(fontSize: 13)),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: _navy,
                                  side: BorderSide(
                                      color: _navy.withValues(alpha: 0.5)),
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 13),
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(10)),
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: FilledButton.icon(
                                onPressed: (_selectedModel == null ||
                                        _previewBytes == null ||
                                        isUploading)
                                    ? null
                                    : uploadImage,
                                icon: isUploading
                                    ? const SizedBox(
                                        width: 16,
                                        height: 16,
                                        child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            color: Colors.white))
                                    : const Icon(Icons.auto_awesome, size: 16),
                                label: Text(
                                    isUploading ? 'Classifying…' : 'Classify',
                                    style: const TextStyle(fontSize: 13)),
                                style: FilledButton.styleFrom(
                                  backgroundColor: _teal,
                                  foregroundColor: Colors.white,
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 13),
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(10)),
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
          ), // end Flexible LEFT

          // ─── RIGHT PANEL 60% ─────────────────────────────────────────────
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
                        color: _navy.withValues(alpha: 0.35), width: 1.5)),
                clipBehavior: Clip.antiAlias,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // ── Header ──
                    Container(
                      color: _navy,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 14),
                      child: Row(
                        children: [
                          const Icon(Icons.history_rounded,
                              color: Colors.white70, size: 18),
                          const SizedBox(width: 8),
                          const Text('History',
                              style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white,
                                  letterSpacing: 0.3)),
                          const SizedBox(width: 8),
                          if (!isLoading)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 7, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text('${potteryList.length}',
                                  style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12)),
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
                                            color: Colors.white70))
                                    : const Icon(Icons.refresh_rounded,
                                        color: Colors.white70, size: 18),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    // ── Latest result card ──
                    if (_lastResult != null)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                        child: _buildResultCard(_lastResult!),
                      ),

                    // ── History list ──
                    Expanded(
                      child: isLoading
                          ? const Center(
                              child: CircularProgressIndicator(color: _teal))
                          : potteryList.isEmpty
                              ? Center(
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.image_search,
                                          size: 56,
                                          color: _navy.withValues(alpha: 0.2)),
                                      const SizedBox(height: 12),
                                      Text('No records yet',
                                          style: TextStyle(
                                              fontSize: 15,
                                              color: _navy.withValues(
                                                  alpha: 0.4))),
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
    final label = result['predicted_label'] ?? 'Unknown';
    final model = result['ai_model'] ?? _selectedModel ?? '';
    final rawText = (result['raw_text'] as String? ?? '').trim();

    // ── Not-pottery branch ──────────────────────────────────────────
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
                offset: const Offset(0, 3)),
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
                const Icon(Icons.warning_rounded,
                    color: Colors.amber, size: 24),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Không phải gốm',
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.bold)),
                      if (rawText.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        _TypewriterText(
                          text: rawText,
                          style: const TextStyle(
                              color: Colors.white70, fontSize: 13, height: 1.6),
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

    // ── Normal pottery result ────────────────────────────────────────
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
              offset: const Offset(0, 3)),
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
                child: Text(label,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.3)),
              ),
              const SizedBox(width: 10),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                    color: confColor, borderRadius: BorderRadius.circular(20)),
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
          if (rawText.isNotEmpty) ...[
            const SizedBox(height: 14),
            const Divider(color: Colors.white24, height: 1),
            const SizedBox(height: 12),
            _TypewriterText(
              text: rawText,
              style: const TextStyle(
                  color: Colors.white, fontSize: 13, height: 1.7),
            ),
          ],
        ],
      ),
    );
  }

  // ── Shared result card header ──────────────────────────────────────
  Widget _resultHeader(String model, IconData icon) {
    return Row(
      children: [
        Icon(icon, color: Colors.white70, size: 15),
        const SizedBox(width: 6),
        const Text('Kết quả phân tích',
            style: TextStyle(
                color: Colors.white70,
                fontSize: 11,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.5)),
        const Spacer(),
        if (model.isNotEmpty)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(model,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w700)),
          ),
      ],
    );
  }

  // ── History list item with expandable AI answer ────────────────────
  Widget _buildHistoryItem(Map<String, dynamic> item) {
    final conf = _confidenceValue(item['confidence']);
    final confColor = _confidenceColor(conf);
    final imgUrl =
        item['image_path'] != null ? _imageUrl(item['image_path']) : null;
    final rawAnswer = (item['raw_answer'] as String? ?? '').trim();
    final label = item['predicted_label'] ?? 'Unknown';
    final isNotPottery = label == 'not_pottery';
    final hasAnswer = rawAnswer.isNotEmpty;

    final thumbnail = Container(
      width: 80,
      height: 80,
      color: _navyLight,
      child: imgUrl != null
          ? Image.network(imgUrl,
              fit: BoxFit.contain,
              errorBuilder: (_, __, ___) => Icon(
                    Icons.broken_image_outlined,
                    color: _navy.withValues(alpha: 0.4),
                  ))
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
                      color: isNotPottery ? Colors.red.shade700 : _navy),
                ),
              ),
              if (item['ai_model'] != null)
                Container(
                  margin: const EdgeInsets.only(left: 4),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                  decoration: BoxDecoration(
                    color: _teal.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(5),
                  ),
                  child: Text(item['ai_model'],
                      style: TextStyle(
                          fontSize: 9,
                          color: _teal,
                          fontWeight: FontWeight.w800)),
                ),
              SizedBox(
                width: 28,
                height: 28,
                child: IconButton(
                  padding: EdgeInsets.zero,
                  tooltip: 'Delete',
                  icon: Icon(Icons.delete_outline_rounded,
                      size: 16, color: Colors.red.withValues(alpha: 0.7)),
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
                  fontSize: 10, color: confColor, fontWeight: FontWeight.w600),
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
      child: hasAnswer
          ? Theme(
              data:
                  Theme.of(context).copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                tilePadding: EdgeInsets.zero,
                childrenPadding: EdgeInsets.zero,
                trailing: Icon(Icons.expand_more_rounded,
                    size: 18, color: _navy.withValues(alpha: 0.45)),
                title: Row(children: [thumbnail, Expanded(child: infoSection)]),
                children: [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.fromLTRB(14, 4, 14, 14),
                    color: _navyLight.withValues(alpha: 0.5),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Divider(height: 12),
                        Row(children: [
                          Icon(Icons.chat_bubble_outline_rounded,
                              size: 12, color: _navy.withValues(alpha: 0.5)),
                          const SizedBox(width: 4),
                          Text('Câu trả lời AI',
                              style: TextStyle(
                                  fontSize: 10,
                                  color: _navy.withValues(alpha: 0.5),
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 0.4)),
                        ]),
                        const SizedBox(height: 6),
                        Text(rawAnswer,
                            style: TextStyle(
                                fontSize: 12,
                                color: _navy.withValues(alpha: 0.85),
                                height: 1.6)),
                      ],
                    ),
                  ),
                ],
              ),
            )
          : Row(children: [thumbnail, Expanded(child: infoSection)]),
    );
  }
}

// ---------------------------------------------------------------------------
// Typewriter animation widget
// ---------------------------------------------------------------------------
class _TypewriterText extends StatefulWidget {
  final String text;
  final TextStyle? style;

  /// Delay between each revealed character.
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
    _charCount = IntTween(begin: 0, end: text.length)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.linear));
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
      builder: (_, __) => Text(
        widget.text.substring(0, _charCount.value),
        style: widget.style,
      ),
    );
  }
}
