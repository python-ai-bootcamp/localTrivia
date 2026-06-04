import 'dart:async';
import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../services/websocket_service.dart';
import 'lobby_screen.dart';

class QuestionScreen extends StatefulWidget {
  final String contestId;
  final WebSocketService wsService;
  final Map<String, dynamic> initialEvent;

  const QuestionScreen({
    super.key,
    required this.contestId,
    required this.wsService,
    required this.initialEvent,
  });

  @override
  State<QuestionScreen> createState() => _QuestionScreenState();
}

class _QuestionScreenState extends State<QuestionScreen> with TickerProviderStateMixin {
  StreamSubscription? _wsSubscription;
  
  // Game states
  int _questionIndex = 0;
  String _questionId = '';
  String _questionText = '';
  List<dynamic> _options = [];
  int _timeLimit = 10;
  int _initialScore = 1000;
  
  // Participant state
  int? _selectedIndex;
  bool _hasAnswered = false;
  bool _isCorrect = false;
  double _scoreEarned = 0.0;
  bool _isTimeout = false;
  
  // Buffer state
  bool _inBuffer = false;
  int _correctOptionIndex = 0;
  List<dynamic> _midLeaderboard = [];
  int _bufferSecondsLeft = 5;
  Timer? _bufferTimer;

  // Timers and Animation Controllers
  DateTime? _questionStartTime;
  AnimationController? _timerController;

  @override
  void initState() {
    super.initState();
    _listenToEvents();
    _handleQuestionStart(widget.initialEvent['data']);
  }

  @override
  void dispose() {
    _wsSubscription?.cancel();
    _bufferTimer?.cancel();
    _timerController?.dispose();
    super.dispose();
  }

  void _listenToEvents() {
    _wsSubscription = widget.wsService.events.listen((msg) {
      final event = msg['event'];
      final data = msg['data'];

      if (event == 'QUESTION_START') {
        _handleQuestionStart(data);
      } else if (event == 'QUESTION_END') {
        _handleQuestionEnd(data);
      } else if (event == 'CONTEST_ENDED') {
        _handleContestEnded(data);
      }
    });
  }

  void _handleQuestionStart(Map<String, dynamic> data) {
    _bufferTimer?.cancel();
    _timerController?.dispose();

    setState(() {
      _questionIndex = data['questionIndex'] ?? 0;
      _questionId = data['questionId'] ?? '';
      _questionText = data['questionText'] ?? '';
      _options = data['options'] ?? [];
      _timeLimit = data['timeLimitSeconds'] ?? 10;
      _initialScore = data['initialScore'] ?? 1000;
      
      _selectedIndex = null;
      _hasAnswered = false;
      _isCorrect = false;
      _scoreEarned = 0.0;
      _isTimeout = false;
      _inBuffer = false;
      
      _questionStartTime = DateTime.now();
    });

    // Start progress timer bar
    _timerController = AnimationController(
      vsync: this,
      duration: Duration(seconds: _timeLimit),
    );
    
    _timerController!.forward(from: 0.0).then((_) {
      if (mounted && !_hasAnswered) {
        _handleTimeout();
      }
    });
  }

  void _handleTimeout() {
    setState(() {
      _hasAnswered = true;
      _isTimeout = true;
      _isCorrect = false;
      _scoreEarned = 0.0;
    });
  }

