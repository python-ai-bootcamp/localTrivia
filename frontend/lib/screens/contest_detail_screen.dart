import 'dart:async';
import 'package:flutter/material.dart';
import '../services/api_service.dart';
import 'lobby_screen.dart';

class ContestDetailScreen extends StatefulWidget {
  final String contestId;

  const ContestDetailScreen({super.key, required this.contestId});

  @override
  State<ContestDetailScreen> createState() => _ContestDetailScreenState();
}

class _ContestDetailScreenState extends State<ContestDetailScreen> {
  Map<String, dynamic>? _contest;
  bool _isLoading = false;
  bool _isActionLoading = false;
  String _errorMessage = '';
  Timer? _countdownTimer;
  Duration _timeLeft = Duration.zero;

  @override
  void initState() {
    super.initState();
    _fetchDetails();
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    super.dispose();
  }

  Future<void> _fetchDetails() async {
    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });

    try {
      final details = await ApiService.getContestDetail(widget.contestId);
      setState(() {
        _contest = details;
      });
      _startCountdown();
    } catch (e) {
      setState(() {
        _errorMessage = e.toString();
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _startCountdown() {
    _countdownTimer?.cancel();
    if (_contest == null) return;

    final startEpoch = _contest!['scheduledStartTime'] as int;
    final startDateTime = DateTime.fromMillisecondsSinceEpoch(startEpoch * 1000);
    
    _updateTimeLeft(startDateTime);

    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      _updateTimeLeft(startDateTime);
    });
  }

  void _updateTimeLeft(DateTime startDateTime) {
    final now = DateTime.now();
    final difference = startDateTime.difference(now);
    
    if (difference.isNegative) {
      _countdownTimer?.cancel();
      setState(() {
        _timeLeft = Duration.zero;
      });
    } else {
      setState(() {
        _timeLeft = difference;
      });
    }
  }

  Future<void> _enlist() async {
    setState(() {
      _isActionLoading = true;
    });

    try {
      await ApiService.enlistContest(widget.contestId);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Successfully registered and paid!'),
          backgroundColor: Colors.green,
        ),
      );
      _fetchDetails();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to register: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      setState(() {
        _isActionLoading = false;
      });
    }
  }

  String _formatDuration(Duration d) {
    if (d == Duration.zero) return 'Contest in progress / ended';
    final days = d.inDays;
    final hours = d.inHours.remainder(24).toString().padLeft(2, '0');
    final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');

    if (days > 0) {
      return '$days days, $hours:$minutes:$seconds';
    }
    return '$hours:$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (_errorMessage.isNotEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('Contest Details')),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(_errorMessage, style: const TextStyle(color: Colors.white54)),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _fetchDetails,
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    if (_contest == null) {
      return const Scaffold(
        body: Center(child: Text('No details found')),
      );
    }

    final status = _contest!['status'];
    final fee = _contest!['entryFee'];
    final prizePool = _contest!['prizePool'];
    final contendersCount = _contest!['contendersCount'];
    final startEpoch = _contest!['scheduledStartTime'] as int;
    final startDate = DateTime.fromMillisecondsSinceEpoch(startEpoch * 1000);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Contest Details'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Details Card
            Card(
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _contest!['questionnaireTitle'],
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 24),
                    _buildDetailRow(Icons.payments_outlined, 'Entry Fee', '\$$fee'),
                    _buildDetailRow(Icons.monetization_on_outlined, 'Prize Pool', '\$$prizePool'),
                    _buildDetailRow(Icons.people_outline, 'Registered Players', '$contendersCount'),
                    _buildDetailRow(
                      Icons.calendar_month_outlined,
                      'Start Date',
                      '${startDate.day}/${startDate.month}/${startDate.year} @ ${startDate.hour.toString().padLeft(2, '0')}:${startDate.minute.toString().padLeft(2, '0')}',
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            
            // Countdown Card
            if (status != 'COMPLETED' && status != 'LIVE') ...[
              Card(
                color: theme.colorScheme.surface.withOpacity(0.5),
                child: Padding(
                  padding: const EdgeInsets.all(20.0),
                  child: Column(
                    children: [
                      const Text(
                        'COUNTDOWN TO START',
                        style: TextStyle(color: Colors.white38, fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _formatDuration(_timeLeft),
                        style: TextStyle(
                          color: theme.colorScheme.primary,
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 32),
            ],

            // Action Buttons
            if (status == 'ADDED') ...[
              ElevatedButton(
                onPressed: _isActionLoading ? null : _enlist,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 18),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  backgroundColor: theme.colorScheme.primary,
                  foregroundColor: Colors.white,
                ),
                child: _isActionLoading
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Text(
                        'Enlist & Pay Entry Fee',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
              ),
            ] else if (status == 'ENLISTED') ...[
              ElevatedButton(
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => LobbyScreen(contestId: widget.contestId),
                    ),
                  );
                },
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 18),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                ),
                child: const Text(
                  'Enter Lobby',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
            ] else if (status == 'LIVE') ...[
              ElevatedButton(
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => LobbyScreen(contestId: widget.contestId),
                    ),
                  );
                },
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 18),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  backgroundColor: theme.colorScheme.primary,
                  foregroundColor: Colors.white,
                ),
                child: const Text(
                  'Enter Game Room',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildDetailRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16.0),
      child: Row(
        children: [
          Icon(icon, color: Colors.white38, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: const TextStyle(color: Colors.white38, fontSize: 13)),
                const SizedBox(height: 2),
                Text(value, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
