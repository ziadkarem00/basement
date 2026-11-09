import 'package:flutter/material.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
final GlobalKey<ScaffoldMessengerState> scaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();

typedef RoomCleanupCallback = void Function();
RoomCleanupCallback? activeRoomCleanup;

bool _goingHome = false;

void resetGoingHome() {
  _goingHome = false;
}

Widget Function()? homeScreenBuilder;

class HomeScreenWrapper extends StatelessWidget {
  const HomeScreenWrapper({super.key});

  @override
  Widget build(BuildContext context) {
    resetGoingHome();
    if (homeScreenBuilder != null) {
      return homeScreenBuilder!();
    }
    return const Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: Text(
          'BASEMENT',
          style: TextStyle(
            color: Colors.white,
            fontSize: 32,
            letterSpacing: 6,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
}

void goHome({String? message}) {
  if (_goingHome) return;
  _goingHome = true;

  try {
    activeRoomCleanup?.call();
  } catch (_) {}
  activeRoomCleanup = null;

  navigatorKey.currentState?.pushAndRemoveUntil(
    MaterialPageRoute(builder: (_) => const HomeScreenWrapper()),
    (route) => false,
  );

  if (message != null && message.isNotEmpty) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      scaffoldMessengerKey.currentState?.showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: const Color(0xFF222222),
          duration: const Duration(seconds: 4),
        ),
      );
    });
  }
}

