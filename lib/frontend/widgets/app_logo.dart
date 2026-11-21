import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Renders authentic, pixel-perfect logos for major apps and services.
class AppLogo extends StatelessWidget {
  final String appName;
  final String? packageName;
  final double size;

  const AppLogo({
    super.key,
    required this.appName,
    this.packageName,
    this.size = 32.0,
  });

  @override
  Widget build(BuildContext context) {
    final key = _normalizeKey(appName, packageName);

    return SizedBox(
      width: size,
      height: size,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(size * 0.22),
        child: CustomPaint(
          size: Size(size, size),
          painter: _AppLogoPainter(key: key, appName: appName, size: size),
        ),
      ),
    );
  }

  static String _normalizeKey(String name, String? pkg) {
    final lowerName = name.toLowerCase().trim();
    final lowerPkg = (pkg ?? '').toLowerCase().trim();

    if (lowerName.contains('youtube') || lowerPkg.contains('youtube')) return 'youtube';
    if (lowerName.contains('instagram') || lowerPkg.contains('instagram')) return 'instagram';
    if (lowerName.contains('facebook messenger') || lowerPkg.contains('orca')) return 'messenger';
    if (lowerName.contains('facebook') || lowerPkg.contains('katana')) return 'facebook';
    if (lowerName.contains('reddit') || lowerPkg.contains('reddit')) return 'reddit';
    if (lowerName.contains('tiktok') || lowerPkg.contains('musical') || lowerPkg.contains('trill')) return 'tiktok';
    if (lowerName.contains('snapchat') || lowerPkg.contains('snapchat')) return 'snapchat';
    if (lowerName.contains('twitter') || lowerPkg.contains('twitter') || lowerName == 'x' || lowerName == 'x (twitter)') return 'twitter';
    if (lowerName.contains('whatsapp') || lowerPkg.contains('whatsapp')) return 'whatsapp';
    if (lowerName.contains('telegram') || lowerPkg.contains('telegram')) return 'telegram';
    if (lowerName.contains('netflix') || lowerPkg.contains('netflix')) return 'netflix';
    if (lowerName.contains('spotify') || lowerPkg.contains('spotify')) return 'spotify';
    if (lowerName.contains('discord') || lowerPkg.contains('discord')) return 'discord';
    if (lowerName.contains('pinterest') || lowerPkg.contains('pinterest')) return 'pinterest';
    if (lowerName.contains('linkedin') || lowerPkg.contains('linkedin')) return 'linkedin';
    if (lowerName.contains('twitch') || lowerPkg.contains('twitch')) return 'twitch';
    if (lowerName.contains('prime video') || lowerPkg.contains('avod')) return 'prime_video';
    if (lowerName.contains('disney') || lowerName.contains('hotstar') || lowerPkg.contains('hotstar')) return 'disney';
    if (lowerName.contains('threads') || lowerPkg.contains('barcelona')) return 'threads';
    if (lowerName.contains('roblox') || lowerPkg.contains('roblox')) return 'roblox';
    if (lowerName.contains('chrome') || lowerPkg.contains('chrome')) return 'chrome';

    return 'generic';
  }
}

class _AppLogoPainter extends CustomPainter {
  final String key;
  final String appName;
  final double size;

  _AppLogoPainter({
    required this.key,
    required this.appName,
    required this.size,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final center = Offset(w / 2, h / 2);

    switch (key) {
      case 'youtube':
        _paintYouTube(canvas, w, h);
        break;
      case 'instagram':
        _paintInstagram(canvas, w, h);
        break;
      case 'facebook':
        _paintFacebook(canvas, w, h);
        break;
      case 'reddit':
        _paintReddit(canvas, w, h);
        break;
      case 'tiktok':
        _paintTikTok(canvas, w, h);
        break;
      case 'snapchat':
        _paintSnapchat(canvas, w, h);
        break;
      case 'twitter':
        _paintX(canvas, w, h);
        break;
      case 'whatsapp':
        _paintWhatsApp(canvas, w, h);
        break;
      case 'telegram':
        _paintTelegram(canvas, w, h);
        break;
      case 'netflix':
        _paintNetflix(canvas, w, h);
        break;
      case 'spotify':
        _paintSpotify(canvas, w, h);
        break;
      case 'discord':
        _paintDiscord(canvas, w, h);
        break;
      case 'pinterest':
        _paintPinterest(canvas, w, h);
        break;
      case 'linkedin':
        _paintLinkedIn(canvas, w, h);
        break;
      case 'twitch':
        _paintTwitch(canvas, w, h);
        break;
      case 'prime_video':
        _paintPrimeVideo(canvas, w, h);
        break;
      case 'disney':
        _paintDisney(canvas, w, h);
        break;
      case 'threads':
        _paintThreads(canvas, w, h);
        break;
      case 'roblox':
        _paintRoblox(canvas, w, h);
        break;
      case 'messenger':
        _paintMessenger(canvas, w, h);
        break;
      case 'chrome':
        _paintChrome(canvas, w, h);
        break;
      default:
        _paintGeneric(canvas, w, h);
        break;
    }
  }

  void _paintYouTube(Canvas canvas, double w, double h) {
    // YouTube vibrant red background
    final bgPaint = Paint()..color = const Color(0xFFFF0000);
    canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(0, 0, w, h), Radius.circular(w * 0.22)), bgPaint);

