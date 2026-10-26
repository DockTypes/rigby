import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/models/user_profile.dart';
import '../../../core/services/auth_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../auth/screens/auth_screen.dart';
import '../../chat/screens/chat_screen.dart';
import '../widgets/rigby_logo.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _textCtrl;
  late Animation<double> _textFade;

  @override
  void initState() {
    super.initState();
    _textCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _textFade = CurvedAnimation(parent: _textCtrl, curve: Curves.easeOut);
  }

  @override
  void dispose() {
    _textCtrl.dispose();
    super.dispose();
  }

  Future<void> _onDrawComplete() async {
    if (!mounted) return;
    await _textCtrl.forward();
    await Future.delayed(const Duration(milliseconds: 500));
    if (!mounted) return;
    // Incomplete profile (e.g. after reinstall with clear SharedPreferences while
    // Firebase retains session) routes to AuthScreen to complete setup.
    final destination = AuthService.isLoggedIn && UserProfile.isComplete
        ? const ChatScreen()
        : const AuthScreen();
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        pageBuilder: (ctx, anim, sec) => destination,
        transitionDuration: const Duration(milliseconds: 600),
        transitionsBuilder: (ctx, anim, sec, child) => FadeTransition(
          opacity: CurvedAnimation(parent: anim, curve: Curves.easeInOut),
          child: child,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            RigbyLogo(
              size: 280,
              onDrawComplete: _onDrawComplete,
            ),
            const SizedBox(height: 24),
            FadeTransition(
              opacity: _textFade,
              child: Text(
                'Rigby',
                style: GoogleFonts.orbitron(
                  fontSize: 28,
                  fontWeight: FontWeight.w700,
                  color: AppColors.neonWhite,
                  letterSpacing: 12,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
