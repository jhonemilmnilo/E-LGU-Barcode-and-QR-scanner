import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../services/api_service.dart';
import 'login_screen.dart';

class ScannerScreen extends StatefulWidget {
  const ScannerScreen({super.key});

  @override
  State<ScannerScreen> createState() => _ScannerScreenState();
}

class _ScannerScreenState extends State<ScannerScreen> {
  final MobileScannerController _scannerController = MobileScannerController(
    detectionSpeed: DetectionSpeed.normal,
    facing: CameraFacing.back,
    torchEnabled: false,
  );

  final TextEditingController _manualInputController = TextEditingController();
  bool _isProcessing = false;
  bool _isFlashOn = false;
  DateTime? _lastScannedTime;
  String? _lastScannedCode;

  @override
  void dispose() {
    _scannerController.dispose();
    _manualInputController.dispose();
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

  Future<void> _handleCheckIn(String code, {bool isPriority = false}) async {
    setState(() {
      _isProcessing = true;
      _lastScannedCode = code;
      _lastScannedTime = DateTime.now();
    });

    // Provide haptic feedback
    HapticFeedback.mediumImpact();

    final result = await ApiService.checkIn(
      ticketOrQueueNumber: code,
      isPriority: isPriority,
    );

    if (!mounted) return;

    _showResultDialog(code: code, result: result);
  }

  void _showResultDialog({required String code, required Map<String, dynamic> result}) {
    final bool isSuccess = result['success'] == true;
    final ticketData = result['ticket'];

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Container(
          padding: const EdgeInsets.all(24),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 48,
                height: 5,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: isSuccess ? const Color(0xFFDCFCE7) : const Color(0xFFFEE2E2),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  isSuccess ? Icons.check_circle_rounded : Icons.cancel_rounded,
                  color: isSuccess ? const Color(0xFF16A34A) : const Color(0xFFDC2626),
                  size: 48,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                isSuccess ? 'CHECK-IN SUCCESSFUL' : 'CHECK-IN REJECTED',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  color: isSuccess ? const Color(0xFF16A34A) : const Color(0xFFDC2626),
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 8),
              if (ticketData != null && ticketData['queueNumber'] != null) ...[
                Text(
                  'Queue: ${ticketData['queueNumber']}',
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF0F172A),
                  ),
                ),
                if (ticketData['serviceName'] != null)
                  Text(
                    '${ticketData['serviceName']}',
                    style: const TextStyle(fontSize: 14, color: Color(0xFF64748B)),
                  ),
                const SizedBox(height: 8),
              ],
              Text(
                isSuccess
                    ? (result['message'] ?? 'Ticket has been queued for calling.')
                    : (result['error'] ?? 'Invalid or expired ticket'),
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  color: isSuccess ? const Color(0xFF334155) : const Color(0xFF991B1B),
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.pop(context);
                    setState(() {
                      _isProcessing = false;
                    });
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: isSuccess ? const Color(0xFF16A34A) : const Color(0xFF0F172A),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text(
                    'Scan Next Ticket',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    ).then((_) {
      if (mounted) {
        setState(() => _isProcessing = false);
      }
    });
  }

  void _showManualInputDialog() {
    _manualInputController.clear();
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('Manual Ticket Entry', style: TextStyle(fontWeight: FontWeight.bold)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Enter the Ticket No, Queue No, or Transaction ID:',
                style: TextStyle(fontSize: 13, color: Colors.black54),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _manualInputController,
                autofocus: true,
                textCapitalization: TextCapitalization.characters,
                decoration: InputDecoration(
                  labelText: 'Ticket / Queue Code',
                  hintText: 'e.g. T-001 or CUID',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  prefixIcon: const Icon(Icons.receipt_long_rounded),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                final code = _manualInputController.text.trim();
                if (code.isNotEmpty) {
                  Navigator.pop(context);
                  _handleCheckIn(code);
                }
              },
              child: const Text('Check In'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _logout() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Sign Out'),
        content: const Text('Are you sure you want to log out of the scanner?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Log Out'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await ApiService.clearAuth();
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const LoginScreen()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text(
          'Frontdesk Scanner',
          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
        ),
        actions: [
          IconButton(
            icon: Icon(_isFlashOn ? Icons.flash_on_rounded : Icons.flash_off_rounded),
            onPressed: () async {
              await _scannerController.toggleTorch();
              setState(() => _isFlashOn = !_isFlashOn);
            },
            tooltip: 'Toggle Flashlight',
          ),
          IconButton(
            icon: const Icon(Icons.keyboard_alt_outlined),
            onPressed: _showManualInputDialog,
            tooltip: 'Manual Entry',
          ),
          IconButton(
            icon: const Icon(Icons.logout_rounded),
            onPressed: _logout,
            tooltip: 'Sign Out',
          ),
        ],
      ),
      body: Stack(
        alignment: Alignment.center,
        children: [
          MobileScanner(
            controller: _scannerController,
            onDetect: _onDetect,
          ),
          // Viewfinder reticle overlay
          Container(
            decoration: BoxDecoration(
              border: Border.all(
                color: _isProcessing ? Colors.amber : Colors.white.withValues(alpha: 0.6),
                width: 2.5,
              ),
              borderRadius: BorderRadius.circular(16),
            ),
            width: 260,
            height: 260,
          ),
          // Helper instructions
          Positioned(
            bottom: 40,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.7),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.center_focus_strong_rounded, color: Colors.white70, size: 18),
                  SizedBox(width: 8),
                  Text(
                    'Point camera at QR Code or Barcode',
                    style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500),
                  ),
                ],
              ),
            ),
          ),
          if (_isProcessing)
            Container(
              color: Colors.black45,
              child: const Center(
                child: CircularProgressIndicator(color: Colors.white),
              ),
            ),
        ],
      ),
    );
  }
}
