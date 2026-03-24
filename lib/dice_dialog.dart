import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';

class DiceDialog extends StatefulWidget {
  final Function(int) onRollFinished;

  const DiceDialog({super.key, required this.onRollFinished});

  @override
  State<DiceDialog> createState() => _DiceDialogState();
}

class _DiceDialogState extends State<DiceDialog> {
  int _currentFace = 1;
  int _rollCount = 0;
  Timer? _timer;
  bool _isRolling = true;

  @override
  void initState() {
    super.initState();
    _startRolling();
  }

  void _startRolling() {
    // 0.1秒ごとにサイコロの目を変える
    _timer = Timer.periodic(const Duration(milliseconds: 100), (timer) {
      setState(() {
        _currentFace = Random().nextInt(6) + 1;
        _rollCount++;
      });

      // 2秒経ったら止める
      if (_rollCount > 20) {
        _stopRolling();
      }
    });
  }

  void _stopRolling() {
    _timer?.cancel();
    setState(() {
      _isRolling = false;
      // 最終的な出目を決定
      _currentFace = Random().nextInt(6) + 1; 
    });
    
    // 少し待ってから結果を返す
    Future.delayed(const Duration(seconds: 1), () {
      if (mounted) {
        Navigator.pop(context); // ダイアログを閉じる
        widget.onRollFinished(_currentFace);
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: Colors.grey[900],
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text("DICE ROLL", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, letterSpacing: 2)),
          const SizedBox(height: 20),
          Icon(
            _getDiceIcon(_currentFace),
            size: 100,
            color: _isRolling ? Colors.grey : Colors.purpleAccent,
          ),
          const SizedBox(height: 20),
          Text(
            _isRolling ? "Rolling..." : "RESULT: $_currentFace",
            style: TextStyle(
              color: _isRolling ? Colors.grey : Colors.yellowAccent,
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  IconData _getDiceIcon(int face) {
    switch (face) {
      case 1: return Icons.looks_one;
      case 2: return Icons.looks_two;
      case 3: return Icons.looks_3;
      case 4: return Icons.looks_4;
      case 5: return Icons.looks_5;
      case 6: return Icons.looks_6;
      default: return Icons.help;
    }
  }
}