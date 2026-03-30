import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:http/http.dart' as http;

List<CameraDescription> cameras = [];

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  cameras = await availableCameras();
  runApp(const MaterialApp(
    debugShowCheckedModeBanner: false,
    home: KioskScreen(),
  ));
}

class KioskScreen extends StatefulWidget {
  const KioskScreen({super.key});

  @override
  State<KioskScreen> createState() => _KioskScreenState();
}

class _KioskScreenState extends State<KioskScreen> {
  CameraController? _controller;
  Timer? _captureTimer;
  
  // Các biến quản lý trạng thái UI
  bool _isProcessing = false; 
  String _statusMessage = "Xin mời đưa khuôn mặt vào khung hình";
  Color _statusColor = Colors.blueAccent;

  @override
  void initState() {
    super.initState();
    _initCamera();
  }

  Future<void> _initCamera() async {
    // Chọn camera trước (nếu có), hoặc camera đầu tiên tìm thấy
    final frontCamera = cameras.firstWhere(
      (camera) => camera.lensDirection == CameraLensDirection.front,
      orElse: () => cameras.first,
    );

    _controller = CameraController(frontCamera, ResolutionPreset.medium);
    await _controller!.initialize();
    
    if (mounted) {
      setState(() {});
      _startAutoCapture(); // Bắt đầu vòng lặp tự động chụp
    }
  }

  void _startAutoCapture() {
    // Cứ mỗi 4 giây sẽ tự động kích hoạt hàm chụp ảnh
    _captureTimer = Timer.periodic(const Duration(seconds: 4), (timer) {
      if (!_isProcessing) {
        _takePictureAndVerify();
      }
    });
  }

  Future<void> _takePictureAndVerify() async {
    if (_controller == null || !_controller!.value.isInitialized) return;

    setState(() {
      _isProcessing = true; // Khóa màn hình, hiện Loading
      _statusMessage = "Đang kiểm tra vé & sinh trắc học...";
      _statusColor = Colors.orange;
    });

    try {
      // 1. Chụp ảnh
      XFile imageFile = await _controller!.takePicture();
      
      // 2. Gửi ảnh xuống Local Python Server (chạy ngầm trên Raspberry Pi)
      var request = http.MultipartRequest(
        'POST', 
        Uri.parse('http://127.0.0.1:5000/verify-gate') // Link API Python local
      );
      request.files.add(await http.MultipartFile.fromPath('file', imageFile.path));
      
      var response = await request.send().timeout(const Duration(seconds: 10));
      var responseData = await response.stream.bytesToString();
      var jsonResult = json.decode(responseData);

      // 3. Xử lý logic đổi màu thông báo dựa trên kết quả
      setState(() {
        if (jsonResult['status'] == 'success') {
          _statusColor = Colors.green;
          _statusMessage = "Xin chào ${jsonResult['name']}, mời bạn qua cửa!";
        } else if (jsonResult['status'] == 'need_checkin') {
          _statusColor = Colors.amber;
          _statusMessage = "Mời bạn check-in online và thử lại!";
        } else if (jsonResult['status'] == 'not_paid') {
          _statusColor = Colors.red;
          _statusMessage = "Người dùng chưa thanh toán vé!";
        } else {
          _statusColor = Colors.redAccent;
          _statusMessage = "Người dùng hiện tại chưa đặt vé!";
        }
      });

    } catch (e) {
      // Nếu Python chưa chạy hoặc lỗi mạng, báo lỗi tạm
      setState(() {
        _statusColor = Colors.grey;
        _statusMessage = "Đang chờ kết nối với hệ thống cửa... ($e)";
      });
    } finally {
      // 4. Giữ thông báo trên màn hình 3 giây rồi reset lại từ đầu
      await Future.delayed(const Duration(seconds: 3));
      if (mounted) {
        setState(() {
          _statusMessage = "Xin mời đưa khuôn mặt vào khung hình";
          _statusColor = Colors.blueAccent;
          _isProcessing = false; // Mở khóa cho nhịp chụp tiếp theo
        });
      }
    }
  }

  @override
  void dispose() {
    _captureTimer?.cancel();
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_controller == null || !_controller!.value.isInitialized) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Lớp dưới cùng: Camera toàn màn hình
          CameraPreview(_controller!),

          // Lớp trên cùng: Thanh thông báo trạng thái
          Positioned(
            bottom: 0, left: 0, right: 0,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 25, horizontal: 20),
              decoration: BoxDecoration(
                color: _statusColor.withOpacity(0.9), // Nền hơi trong suốt
                borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _statusMessage,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold),
                  ),
                  if (_isProcessing) ...[
                    const SizedBox(height: 15),
                    const CircularProgressIndicator(color: Colors.white),
                  ]
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}