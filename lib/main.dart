import 'dart:io';
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import 'package:http/http.dart' as http;

void main() {
  runApp(LyricsPlayerApp());
}

class LyricsPlayerApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Lyrics Player',
      theme: ThemeData.dark(),
      home: MusicLyricsScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class MusicLyricsScreen extends StatefulWidget {
  @override
  _MusicLyricsScreenState createState() => _MusicLyricsScreenState();
}

class _MusicLyricsScreenState extends State<MusicLyricsScreen> {
  final AudioPlayer _player = AudioPlayer();
  Timer? _timer;

  String _songTitle = "No song selected";
  String _manualLyrics = "Lyrics will appear here";

  List<Map<String, dynamic>> lrcLines = [];
  int currentLine = 0;

  final TextEditingController _manualController = TextEditingController();

  // 🎵 PICK AUDIO FILE
  Future<void> pickFile() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.audio,
        allowMultiple: false,
      );

      if (result == null) return;

      final file = result.files.single;

      // iOS fix: path can be null (iCloud files)
      if (file.path == null) {
        setState(() {
          _manualLyrics =
              "Cannot access this file.\nDownload it locally in Files app.";
        });
        return;
      }

      String path = file.path!;
      String filename = p.basenameWithoutExtension(path);

      // Stop previous audio
      await _player.stop();

      setState(() {
        _songTitle = filename;
        lrcLines = [];
        currentLine = 0;
        _manualLyrics = "Loading lyrics...";
      });

      await _player.setFilePath(path);
      _player.play();

      // Try LRC first
      String lrcPath = path.replaceAll(p.extension(path), '.lrc');
      List<Map<String, dynamic>> loadedLrc = await readLRC(lrcPath);

      if (loadedLrc.isNotEmpty) {
        setState(() {
          lrcLines = loadedLrc;
        });
        startLrcTimer();
      } else {
        await fetchLyricsFromFilename(filename);
      }
    } catch (e) {
      setState(() {
        _manualLyrics = "Error picking file: $e";
      });
    }
  }

  // 📄 READ LRC FILE
  Future<List<Map<String, dynamic>>> readLRC(String path) async {
    List<Map<String, dynamic>> lines = [];
    final file = File(path);

    if (!await file.exists()) return lines;

    List<String> content = await file.readAsLines();

    final regex = RegExp(r'\[(\d+):(\d+\.?\d*)\](.*)');

    for (String line in content) {
      final match = regex.firstMatch(line);

      if (match != null) {
        int min = int.parse(match.group(1)!);
        double sec = double.parse(match.group(2)!);
        String text = match.group(3)!.trim();

        double time = min * 60 + sec;

        lines.add({'time': time, 'text': text});
      }
    }

    return lines;
  }

  // ⏱️ SYNC LYRICS TIMER (optimized)
  void startLrcTimer() {
    _timer?.cancel();

    _timer = Timer.periodic(Duration(milliseconds: 200), (_) {
      double pos = _player.position.inMilliseconds / 1000.0;

      for (int i = currentLine; i < lrcLines.length; i++) {
        if (i == lrcLines.length - 1 ||
            (pos >= lrcLines[i]['time'] &&
                pos < lrcLines[i + 1]['time'])) {
          if (currentLine != i) {
            setState(() {
              currentLine = i;
            });
          }
          break;
        }
      }
    });
  }

  // 🌐 FETCH LYRICS MANUALLY
  Future<void> fetchLyricsManually(String input) async {
    List<String> parts = input.split('/');

    if (parts.length != 2) {
      setState(() {
        _manualLyrics = "Use format: artist/song";
      });
      return;
    }

    String artist = parts[0].trim();
    String song = parts[1].trim();

    final url = Uri.parse('https://api.lyrics.ovh/v1/$artist/$song');

    try {
      final response = await http.get(url);

      if (response.statusCode == 200) {
        final data = json.decode(response.body);

        setState(() {
          _manualLyrics = data['lyrics'] ?? "Lyrics not found";
        });
      } else {
        setState(() {
          _manualLyrics = "Lyrics not found";
        });
      }
    } catch (e) {
      setState(() {
        _manualLyrics = "Error: $e";
      });
    }
  }

  // 🤖 FETCH FROM FILENAME
  Future<void> fetchLyricsFromFilename(String filename) async {
    if (!filename.contains('-')) {
      setState(() {
        _manualLyrics = "Use manual input (artist/song)";
      });
      return;
    }

    List<String> parts = filename.split('-');

    String artist = parts[0].trim();
    String song = parts[1].trim();

    final url = Uri.parse('https://api.lyrics.ovh/v1/$artist/$song');

    try {
      final response = await http.get(url);

      if (response.statusCode == 200) {
        final data = json.decode(response.body);

        setState(() {
          _manualLyrics = data['lyrics'] ?? "Lyrics not found";
        });
      } else {
        setState(() {
          _manualLyrics = "Lyrics not found";
        });
      }
    } catch (e) {
      setState(() {
        _manualLyrics = "Error fetching lyrics";
      });
    }
  }

  @override
  void dispose() {
    _player.dispose();
    _timer?.cancel();
    _manualController.dispose();
    super.dispose();
  }

  // 🎨 UI
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Lyrics Player')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            ElevatedButton(
              onPressed: pickFile,
              child: Text("Pick Audio File"),
            ),
            SizedBox(height: 10),

            TextField(
              controller: _manualController,
              decoration: InputDecoration(
                labelText: "artist/song",
                border: OutlineInputBorder(),
              ),
            ),

            SizedBox(height: 5),

            ElevatedButton(
              onPressed: () =>
                  fetchLyricsManually(_manualController.text.trim()),
              child: Text("Fetch Lyrics"),
            ),

            SizedBox(height: 10),

            Text(
              _songTitle,
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),

            SizedBox(height: 10),

            Expanded(
              child: lrcLines.isNotEmpty
                  ? ListView.builder(
                      itemCount: lrcLines.length,
                      itemBuilder: (context, index) {
                        return Container(
                          padding: EdgeInsets.symmetric(vertical: 3),
                          color: index == currentLine
                              ? Colors.blue.withOpacity(0.3)
                              : null,
                          child: Text(
                            lrcLines[index]['text'],
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: index == currentLine
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                            ),
                          ),
                        );
                      },
                    )
                  : SingleChildScrollView(
                      child: Text(_manualLyrics),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}