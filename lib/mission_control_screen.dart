import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class MissionScreen extends StatelessWidget {
  const MissionScreen({super.key});

  Future<void> _sendMission(BuildContext context, String title, String body, {String type = 'MISSION'}) async {
    await FirebaseFirestore.instance.collection('games').doc('game_001').collection('messages').add({
      'title': title,
      'body': body,
      'type': type,
      'toUid': 'ALL',
      'createdAt': FieldValue.serverTimestamp(),
      'fromName': 'GAME MASTER',
    });
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("ミッション送信完了")));
  }

  Future<void> _releaseHunters(BuildContext context) async {
    // ハンター放出ロジック（通知 + 設定変更など）
    await _sendMission(context, "ハンター放出！", "ハンターが放出されました。逃走者は警戒してください。", type: 'CAUGHT');
    // 必要ならゲーム設定のハンター数などをここでAPI更新する
  }

  Future<void> _exposeLocations(BuildContext context) async {
    // 位置情報公開
    var players = await FirebaseFirestore.instance.collection('games').doc('game_001').collection('players').where('role', isEqualTo: 'RUNNER').get();
    var batch = FirebaseFirestore.instance.batch();
    for (var doc in players.docs) {
      batch.update(doc.reference, {'isExposed': true});
    }
    await batch.commit();
    await _sendMission(context, "位置情報公開", "全員の位置情報が公開されました！", type: 'MISSION');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(title: const Text("MISSION CONTROL"), backgroundColor: Colors.red[900]),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text("ミッション発動パネル (Mode C用)", style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 20),
          _buildMissionButton(context, "ハンター放出", Icons.run_circle, Colors.red, () => _releaseHunters(context)),
          const SizedBox(height: 10),
          _buildMissionButton(context, "位置情報公開 (全員)", Icons.location_on, Colors.orange, () => _exposeLocations(context)),
          const SizedBox(height: 10),
          _buildMissionButton(context, "ミッション通達 (汎用)", Icons.mail, Colors.blue, () {
            _sendMission(context, "ミッション発動！", "次の駅へ移動せよ！");
          }),
          const SizedBox(height: 30),
          const Text("その他の操作", style: TextStyle(color: Colors.white)),
          const SizedBox(height: 10),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.grey),
            onPressed: () async {
              // 位置公開解除
              var players = await FirebaseFirestore.instance.collection('games').doc('game_001').collection('players').get();
              var batch = FirebaseFirestore.instance.batch();
              for (var doc in players.docs) batch.update(doc.reference, {'isExposed': false});
              await batch.commit();
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("位置公開を解除しました")));
            },
            child: const Text("位置公開をリセット"),
          ),
        ],
      ),
    );
  }

  Widget _buildMissionButton(BuildContext context, String label, IconData icon, Color color, VoidCallback onTap) {
    return SizedBox(
      width: double.infinity,
      height: 60,
      child: ElevatedButton.icon(
        style: ElevatedButton.styleFrom(backgroundColor: color, foregroundColor: Colors.white),
        icon: Icon(icon, size: 30),
        label: Text(label, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        onPressed: onTap,
      ),
    );
  }
}