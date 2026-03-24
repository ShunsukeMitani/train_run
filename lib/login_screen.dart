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
  String _selectedTeam = 'RED'; // デフォルトチーム
  bool _isLoading = false;

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

      // ゲームデータ自動生成 (GAME MASTERのみ)
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
            'team': _selectedTeam, // ★チーム情報を保存
          });

      if (!mounted) return;
      
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) => HomeScreen(
            myRole: _selectedRole,
            myName: name,
          ),
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e")));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    bool needsNameInput = (_selectedRole != 'GAME MASTER' && _selectedRole != 'DEVELOPER');
    bool needsPasswordInput = (_selectedRole == 'GAME MASTER' || _selectedRole == 'DEVELOPER');
    // チーム選択が必要なのはランナーとハンター
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

              // ロール選択
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

              // ★チーム選択 (追加)
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
            ],
          ),
        ),
      ),
    );
  }
}