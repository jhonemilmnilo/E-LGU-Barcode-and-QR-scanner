import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

class ScannerScreen extends StatefulWidget {
  const ScannerScreen({super.key});

  @override
  State<ScannerScreen> createState() => _ScannerScreenState();
}

class _ScannerScreenState extends State<ScannerScreen> with SingleTickerProviderStateMixin {
  final MobileScannerController _scannerController = MobileScannerController(
    detectionSpeed: DetectionSpeed.normal,
    facing: CameraFacing.back,
    torchEnabled: false,
  );

  bool _isProcessing = false;
  bool _isFlashOn = false;
  bool _isCameraReady = false;

  late AnimationController _animationController;
  late Animation<double> _laserAnimation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat(reverse: true);

    _laserAnimation = Tween<double>(begin: 0.05, end: 0.95).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeInOut),
    );

    // Preload buffer: camera hardware initialization delay
    Future.delayed(const Duration(milliseconds: 550), () {
      if (mounted) {
        setState(() => _isCameraReady = true);
      }
    });
  }

  @override
  void dispose() {
    _animationController.dispose();
    _scannerController.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_isProcessing) return;

    final List<Barcode> barcodes = capture.barcodes;
    if (barcodes.isEmpty) return;

    final String? rawValue = barcodes.first.rawValue;
    if (rawValue == null || rawValue.trim().isEmpty) return;

    final code = rawValue.trim();

    setState(() => _isProcessing = true);
    HapticFeedback.mediumImpact();

    // Immediately pop back to HomeScreen with the scanned code
    Navigator.pop(context, code);
  }

  @override
  Widget build(BuildContext context) {
    const double cutOutSize = 260.0;

    return Scaffold(
      backgroundColor: Colors.black,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: Colors.white,
        systemOverlayStyle: SystemUiOverlayStyle.light,
        leading: Container(
          margin: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.4),
            shape: BoxShape.circle,
          ),
          child: IconButton(
            icon: const Icon(Icons.arrow_back_rounded, size: 20),
            onPressed: () => Navigator.pop(context),
            tooltip: 'Back',
          ),
        ),
        title: const Text(
          'Scan QR Ticket',
          style: TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 17,
            letterSpacing: 0.3,
            color: Colors.white,
          ),
        ),
        centerTitle: true,
        actions: [
          Container(
            margin: const EdgeInsets.only(right: 12),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.4),
              shape: BoxShape.circle,
            ),
            child: IconButton(
              icon: Icon(
                _isFlashOn ? Icons.flash_on_rounded : Icons.flash_off_rounded,
                color: _isFlashOn ? Colors.amber : Colors.white,
                size: 20,
              ),
              onPressed: () async {
                await _scannerController.toggleTorch();
                setState(() => _isFlashOn = !_isFlashOn);
              },
              tooltip: 'Toggle Flash',
            ),
          ),
        ],
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          // 1. Live Camera Stream
          MobileScanner(
            controller: _scannerController,
            onDetect: _onDetect,
          ),

          // 2. Preload Shimmer Placeholder (fades out once camera hardware is warm)
          AnimatedOpacity(
            opacity: _isCameraReady ? 0.0 : 1.0,
            duration: const Duration(milliseconds: 300),
            child: IgnorePointer(
              ignoring: _isCameraReady,
              child: Container(
                color: const Color(0xFF0F172A),
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 70,
                        height: 70,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
                        ),
                        child: const CircularProgressIndicator(
                          strokeWidth: 2.5,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 18),
                      const Text(
                        'Starting Scanner Camera...',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.2,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Calibrating optical sensor',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.5),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),

          // 3. Darkened Semi-Transparent Vignette Mask with Clear Cutout
          if (_isCameraReady)
            ColorFiltered(
              colorFilter: ColorFilter.mode(
                Colors.black.withValues(alpha: 0.65),
                BlendMode.srcOut,
              ),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Container(
                    decoration: const BoxDecoration(
                      color: Colors.black,
                      backgroundBlendMode: BlendMode.dstOut,
                    ),
                  ),
                  Center(
                    child: Container(
                      width: cutOutSize,
                      height: cutOutSize,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20),
                      ),
                    ),
                  ),
                ],
              ),
            ),

          // 4. Viewfinder Frame: 4 Laser Corner Accents + Scanning Laser Beam
          if (_isCameraReady)
            Center(
              child: SizedBox(
                width: cutOutSize,
                height: cutOutSize,
                child: Stack(
                  children: [
                    // Viewfinder Custom Corner Borders
                    CustomPaint(
                      size: const Size(cutOutSize, cutOutSize),
                      painter: _ViewfinderCornerPainter(
                        cornerColor: _isProcessing ? Colors.greenAccent : const Color(0xFF38BDF8),
                      ),
                    ),

                    // Laser Scanning Bar
                    AnimatedBuilder(
                      animation: _laserAnimation,
                      builder: (context, child) {
                        return Positioned(
                          top: _laserAnimation.value * (cutOutSize - 20),
                          left: 12,
                          right: 12,
                          child: Container(
                            height: 3,
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  Colors.transparent,
                                  _isProcessing ? Colors.greenAccent : const Color(0xFF38BDF8),
                                  _isProcessing ? Colors.white : Colors.cyanAccent,
                                  _isProcessing ? Colors.greenAccent : const Color(0xFF38BDF8),
                                  Colors.transparent,
                                ],
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: (_isProcessing ? Colors.greenAccent : const Color(0xFF38BDF8)).withValues(alpha: 0.7),
                                  blurRadius: 10,
                                  spreadRadius: 2,
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),

          // 5. Instruction Pill at Bottom
          if (_isCameraReady)
            Positioned(
              bottom: 48,
              left: 20,
              right: 20,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.75),
                    borderRadius: BorderRadius.circular(30),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.3),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _isProcessing ? Icons.check_circle_rounded : Icons.qr_code_scanner_rounded,
                        color: _isProcessing ? Colors.greenAccent : const Color(0xFF38BDF8),
                        size: 18,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _isProcessing ? 'Verifying Ticket...' : 'Align QR code inside the frame',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.2,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

          // 6. Processing Fullscreen Dimmer (when scanned)
          if (_isProcessing)
            Container(
              color: Colors.black.withValues(alpha: 0.4),
              child: const Center(
                child: CircularProgressIndicator(
                  strokeWidth: 3,
                  color: Colors.greenAccent,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Custom Painter that draws high-tech 4-corner brackets for the viewfinder HUD
class _ViewfinderCornerPainter extends CustomPainter {
  final Color cornerColor;
  final double cornerLength;
  final double strokeWidth;
  final double borderRadius;

  _ViewfinderCornerPainter({
    required this.cornerColor,
    this.cornerLength = 28.0,
    this.strokeWidth = 3.5,
    this.borderRadius = 16.0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = cornerColor
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final w = size.width;
    final h = size.height;

    // Top-Left Corner
    final tlPath = Path()
      ..moveTo(0, cornerLength)
      ..lineTo(0, borderRadius)
      ..quadraticBezierTo(0, 0, borderRadius, 0)
      ..lineTo(cornerLength, 0);
    canvas.drawPath(tlPath, paint);

    // Top-Right Corner
    final trPath = Path()
      ..moveTo(w - cornerLength, 0)
      ..lineTo(w - borderRadius, 0)
      ..quadraticBezierTo(w, 0, w, borderRadius)
      ..lineTo(w, cornerLength);
    canvas.drawPath(trPath, paint);

    // Bottom-Left Corner
    final blPath = Path()
      ..moveTo(0, h - cornerLength)
      ..lineTo(0, h - borderRadius)
      ..quadraticBezierTo(0, h, borderRadius, h)
      ..lineTo(cornerLength, h);
    canvas.drawPath(blPath, paint);

    // Bottom-Right Corner
    final brPath = Path()
      ..moveTo(w - cornerLength, h)
      ..lineTo(w - borderRadius, h)
      ..quadraticBezierTo(w, h, w, h - borderRadius)
      ..lineTo(w, h - cornerLength);
    canvas.drawPath(brPath, paint);
  }

  @override
  bool shouldRepaint(covariant _ViewfinderCornerPainter oldDelegate) {
    return oldDelegate.cornerColor != cornerColor;
  }
}
