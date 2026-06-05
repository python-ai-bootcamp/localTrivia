import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../services/api_service.dart';
import 'contest_detail_screen.dart';
import 'profile_screen.dart';
import 'question_screen.dart'; // To handle LIVE taps if user wants to re-enter
import 'lobby_screen.dart';
import 'onboarding_screen.dart';

class ContestsTab extends StatefulWidget {
  const ContestsTab({super.key});

  @override
  State<ContestsTab> createState() => _ContestsTabState();
}

class _ContestsTabState extends State<ContestsTab> {
  List<dynamic> _contests = [];
  bool _isLoading = false;
  String _errorMessage = '';

  @override
  void initState() {
    super.initState();
    _checkClipboard();
    _fetchContests();
  }

  Future<void> _checkClipboard() async {
    try {
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      if (data?.text?.startsWith('TRIVIA:') == true) {
        final contestId = data!.text!.substring(7).trim();
        final qrUrl = '${ApiService.baseUrl}/join?contestId=$contestId';

        await ApiService.addContest(qrUrl);
        await Clipboard.setData(const ClipboardData(text: ''));

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Contest added from your QR scan!'),
              backgroundColor: Colors.green,
            ),
          );
        }
        _fetchContests();
      }
    } catch (e) {
      if (e.toString() == 'unauthorized') {
        await ApiService.logout();
        if (mounted) {
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(builder: (_) => const OnboardingScreen()),
            (route) => false,
          );
        }
      }
    }
  }

  Future<void> _fetchContests() async {
    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });

    try {
      final list = await ApiService.getContests();
      setState(() {
        _contests = list;
      });
    } catch (e) {
      if (e.toString() == 'unauthorized') {
        await ApiService.logout();
        if (mounted) {
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(builder: (_) => const OnboardingScreen()),
            (route) => false,
          );
        }
        return;
      }
      setState(() {
        _errorMessage = e.toString();
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _openScanner() {
    bool isScanned = false;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.black,
      builder: (ctx) => SizedBox(
        height: MediaQuery.of(context).size.height * 0.7,
        child: Column(
          children: [
            AppBar(
              title: const Text('Scan Contest QR Code'),
              leading: IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.pop(ctx),
              ),
              backgroundColor: Colors.transparent,
            ),
            Expanded(
              child: MobileScanner(
                onDetect: (capture) async {
                  if (isScanned) return;
                  final List<Barcode> barcodes = capture.barcodes;
                  for (final barcode in barcodes) {
                    if (barcode.rawValue != null) {
                      isScanned = true;
                      final qrUrl = barcode.rawValue!;
                      Navigator.pop(ctx);
                      
                      setState(() {
                        _isLoading = true;
                      });
                      
                      try {
                        await ApiService.addContest(qrUrl);
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Contest added successfully!'),
                              backgroundColor: Colors.green,
                            ),
                          );
                        }
                        _fetchContests();
                      } catch (e) {
                        if (e.toString() == 'unauthorized') {
                          await ApiService.logout();
                          if (mounted) {
                            Navigator.of(context).pushAndRemoveUntil(
                              MaterialPageRoute(builder: (_) => const OnboardingScreen()),
                              (route) => false,
                            );
                          }
                          return;
                        }
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Failed to add contest: $e'),
                            backgroundColor: Colors.red,
                          ),
                        );
                        setState(() {
                          _isLoading = false;
                        });
                      }
                      break;
                    }
                  }
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'LIVE':
        return const Color(0xFFE53935);
      case 'ENLISTED':
        return const Color(0xFF4CAF50);
      case 'ADDED':
        return const Color(0xFF90A4AE);
      case 'COMPLETED':
        return const Color(0xFF3F51B5);
      case 'MISSED':
      default:
        return const Color(0xFF546E7A);
    }
  }

  String _getStatusLabel(String status) {
    switch (status) {
      case 'LIVE':
        return 'LIVE PLAY';
      case 'ENLISTED':
        return 'REGISTERED';
      case 'ADDED':
        return 'DISCOVERED';
      case 'COMPLETED':
        return 'FINISHED';
      case 'MISSED':
      default:
        return 'MISSED';
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('My Contests'),
        actions: [
          IconButton(
            icon: const Icon(Icons.account_circle_outlined),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const ProfileScreen()),
              ).then((_) => _fetchContests());
            },
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _fetchContests,
        color: theme.colorScheme.primary,
        backgroundColor: theme.cardTheme.color,
        child: _isLoading && _contests.isEmpty
            ? const Center(child: CircularProgressIndicator())
            : _errorMessage.isNotEmpty && _contests.isEmpty
                ? ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    children: [
                      SizedBox(height: MediaQuery.of(context).size.height * 0.3),
                      Center(child: Text(_errorMessage, style: const TextStyle(color: Colors.white60))),
                      const SizedBox(height: 16),
                      Center(
                        child: ElevatedButton(
                          onPressed: _fetchContests,
                          child: const Text('Retry'),
                        ),
                      )
                    ],
                  )
                : _contests.isEmpty
                    ? ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        children: [
                          SizedBox(height: MediaQuery.of(context).size.height * 0.3),
                          const Center(
                            child: Padding(
                              padding: EdgeInsets.symmetric(horizontal: 40.0),
                              child: Text(
                                'No contests added yet.\nScan a contest QR code to get started!',
                                textAlign: TextAlign.center,
                                style: TextStyle(color: Colors.white38, fontSize: 16, height: 1.5),
                              ),
                            ),
                          ),
                        ],
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.all(16.0),
                        itemCount: _contests.length,
                        itemBuilder: (ctx, index) {
                          final contest = _contests[index];
                          final status = contest['status'];
                          final startEpoch = contest['scheduledStartTime'] as int;
                          final startDate = DateTime.fromMillisecondsSinceEpoch(startEpoch * 1000);
                          final fee = contest['entryFee'];

                          return Card(
                            margin: const EdgeInsets.only(bottom: 16.0),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(16),
                              onTap: () {
                                if (status == 'COMPLETED') {
                                  // Open results screen directly
                                  Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (_) => LobbyScreen(contestId: contest['id']),
                                    ),
                                  );
                                } else {
                                  Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (_) => ContestDetailScreen(contestId: contest['id']),
                                    ),
                                  ).then((_) => _fetchContests());
                                }
                              },
                              child: Padding(
                                padding: const EdgeInsets.all(18.0),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Expanded(
                                          child: Text(
                                            contest['questionnaireTitle'],
                                            style: const TextStyle(
                                              fontSize: 18,
                                              fontWeight: FontWeight.bold,
                                              color: Colors.white,
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                          decoration: BoxDecoration(
                                            color: _getStatusColor(status).withOpacity(0.15),
                                            borderRadius: BorderRadius.circular(6),
                                            border: Border.all(color: _getStatusColor(status), width: 1),
                                          ),
                                          child: Text(
                                            _getStatusLabel(status),
                                            style: TextStyle(
                                              color: _getStatusColor(status),
                                              fontSize: 12,
                                              fontWeight: FontWeight.w900,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 12),
                                    Row(
                                      children: [
                                        const Icon(Icons.calendar_month, size: 18, color: Colors.white38),
                                        const SizedBox(width: 8),
                                        Text(
                                          '${startDate.day}/${startDate.month} @ ${startDate.hour.toString().padLeft(2, '0')}:${startDate.minute.toString().padLeft(2, '0')}',
                                          style: const TextStyle(color: Colors.white60, fontSize: 14),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 8),
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Row(
                                          children: [
                                            const Icon(Icons.payments_outlined, size: 18, color: Colors.white38),
                                            const SizedBox(width: 8),
                                            Text(
                                              'Entry Fee: \$$fee',
                                              style: const TextStyle(color: Colors.white60, fontSize: 14),
                                            ),
                                          ],
                                        ),
                                        if (contest['prizePool'] > 0)
                                          Text(
                                            'Pool: \$${contest['prizePool']}',
                                            style: TextStyle(
                                              color: theme.colorScheme.primary,
                                              fontWeight: FontWeight.bold,
                                              fontSize: 14,
                                            ),
                                          ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openScanner,
        icon: const Icon(Icons.qr_code_scanner),
        label: const Text('Scan QR Code'),
        backgroundColor: theme.colorScheme.primary,
        foregroundColor: Colors.white,
      ),
    );
  }
}
