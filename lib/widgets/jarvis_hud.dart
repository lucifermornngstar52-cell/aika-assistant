import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class JarvisHud extends StatelessWidget {
  final String status;
  final bool isActive;

  const JarvisHud({
    Key? key,
    this.status = 'READY',
    this.isActive = false,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: AikaTheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isActive
              ? AikaTheme.neonBlue.withOpacity(0.7)
              : Colors.white12,
        ),
        boxShadow: isActive
            ? [BoxShadow(color: AikaTheme.neonBlue.withOpacity(0.2), blurRadius: 12)]
            : null,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isActive ? AikaTheme.neonBlue : Colors.white24,
              boxShadow: isActive
                  ? [BoxShadow(color: AikaTheme.neonBlue, blurRadius: 6)]
                  : null,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            status,
            style: TextStyle(
              color: isActive ? AikaTheme.neonBlue : Colors.white38,
              fontSize: 11,
              letterSpacing: 2,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}
