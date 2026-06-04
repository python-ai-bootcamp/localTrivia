import 'dart:async';
import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../services/websocket_service.dart';
import 'question_screen.dart';

class LobbyScreen extends StatefulWidget {
  final String contestId;

  const LobbyScreen({super.key, required this.contestId});

  @override
  State<LobbyScreen> createState() => _LobbyScreenState();
}

class _LobbyScreenState extends State<LobbyScreen> {
  WebSocketService? _wsService;
  StreamSubscription? _wsSubscription;
  
  bool _isLoading = true;
  String _errorMessage = '';
  Map<String, dynamic>? _contestDetails;
  
  // Countdown details
  Timer? _lobbyTimer;
  Duration _timeLeft = Duration.zero;

  @override
  void initState() {
    super.initState();
    _initLobby();
  }

  @override
  void dispose() {
    _lobbyTimer?.cancel();
    _wsSubscription?.cancel();
    // Do not close _wsService here if navigating to QuestionScreen,
    // we pass ownership to the QuestionScreen. But if we leave the Lobby, we close it.
    if (mounted) {
      _wsService?.close();
    }
    super.dispose();
  }

  Future<void> _initLobby() async {
    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });

    try {
      final details = await ApiService.getContestDetail(widget.contestId);
      setState(() {
        _contestDetails = details;
      });

      if (details['status'] == 'COMPLETED') {
        setState(() {
          _isLoading = false;
        });
        return; // Just render final results
      }

      // Initialize WebSockets
      _wsService = WebSocketService(contestId: widget.contestId);
      _wsService!.connect();
      
      _wsSubscription = _wsService!.events.listen((msg) {
        final event = msg['event'];
        final data = msg['data'];
        
        if (event == 'CONTEST_STARTED' || event == 'QUESTION_START') {
          _wsSubscription?.cancel(); // Yield control of events to QuestionScreen
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(
              builder: (_) => QuestionScreen(
                contestId: widget.contestId,
                wsService: _wsService!,
                initialEvent: msg,
              ),
            ),
          );
        }
      });

      // Start Countdown for scheduled start
      final startEpoch = details['scheduledStartTime'] as int;
      final startDateTime = DateTime.fromMillisecondsSinceEpoch(startEpoch * 1000);
      _updateTimeLeft(startDateTime);
      _lobbyTimer = Timer.periodic(const Duration(seconds: 1), (t) => _updateTimeLeft(startDateTime));
      
      setState(() {
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = e.toString();
        _isLoading = false;
      });
    }
  }

  void _updateTimeLeft(DateTime startDateTime) {
    final now = DateTime.now();
    final diff = startDateTime.difference(now);
    if (diff.isNegative) {
      _lobbyTimer?.cancel();
      setState(() {
        _timeLeft = Duration.zero;
      });
    } else {
      setState(() {
        _timeLeft = diff;
      });
    }
  }

  String _formatDuration(Duration d) {
    if (d == Duration.zero) return '00:00:00';
    final hours = d.inHours.toString().padLeft(2, '0');
    final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
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
        appBar: AppBar(title: const Text('Game Room')),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(_errorMessage, style: const TextStyle(color: Colors.white54)),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _initLobby,
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    final isCompleted = _contestDetails?['status'] == 'COMPLETED';

    if (isCompleted) {
      return _buildFinalResultsView(theme);
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Countdown Lobby'),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(28.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.hourglass_empty_rounded,
                size: 90,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(height: 24),
              const Text(
                'WAITING FOR START',
                style: TextStyle(
                  color: Colors.white38,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.5,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                _formatDuration(_timeLeft),
                style: TextStyle(
                  color: theme.colorScheme.primary,
                  fontSize: 48,
                  fontWeight: FontWeight.w900,
                  fontFamily: 'monospace',
                ),
              ),
              const SizedBox(height: 32),
              Text(
                _contestDetails?['questionnaireTitle'] ?? 'Trivia Contest',
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              const Text(
                'Keep this screen open. You will be automatically redirected when live play starts.',
                style: TextStyle(color: Colors.white30, fontSize: 13),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 48),
              const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(
                    height: 16,
                    width: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  SizedBox(width: 12),
                  Text(
                    'WebSocket Channel Connected',
                    style: TextStyle(color: Colors.green, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFinalResultsView(ThemeData theme) {
    final List<dynamic> leaderboard = _contestDetails?['finalLeaderboard'] ?? [];
    final contendersCount = _contestDetails?['contendersCount'] ?? 0;
    
    // Find my entry
    final myUsername = ApiService.username;
    final myEntry = leaderboard.firstWhere(
      (e) => e['username'] == myUsername,
      orElse: () => null,
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('Contest Standings'),
        automaticallyImplyLeading: false,
      ),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Top Badge own rank
            if (myEntry != null) ...[
              Card(
                color: theme.colorScheme.primary.withOpacity(0.12),
                child: Padding(
                  padding: const EdgeInsets.all(20.0),
                  child: Row(
                    children: [
                      Icon(Icons.emoji_events_outlined, color: theme.colorScheme.primary, size: 36),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Congratulations, $myUsername!',
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'You placed #${myEntry['rank']} out of $contendersCount players',
                              style: const TextStyle(color: Colors.white70, fontSize: 14),
                            ),
                          ],
                        ),
                      ),
                      Text(
                        '${myEntry['score']} pts',
                        style: TextStyle(
                          color: theme.colorScheme.primary,
                          fontWeight: FontWeight.w900,
                          fontSize: 18,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),
            ],
            
            const Text(
              'LEADERBOARD STANDINGS',
              style: TextStyle(color: Colors.white38, fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1),
            ),
            const SizedBox(height: 10),
            
            // Leaderboard list
            Expanded(
              child: ListView.builder(
                itemCount: leaderboard.length,
                itemBuilder: (ctx, index) {
                  final entry = leaderboard[index];
                  final isMe = entry['username'] == myUsername;
                  final rank = entry['rank'];
                  
                  // Highlight top 3
                  Color rankColor = Colors.white54;
                  if (rank == 1) rankColor = const Color(0xFFFFD700); // Gold
                  if (rank == 2) rankColor = const Color(0xFFC0C0C0); // Silver
                  if (rank == 3) rankColor = const Color(0xFFCD7F32); // Bronze

                  return Container(
                    padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
                    margin: const EdgeInsets.only(bottom: 10),
                    decoration: BoxDecoration(
                      color: isMe ? Colors.white.withOpacity(0.06) : Colors.white.withOpacity(0.02),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isMe ? theme.colorScheme.primary.withOpacity(0.5) : Colors.white10,
                        width: 1,
                      ),
                    ),
                    child: Row(
                      children: [
                        Text(
                          '#$rank',
                          style: TextStyle(
                            color: rankColor,
                            fontWeight: FontWeight.w900,
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Text(
                            entry['username'],
                            style: TextStyle(
                              color: isMe ? theme.colorScheme.primary : Colors.white,
                              fontWeight: isMe ? FontWeight.bold : FontWeight.normal,
                              fontSize: 15,
                            ),
                          ),
                        ),
                        Text(
                          '${entry['score']} pts',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.white70),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                backgroundColor: theme.colorScheme.surface,
              ),
              child: const Text('Back to Contests', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }
}