  Future<void> _submitAnswer(int index) async {
    if (_hasAnswered) return;
    
    final answerTime = DateTime.now();
    final timeTakenMs = answerTime.difference(_questionStartTime!).inMilliseconds;

    setState(() {
      _selectedIndex = index;
      _hasAnswered = true;
    });

    _timerController?.stop();

    try {
      final result = await ApiService.submitAnswer(
        widget.contestId,
        _questionId,
        index,
        timeTakenMs,
      );

      setState(() {
        _isCorrect = result['isCorrect'] ?? false;
        _scoreEarned = (result['score'] as num).toDouble();
      });
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Submission error: $e'), backgroundColor: Colors.red),
      );
    }
  }

  void _handleQuestionEnd(Map<String, dynamic> data) {
    _timerController?.stop();
    
    setState(() {
      _inBuffer = true;
      _correctOptionIndex = data['correctOptionIndex'] ?? 0;
      _midLeaderboard = data['leaderboard'] ?? [];
      _bufferSecondsLeft = 5; 
    });

    _bufferTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        setState(() {
          if (_bufferSecondsLeft > 1) {
            _bufferSecondsLeft--;
          } else {
            _bufferTimer?.cancel();
          }
        });
      }
    });
  }

  void _handleContestEnded(Map<String, dynamic> data) {
    _wsSubscription?.cancel();
    _bufferTimer?.cancel();

    // Route back to LobbyScreen which will fetch final results and display them
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => LobbyScreen(contestId: widget.contestId),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final progress = _timerController != null 
        ? 1.0 - _timerController!.value 
        : 1.0;

    return Scaffold(
      appBar: AppBar(
        title: Text('Question ${_questionIndex + 1}'),
        automaticallyImplyLeading: false,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16.0),
            child: Center(
              child: Text(
                'Worth: $_initialScore pts',
                style: const TextStyle(color: Colors.white38, fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ],
      ),
      body: Stack(
        children: [
          Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Live Progress Timer Bar
                if (_timerController != null && !_inBuffer)
                  AnimatedBuilder(
                    animation: _timerController!,
                    builder: (context, child) {
                      return ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: 1.0 - _timerController!.value,
                          backgroundColor: Colors.white10,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            (1.0 - _timerController!.value) < 0.25 
                                ? theme.colorScheme.error 
                                : theme.colorScheme.primary,
                          ),
                          minHeight: 8,
                        ),
                      );
                    },
                  ),
                const SizedBox(height: 32),
                
                // Question Text
                Text(
                  _questionText,
                  style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, height: 1.4),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 48),
                
                // Options Grid
                Expanded(
                  child: ListView.builder(
                    itemCount: _options.length,
                    itemBuilder: (ctx, index) {
                      final optionText = _options[index];
                      
                      // Compute option background colors based on states
                      Color buttonColor = theme.cardTheme.color!;
                      Color borderColor = const Color(0xFF2C2254);
                      
                      if (_hasAnswered) {
                        if (index == _selectedIndex) {
                          if (_isCorrect) {
                            buttonColor = Colors.green.withOpacity(0.15);
                            borderColor = Colors.green;
                          } else if (!_isTimeout) {
                            buttonColor = theme.colorScheme.error.withOpacity(0.15);
                            borderColor = theme.colorScheme.error;
                          }
                        }
                        
                        if (_inBuffer && index == _correctOptionIndex) {
                          buttonColor = Colors.green.withOpacity(0.2);
                          borderColor = Colors.green;
                        }
                      }

                      return Padding(
                        padding: const EdgeInsets.only(bottom: 16.0),
                        child: InkWell(
                          onTap: _hasAnswered ? null : () => _submitAnswer(index),
                          borderRadius: BorderRadius.circular(12),
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 24),
                            decoration: BoxDecoration(
                              color: buttonColor,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: borderColor, width: 1.5),
                            ),
                            child: Row(
                              children: [
                                CircleAvatar(
                                  radius: 14,
                                  backgroundColor: Colors.white.withOpacity(0.08),
                                  child: Text(
                                    String.fromCharCode(65 + index),
                                    style: const TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.bold),
                                  ),
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: Text(
                                    optionText,
                                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                                  ),
                                ),
                                if (_hasAnswered && index == _selectedIndex) ...[
                                  if (_isCorrect)
                                    const Icon(Icons.check_circle, color: Colors.green)
                                  else if (!_isTimeout)
                                    Icon(Icons.cancel, color: theme.colorScheme.error),
                                ],
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
          
          // Faded Buffer Overlay (Next question countdown & stand summary)
          if (_inBuffer) _buildBufferOverlay(theme),
        ],
      ),
    );
  }

  Widget _buildBufferOverlay(ThemeData theme) {
    // Show top 3 in leaderboard
    final topStandings = _midLeaderboard.take(3).toList();

    return Container(
      color: Colors.black.withOpacity(0.85),
      padding: const EdgeInsets.all(28.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Icon(
            _isCorrect ? Icons.check_circle_outline_rounded : Icons.highlight_off_rounded,
            size: 80,
            color: _isCorrect ? Colors.green : theme.colorScheme.error,
          ),
          const SizedBox(height: 16),
          Text(
            _isCorrect ? 'CORRECT!' : _isTimeout ? 'TIME OUT!' : 'INCORRECT!',
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w900,
              color: _isCorrect ? Colors.green : theme.colorScheme.error,
            ),
            textAlign: TextAlign.center,
          ),
          if (_isCorrect) ...[
            const SizedBox(height: 8),
            Text(
              '+${_scoreEarned.toStringAsFixed(0)} Points',
              style: const TextStyle(fontSize: 18, color: Colors.white, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
          ],
          const SizedBox(height: 48),
          
          const Text(
            'STANDINGS SNAPSHOT',
            style: TextStyle(color: Colors.white38, fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          
          ...topStandings.map((entry) {
            final isMe = entry['username'] == ApiService.username;
            return Container(
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
              margin: const EdgeInsets.only(bottom: 8),
              decoration: BoxDecoration(
                color: isMe ? Colors.white.withOpacity(0.08) : Colors.white.withOpacity(0.02),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: isMe ? theme.colorScheme.primary.withOpacity(0.5) : Colors.white10),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '#${entry['rank']} ${entry['username']}',
                    style: TextStyle(fontWeight: isMe ? FontWeight.bold : FontWeight.normal),
                  ),
                  Text('${entry['score']} pts', style: const TextStyle(fontWeight: FontWeight.bold)),
                ],
              ),
            );
          }),
          
          const Spacer(),
          Text(
            'Next question in $_bufferSecondsLeft...',
            style: TextStyle(color: theme.colorScheme.primary, fontSize: 16, fontWeight: FontWeight.bold),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }
}
