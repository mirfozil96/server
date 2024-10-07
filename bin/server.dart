import 'dart:io';
import 'dart:convert'; // For JSON encoding/decoding
import 'dart:math';

void main() async {
  HttpServer server = await HttpServer.bind(InternetAddress.anyIPv4, 3000);
  print('Server ishga tushdi: ws://192.168.0.100:3000');

  var clients = <WebSocket, String>{}; // Map to store WebSocket and client ID

  // Function to generate a random string of 4 alphanumeric characters
  String generateClientId(int length) {
    const characters =
        'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';
    Random random = Random();
    return String.fromCharCodes(Iterable.generate(length,
        (_) => characters.codeUnitAt(random.nextInt(characters.length))));
  }

  await for (HttpRequest request in server) {
    if (WebSocketTransformer.isUpgradeRequest(request)) {
      var socket = await WebSocketTransformer.upgrade(request);
      print('Yangi ulanish o\'rnatildi.');

      // Assign a random 4-character clientId
      String clientId = generateClientId(4);
      clients[socket] = clientId;

      // Send the client ID back to the client
      socket.add(jsonEncode({'type': 'init', 'clientId': clientId}));

      // Notify all clients about the new user
      var userList = clients.values.toList();
      for (var client in clients.keys) {
        client.add(jsonEncode({'type': 'user_list', 'users': userList}));
      }
      print('Yangi foydalanuvchi qo\'shildi: $clientId');

      socket.listen((message) {
        var data = jsonDecode(message);

        if (data['type'] == 'message') {
          // Handle incoming messages
          String text = data['text'];
          String? sender = clients[socket];

          if (sender == null) {
            // The sender's ID is not found
            print('Error: Sender not found for socket $socket');
            return;
          }

          if (data['to'] == 'all') {
            // Broadcast to all clients
            for (var client in clients.keys) {
              client.add(jsonEncode({
                'type': 'message',
                'from': sender,
                'text': text,
                'to': 'all',
              }));
            }
          } else {
            // Send to a specific user
            String recipientId = data['to'];

            // Find the recipient's WebSocket
            var recipientEntries =
                clients.entries.where((entry) => entry.value == recipientId);
            WebSocket? recipientSocket =
                recipientEntries.isNotEmpty ? recipientEntries.first.key : null;

            if (recipientSocket != null) {
              recipientSocket.add(jsonEncode({
                'type': 'message',
                'from': sender,
                'text': text,
                'to': recipientId,
              }));
              // Optionally, send a copy to the sender
              socket.add(jsonEncode({
                'type': 'message',
                'from': sender,
                'text': text,
                'to': recipientId,
              }));
            } else {
              print('Error: Recipient $recipientId not found.');
            }
          }
        }
      }, onDone: () {
        String? clientId = clients[socket];
        print('$clientId chiqdi.');
        clients.remove(socket);

        // Update the user list for all clients
        var userList = clients.values.toList();
        for (var client in clients.keys) {
          client.add(jsonEncode({'type': 'user_list', 'users': userList}));
        }
      }, onError: (error) {
        print('Xato: $error');
        clients.remove(socket);
      });
    } else {
      request.response.statusCode = HttpStatus.forbidden;
      request.response.close();
    }
  }
}
