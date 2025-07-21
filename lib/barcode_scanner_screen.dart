import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:vibration/vibration.dart';
import 'package:shared_preferences/shared_preferences.dart';

class BarcodeScannerScreen extends StatefulWidget {
  const BarcodeScannerScreen({Key? key}) : super(key: key);

  @override
  State<BarcodeScannerScreen> createState() => _BarcodeScannerScreenState();
}

class _BarcodeScannerScreenState extends State<BarcodeScannerScreen> {
  final MobileScannerController cameraController = MobileScannerController(
    torchEnabled: false,
    formats: [
      BarcodeFormat.code128,
      BarcodeFormat.code39,
      BarcodeFormat.code93,
      BarcodeFormat.ean8,
      BarcodeFormat.ean13,
      BarcodeFormat.upcA,
      BarcodeFormat.upcE,
      BarcodeFormat.itf,
      BarcodeFormat.codabar,
      BarcodeFormat.qrCode,
      BarcodeFormat.pdf417,
      BarcodeFormat.aztec,
      BarcodeFormat.dataMatrix,
    ],
  );

  bool _screenOpened = false;
  bool _torchEnabled = false;
  CameraFacing _cameraFacing = CameraFacing.back;
  StreamSubscription<BarcodeCapture>? _subscription;
  int _currentLanguageFlag = 1; // Default to English
  String _phOrJp = "ph"; // Default to ph

  // Variables for threshold checking
  final int _requiredConsecutiveScans = 3;
  String? _lastScannedCode;
  int _consecutiveScanCount = 0;
  Timer? _scanResetTimer;

  @override
  void initState() {
    super.initState();
    _loadPreferences();
    _startListening();
    _torchEnabled = cameraController.torchEnabled;
  }

