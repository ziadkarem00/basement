import 'package:flutter/material.dart';

class AppTheme {
  // Page background: pure black #000000
  static const Color background = Color(0xFF000000);

  // Message bubbles
  static const Color myBubble = Color(0xFF0A3A6B); // dark blue
  static const Color othersBubble = Color(0xFF1C1C1E); // dark grey

  // Typography
  static const Color text = Color(0xFFFFFFFF); // white
  static const Color subtext = Color(0xFF9A9A9A); // grey

  // Reply quote block inside a bubble
  static const Color replyMyBg = Color(0xFF0D4785); // slightly lighter shade of my bubble
  static const Color replyOthersBg = Color(0xFF2C2C2E); // slightly lighter shade of others bubble
  static const Color replyBorder = Color(0xFF9A9A9A); // thin grey left line

  // Bubble border radius: 16px, corner nearest sender's side only 4px
  static const BorderRadius myBubbleRadius = BorderRadius.only(
    topLeft: Radius.circular(16),
    topRight: Radius.circular(16),
    bottomLeft: Radius.circular(16),
    bottomRight: Radius.circular(4),
  );

  static const BorderRadius othersBubbleRadius = BorderRadius.only(
    topLeft: Radius.circular(16),
    topRight: Radius.circular(16),
    bottomLeft: Radius.circular(4),
    bottomRight: Radius.circular(16),
  );

  // Padding: 10px 12px
  static const EdgeInsets bubblePadding = EdgeInsets.symmetric(horizontal: 12, vertical: 10);
}

