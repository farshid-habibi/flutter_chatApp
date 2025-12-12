import 'package:flutter/material.dart';
import 'package:voice_message_package/voice_message_package.dart';

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
  late final VoiceController _voiceController;
  bool _isInitError = false;

  @override
  void initState() {
    super.initState();

    _voiceController = VoiceController(
      audioSrc: widget.audioUrl,
      maxDuration: const Duration(minutes: 30),
      isFile: false,
      onComplete: () => setState(() {}),
      onPause: () => setState(() {}),
      onPlaying: () => setState(() {}),
      onError: (err) {
        debugPrint('Voice controller error: $err');
      },
    );

    _initController();
  }

  Future<void> _initController() async {
    try {
      await _voiceController.init();
      if (mounted) setState(() {});
    } catch (e) {
      debugPrint('❌ Failed to init voice controller: $e');
      setState(() => _isInitError = true);
    }
  }

  @override
  void dispose() {
    _voiceController.dispose();
    super.dispose();
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

    return Align(
      alignment: widget.isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 230),
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 2, horizontal: 4),
          padding: const EdgeInsets.symmetric(vertical: 1, horizontal: 8),
          decoration: BoxDecoration(
            color: bubbleColor,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: widget.isMe
                ? CrossAxisAlignment.end
                : CrossAxisAlignment.start,
            children: [
              if (_isInitError)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: const [
                    Icon(Icons.error, color: Colors.redAccent, size: 16),
                    SizedBox(width: 6),
                    Text("Error loading voice", style: TextStyle(fontSize: 12)),
                  ],
                )
              else
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Expanded(
                      child: VoiceMessageView(
                        controller: _voiceController,
                        backgroundColor: bubbleColor,
                        activeSliderColor: iconColor,
                        size: 36,
                        innerPadding: 1,
                        cornerRadius: 10,
                      ),
                    ),
                  ],
                ),

              const SizedBox(height: 2),

              Align(
                alignment: widget.isMe
                    ? Alignment.centerRight
                    : Alignment.centerLeft,
                child: Padding(
                  padding: const EdgeInsets.only(left: 5, right: 5, bottom: 2),
                  child: Text(
                    _formatSentTime(widget.sentTime),
                    style: TextStyle(
                      color: Colors.black87.withOpacity(0.8),
                      fontSize: 10,
                    ),
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