  Future<void> _loadPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _phOrJp = prefs.getString('phorjp') ?? "ph";
      if (_phOrJp == "ph") {
        _currentLanguageFlag = prefs.getInt('languageFlag') ?? 1;
      } else {
        _currentLanguageFlag = prefs.getInt('languageFlagJP') ?? 1;
      }
    });
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _scanResetTimer?.cancel();
    cameraController.dispose();
    super.dispose();
  }

  void _startListening() {
    _subscription = cameraController.barcodes.listen(
          (BarcodeCapture capture) {
        if (!_screenOpened && capture.barcodes.isNotEmpty) {
          final String code = capture.barcodes.first.displayValue ?? '';
          if (code.isNotEmpty) {
            _processScannedCode(code);
          }
        }
      },
    );
  }

  void _processScannedCode(String code) {
    _scanResetTimer?.cancel();

    if (_lastScannedCode == code) {
      _consecutiveScanCount++;
    } else {
      _lastScannedCode = code;
      _consecutiveScanCount = 1;
    }

    _scanResetTimer = Timer(const Duration(milliseconds: 500), () {
      _consecutiveScanCount = 0;
      _lastScannedCode = null;
    });

    if (_consecutiveScanCount >= _requiredConsecutiveScans) {
      _scanResetTimer?.cancel();
      _screenOpened = true;
      _foundBarcode(code);
    }
  }

  void _foundBarcode(String code) async {
    if (await Vibration.hasVibrator() ?? false) {
      Vibration.vibrate(duration: 200);
    }

    SystemSound.play(SystemSoundType.click);

    if (mounted) {
      Navigator.of(context).pop(code);
    }
  }

  Future<void> _toggleTorch() async {
    setState(() {
      _torchEnabled = !_torchEnabled;
    });
    await cameraController.toggleTorch();
  }

  Future<void> _switchCamera() async {
    setState(() {
      _cameraFacing = _cameraFacing == CameraFacing.back
          ? CameraFacing.front
          : CameraFacing.back;
    });
    await cameraController.switchCamera();
  }

  String get _titleText => _currentLanguageFlag == 2
      ? "バーコードスキャン"
      : "Scan Barcode";

  String get _positionBarcodeText => _currentLanguageFlag == 2
      ? "バーコードをフレーム内に配置してスキャンしてください"
      : "Position the barcode within the frame to scan";

  String get _flashOnTooltip => _currentLanguageFlag == 2
      ? "フラッシュオン"
      : "Flash on";

  String get _flashOffTooltip => _currentLanguageFlag == 2
      ? "フラッシュオフ"
      : "Flash off";

  String get _frontCameraTooltip => _currentLanguageFlag == 2
      ? "フロントカメラ"
      : "Front camera";

  String get _rearCameraTooltip => _currentLanguageFlag == 2
      ? "リアカメラ"
      : "Rear camera";

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
          tooltip: _currentLanguageFlag == 2 ? "戻る" : "Back",
        ),
        title: Text(
          _titleText,
          style: TextStyle(
            color: Colors.white,
            fontSize: _currentLanguageFlag == 2 ? 18.0 : 20.0,
          ),
        ),
      ),
      body: Stack(
        children: [
          MobileScanner(
            controller: cameraController,
            fit: BoxFit.cover,
          ),
          CustomScannerOverlay(
            borderColor: Colors.red,
            borderRadius: 10,
            borderLength: 30,
            borderWidth: 10,
            cutOutSize: 300,
          ),
          Positioned(
            bottom: 100,
            left: 0,
            right: 0,
            child: Container(
              padding: const EdgeInsets.all(16),
              child: Text(
                _positionBarcodeText,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ),
          // Positioned torch and camera switch buttons at the bottom
          Positioned(
            bottom: 40,
            left: 0,
            right: 0,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Torch button
                Container(
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.5),
                    shape: BoxShape.circle,
                  ),
                  child: IconButton(
                    icon: Icon(
                      _torchEnabled ? Icons.flash_on : Icons.flash_off,
                      color: Colors.white,
                      size: 32,
                    ),
                    onPressed: _toggleTorch,
                    tooltip: _torchEnabled ? _flashOffTooltip : _flashOnTooltip,
                  ),
                ),
                SizedBox(width: 40),
                // Camera switch button
                Container(
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.5),
                    shape: BoxShape.circle,
                  ),
                  child: IconButton(
                    icon: Icon(
                      _cameraFacing == CameraFacing.back
                          ? Icons.camera_front
                          : Icons.camera_rear,
                      color: Colors.white,
                      size: 32,
                    ),
                    onPressed: _switchCamera,
                    tooltip: _cameraFacing == CameraFacing.back
                        ? _frontCameraTooltip
                        : _rearCameraTooltip,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class CustomScannerOverlay extends StatelessWidget {
  final Color borderColor;
  final double borderWidth;
  final double borderRadius;
  final double borderLength;
  final double cutOutSize;

  const CustomScannerOverlay({
    this.borderColor = Colors.red,
    this.borderWidth = 3.0,
    this.borderRadius = 0,
    this.borderLength = 40,
    this.cutOutSize = 250,
    Key? key,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final double width = constraints.maxWidth;
        final double height = constraints.maxHeight;
        final double borderWidthSize = width / 2;
        final double borderOffset = borderWidth / 2;
        final double _borderLength = borderLength > cutOutSize / 2 + borderWidth * 2
            ? borderWidthSize / 2
            : borderLength;
        final double _cutOutSize = cutOutSize < width ? cutOutSize : width - borderOffset;

        return Stack(
          children: [
            Container(
              color: Colors.black.withOpacity(0.5),
            ),
            Center(
              child: Container(
                width: _cutOutSize,
                height: _cutOutSize,
                decoration: BoxDecoration(
                  border: Border.all(
                    color: Colors.transparent,
                    width: borderWidth,
                  ),
                  borderRadius: BorderRadius.circular(borderRadius),
                ),
              ),
            ),
            Positioned(
              top: height / 2 - _cutOutSize / 2 - borderOffset,
              left: width / 2 - _cutOutSize / 2 - borderOffset,
              child: CustomPaint(
                size: Size(_borderLength + borderWidth, _borderLength + borderWidth),
                painter: CornerPainter(
                  borderColor: borderColor,
                  borderWidth: borderWidth,
                  cornerSide: CornerSide.topLeft,
                ),
              ),
            ),
            Positioned(
              top: height / 2 - _cutOutSize / 2 - borderOffset,
              left: width / 2 + _cutOutSize / 2 - _borderLength - borderOffset,
              child: CustomPaint(
                size: Size(_borderLength + borderWidth, _borderLength + borderWidth),
                painter: CornerPainter(
                  borderColor: borderColor,
                  borderWidth: borderWidth,
                  cornerSide: CornerSide.topRight,
                ),
              ),
            ),
            Positioned(
              top: height / 2 + _cutOutSize / 2 - _borderLength - borderOffset,
              left: width / 2 - _cutOutSize / 2 - borderOffset,
              child: CustomPaint(
                size: Size(_borderLength + borderWidth, _borderLength + borderWidth),
                painter: CornerPainter(
                  borderColor: borderColor,
                  borderWidth: borderWidth,
                  cornerSide: CornerSide.bottomLeft,
                ),
              ),
            ),
            Positioned(
              top: height / 2 + _cutOutSize / 2 - _borderLength - borderOffset,
              left: width / 2 + _cutOutSize / 2 - _borderLength - borderOffset,
              child: CustomPaint(
                size: Size(_borderLength + borderWidth, _borderLength + borderWidth),
                painter: CornerPainter(
                  borderColor: borderColor,
                  borderWidth: borderWidth,
                  cornerSide: CornerSide.bottomRight,
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

enum CornerSide { topLeft, topRight, bottomLeft, bottomRight }

class CornerPainter extends CustomPainter {
  final Color borderColor;
  final double borderWidth;
  final CornerSide cornerSide;

  CornerPainter({
    required this.borderColor,
    required this.borderWidth,
    required this.cornerSide,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()
      ..color = borderColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = borderWidth;

    final Path path = Path();

    switch (cornerSide) {
      case CornerSide.topLeft:
        path.moveTo(0, size.height);
        path.lineTo(0, borderWidth);
        path.quadraticBezierTo(0, 0, borderWidth, 0);
        path.lineTo(size.width, 0);
        break;
      case CornerSide.topRight:
        path.moveTo(0, 0);
        path.lineTo(size.width - borderWidth, 0);
        path.quadraticBezierTo(size.width, 0, size.width, borderWidth);
        path.lineTo(size.width, size.height);
        break;
      case CornerSide.bottomLeft:
        path.moveTo(0, 0);
        path.lineTo(0, size.height - borderWidth);
        path.quadraticBezierTo(0, size.height, borderWidth, size.height);
        path.lineTo(size.width, size.height);
        break;
      case CornerSide.bottomRight:
        path.moveTo(size.width, 0);
        path.lineTo(size.width, size.height - borderWidth);
        path.quadraticBezierTo(size.width, size.height, size.width - borderWidth, size.height);
        path.lineTo(0, size.height);
        break;
    }

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) => false;
}