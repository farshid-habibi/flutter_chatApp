import 'dart:io';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:audio_waveforms/audio_waveforms.dart';
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;

class WhatsAppVoiceBubble extends StatefulWidget {
  final String audioUrl;
  final bool isMe;
  final DateTime? sentTime;

  const WhatsAppVoiceBubble({
    super.key,
    required this.audioUrl,
    required this.isMe,
    this.sentTime,
  });

  @override
  State<WhatsAppVoiceBubble> createState() => _WhatsAppVoiceBubbleState();
}

class _WhatsAppVoiceBubbleState extends State<WhatsAppVoiceBubble> {
  late final AudioPlayer _player;
  late final PlayerController _waveController;
  bool _isPlaying = false;
  bool _isLoading = true;
  bool _hasError = false;
  Duration _duration = Duration.zero;
  Duration _position = Duration.zero;
  String? _localPath;

  @override
  void initState() {
    super.initState();
    _player = AudioPlayer();
    _waveController = PlayerController()..updateFrequency = UpdateFrequency.low;
    _initAudio();
  }

  Future<void> _initAudio() async {
    try {
      final tempDir = await getTemporaryDirectory();
      final tempFile = File(
        '${tempDir.path}/${DateTime.now().millisecondsSinceEpoch}.aac',
      );
      final response = await http.get(Uri.parse(widget.audioUrl));
      if (response.statusCode != 200)
        throw Exception('Failed to download audio');
      await tempFile.writeAsBytes(response.bodyBytes);
      _localPath = tempFile.path;

      await _waveController.preparePlayer(
        path: _localPath!,
        shouldExtractWaveform: true,
      );

      await _player.setFilePath(_localPath!);
      _duration = _player.duration ?? Duration.zero;

      setState(() => _isLoading = false);

      _player.positionStream.listen((pos) {
        if (mounted) {
          setState(() => _position = pos);
          _waveController.seekTo(pos.inMilliseconds);
        }
      });

      _player.playerStateStream.listen((state) {
        if (mounted) setState(() => _isPlaying = state.playing);

        // وقتی پخش تمام شد، فقط آیکون به Play برمی‌گردد، پخش خودکار نشود
        if (state.processingState == ProcessingState.completed) {
          setState(() {
            _isPlaying = false;
            _position = _duration; // موقعیت آخر فایل
          });
        }
      });
    } catch (e) {
      debugPrint('❌ خطا در لود ویس: $e');
      setState(() {
        _hasError = true;
        _isLoading = false;
      });
    }
  }

  @override
  void dispose() {
    _player.dispose();
    _waveController.dispose();
    super.dispose();
  }

  void _togglePlayPause() async {
    if (_isPlaying) {
      await _player.pause();
    } else {
      // اگر ویس قبلاً تمام شده، ابتدا به ابتدای فایل برو و سپس پخش کن
      if (_position >= _duration) {
        await _player.seek(Duration.zero);
      }
      await _player.play(); // مطمئن شو که بعد از seek پخش شروع شود
    }
  }

  String _formatDuration(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  String _formatSentTime(DateTime? t) {
    if (t == null) return '';
    final h = t.hour.toString().padLeft(2, '0');
    final m = t.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  @override
  Widget build(BuildContext context) {
    final bubbleColor = widget.isMe ? const Color(0xFFD2F8C6) : Colors.white;
    final iconColor = widget.isMe
        ? Colors.green.shade700
        : Colors.blue.shade700;
    final textColor = Colors.black87;

    final double bubbleWidth = MediaQuery.of(context).size.width * 0.5;
    final double waveHeight = 35;
    final double verticalPadding = 6;

    return Align(
      alignment: widget.isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        width: bubbleWidth,
        margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 12),
        padding: EdgeInsets.symmetric(
          horizontal: 12,
          vertical: verticalPadding,
        ),
        decoration: BoxDecoration(
          color: bubbleColor,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: widget.isMe
              ? CrossAxisAlignment.end
              : CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                // دکمه Play/Pause
                InkWell(
                  onTap: _hasError ? null : _togglePlayPause,
                  child: CircleAvatar(
                    radius: 20,
                    backgroundColor: iconColor.withOpacity(0.15),
                    child: _isLoading
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : _hasError
                        ? const Icon(Icons.error, color: Colors.redAccent)
                        : Icon(
                            _isPlaying ? Icons.pause : Icons.play_arrow,
                            color: iconColor,
                            size: 26,
                          ),
                  ),
                ),
                const SizedBox(width: 8),
                // موج صوتی
                Expanded(
                  child: SizedBox(
                    height: waveHeight,
                    child: AudioFileWaveforms(
                      playerController: _waveController,
                      size: Size(double.infinity, waveHeight),
                      enableSeekGesture: true,
                      playerWaveStyle: PlayerWaveStyle(
                        fixedWaveColor: Colors.grey.shade300.withOpacity(0), // موج ثابت
                        liveWaveColor: iconColor, // موج در حال پخش
                        waveThickness: 2,
                        spacing: 3,
                        showSeekLine: false,
                        showTop: true,
                        showBottom: true,
                        
                        
                        scaleFactor: 70,
                        
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                // زمان ویس
                Text(
                  _formatDuration(_isPlaying ? _position : _duration),
                  style: TextStyle(
                    color: textColor.withOpacity(0.9),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            // زمان ارسال پیام
            Text(
              _formatSentTime(widget.sentTime),
              style: TextStyle(color: textColor.withOpacity(0.6), fontSize: 10),
            ),
          ],
        ),
      ),
    );
  }
}
