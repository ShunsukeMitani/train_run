import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';

class MailScreen extends StatefulWidget {
  const MailScreen({super.key});

  @override
  State<MailScreen> createState() => _MailScreenState();
}

class _MailScreenState extends State<MailScreen> {
  String? _myRole;

  @override
  void initState() {
    super.initState();
    _checkRole();
  }

  Future<void> _checkRole() async {
    String uid = FirebaseAuth.instance.currentUser!.uid;
    var doc = await FirebaseFirestore.instance.collection('games').doc('game_001').collection('players').doc(uid).get();
    if (doc.exists && mounted) {
      setState(() {
        _myRole = doc.data()?['role'];
      });
    }
  }

  void _showComposeDialog() {
    TextEditingController titleCtrl = TextEditingController();
    TextEditingController bodyCtrl = TextEditingController();
    String selectedTo = 'ALL';
    List<DropdownMenuItem<String>> items = [
      const DropdownMenuItem(value: 'ALL', child: Text("全員")),
    ];

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setStateSB) {
          // プレイヤーリスト取得
          if (items.length == 1) {
            FirebaseFirestore.instance.collection('games').doc('game_001').collection('players').get().then((snap) {
              List<DropdownMenuItem<String>> newItems = [
                const DropdownMenuItem(value: 'ALL', child: Text("全員")),
              ];
              for (var doc in snap.docs) {
                newItems.add(DropdownMenuItem(
                  value: doc.id,
                  child: Text("${doc['name']} (${doc['role']})"),
                ));
              }
              setStateSB(() => items = newItems);
            });
          }

          return AlertDialog(
            backgroundColor: Colors.grey[900],
            title: const Text("メール送信 (GM)", style: TextStyle(color: Colors.white)),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButton<String>(
                    value: selectedTo,
                    dropdownColor: Colors.grey[800],
                    style: const TextStyle(color: Colors.white),
                    isExpanded: true,
                    items: items,
                    onChanged: (v) => setStateSB(() => selectedTo = v!),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: titleCtrl,
                    style: const TextStyle(color: Colors.white),
                    decoration: const InputDecoration(labelText: "タイトル", labelStyle: TextStyle(color: Colors.grey)),
                  ),
                  TextField(
                    controller: bodyCtrl,
                    style: const TextStyle(color: Colors.white),
                    maxLines: 3,
                    decoration: const InputDecoration(labelText: "本文", labelStyle: TextStyle(color: Colors.grey)),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("キャンセル")),
              ElevatedButton(
                onPressed: () async {
                  if (titleCtrl.text.isEmpty || bodyCtrl.text.isEmpty) return;
                  await FirebaseFirestore.instance.collection('games').doc('game_001').collection('messages').add({
                    'title': titleCtrl.text,
                    'body': bodyCtrl.text,
                    'toUid': selectedTo,
                    'type': 'INFO',
                    'createdAt': FieldValue.serverTimestamp(),
                    'fromName': 'GAME MASTER',
                  });
                  if (mounted) Navigator.pop(ctx);
                },
                child: const Text("送信"),
              ),
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    String myUid = FirebaseAuth.instance.currentUser!.uid;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text("MAIL", style: TextStyle(fontFamily: 'Courier', fontWeight: FontWeight.bold, letterSpacing: 2)),
        backgroundColor: Colors.grey[900],
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('games')
            .doc('game_001')
            .collection('messages')
            .orderBy('createdAt', descending: true)
            .snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());

          var messages = snapshot.data!.docs.where((doc) {
            var data = doc.data() as Map<String, dynamic>;
            String to = data['toUid'] ?? 'ALL';
            // 自分宛て、全員宛て、または自分が送信したもの
            return to == 'ALL' || to == myUid || (_myRole == 'GAME MASTER'); 
          }).toList();

          if (messages.isEmpty) return const Center(child: Text("受信トレイは空です", style: TextStyle(color: Colors.grey)));

          return ListView.separated(
            padding: const EdgeInsets.all(10),
            itemCount: messages.length,
            separatorBuilder: (ctx, i) => const Divider(color: Colors.grey),
            itemBuilder: (context, index) {
              var data = messages[index].data() as Map<String, dynamic>;
              String type = data['type'] ?? 'INFO';
              String to = data['toUid'] ?? 'ALL';
              bool isPrivate = (to != 'ALL');
              
              Color typeColor = Colors.blueAccent;
              IconData typeIcon = Icons.info_outline;
              if (type == 'MISSION') { typeColor = Colors.orangeAccent; typeIcon = Icons.notifications_active; }
              else if (type == 'CAUGHT') { typeColor = Colors.redAccent; typeIcon = Icons.warning_amber; }
              else if (type == 'SUCCESS') { typeColor = Colors.greenAccent; typeIcon = Icons.check_circle_outline; }
              if (isPrivate) { typeColor = Colors.purpleAccent; typeIcon = Icons.lock; }

              String timeStr = "";
              if (data['createdAt'] != null) {
                DateTime dt = (data['createdAt'] as Timestamp).toDate();
                timeStr = DateFormat('HH:mm').format(dt);
              }

              return Card(
                color: Colors.grey[900],
                shape: RoundedRectangleBorder(
                  side: BorderSide(color: typeColor.withOpacity(0.5), width: 1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: ExpansionTile(
                  leading: Icon(typeIcon, color: typeColor, size: 30),
                  title: Text(
                    data['title'] ?? "NO TITLE",
                    style: TextStyle(color: typeColor, fontWeight: FontWeight.bold, fontFamily: 'Courier'),
                  ),
                  subtitle: Text(
                    "$timeStr ${isPrivate ? '(個別)' : ''} To: ${to == 'ALL' ? '全員' : '個人'}",
                    style: const TextStyle(color: Colors.grey, fontSize: 12),
                  ),
                  iconColor: Colors.white,
                  collapsedIconColor: Colors.grey,
                  children: [
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(15),
                      color: Colors.black26,
                      child: Text(
                        data['body'] ?? "",
                        style: const TextStyle(color: Colors.white, fontSize: 16, height: 1.5),
                      ),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
      floatingActionButton: _myRole == 'GAME MASTER'
          ? FloatingActionButton(
              backgroundColor: Colors.blueAccent,
              child: const Icon(Icons.add, color: Colors.white),
              onPressed: _showComposeDialog,
            )
          : null,
    );
  }
}