import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'login_screen.dart';

class DeveloperScreen extends StatelessWidget {
  const DeveloperScreen({super.key});

  @override
  Widget build(BuildContext context) {
    // ID入力用コントローラー
    final TextEditingController poolIdCtrl = TextEditingController();

    return Scaffold(
      backgroundColor: Colors.grey[900],
      appBar: AppBar(
        title: const Text(
          "DEVELOPER MODE",
          style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 2),
        ),
        backgroundColor: Colors.black,
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () => Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (context) => const LoginScreen()),
            ),
          ),
        ],
      ),
      body: Row(
        children: [
          // 左側: プレイヤーリスト（前回と同じ）
          Expanded(
            flex: 2,
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('games')
                  .doc('game_001')
                  .collection('players')
                  .orderBy('joinedAt')
                  .snapshots(),
              builder: (context, snapshot) {
                if (!snapshot.hasData)
                  return const Center(child: CircularProgressIndicator());
                return ListView.separated(
                  itemCount: snapshot.data!.docs.length,
                  separatorBuilder: (ctx, i) =>
                      const Divider(color: Colors.grey),
                  itemBuilder: (context, index) {
                    var data =
                        snapshot.data!.docs[index].data()
                            as Map<String, dynamic>;
                    return ListTile(
                      leading: Icon(
                        data['role'] == 'HUNTER'
                            ? Icons.remove_red_eye
                            : Icons.directions_run,
                        color: data['role'] == 'HUNTER'
                            ? Colors.red
                            : Colors.green,
                      ),
                      title: Text(
                        data['name'],
                        style: const TextStyle(color: Colors.white),
                      ),
                      subtitle: Text(
                        "ID: ${data['discordId'] ?? '未割当'}",
                        style: TextStyle(
                          color: data['discordId'] != null
                              ? Colors.blueAccent
                              : Colors.grey,
                        ),
                      ),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete, color: Colors.red),
                        onPressed: () =>
                            snapshot.data!.docs[index].reference.delete(),
                      ),
                    );
                  },
                );
              },
            ),
          ),

          // 右側: 管理・設定エリア
          Expanded(
            flex: 1,
            child: Container(
              color: Colors.black87,
              padding: const EdgeInsets.all(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    "GAME CONTROL",
                    style: TextStyle(
                      color: Colors.yellowAccent,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 10),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
                      minimumSize: const Size.fromHeight(40),
                    ),
                    onPressed: () => FirebaseFirestore.instance
                        .collection('games')
                        .doc('game_001')
                        .update({'status': 'ACTIVE'}),
                    child: const Text("強制開始"),
                  ),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.grey,
                      minimumSize: const Size.fromHeight(40),
                    ),
                    onPressed: () => FirebaseFirestore.instance
                        .collection('games')
                        .doc('game_001')
                        .update({'status': 'WAITING'}),
                    child: const Text("待機へ戻す"),
                  ),

                  const Divider(color: Colors.white24, height: 30),

                  // ★追加: Discord ID 在庫管理
                  const Text(
                    "DISCORD ID POOL (在庫)",
                    style: TextStyle(
                      color: Colors.purpleAccent,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: poolIdCtrl,
                          style: const TextStyle(color: Colors.white),
                          decoration: const InputDecoration(
                            hintText: "ID入力",
                            hintStyle: TextStyle(color: Colors.grey),
                            isDense: true,
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.add, color: Colors.green),
                        onPressed: () {
                          if (poolIdCtrl.text.isNotEmpty) {
                            FirebaseFirestore.instance
                                .collection('games')
                                .doc('game_001')
                                .collection('discord_pool')
                                .add({
                                  'id': poolIdCtrl.text.trim(),
                                  'isUsed': false,
                                  'assignedTo': null,
                                  'createdAt': FieldValue.serverTimestamp(),
                                });
                            poolIdCtrl.clear();
                          }
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Expanded(
                    child: StreamBuilder<QuerySnapshot>(
                      stream: FirebaseFirestore.instance
                          .collection('games')
                          .doc('game_001')
                          .collection('discord_pool')
                          .orderBy('createdAt')
                          .snapshots(),
                      builder: (context, snapshot) {
                        if (!snapshot.hasData) return const SizedBox();
                        return ListView.builder(
                          itemCount: snapshot.data!.docs.length,
                          itemBuilder: (context, index) {
                            var doc = snapshot.data!.docs[index];
                            var d = doc.data() as Map<String, dynamic>;
                            bool isUsed = d['isUsed'] ?? false;
                            return ListTile(
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                              title: Text(
                                d['id'],
                                style: TextStyle(
                                  color: isUsed ? Colors.grey : Colors.white,
                                ),
                              ),
                              subtitle: Text(
                                isUsed
                                    ? "割当済: ${d['assignedName'] ?? ''}"
                                    : "未使用",
                                style: TextStyle(
                                  color: isUsed ? Colors.red : Colors.green,
                                  fontSize: 10,
                                ),
                              ),
                              trailing: IconButton(
                                icon: const Icon(
                                  Icons.close,
                                  size: 16,
                                  color: Colors.grey,
                                ),
                                onPressed: () => doc.reference.delete(),
                              ),
                            );
                          },
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
