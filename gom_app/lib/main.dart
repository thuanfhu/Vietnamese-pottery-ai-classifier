import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: HomeScreen(),
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

  List<dynamic> potteryList = [];
  bool isLoading = true;
  bool isUploading = false;
  String? resultMessage;
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
        setState(() {
          potteryList = jsonDecode(response.body);
        });
      }
    } catch (e) {
      debugPrint('Fetch error: $e');
    } finally {
      setState(() => isLoading = false);
    }
  }

  Future<void> pickAndUpload() async {
    final XFile? image = await _picker.pickImage(source: ImageSource.gallery);
    if (image == null) return;

    setState(() {
      isUploading = true;
      resultMessage = null;
    });

    try {
      final request = http.MultipartRequest(
        'POST',
        Uri.parse('$_baseUrl/api/upload'),
      );
      request.headers['Accept'] = 'application/json';
      request.files.add(await http.MultipartFile.fromPath('image', image.path));

      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);
      final body = jsonDecode(response.body);

      if (response.statusCode == 200) {
        final data = body['data'];
        setState(() {
          resultMessage =
              'Success: ${data['predicted_label']} (${((data['confidence'] ?? 0) * 100).toStringAsFixed(0)}%)';
        });
        await fetchPotteries();
      } else {
        setState(() {
          resultMessage = 'Error: ${body['message'] ?? response.statusCode}';
        });
      }
    } catch (e) {
      setState(() => resultMessage = 'Connection error: $e');
    } finally {
      setState(() => isUploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Pottery Classification'),
        backgroundColor: Colors.brown,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: fetchPotteries,
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                ElevatedButton.icon(
                  onPressed: isUploading ? null : pickAndUpload,
                  icon: isUploading
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.upload_file),
                  label: Text(
                      isUploading ? 'Processing...' : 'Select Image & Upload'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.brown,
                    foregroundColor: Colors.white,
                    minimumSize: const Size.fromHeight(48),
                  ),
                ),
                if (resultMessage != null) ...[
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: resultMessage!.startsWith('Success')
                          ? Colors.green.shade50
                          : Colors.red.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: resultMessage!.startsWith('Success')
                            ? Colors.green
                            : Colors.red,
                      ),
                    ),
                    child: Text(
                      resultMessage!,
                      style: const TextStyle(fontSize: 16),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const Divider(),
          Expanded(
            child: isLoading
                ? const Center(child: CircularProgressIndicator())
                : potteryList.isEmpty
                    ? const Center(
                        child: Text(
                            'No records found. Upload an image to get started.'))
                    : ListView.builder(
                        itemCount: potteryList.length,
                        itemBuilder: (context, index) {
                          final item = potteryList[index];
                          final confidence = item['confidence'] != null
                              ? '${((item['confidence'] as num) * 100).toStringAsFixed(0)}%'
                              : '--';
                          return Card(
                            margin: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 6),
                            child: ListTile(
                              leading:
                                  const Icon(Icons.image, color: Colors.brown),
                              title: Text(
                                item['predicted_label'] ?? 'Unknown',
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold),
                              ),
                              subtitle:
                                  Text('Path: ${item['image_path'] ?? ''}'),
                              trailing: Chip(
                                label: Text(confidence),
                                backgroundColor: Colors.brown.shade100,
                              ),
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}
