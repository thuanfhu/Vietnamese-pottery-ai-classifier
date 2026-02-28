import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

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
  List<dynamic> potteryList = [];
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    fetchPottery();
  }

  Future<void> fetchPottery() async {
    try {
      final response = await http.post(
  Uri.parse("http://localhost:8000/api/upload"),
  headers: {
    "Content-Type": "application/json"
  },
  body: jsonEncode({
    "name": "test"
  }),
);

if (response.statusCode == 200) {
  print(response.body);
} else {
  print("Lỗi server: ${response.statusCode}");
}
    } catch (e) {
      setState(() {
        isLoading = false;
      });
      debugPrint("Lỗi: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Danh sách Gốm Sứ"),
        backgroundColor: Colors.brown,
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView.builder(
              itemCount: potteryList.length,
              itemBuilder: (context, index) {
                final item = potteryList[index];
                return Card(
                  margin: const EdgeInsets.all(10),
                  child: ListTile(
                    title: Text(item['name'] ?? "Không có tên"),
                    subtitle: Text(item['description'] ?? ""),
                    trailing: Text(
                      item['price'] != null
                          ? "${item['price']} đ"
                          : "",
                      style: const TextStyle(
                        color: Colors.red,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                );
              },
            ),
    );
  }
}