import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Shared visual acknowledgement while a named player awaits a voice command.
class VoicePlayerCue extends StatefulWidget {
  const VoicePlayerCue({super.key, required this.active, required this.child});

  final bool active;
  final Widget child;

  @override
  State<VoicePlayerCue> createState() => _VoicePlayerCueState();
}

class _VoicePlayerCueState extends State<VoicePlayerCue>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 360),
  );

  void _updateAnimation() {
    if (widget.active && !MediaQuery.disableAnimationsOf(context)) {
      if (!_controller.isAnimating) _controller.repeat();
    } else {
      _controller.stop();
      _controller.value = 0;
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _updateAnimation();
  }

  @override
  void didUpdateWidget(VoicePlayerCue oldWidget) {
    super.didUpdateWidget(oldWidget);
    _updateAnimation();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Semantics(
        selected: widget.active,
        label: widget.active ? 'Нэр танигдлаа. Команд хүлээж байна.' : null,
        child: AnimatedBuilder(
          animation: _controller,
          child: Stack(
            fit: StackFit.passthrough,
            children: [
              widget.child,
              if (widget.active)
                Positioned.fill(
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        border:
                            Border.all(color: Colors.lightBlueAccent, width: 3),
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
            ],
          ),
          builder: (context, child) => Transform.translate(
            offset: Offset(math.sin(_controller.value * math.pi * 2) * 2.5, 0),
            child: child,
          ),
        ),
      );
}