    // Centered white play triangle
    final playPath = Path();
    final triW = w * 0.34;
    final triH = h * 0.40;
    final startX = (w - triW) / 2 + (w * 0.03);
    final startY = (h - triH) / 2;

    playPath.moveTo(startX, startY);
    playPath.lineTo(startX + triW, startY + triH / 2);
    playPath.lineTo(startX, startY + triH);
    playPath.close();

    final whitePaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;
    canvas.drawPath(playPath, whitePaint);
  }

  void _paintInstagram(Canvas canvas, double w, double h) {
    // Official Instagram 45-degree gradient
    final bgPaint = Paint()
      ..shader = const LinearGradient(
        colors: [Color(0xFF833AB4), Color(0xFFFD1D1D), Color(0xFFFCB045)],
        begin: Alignment.bottomLeft,
        end: Alignment.topRight,
      ).createShader(Rect.fromLTWH(0, 0, w, h));
    canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(0, 0, w, h), Radius.circular(w * 0.22)), bgPaint);

    final whiteStroke = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1.8, w * 0.075)
      ..strokeCap = StrokeCap.round;

    // Outer rounded camera body
    final pad = w * 0.22;
    final camRect = Rect.fromLTWH(pad, pad, w - pad * 2, h - pad * 2);
    canvas.drawRRect(RRect.fromRectAndRadius(camRect, Radius.circular(w * 0.16)), whiteStroke);

    // Center circular lens
    canvas.drawCircle(Offset(w / 2, h / 2), w * 0.16, whiteStroke);

    // Top-right flash dot
    final dotPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;
    canvas.drawCircle(Offset(w * 0.69, h * 0.31), math.max(1.5, w * 0.035), dotPaint);
  }

  void _paintFacebook(Canvas canvas, double w, double h) {
    // Facebook iconic #1877F2 blue circle
    final bgPaint = Paint()..color = const Color(0xFF1877F2);
    canvas.drawCircle(Offset(w / 2, h / 2), w / 2, bgPaint);

    // Crisp white bold 'f'
    final textPainter = TextPainter(
      text: TextSpan(
        text: 'f',
        style: TextStyle(
          color: Colors.white,
          fontSize: w * 0.82,
          fontWeight: FontWeight.w900,
          fontFamily: 'sans-serif',
          height: 1.0,
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    textPainter.layout();
    textPainter.paint(canvas, Offset(w * 0.40, h * 0.08));
  }

  void _paintReddit(Canvas canvas, double w, double h) {
    // Reddit Orangred #FF4500 background
    final bgPaint = Paint()..color = const Color(0xFFFF4500);
    canvas.drawCircle(Offset(w / 2, h / 2), w / 2, bgPaint);

    final whiteFill = Paint()..color = Colors.white;
    final orangeFill = Paint()..color = const Color(0xFFFF4500);
    final whiteStroke = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1.4, w * 0.05)
      ..strokeCap = StrokeCap.round;

    // Antenna stem & orange tip
    final antPath = Path();
    antPath.moveTo(w * 0.50, h * 0.36);
    antPath.lineTo(w * 0.52, h * 0.22);
    antPath.lineTo(w * 0.68, h * 0.18);
    canvas.drawPath(antPath, whiteStroke);
    canvas.drawCircle(Offset(w * 0.69, h * 0.18), w * 0.075, whiteFill);
    canvas.drawCircle(Offset(w * 0.69, h * 0.18), w * 0.045, orangeFill);

    // Left & right ears
    canvas.drawOval(Rect.fromCenter(center: Offset(w * 0.25, h * 0.52), width: w * 0.18, height: w * 0.18), whiteFill);
    canvas.drawOval(Rect.fromCenter(center: Offset(w * 0.75, h * 0.52), width: w * 0.18, height: w * 0.18), whiteFill);

    // Head oval
    final headRect = Rect.fromCenter(center: Offset(w * 0.50, h * 0.57), width: w * 0.66, height: h * 0.46);
    canvas.drawOval(headRect, whiteFill);

    // Orange round eyes
    canvas.drawCircle(Offset(w * 0.39, h * 0.56), w * 0.07, orangeFill);
    canvas.drawCircle(Offset(w * 0.61, h * 0.56), w * 0.07, orangeFill);

    // Smiling curved mouth
    final mouthPaint = Paint()
      ..color = const Color(0xFFFF4500)
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1.2, w * 0.04)
      ..strokeCap = StrokeCap.round;
    final mouthPath = Path();
    mouthPath.moveTo(w * 0.40, h * 0.67);
    mouthPath.quadraticBezierTo(w * 0.50, h * 0.74, w * 0.60, h * 0.67);
    canvas.drawPath(mouthPath, mouthPaint);
  }

  void _paintTikTok(Canvas canvas, double w, double h) {
    // Black background
    final bgPaint = Paint()..color = const Color(0xFF000000);
    canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(0, 0, w, h), Radius.circular(w * 0.22)), bgPaint);

    // Cyan shadow offset
    _drawMusicNote(canvas, w, h, dx: -w * 0.04, dy: -h * 0.02, color: const Color(0xFF25F4EE));
    // Pink shadow offset
    _drawMusicNote(canvas, w, h, dx: w * 0.04, dy: h * 0.03, color: const Color(0xFFFE2C55));
    // Crisp white note
    _drawMusicNote(canvas, w, h, dx: 0, dy: 0, color: Colors.white);
  }

  void _drawMusicNote(Canvas canvas, double w, double h, {required double dx, required double dy, required Color color}) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1.8, w * 0.08)
      ..strokeCap = StrokeCap.round;

    final cx = w * 0.50 + dx;
    final cy = h * 0.58 + dy;

    // Bottom note circle
    canvas.drawOval(Rect.fromCenter(center: Offset(cx, cy), width: w * 0.28, height: h * 0.22), paint);

    // Stem going up
    final stemX = cx + w * 0.10;
    final stemTopY = h * 0.24 + dy;
    canvas.drawLine(Offset(stemX, cy), Offset(stemX, stemTopY), stroke);

    // Top flag hook
    final flagPath = Path();
    flagPath.moveTo(stemX, stemTopY);
    flagPath.quadraticBezierTo(stemX + w * 0.18, stemTopY + h * 0.02, stemX + w * 0.22, stemTopY + h * 0.18);
    canvas.drawPath(flagPath, stroke);
  }

  void _paintSnapchat(Canvas canvas, double w, double h) {
    // Yellow background
    final bgPaint = Paint()..color = const Color(0xFFFFFC00);
    canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(0, 0, w, h), Radius.circular(w * 0.22)), bgPaint);

    final ghostPath = Path();
    // Simplified silhouette of Snapchat ghost
    ghostPath.moveTo(w * 0.50, h * 0.20);
    // Head top
    ghostPath.quadraticBezierTo(w * 0.68, h * 0.20, w * 0.68, h * 0.44);
    // Right arm
    ghostPath.quadraticBezierTo(w * 0.82, h * 0.50, w * 0.72, h * 0.58);
    ghostPath.quadraticBezierTo(w * 0.68, h * 0.56, w * 0.66, h * 0.64);
    // Right wave
    ghostPath.quadraticBezierTo(w * 0.74, h * 0.78, w * 0.62, h * 0.78);
    // Bottom waves
    ghostPath.quadraticBezierTo(w * 0.56, h * 0.82, w * 0.50, h * 0.78);
    ghostPath.quadraticBezierTo(w * 0.44, h * 0.82, w * 0.38, h * 0.78);
    ghostPath.quadraticBezierTo(w * 0.26, h * 0.78, w * 0.34, h * 0.64);
    // Left arm
    ghostPath.quadraticBezierTo(w * 0.32, h * 0.56, w * 0.28, h * 0.58);
    ghostPath.quadraticBezierTo(w * 0.18, h * 0.50, w * 0.32, h * 0.44);
    // Head left
    ghostPath.quadraticBezierTo(w * 0.32, h * 0.20, w * 0.50, h * 0.20);
    ghostPath.close();

    final whiteFill = Paint()..color = Colors.white;
    final blackStroke = Paint()
      ..color = Colors.black
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1.5, w * 0.05)
      ..strokeJoin = StrokeJoin.round;

    canvas.drawPath(ghostPath, whiteFill);
    canvas.drawPath(ghostPath, blackStroke);
  }

  void _paintX(Canvas canvas, double w, double h) {
    // Matte black background
    final bgPaint = Paint()..color = const Color(0xFF000000);
    canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(0, 0, w, h), Radius.circular(w * 0.22)), bgPaint);

    // Authentic stylized X logo
    final whitePaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1.8, w * 0.08)
      ..strokeCap = StrokeCap.square;

    final xPath1 = Path();
    xPath1.moveTo(w * 0.26, h * 0.24);
    xPath1.lineTo(w * 0.74, h * 0.76);
    canvas.drawPath(xPath1, whitePaint);

    final xPath2 = Path();
    xPath2.moveTo(w * 0.74, h * 0.24);
    xPath2.lineTo(w * 0.26, h * 0.76);
    canvas.drawPath(xPath2, whitePaint);
  }

  void _paintWhatsApp(Canvas canvas, double w, double h) {
    // WhatsApp Green circle
    final bgPaint = Paint()..color = const Color(0xFF25D366);
    canvas.drawCircle(Offset(w / 2, h / 2), w / 2, bgPaint);

    // White speech bubble
    final bubbleRect = Rect.fromCenter(center: Offset(w * 0.50, h * 0.48), width: w * 0.62, height: h * 0.62);
    final whitePaint = Paint()..color = Colors.white;
    canvas.drawCircle(Offset(w * 0.50, h * 0.48), w * 0.30, whitePaint);

    final tailPath = Path();
    tailPath.moveTo(w * 0.30, h * 0.60);
    tailPath.lineTo(w * 0.20, h * 0.78);
    tailPath.lineTo(w * 0.42, h * 0.72);
    tailPath.close();
    canvas.drawPath(tailPath, whitePaint);

    // Green phone icon inside
    final textPainter = TextPainter(
      text: TextSpan(
        text: '📞',
        style: TextStyle(fontSize: w * 0.32),
      ),
      textDirection: TextDirection.ltr,
    );
    textPainter.layout();
    textPainter.paint(canvas, Offset(w * 0.34, h * 0.32));
  }

  void _paintTelegram(Canvas canvas, double w, double h) {
    // Telegram Sky Blue circle
    final bgPaint = Paint()..color = const Color(0xFF2AABEE);
    canvas.drawCircle(Offset(w / 2, h / 2), w / 2, bgPaint);

    // White paper plane
    final planePath = Path();
    planePath.moveTo(w * 0.22, h * 0.52);
    planePath.lineTo(w * 0.78, h * 0.25);
    planePath.lineTo(w * 0.58, h * 0.75);
    planePath.lineTo(w * 0.44, h * 0.62);
    planePath.lineTo(w * 0.42, h * 0.72);
    planePath.lineTo(w * 0.38, h * 0.58);
    planePath.close();

    final planePaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;
    canvas.drawPath(planePath, planePaint);
  }

  void _paintNetflix(Canvas canvas, double w, double h) {
    // Black background
    final bgPaint = Paint()..color = const Color(0xFF000000);
    canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(0, 0, w, h), Radius.circular(w * 0.22)), bgPaint);

    // Iconic Netflix 'N'
    final redPaint = Paint()..color = const Color(0xFFE50914);
    final darkRedPaint = Paint()..color = const Color(0xFFB81D24);

    final legW = w * 0.16;
    // Left vertical ribbon
    canvas.drawRect(Rect.fromLTWH(w * 0.26, h * 0.18, legW, h * 0.64), redPaint);
    // Right vertical ribbon
    canvas.drawRect(Rect.fromLTWH(w * 0.58, h * 0.18, legW, h * 0.64), redPaint);

    // Center diagonal ribbon
    final diagPath = Path();
    diagPath.moveTo(w * 0.26, h * 0.18);
    diagPath.lineTo(w * 0.26 + legW, h * 0.18);
    diagPath.lineTo(w * 0.58 + legW, h * 0.82);
    diagPath.lineTo(w * 0.58, h * 0.82);
    diagPath.close();
    canvas.drawPath(diagPath, darkRedPaint);
  }

  void _paintSpotify(Canvas canvas, double w, double h) {
    // Spotify vibrant green circle
    final bgPaint = Paint()..color = const Color(0xFF1DB954);
    canvas.drawCircle(Offset(w / 2, h / 2), w / 2, bgPaint);

    final wavePaint = Paint()
      ..color = Colors.black
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    // Top arc
    wavePaint.strokeWidth = math.max(1.8, w * 0.08);
    final path1 = Path();
    path1.moveTo(w * 0.26, h * 0.42);
    path1.quadraticBezierTo(w * 0.52, h * 0.32, w * 0.74, h * 0.46);
    canvas.drawPath(path1, wavePaint);

    // Middle arc
    wavePaint.strokeWidth = math.max(1.5, w * 0.07);
    final path2 = Path();
    path2.moveTo(w * 0.30, h * 0.55);
    path2.quadraticBezierTo(w * 0.52, h * 0.47, w * 0.70, h * 0.58);
    canvas.drawPath(path2, wavePaint);

    // Bottom arc
    wavePaint.strokeWidth = math.max(1.2, w * 0.06);
    final path3 = Path();
    path3.moveTo(w * 0.34, h * 0.68);
    path3.quadraticBezierTo(w * 0.52, h * 0.62, w * 0.66, h * 0.70);
    canvas.drawPath(path3, wavePaint);
  }

  void _paintDiscord(Canvas canvas, double w, double h) {
    // Discord blurple #5865F2
    final bgPaint = Paint()..color = const Color(0xFF5865F2);
    canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(0, 0, w, h), Radius.circular(w * 0.22)), bgPaint);

    // White Clyde Gamepad
    final clydePath = Path();
    clydePath.moveTo(w * 0.30, h * 0.32);
    clydePath.quadraticBezierTo(w * 0.50, h * 0.26, w * 0.70, h * 0.32);
    clydePath.quadraticBezierTo(w * 0.85, h * 0.42, w * 0.82, h * 0.68);
    clydePath.lineTo(w * 0.72, h * 0.64);
    clydePath.lineTo(w * 0.66, h * 0.72);
    clydePath.quadraticBezierTo(w * 0.50, h * 0.68, w * 0.34, h * 0.72);
    clydePath.lineTo(w * 0.28, h * 0.64);
    clydePath.lineTo(w * 0.18, h * 0.68);
    clydePath.quadraticBezierTo(w * 0.15, h * 0.42, w * 0.30, h * 0.32);
    clydePath.close();

    final whitePaint = Paint()..color = Colors.white;
    canvas.drawPath(clydePath, whitePaint);

    // Blurple eyes
    final eyePaint = Paint()..color = const Color(0xFF5865F2);
    canvas.drawOval(Rect.fromCenter(center: Offset(w * 0.40, h * 0.50), width: w * 0.12, height: h * 0.15), eyePaint);
    canvas.drawOval(Rect.fromCenter(center: Offset(w * 0.60, h * 0.50), width: w * 0.12, height: h * 0.15), eyePaint);
  }

  void _paintPinterest(Canvas canvas, double w, double h) {
    // Red circle
    final bgPaint = Paint()..color = const Color(0xFFE60023);
    canvas.drawCircle(Offset(w / 2, h / 2), w / 2, bgPaint);

    // Stylized cursive 'P'
    final textPainter = TextPainter(
      text: TextSpan(
        text: 'P',
        style: TextStyle(
          color: Colors.white,
          fontSize: w * 0.72,
          fontWeight: FontWeight.bold,
          fontStyle: FontStyle.italic,
          fontFamily: 'serif',
          height: 1.0,
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    textPainter.layout();
    textPainter.paint(canvas, Offset(w * 0.28, h * 0.12));
  }

  void _paintLinkedIn(Canvas canvas, double w, double h) {
    // LinkedIn blue
    final bgPaint = Paint()..color = const Color(0xFF0A66C2);
    canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(0, 0, w, h), Radius.circular(w * 0.22)), bgPaint);

    final textPainter = TextPainter(
      text: TextSpan(
        text: 'in',
        style: TextStyle(
          color: Colors.white,
          fontSize: w * 0.54,
          fontWeight: FontWeight.w900,
          fontFamily: 'sans-serif',
          height: 1.0,
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    textPainter.layout();
    textPainter.paint(canvas, Offset(w * 0.24, h * 0.24));
  }

  void _paintTwitch(Canvas canvas, double w, double h) {
    // Twitch violet
    final bgPaint = Paint()..color = const Color(0xFF9146FF);
    canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(0, 0, w, h), Radius.circular(w * 0.22)), bgPaint);

    // White chat bubble
    final bubblePath = Path();
    bubblePath.moveTo(w * 0.25, h * 0.24);
    bubblePath.lineTo(w * 0.75, h * 0.24);
    bubblePath.lineTo(w * 0.75, h * 0.64);
    bubblePath.lineTo(w * 0.58, h * 0.64);
    bubblePath.lineTo(w * 0.48, h * 0.76);
    bubblePath.lineTo(w * 0.48, h * 0.64);
    bubblePath.lineTo(w * 0.25, h * 0.64);
    bubblePath.close();

    final whitePaint = Paint()..color = Colors.white;
    canvas.drawPath(bubblePath, whitePaint);

    // Purple rectangular eyes
    final eyePaint = Paint()..color = const Color(0xFF9146FF);
    canvas.drawRect(Rect.fromLTWH(w * 0.42, h * 0.38, w * 0.08, h * 0.14), eyePaint);
    canvas.drawRect(Rect.fromLTWH(w * 0.58, h * 0.38, w * 0.08, h * 0.14), eyePaint);
  }

  void _paintPrimeVideo(Canvas canvas, double w, double h) {
    // Midnight Blue
    final bgPaint = Paint()..color = const Color(0xFF00053D);
    canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(0, 0, w, h), Radius.circular(w * 0.22)), bgPaint);

    // White 'prime' text
    final textPainter = TextPainter(
      text: TextSpan(
        text: 'prime',
        style: TextStyle(
          color: Colors.white,
          fontSize: w * 0.28,
          fontWeight: FontWeight.bold,
          letterSpacing: -0.5,
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    textPainter.layout();
    textPainter.paint(canvas, Offset(w * 0.15, h * 0.24));

    // Turquoise smile curve
    final smilePaint = Paint()
      ..color = const Color(0xFF00A8E1)
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1.4, w * 0.06)
      ..strokeCap = StrokeCap.round;

    final smilePath = Path();
    smilePath.moveTo(w * 0.16, h * 0.64);
    smilePath.quadraticBezierTo(w * 0.52, h * 0.76, w * 0.82, h * 0.60);
    canvas.drawPath(smilePath, smilePaint);
  }

  void _paintDisney(Canvas canvas, double w, double h) {
    // Deep royal blue gradient
    final bgPaint = Paint()
      ..shader = const LinearGradient(
        colors: [Color(0xFF040714), Color(0xFF113CCF)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ).createShader(Rect.fromLTWH(0, 0, w, h));
    canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(0, 0, w, h), Radius.circular(w * 0.22)), bgPaint);

    // White 'D+' text
    final textPainter = TextPainter(
      text: TextSpan(
        text: 'D+',
        style: TextStyle(
          color: Colors.white,
          fontSize: w * 0.44,
          fontWeight: FontWeight.w900,
          fontFamily: 'serif',
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    textPainter.layout();
    textPainter.paint(canvas, Offset(w * 0.22, h * 0.28));
  }

  void _paintThreads(Canvas canvas, double w, double h) {
    final bgPaint = Paint()..color = const Color(0xFF000000);
    canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(0, 0, w, h), Radius.circular(w * 0.22)), bgPaint);

    final textPainter = TextPainter(
      text: TextSpan(
        text: '@',
        style: TextStyle(
          color: Colors.white,
          fontSize: w * 0.68,
          fontWeight: FontWeight.bold,
          fontFamily: 'sans-serif',
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    textPainter.layout();
    textPainter.paint(canvas, Offset(w * 0.22, h * 0.14));
  }

  void _paintRoblox(Canvas canvas, double w, double h) {
    final bgPaint = Paint()..color = const Color(0xFF111111);
    canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(0, 0, w, h), Radius.circular(w * 0.22)), bgPaint);

    canvas.save();
    canvas.translate(w / 2, h / 2);
    canvas.rotate(-15 * math.pi / 180);

    final silverPaint = Paint()..color = const Color(0xFFDDDDDD);
    final darkPaint = Paint()..color = const Color(0xFF111111);

    final sqSize = w * 0.46;
    canvas.drawRect(Rect.fromCenter(center: Offset.zero, width: sqSize, height: sqSize), silverPaint);
    canvas.drawRect(Rect.fromCenter(center: Offset.zero, width: sqSize * 0.42, height: sqSize * 0.42), darkPaint);

    canvas.restore();
  }

  void _paintMessenger(Canvas canvas, double w, double h) {
    // Gradient
    final bgPaint = Paint()
      ..shader = const LinearGradient(
        colors: [Color(0xFF0084FF), Color(0xFFA033FF), Color(0xFFFF5A79)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ).createShader(Rect.fromLTWH(0, 0, w, h));
    canvas.drawCircle(Offset(w / 2, h / 2), w / 2, bgPaint);

    // Lightning bolt
    final boltPath = Path();
    boltPath.moveTo(w * 0.62, h * 0.32);
    boltPath.lineTo(w * 0.34, h * 0.54);
    boltPath.lineTo(w * 0.48, h * 0.54);
    boltPath.lineTo(w * 0.38, h * 0.72);
    boltPath.lineTo(w * 0.66, h * 0.48);
    boltPath.lineTo(w * 0.52, h * 0.48);
    boltPath.close();

    final whitePaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;
    canvas.drawPath(boltPath, whitePaint);
  }

  void _paintChrome(Canvas canvas, double w, double h) {
    final center = Offset(w / 2, h / 2);
    final r = w / 2;

    final redPaint = Paint()..color = const Color(0xFFEA4335);
    final greenPaint = Paint()..color = const Color(0xFF34A853);
    final yellowPaint = Paint()..color = const Color(0xFFFBBC05);
    final bluePaint = Paint()..color = const Color(0xFF4285F4);
    final whitePaint = Paint()..color = Colors.white;

    canvas.drawArc(Rect.fromCircle(center: center, radius: r), -math.pi / 2, 2 * math.pi / 3, true, redPaint);
    canvas.drawArc(Rect.fromCircle(center: center, radius: r), math.pi / 6, 2 * math.pi / 3, true, greenPaint);
    canvas.drawArc(Rect.fromCircle(center: center, radius: r), 5 * math.pi / 6, 2 * math.pi / 3, true, yellowPaint);

    canvas.drawCircle(center, r * 0.50, whitePaint);
    canvas.drawCircle(center, r * 0.40, bluePaint);
  }

  void _paintGeneric(Canvas canvas, double w, double h) {
    // Generate unique brand gradient based on appName
    final hash = appName.codeUnits.fold<int>(0, (prev, elem) => prev + elem);
    final hue1 = (hash * 37) % 360;
    final hue2 = (hue1 + 40) % 360;

    final c1 = HSLColor.fromAHSL(1.0, hue1.toDouble(), 0.70, 0.45).toColor();
    final c2 = HSLColor.fromAHSL(1.0, hue2.toDouble(), 0.75, 0.35).toColor();

    final bgPaint = Paint()
      ..shader = LinearGradient(
        colors: [c1, c2],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ).createShader(Rect.fromLTWH(0, 0, w, h));

    canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(0, 0, w, h), Radius.circular(w * 0.24)), bgPaint);

    final letter = appName.trim().isNotEmpty ? appName.trim()[0].toUpperCase() : 'A';
    final textPainter = TextPainter(
      text: TextSpan(
        text: letter,
        style: TextStyle(
          color: Colors.white,
          fontSize: w * 0.52,
          fontWeight: FontWeight.w800,
          fontFamily: 'sans-serif',
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    textPainter.layout();
    textPainter.paint(canvas, Offset((w - textPainter.width) / 2, (h - textPainter.height) / 2));
  }

  @override
  bool shouldRepaint(covariant _AppLogoPainter oldDelegate) {
    return oldDelegate.key != key || oldDelegate.size != size || oldDelegate.appName != appName;
  }
}
