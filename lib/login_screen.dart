import 'dart:math';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'home_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final TextEditingController _nameCtrl = TextEditingController();
  final TextEditingController _passCtrl = TextEditingController();
  String _selectedRole = 'RUNNER';
  String _selectedTeam = 'RED'; 
  bool _isLoading = false;

  // ★追加: 4桁のランダムなPINコードを生成する関数
  String _generatePinCode() {
    var rng = Random();
    String code = "";
    for (var i = 0; i < 4; i++) {
      code += rng.nextInt(10).toString();
    }
    return code;
  }

  // ★追加: 初回ログイン時に発行されたPINコードを画面に表示するダイアログ
  Future<void> _showPinDialog(String pinCode, String role, String name) async {
    return showDialog<void>(
      context: context,
      barrierDismissible: false, // ユーザーが「OK」を押すまで閉じられない
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: Colors.grey[900],
          title: const Text('💡 復帰用PINコード発行', style: TextStyle(color: Colors.amberAccent, fontWeight: FontWeight.bold)),
          content: SingleChildScrollView(
            child: ListBody(
              children: <Widget>[
                const Text('アプリが落ちてしまった場合、このPINコードを入力することでデータを引き継いで復帰できます。', style: TextStyle(color: Colors.white70)),
                const SizedBox(height: 20),
                Center(
                  child: Text(
                    pinCode,
                    style: const TextStyle(fontSize: 48, fontWeight: FontWeight.bold, color: Colors.white, letterSpacing: 10),
                  ),
                ),
                const SizedBox(height: 10),
                const Center(child: Text('※必ずメモしておいてください！', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold))),
              ],
            ),
          ),
          actions: <Widget>[
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.greenAccent, foregroundColor: Colors.black),
              child: const Text('確認してゲーム開始！', style: TextStyle(fontWeight: FontWeight.bold)),
              onPressed: () {
                Navigator.of(context).pop();
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(
                    builder: (context) => HomeScreen(
                      myRole: role,
                      myName: name,
                    ),
                  ),
                );
              },
            ),
          ],
        );
      },
    );
  }

  // --- 通常の新規参加処理 ---
  Future<void> _joinGame() async {
    String name = _nameCtrl.text.trim();
    String pass = _passCtrl.text.trim();

    if (_selectedRole == 'GAME MASTER') {
      name = "Game Master";
    } else if (_selectedRole == 'DEVELOPER') {
      name = "Developer";
    } else {
      if (name.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("名前を入力してください")));
        return;
      }
    }

    if (_selectedRole == 'DEVELOPER' && pass != 'admin') {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Wrong Password")));
      return;
    }
    if (_selectedRole == 'GAME MASTER' && pass != '999') {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Wrong Password")));
      return;
    }

    setState(() => _isLoading = true);

    try {
      UserCredential userCredential = await FirebaseAuth.instance.signInAnonymously();
      String uid = userCredential.user!.uid;

      if (_selectedRole == 'GAME MASTER') {
        var gameRef = FirebaseFirestore.instance.collection('games').doc('game_001');
        var gameSnap = await gameRef.get();
        if (!gameSnap.exists) {
          await gameRef.set({
            'status': 'WAITING',
            'mode': 'A',
            'startTime': FieldValue.serverTimestamp(),
            'createdBy': uid,
          });
        }
      }

      // ★追加: このプレイヤー専用の4桁のPINコードを発行
      String generatedPin = _generatePinCode();

      await FirebaseFirestore.instance
          .collection('games')
          .doc('game_001')
          .collection('players')
          .doc(uid)
          .set({
            'name': name,
            'role': _selectedRole,
            'status': 'ALIVE',
            'joinedAt': FieldValue.serverTimestamp(),
            'money': 0,
            'team': _selectedTeam, 
            'pinCode': generatedPin, // ★追加: FirebaseにPINコードを保存
          });

      if (!mounted) return;
      
      // ★変更: すぐにHomeScreenに飛ばさず、PINを書き留めさせるダイアログを挟む
      await _showPinDialog(generatedPin, _selectedRole, name);

    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e")));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ★追加: PINコードを使って過去のデータに復帰（引き継ぎ）する処理
  Future<void> _recoverWithPin(String inputPin) async {
    setState(() => _isLoading = true);
    try {
      // 1. Firebaseのplayersコレクションから、入力されたPINコードを持つプレイヤーを探す
      var playersRef = FirebaseFirestore.instance.collection('games').doc('game_001').collection('players');
      var snapshot = await playersRef.where('pinCode', isEqualTo: inputPin).get();

      if (snapshot.docs.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("PINコードが間違っているか、データが存在しません"), backgroundColor: Colors.redAccent));
        setState(() => _isLoading = false);
        return;
      }

      // 2. 見つかった古いデータを取得
      var oldDoc = snapshot.docs.first;
      Map<String, dynamic> oldData = oldDoc.data();
      String oldUid = oldDoc.id;

      // 3. 新しく匿名ログインして新しいUIDを取得
      UserCredential userCredential = await FirebaseAuth.instance.signInAnonymously();
      String newUid = userCredential.user!.uid;

      // 4. 古いデータをそっくりそのまま新しいUIDのドキュメントにコピー（お引越し）
      await playersRef.doc(newUid).set(oldData);

      // 5. 古い（重複した）ドキュメントを綺麗に削除
      await playersRef.doc(oldUid).delete();

      // 復帰完了！ゲーム画面へジャンプ
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("データの復帰に成功しました！"), backgroundColor: Colors.green));
      
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) => HomeScreen(
            myRole: oldData['role'],
            myName: oldData['name'],
          ),
        ),
      );

    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("復帰エラー: $e"), backgroundColor: Colors.redAccent));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ★追加: PIN入力用ダイアログを表示
  void _showRecoveryDialog() {
    TextEditingController pinCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.grey[900],
        title: const Text("復帰用PINを入力", style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: pinCtrl,
          keyboardType: TextInputType.number,
          maxLength: 4,
          style: const TextStyle(color: Colors.white, fontSize: 32, letterSpacing: 10, fontWeight: FontWeight.bold),
          textAlign: TextAlign.center,
          decoration: const InputDecoration(
            counterText: "",
            hintText: "0000",
            hintStyle: TextStyle(color: Colors.grey),
            enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.grey)),
            focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.greenAccent)),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("キャンセル", style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.blueAccent),
            onPressed: () {
              String pin = pinCtrl.text.trim();
              if (pin.length == 4) {
                Navigator.pop(ctx);
                _recoverWithPin(pin);
              } else {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("4桁の数字を入力してください")));
              }
            },
            child: const Text("復帰する", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    bool needsNameInput = (_selectedRole != 'GAME MASTER' && _selectedRole != 'DEVELOPER');
    bool needsPasswordInput = (_selectedRole == 'GAME MASTER' || _selectedRole == 'DEVELOPER');
    bool needsTeamInput = (_selectedRole == 'RUNNER' || _selectedRole == 'HUNTER');

    return Scaffold(
      backgroundColor: Colors.black,
      body: Padding(
        padding: const EdgeInsets.all(30.0),
        child: SingleChildScrollView(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const SizedBox(height: 50),
              const Text(
                "TRAIN RUN", 
                style: TextStyle(
                  fontFamily: 'Courier',
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                  color: Colors.greenAccent,
                ),
              ),
              const SizedBox(height: 40),

              DropdownButton<String>(
                value: _selectedRole,
                dropdownColor: Colors.grey[900],
                style: const TextStyle(color: Colors.white, fontSize: 18),
                isExpanded: true,
                items: ['RUNNER', 'HUNTER', 'GAME MASTER', 'DEVELOPER'].map((String role) {
                  return DropdownMenuItem(value: role, child: Text(role));
                }).toList(),
                onChanged: (val) {
                  setState(() => _selectedRole = val!);
                },
              ),
              const SizedBox(height: 20),

              if (needsTeamInput) ...[
                const Align(alignment: Alignment.centerLeft, child: Text("TEAM SELECT", style: TextStyle(color: Colors.grey, fontSize: 12))),
                DropdownButton<String>(
                  value: _selectedTeam,
                  dropdownColor: Colors.grey[900],
                  style: const TextStyle(color: Colors.white, fontSize: 18),
                  isExpanded: true,
                  items: ['RED', 'BLUE', 'YELLOW', 'GREEN'].map((String team) {
                    Color c = Colors.white;
                    if(team == 'RED') c = Colors.redAccent;
                    if(team == 'BLUE') c = Colors.blueAccent;
                    if(team == 'YELLOW') c = Colors.yellowAccent;
                    if(team == 'GREEN') c = Colors.greenAccent;
                    return DropdownMenuItem(
                      value: team, 
                      child: Text(team, style: TextStyle(color: c, fontWeight: FontWeight.bold))
                    );
                  }).toList(),
                  onChanged: (val) {
                    setState(() => _selectedTeam = val!);
                  },
                ),
                const SizedBox(height: 20),
              ],

              if (needsNameInput)
                TextField(
                  controller: _nameCtrl,
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(
                    labelText: "PLAYER NAME",
                    labelStyle: TextStyle(color: Colors.grey),
                    enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.grey)),
                    focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.greenAccent)),
                  ),
                ),

              if (needsNameInput) const SizedBox(height: 20),

              if (needsPasswordInput)
                TextField(
                  controller: _passCtrl,
                  obscureText: true,
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(
                    labelText: "PASSWORD",
                    labelStyle: TextStyle(color: Colors.grey),
                    enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.grey)),
                    focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.redAccent)),
                  ),
                ),

              const SizedBox(height: 40),

              _isLoading
                  ? const CircularProgressIndicator(color: Colors.greenAccent)
                  : SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.greenAccent,
                          foregroundColor: Colors.black,
                        ),
                        onPressed: _joinGame,
                        child: const Text(
                          "JOIN GAME",
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                        ),
                      ),
                    ),
              
              const SizedBox(height: 40),
              
              // ★追加: 復帰用のリンクボタン
              if (!_isLoading)
                TextButton.icon(
                  icon: const Icon(Icons.history, color: Colors.blueAccent),
                  label: const Text(
                    "💡 アプリが落ちた方：PINで復帰する", 
                    style: TextStyle(color: Colors.blueAccent, decoration: TextDecoration.underline)
                  ),
                  onPressed: _showRecoveryDialog,
                ),
            ],
          ),
        ),
      ),
    );
  }
}