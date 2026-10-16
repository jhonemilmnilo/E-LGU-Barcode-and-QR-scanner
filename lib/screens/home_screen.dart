import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../services/api_service.dart';
import 'login_screen.dart';
import 'scanner_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final TextEditingController _manualQueueController = TextEditingController();
  bool _isManualCheckingIn = false;
  int _currentTabIndex = 0;
  bool _isLoading = true;
  

  // Theming & Branding (Dynamic from systemSettings)
  Color _themeColor = const Color(0xFF1E3A8A);
  String? _siteLogo;
  String _municipalityName = "Municipal Front Desk";

  // Dashboard Metrics
  int _totalToday = 0;
  int _inQueue = 0;
  int _served = 0;
  List<dynamic> _activeQueue = [];

  // Live Clock
  late Timer _clockTimer;
  DateTime _currentTime = DateTime.now();
  Timer? _pollingTimer;

  @override
  void initState() {
    super.initState();
    _loadInitialBranding();
    _clockTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        setState(() => _currentTime = DateTime.now());
      }
    });

    _fetchDashboardData();
    // Periodic poll every 15s to keep active queue fresh
    _pollingTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      _fetchDashboardData(silent: true);
    });
  }

  Future<void> _loadInitialBranding() async {
    // 1. Instant cached branding
    final cachedTheme = await ApiService.getCachedThemeColor();
    final cachedLogo = await ApiService.getCachedLogo();
    final cachedMuni = await ApiService.getCachedMunicipalityName();

    if (mounted) {
      setState(() {
        if (cachedTheme != null && cachedTheme.isNotEmpty) {
          _themeColor = _hexToColor(cachedTheme);
        }
        if (cachedLogo != null && cachedLogo.isNotEmpty) {
          _siteLogo = cachedLogo;
        }
        if (cachedMuni != null && cachedMuni.isNotEmpty) {
          _municipalityName = cachedMuni;
        }
      });
    }

    // 2. Fetch fresh dynamic settings (with Supabase fallback)
    final fresh = await ApiService.fetchPublicSettings();
    if (mounted && fresh.isNotEmpty) {
      setState(() {
        if (fresh['themeColor'] != null) {
          _themeColor = _hexToColor(fresh['themeColor']);
        }
        if (fresh['siteLogo'] != null && (fresh['siteLogo'] as String).isNotEmpty) {
          _siteLogo = fresh['siteLogo'];
        }
        if (fresh['municipalityName'] != null) {
          _municipalityName = fresh['municipalityName'];
        }
      });
    }
  }

  @override
  void dispose() {
    _manualQueueController.dispose();
    _clockTimer.cancel();
    _pollingTimer?.cancel();
    super.dispose();
  }

  Color _hexToColor(String? hexString) {
    if (hexString == null || hexString.isEmpty) return const Color(0xFF1E3A8A);
    final buffer = StringBuffer();
    if (hexString.length == 6 || hexString.length == 7) buffer.write('ff');
    buffer.write(hexString.replaceFirst('#', ''));
    try {
      return Color(int.parse(buffer.toString(), radix: 16));
    } catch (_) {
      return const Color(0xFF1E3A8A);
    }
  }

  Future<void> _fetchDashboardData({bool silent = false}) async {
    if (!silent) setState(() => _isLoading = true);

    final res = await ApiService.getDashboard();

    if (!mounted) return;

    if (res['success'] == true) {
      setState(() {
        _isLoading = false;
        
        if (res['themeColor'] != null) {
          _themeColor = _hexToColor(res['themeColor']);
        }
        if (res['siteLogo'] != null && (res['siteLogo'] as String).isNotEmpty) {
          _siteLogo = res['siteLogo'];
        }
        if (res['municipalityName'] != null) {
          _municipalityName = res['municipalityName'];
        }

        final stats = res['stats'] ?? {};
        _totalToday = stats['totalToday'] ?? 0;
        _inQueue = stats['inQueue'] ?? 0;
        _served = stats['served'] ?? 0;
        _activeQueue = res['activeQueue'] ?? [];
      });
    } else {
      if (!silent) {
        setState(() {
          _isLoading = false;
          
        });
      }
    }
  }

  

  Future<void> _openScanner() async {
    final scannedCode = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => const ScannerScreen()),
    );
    if (scannedCode != null && scannedCode.isNotEmpty) {
      _processTicketConfirmation(scannedCode);
    } else {
      _fetchDashboardData(silent: true);
    }
  }

  Future<void> _handleManualCheckIn() async {
    final code = _manualQueueController.text.trim();
    if (code.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter a queue number or ticket code'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }
    FocusScope.of(context).unfocus();
    _processTicketConfirmation(code);
  }

  Future<void> _processTicketConfirmation(String code) async {
    // Show loading indicator
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(
        child: CircularProgressIndicator(color: Colors.white),
      ),
    );

    final infoRes = await ApiService.getTicketInfo(code);

    if (!mounted) return;
    Navigator.pop(context); // Close loading dialog

    if (infoRes['success'] != true) {
      _showResultDialog(
        code: code,
        result: {
          'success': false,
          'error': infoRes['error'] ?? 'Ticket not found or invalid.',
        },
      );
      return;
    }

    final ticket = infoRes;
    _showConfirmationModal(code: code, ticket: ticket);
  }

  void _showConfirmationModal({required String code, required Map<String, dynamic> ticket}) {
    bool isPriority = ticket['isPriority'] == true || ticket['isSenior'] == true || ticket['isPWD'] == true;
    final bool isSenior = ticket['isSenior'] == true;
    final bool isPWD = ticket['isPWD'] == true;
    String priorityReason = 'Senior / PWD Priority';
    if (isSenior && isPWD) {
      priorityReason = 'Senior Citizen & PWD';
    } else if (isSenior) {
      priorityReason = 'Senior Citizen';
    } else if (isPWD) {
      priorityReason = 'PWD';
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 48,
                      height: 5,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade300,
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  
                  // Header
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Verify Citizen Ticket',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w900,
                              color: Color(0xFF0F172A),
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            ticket['serviceCategory'] ?? 'Service Request',
                            style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                          ),
                        ],
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: const Color(0xFFEFF6FF),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          ticket['queueNumber'] ?? code,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: _themeColor,
                            fontFamily: 'monospace',
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Resident & Ticket Information Card
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.person_rounded, size: 20, color: Color(0xFF475569)),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                ticket['applicantName'] ?? 'Citizen Applicant',
                                style: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF0F172A),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        const Divider(height: 1, color: Color(0xFFE2E8F0)),
                        const SizedBox(height: 10),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('Service:', style: TextStyle(fontSize: 12, color: Color(0xFF64748B))),
                            Flexible(
                              child: Text(
                                ticket['serviceName'] ?? 'Service',
                                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF0F172A)),
                                textAlign: TextAlign.right,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('Barangay:', style: TextStyle(fontSize: 12, color: Color(0xFF64748B))),
                            Text(
                              ticket['barangay'] ?? 'N/A',
                              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF0F172A)),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('Slot:', style: TextStyle(fontSize: 12, color: Color(0xFF64748B))),
                            Text(
                              ticket['appointmentSlot'] ?? 'Regular',
                              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF0F172A)),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Priority Lane Toggle Switch (Auto-toggled if Senior/PWD)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: isPriority ? const Color(0xFFFEF3C7) : const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: isPriority ? const Color(0xFFF59E0B) : const Color(0xFFCBD5E1),
                        width: isPriority ? 1.5 : 1,
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.accessible_forward_rounded,
                          color: isPriority ? const Color(0xFFD97706) : const Color(0xFF64748B),
                          size: 24,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Priority Lane (Senior / PWD)',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                  color: isPriority ? const Color(0xFF92400E) : const Color(0xFF1E293B),
                                ),
                              ),
                              Text(
                                isPriority ? 'Auto-detected: $priorityReason' : 'Regular Lane',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: isPriority ? FontWeight.w600 : FontWeight.normal,
                                  color: isPriority ? const Color(0xFFB45309) : const Color(0xFF64748B),
                                ),
                              ),
                            ],
                          ),
                        ),
                        Switch(
                          value: isPriority,
                          activeColor: const Color(0xFFD97706),
                          onChanged: (val) {
                            setModalState(() {
                              isPriority = val;
                            });
                          },
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Actions
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.pop(ctx),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                            side: BorderSide(color: Colors.grey.shade300),
                          ),
                          child: const Text('Cancel', style: TextStyle(color: Color(0xFF64748B), fontWeight: FontWeight.bold)),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        flex: 2,
                        child: ElevatedButton.icon(
                          onPressed: () async {
                            Navigator.pop(ctx); // Close modal
                            setState(() => _isManualCheckingIn = true);

                            final res = await ApiService.checkIn(
                              ticketOrQueueNumber: code,
                              isPriority: isPriority,
                            );

                            if (!mounted) return;
                            setState(() => _isManualCheckingIn = false);
                            _showResultDialog(code: code, result: res);
                          },
                          icon: const Icon(Icons.check_circle_rounded, size: 20),
                          label: const Text('Confirm & Queue', style: TextStyle(fontWeight: FontWeight.bold)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _themeColor,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                            elevation: 0,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                ],
              ),
            );
          },
        );
      },
    );
  }


  
  void _showResultDialog({required String code, required Map<String, dynamic> result}) {
    final bool isSuccess = result['success'] == true;
    final ticketData = result['ticket'];

    if (isSuccess) {
      _manualQueueController.clear();
      _fetchDashboardData(silent: true);
    }

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
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF0F172A),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Done', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                ),
              ),
              const SizedBox(height: 12),
            ],
          ),
        );
      },
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: _themeColor,
      foregroundColor: Colors.white,
      elevation: 2,
      shadowColor: Colors.black26,
      toolbarHeight: 70,
      titleSpacing: 16,
      automaticallyImplyLeading: false,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(22)),
      ),
      title: Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Row(
          children: [
            // Municipality Seal Logo
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.15),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white.withValues(alpha: 0.3), width: 1.5),
              ),
              child: ClipOval(
                child: _siteLogo != null && _siteLogo!.isNotEmpty
                    ? Image.network(
                        _siteLogo!.startsWith('http')
                            ? _siteLogo!
                            : '${ApiService.defaultBaseUrl}$_siteLogo',
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) => const Icon(
                          Icons.account_balance_rounded,
                          color: Colors.white,
                          size: 22,
                        ),
                      )
                    : const Icon(
                        Icons.account_balance_rounded,
                        color: Colors.white,
                        size: 22,
                      ),
              ),
            ),
            const SizedBox(width: 12),
            // Titles
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _municipalityName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.2,
                    ),
                  ),
                  Text(
                    'Kiosk Check-In Terminal',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.85),
                      fontSize: 11.5,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        Padding(
          padding: const EdgeInsets.only(right: 12, top: 4),
          child: IconButton(
            onPressed: () {
              _fetchDashboardData();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Dashboard refreshed'),
                  duration: Duration(seconds: 1),
                  behavior: SnackBarBehavior.floating,
                ),
              );
            },
            icon: Container(
              padding: const EdgeInsets.all(7),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.18),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.refresh_rounded, color: Colors.white, size: 20),
            ),
            tooltip: 'Refresh',
          ),
        ),
      ],
    );
  }

  Widget _buildDateTimeBanner() {
    final dateFormat = DateFormat('EEEE, MMM d, yyyy');
    final timeFormat = DateFormat('h:mm a');

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 18),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Icon(Icons.calendar_today_rounded, size: 14, color: _themeColor),
              const SizedBox(width: 6),
              Text(
                dateFormat.format(_currentTime),
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF334155),
                ),
              ),
            ],
          ),
          Row(
            children: [
              Container(
                width: 6,
                height: 6,
                decoration: const BoxDecoration(
                  color: Color(0xFF16A34A),
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                timeFormat.format(_currentTime),
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF0F172A),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildScanHeroCard() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 18),
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const Text(
            "Scan Applicant's QR Code",
            style: TextStyle(
              fontSize: 19,
              fontWeight: FontWeight.w800,
              color: Color(0xFF0F172A),
              letterSpacing: -0.3,
            ),
          ),
          const SizedBox(height: 8),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 8),
            child: Text(
              "Scan ticket QR code or enter queue number to verify.",
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12.5,
                color: Color(0xFF64748B),
                height: 1.4,
              ),
            ),
          ),
          const SizedBox(height: 14),
          // Tap to Scan Button
          SizedBox(
            width: double.infinity,
            height: 46,
            child: ElevatedButton.icon(
              onPressed: _openScanner,
              icon: const Icon(Icons.qr_code_scanner_rounded, size: 22),
              label: const Text(
                'Tap to Scan QR Code',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: _themeColor,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                elevation: 0,
              ),
            ),
          ),
          const SizedBox(height: 12),
          // Divider
          Row(
            children: [
              Expanded(child: Divider(color: Colors.grey.shade200, thickness: 1)),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Text(
                  'OR TYPE QUEUE NUMBER',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    color: Colors.grey.shade400,
                    letterSpacing: 0.8,
                  ),
                ),
              ),
              Expanded(child: Divider(color: Colors.grey.shade200, thickness: 1)),
            ],
          ),
          const SizedBox(height: 12),
          // Manual Queue Number Input + Check Button
          Row(
            children: [
              Expanded(
                child: Container(
                  height: 46,
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: TextField(
                    controller: _manualQueueController,
                    textCapitalization: TextCapitalization.characters,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF0F172A),
                      letterSpacing: 0.5,
                    ),
                    decoration: const InputDecoration(
                      hintText: "Enter Queue / Ticket No.",
                      hintStyle: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.normal,
                        color: Color(0xFF94A3B8),
                      ),
                      prefixIcon: Icon(Icons.pin_outlined, color: Color(0xFF64748B), size: 20),
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.symmetric(vertical: 14, horizontal: 12),
                    ),
                    onSubmitted: (_) => _handleManualCheckIn(),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              // Check Button
              SizedBox(
                height: 46,
                width: 50,
                child: ElevatedButton(
                  onPressed: _isManualCheckingIn ? null : _handleManualCheckIn,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF16A34A),
                    foregroundColor: Colors.white,
                    padding: EdgeInsets.zero,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    elevation: 0,
                  ),
                  child: _isManualCheckingIn
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.check_rounded, size: 26),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMetricsCard() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 18),
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFF1F5F9)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildMetricColumn(
            icon: Icons.people_alt_rounded,
            iconColor: const Color(0xFF2563EB),
            iconBg: const Color(0xFFEFF6FF),
            count: _totalToday.toString(),
            label: 'Total Today',
          ),
          Container(width: 1, height: 44, color: const Color(0xFFF1F5F9)),
          _buildMetricColumn(
            icon: Icons.access_time_filled_rounded,
            iconColor: const Color(0xFF6366F1),
            iconBg: const Color(0xFFEEF2FF),
            count: _inQueue.toString(),
            label: 'In Queue',
          ),
          Container(width: 1, height: 44, color: const Color(0xFFF1F5F9)),
          _buildMetricColumn(
            icon: Icons.check_circle_rounded,
            iconColor: const Color(0xFF16A34A),
            iconBg: const Color(0xFFDCFCE7),
            count: _served.toString(),
            label: 'Served',
          ),
        ],
      ),
    );
  }

  Widget _buildMetricColumn({
    required IconData icon,
    required Color iconColor,
    required Color iconBg,
    required String count,
    required String label,
  }) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(color: iconBg, shape: BoxShape.circle),
          child: Icon(icon, color: iconColor, size: 16),
        ),
        const SizedBox(height: 8),
        Text(
          count,
          style: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w900,
            color: Color(0xFF0F172A),
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: const TextStyle(fontSize: 11, color: Color(0xFF64748B), fontWeight: FontWeight.w500),
        ),
      ],
    );
  }

  Widget _buildActiveQueueSection() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Active Queue',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF0F172A),
                ),
              ),
              TextButton(
                onPressed: () {
                  setState(() => _currentTabIndex = 1);
                },
                child: Text(
                  'View All',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: _themeColor,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (_activeQueue.isEmpty)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 16),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: const Column(
                children: [
                  Icon(Icons.checklist_rounded, color: Color(0xFF94A3B8), size: 36),
                  SizedBox(height: 8),
                  Text(
                    'No active queue right now',
                    style: TextStyle(fontSize: 13, color: Color(0xFF64748B), fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            )
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _activeQueue.length > 4 ? 4 : _activeQueue.length,
              separatorBuilder: (_, _) => const SizedBox(height: 6),
              itemBuilder: (context, index) {
                final item = _activeQueue[index];
                final isNowServing = item['status'] == 'Now Serving';

                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFF1F5F9)),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.015),
                        blurRadius: 4,
                        offset: const Offset(0, 1),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      // Compact Badge Pill
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                        decoration: BoxDecoration(
                          color: isNowServing
                              ? const Color(0xFFDCFCE7)
                              : _themeColor.withValues(alpha: 0.09),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          item['queueNumber'] ?? 'N/A',
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0.2,
                            color: isNowServing ? const Color(0xFF16A34A) : _themeColor,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      // Service / Department
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              item['serviceName'] ?? 'Municipal Service',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF0F172A),
                              ),
                            ),
                            Text(
                              item['department'] ?? 'General',
                              style: const TextStyle(
                                fontSize: 11,
                                color: Color(0xFF64748B),
                              ),
                            ),
                          ],
                        ),
                      ),
                      // Compact Status Pill
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
                        decoration: BoxDecoration(
                          color: isNowServing
                              ? const Color(0xFFDCFCE7)
                              : const Color(0xFFEFF6FF),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          item['status'] ?? 'Waiting',
                          style: TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w700,
                            color: isNowServing
                                ? const Color(0xFF16A34A)
                                : const Color(0xFF2563EB),
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return Center(
        child: CircularProgressIndicator(color: _themeColor),
      );
    }

    if (_currentTabIndex == 0) {
      return RefreshIndicator(
        onRefresh: () => _fetchDashboardData(),
        color: _themeColor,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: Column(
            children: [
              const SizedBox(height: 12),
              _buildDateTimeBanner(),
              const SizedBox(height: 10),
              _buildScanHeroCard(),
              const SizedBox(height: 10),
              _buildMetricsCard(),
              const SizedBox(height: 10),
              _buildActiveQueueSection(),
              const SizedBox(height: 24),
            ],
          ),
        ),
      );
    } else if (_currentTabIndex == 1) {
      // Full Queue View
      return Scaffold(
        appBar: AppBar(
          title: const Text('Live Active Queue', style: TextStyle(fontWeight: FontWeight.bold)),
          backgroundColor: _themeColor,
          foregroundColor: Colors.white,
        ),
        body: RefreshIndicator(
          onRefresh: () => _fetchDashboardData(),
          color: _themeColor,
          child: _activeQueue.isEmpty
              ? const Center(child: Text('No active queue tickets'))
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _activeQueue.length,
                  itemBuilder: (context, index) {
                    final item = _activeQueue[index];
                    return Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: _themeColor.withValues(alpha: 0.1),
                          child: Text(
                            item['queueNumber'] ?? 'Q',
                            style: TextStyle(color: _themeColor, fontWeight: FontWeight.bold, fontSize: 12),
                          ),
                        ),
                        title: Text(item['serviceName'] ?? 'Service', style: const TextStyle(fontWeight: FontWeight.bold)),
                        subtitle: Text(item['department'] ?? 'Dept'),
                        trailing: Text(
                          item['status'] ?? 'Waiting',
                          style: TextStyle(
                            color: item['status'] == 'Now Serving' ? Colors.green : Colors.blue,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    );
                  },
                ),
        ),
      );
    } else {
      // Settings / Profile
      return Scaffold(
        appBar: AppBar(
          title: const Text('Terminal Settings', style: TextStyle(fontWeight: FontWeight.bold)),
          backgroundColor: _themeColor,
          foregroundColor: Colors.white,
        ),
        body: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            ListTile(
              leading: Icon(Icons.sync_rounded, color: _themeColor),
              title: const Text('Force Refresh Dashboard'),
              onTap: () {
                _fetchDashboardData();
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Dashboard refreshed!')));
              },
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.logout_rounded, color: Colors.red),
              title: const Text('Sign Out Terminal', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
              onTap: () async {
                await ApiService.clearAuth();
                if (!mounted) return;
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(builder: (_) => const LoginScreen()),
                );
              },
            ),
          ],
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: _currentTabIndex == 0 ? _buildAppBar() : null,
      body: SafeArea(
        top: _currentTabIndex != 0,
        child: _buildBody(),
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: Colors.grey.shade200, width: 1)),
        ),
        child: BottomNavigationBar(
          currentIndex: _currentTabIndex,
          onTap: (index) {
            setState(() => _currentTabIndex = index);
          },
          selectedItemColor: _themeColor,
          unselectedItemColor: const Color(0xFF94A3B8),
          selectedLabelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11),
          unselectedLabelStyle: const TextStyle(fontSize: 11),
          type: BottomNavigationBarType.fixed,
          backgroundColor: Colors.white,
          elevation: 0,
          items: const [
            BottomNavigationBarItem(
              icon: Icon(Icons.qr_code_scanner_rounded),
              label: 'Scan',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.groups_rounded),
              label: 'Queue',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.history_rounded),
              label: 'History',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.settings_outlined),
              label: 'Settings',
            ),
          ],
        ),
      ),
    );
  }
}


