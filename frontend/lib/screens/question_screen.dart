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
  int _totalQuestions = 3;
  String _questionId = '';
  String _questionText = '';
  List<dynamic> _options = [];
  int _timeLimit = 10;
  int _initialScore = 1000;
  
  // Participant state
  int? _selectedIndex;
  int? _correctIndex;
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
    widget.wsService.close();
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
      _totalQuestions = data['totalQuestions'] ?? 3;
      _questionId = data['questionId'] ?? '';
      _questionText = data['questionText'] ?? '';
      _options = data['options'] ?? [];
      _timeLimit = data['timeLimitSeconds'] ?? 10;
      _initialScore = data['initialScore'] ?? 1000;
      
      _selectedIndex = null;
      _correctIndex = null;
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
        _correctIndex = result['correctOptionIndex'] as int?;
      });
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Submission error: $e'), backgroundColor: Colors.red),
      );
    }
  }

  void _handleQuestionEnd(Map<String, dynamic> data) {
    _timerController?.dispose();
    
    setState(() {
      _inBuffer = true;
      _correctOptionIndex = data['correctOptionIndex'] ?? 0;
      _correctIndex = _correctOptionIndex;
      _midLeaderboard = data['leaderboard'] ?? [];
      _bufferSecondsLeft = 5; 
    });

    _timerController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 5),
    );
    _timerController!.forward(from: 0.0);

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

  int getSecondsToNextQuestion() {
    if (_inBuffer) {
      return _bufferSecondsLeft;
    }
    if (_questionStartTime == null) {
      return _timeLimit + 5;
    }
    final elapsed = DateTime.now().difference(_questionStartTime!).inSeconds;
    final remaining = (_timeLimit + 5) - elapsed;
    return remaining > 0 ? remaining : 0;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text('Question ${_questionIndex + 1}'),
        automaticallyImplyLeading: false,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16.0),
            child: Center(
              child: _timerController != null
                  ? AnimatedBuilder(
                      animation: _timerController!,
                      builder: (context, child) {
                        double currentWorth;
                        if (_inBuffer) {
                          currentWorth = _scoreEarned;
                        } else if (_hasAnswered) {
                          if (_correctIndex != null) {
                            currentWorth = _scoreEarned;
                          } else {
                            currentWorth = _initialScore * (1.0 - _timerController!.value);
                          }
                        } else if (_isTimeout) {
                          currentWorth = 0.0;
                        } else {
                          currentWorth = _initialScore * (1.0 - _timerController!.value);
                        }

                        return Text(
                          _inBuffer
                              ? (_isCorrect ? '+${_scoreEarned.toStringAsFixed(0)} pts' : '0 pts')
                              : 'Worth: ${currentWorth.toStringAsFixed(0)} pts',
                          style: TextStyle(
                            color: _inBuffer || _hasAnswered
                                ? (_isCorrect ? Colors.green : theme.colorScheme.error)
                                : theme.colorScheme.secondary,
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        );
                      },
                    )
                  : Text(
                      'Worth: $_initialScore pts',
                      style: const TextStyle(color: Colors.white38, fontWeight: FontWeight.bold),
                    ),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            SliverFillRemaining(
              hasScrollBody: false,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 20.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Live Progress Timer Bar / Next Question / Final Results text countdown
                    if (_inBuffer)
                      Container(
                        alignment: Alignment.center,
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Text(
                          '${_questionIndex == _totalQuestions - 1 ? "FINAL RESULTS" : "NEXT QUESTION"} IN $_bufferSecondsLeft...',
                          style: TextStyle(
                            color: theme.colorScheme.secondary,
                            fontSize: 22,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 1.5,
                          ),
                        ),
                      )
                    else if (_timerController != null)
                      AnimatedBuilder(
                        animation: _timerController!,
                        builder: (context, child) {
                          if (_hasAnswered) {
                            final secondsLeft = getSecondsToNextQuestion();
                            final isFinalQuestion = _questionIndex == _totalQuestions - 1;
                            return Container(
                              alignment: Alignment.center,
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              child: Text(
                                '${isFinalQuestion ? "FINAL RESULTS" : "NEXT QUESTION"} IN $secondsLeft...',
                                style: TextStyle(
                                  color: theme.colorScheme.secondary,
                                  fontSize: 22,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 1.5,
                                ),
                              ),
                            );
                          }

                          final double val = 1.0 - _timerController!.value;
                          return ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: LinearProgressIndicator(
                              value: val,
                              backgroundColor: Colors.white10,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                val < 0.25 
                                    ? theme.colorScheme.error 
                                    : theme.colorScheme.primary,
                              ),
                              minHeight: 8,
                            ),
                          );
                        },
                      ),
                    const SizedBox(height: 16),
                    
                    // Correctness banner / status
                    if (_isTimeout || _correctIndex != null || _inBuffer) ...[
                      const SizedBox(height: 16),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            _isCorrect ? Icons.check_circle_outline_rounded : (_isTimeout ? Icons.alarm_off : Icons.highlight_off_rounded),
                            color: _isCorrect ? Colors.green : (_isTimeout ? Colors.orange : theme.colorScheme.error),
                            size: 24,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            _isCorrect 
                                ? 'CORRECT! +${_scoreEarned.toStringAsFixed(0)} pts' 
                                : (_isTimeout ? 'TIME OUT!' : 'INCORRECT!'),
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: _isCorrect ? Colors.green : (_isTimeout ? Colors.orange : theme.colorScheme.error),
                            ),
                          ),
                        ],
                      ),
                    ],

                    // Standings snapshot
                    if (_inBuffer) ...[
                      const SizedBox(height: 16),
                      _buildStandingsSnapshot(theme),
                    ],

                    // Spacer to push the question and answers to the bottom of the screen
                    const Spacer(),
                    
                    // Question Text
                    Text(
                      _questionText,
                      style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, height: 1.4),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 24),
                    
                    // Options Grid (Suggested Answers)
                    ..._options.asMap().entries.map((entry) {
                      final index = entry.key;
                      final optionText = entry.value;
                      
                      // Compute option background colors based on states
                      Color buttonColor = theme.cardTheme.color ?? theme.cardColor;
                      Color borderColor = const Color(0xFF2C2254);
                      
                      if (_hasAnswered) {
                        final isSelected = index == _selectedIndex;
                        final isPending = _correctIndex == null && !_isTimeout;

                        if (isSelected) {
                          if (isPending) {
                            buttonColor = theme.colorScheme.primary.withOpacity(0.15);
                            borderColor = theme.colorScheme.primary;
                          } else {
                            if (_isCorrect) {
                              buttonColor = Colors.green.withOpacity(0.15);
                              borderColor = Colors.green;
                            } else {
                              buttonColor = theme.colorScheme.error.withOpacity(0.15);
                              borderColor = theme.colorScheme.error;
                            }
                          }
                        }
                        
                        if (!isPending) {
                          final isThisOptionCorrect = index == _correctIndex || (_inBuffer && index == _correctOptionIndex);
                          if (isThisOptionCorrect) {
                            if (!_isCorrect) {
                              buttonColor = Colors.green.withOpacity(0.20);
                              borderColor = Colors.green;
                            }
                          }
                        }
                      }

                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12.0),
                        child: InkWell(
                          onTap: _hasAnswered ? null : () => _submitAnswer(index),
                          borderRadius: BorderRadius.circular(12),
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 20),
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
                                if (_hasAnswered && index == _selectedIndex && _correctIndex != null) ...[
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
                    }),
                    const SizedBox(height: 32), // Extra bottom spacing to avoid overlays / cuts
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStandingsSnapshot(ThemeData theme) {
    final topStandings = _midLeaderboard.take(3).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        const Divider(color: Colors.white10, height: 24),
        const Text(
          'STANDINGS SNAPSHOT',
          style: TextStyle(color: Colors.white38, fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 12),
        ...topStandings.map((entry) {
          final isMe = entry['username'] == ApiService.username;
          return Container(
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
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
      ],
    );
  }
}
