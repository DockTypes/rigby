import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/models/user_profile.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/services/auth_service.dart';
import '../../chat/screens/chat_screen.dart';
import '../../splash/widgets/rigby_logo_painter.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen>
    with SingleTickerProviderStateMixin {
  bool _isLogin = true;
  // Step 1: credentials; Step 2: student details.
  int _registerStep = 1;
  // True when user is authenticated in Firebase but local profile is missing (e.g. after reinstall).
  bool _completeProfileOnly = false;
  bool _loading = false;
  String? _error;

  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  bool _obscurePassword = true;
  bool _obscureConfirm = true;

  final _prenumeCtrl = TextEditingController();
  final _specializareCtrl = TextEditingController();
  final _grupaCtrl = TextEditingController();
  int _anul = 1;

  late AnimationController _formCtrl;
  late Animation<double> _formFade;
  late Animation<Offset> _formSlide;

  @override
  void initState() {
    super.initState();
    _formCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 280),
    );
    _formFade = CurvedAnimation(parent: _formCtrl, curve: Curves.easeOut);
    _formSlide = Tween<Offset>(
      begin: const Offset(0, 0.06),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _formCtrl, curve: Curves.easeOutCubic));

    // If user is authenticated in Firebase but local profile was cleared, skip directly to step 2.
    if (AuthService.isLoggedIn && !UserProfile.isComplete) {
      _completeProfileOnly = true;
      _isLogin = false;
      _registerStep = 2;
    }
    _formCtrl.forward();
  }

  @override
  void dispose() {
    _formCtrl.dispose();
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    _confirmCtrl.dispose();
    _prenumeCtrl.dispose();
    _specializareCtrl.dispose();
    _grupaCtrl.dispose();
    super.dispose();
  }

  void _switchMode(bool login) {
    if (_isLogin == login || _loading) return;
    _formCtrl.reverse().then((_) {
      if (!mounted) return;
      setState(() {
        _isLogin = login;
        _registerStep = 1;
        _error = null;
      });
      _formCtrl.forward();
    });
  }

  void _goToChat() {
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        pageBuilder: (ctx, anim, _) => const ChatScreen(),
        transitionDuration: const Duration(milliseconds: 500),
        transitionsBuilder: (ctx, anim, _, child) => FadeTransition(
          opacity: CurvedAnimation(parent: anim, curve: Curves.easeInOut),
          child: child,
        ),
      ),
    );
  }

  // On successful auth, proceed to chat if profile is complete, otherwise prompt step 2.
  Future<void> _continueAfterAuth() async {
    if (UserProfile.isComplete) {
      _goToChat();
      return;
    }
    await _formCtrl.reverse();
    if (!mounted) return;
    setState(() {
      _completeProfileOnly = true;
      _isLogin = false;
      _registerStep = 2;
      _loading = false;
      _error = null;
    });
    _formCtrl.forward();
  }

  Future<void> _doLogin() async {
    final email = _emailCtrl.text.trim();
    final password = _passwordCtrl.text;
    if (email.isEmpty || password.isEmpty) {
      setState(() => _error = 'Completează toate câmpurile.');
      return;
    }
    setState(() { _loading = true; _error = null; });
    final err = await AuthService.signInWithEmail(email, password);
    if (!mounted) return;
    if (err != null) {
      setState(() { _loading = false; _error = err; });
    } else {
      await _continueAfterAuth();
    }
  }

  Future<void> _onStep1Continue() async {
    final email = _emailCtrl.text.trim();
    final password = _passwordCtrl.text;
    final confirm = _confirmCtrl.text;

    if (email.isEmpty || password.isEmpty || confirm.isEmpty) {
      setState(() => _error = 'Completează toate câmpurile.');
      return;
    }
    if (password != confirm) {
      setState(() => _error = 'Parolele nu se potrivesc.');
      return;
    }
    if (password.length < 6) {
      setState(() => _error = 'Parola trebuie să aibă cel puțin 6 caractere.');
      return;
    }

    await _formCtrl.reverse();
    if (!mounted) return;
    setState(() { _registerStep = 2; _error = null; });
    _formCtrl.forward();
  }

  Future<void> _onStep2Submit() async {
    final prenume = _prenumeCtrl.text.trim();
    final specializare = _specializareCtrl.text.trim();
    final grupa = _grupaCtrl.text.trim();

    if (prenume.isEmpty || specializare.isEmpty || grupa.isEmpty) {
      setState(() => _error = 'Completează toate câmpurile.');
      return;
    }

    setState(() { _loading = true; _error = null; });

    // If user is already authenticated in Firebase, skip registration and save profile.
    if (!_completeProfileOnly) {
      final err = await AuthService.registerWithEmail(
        _emailCtrl.text.trim(),
        _passwordCtrl.text,
      );
      if (!mounted) return;
      if (err != null) {
        setState(() { _loading = false; _error = err; });
        return;
      }
    }

    UserProfile.prenume = prenume;
    UserProfile.specializare = specializare;
    UserProfile.anul = _anul;
    UserProfile.grupa = grupa;

    await AuthService.updateDisplayName(prenume);

    if (!mounted) return;
    _goToChat();
  }

  void _onBack() {
    _formCtrl.reverse().then((_) {
      if (!mounted) return;
      setState(() { _registerStep = 1; _error = null; });
      _formCtrl.forward();
    });
  }

  Future<void> _onGoogle() async {
    if (_loading) return;
    setState(() { _loading = true; _error = null; });
    final err = await AuthService.signInWithGoogle();
    if (!mounted) return;
    if (err != null) {
      setState(() { _loading = false; _error = err; });
    } else {
      await _continueAfterAuth();
    }
  }

  Future<void> _onForgotPassword() async {
    final email = _emailCtrl.text.trim();
    if (email.isEmpty) {
      setState(() => _error = 'Scrie emailul mai întâi, apoi apasă "Ai uitat parola?".');
      return;
    }
    setState(() { _loading = true; _error = null; });
    final err = await AuthService.sendPasswordReset(email);
    if (!mounted) return;
    setState(() { _loading = false; });
    if (err != null) {
      setState(() => _error = err);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Email de resetare trimis! Verifică inbox-ul.'),
          backgroundColor: AppColors.surface,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  bool get _isStep2 => !_isLogin && _registerStep == 2;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: SingleChildScrollView(
          physics: const ClampingScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: MediaQuery.of(context).size.height -
                  MediaQuery.of(context).padding.top -
                  MediaQuery.of(context).padding.bottom,
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const SizedBox(height: 48),

                const _Logo(),
                const SizedBox(height: 12),
                Text(
                  'RIGBY',
                  style: GoogleFonts.orbitron(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: AppColors.neonWhite,
                    letterSpacing: 10,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'asistentul tău AI',
                  style: TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 12,
                    letterSpacing: 1.5,
                  ),
                ),

                const SizedBox(height: 40),

                _TabPicker(isLogin: _isLogin, onChanged: _switchMode),

                const SizedBox(height: 28),

                if (_isStep2) ...[
                  _StepIndicator(step: _registerStep),
                  const SizedBox(height: 20),
                ],

                FadeTransition(
                  opacity: _formFade,
                  child: SlideTransition(
                    position: _formSlide,
                    child: _buildForm(),
                  ),
                ),

                AnimatedSize(
                  duration: const Duration(milliseconds: 220),
                  child: _error != null
                      ? Padding(
                          padding: const EdgeInsets.only(top: 14),
                          child: Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 10),
                            decoration: BoxDecoration(
                              color: const Color(0xFF2A0A0A),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                  color: const Color(0xFF5A1A1A), width: 0.5),
                            ),
                            child: Text(
                              _error!,
                              style: const TextStyle(
                                color: Color(0xFFFF6B6B),
                                fontSize: 12.5,
                              ),
                            ),
                          ),
                        )
                      : const SizedBox.shrink(),
                ),

                const SizedBox(height: 20),

                if (_loading)
                  const SizedBox(
                    height: 52,
                    child: Center(
                      child: SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppColors.neonWhite,
                        ),
                      ),
                    ),
                  ),

                if (!_loading && !_isStep2) ...[
                  Row(children: [
                    Expanded(child: Divider(color: AppColors.border, thickness: 0.5)),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      child: Text('sau',
                          style: TextStyle(color: AppColors.textMuted, fontSize: 11)),
                    ),
                    Expanded(child: Divider(color: AppColors.border, thickness: 0.5)),
                  ]),
                  const SizedBox(height: 20),
                  _GoogleButton(onTap: _onGoogle),
                ],

                const SizedBox(height: 28),

                if (!_isStep2)
                  GestureDetector(
                    onTap: _loading ? null : _goToChat,
                    child: Text(
                      'Continuă fără cont',
                      style: TextStyle(
                        color: AppColors.textMuted,
                        fontSize: 12,
                        decoration: TextDecoration.underline,
                        decorationColor: AppColors.textMuted,
                      ),
                    ),
                  ),

                const SizedBox(height: 40),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildForm() {
    if (_isLogin) {
      return _LoginForm(
        emailCtrl: _emailCtrl,
        passwordCtrl: _passwordCtrl,
        obscurePassword: _obscurePassword,
        onToggleObscure: () => setState(() => _obscurePassword = !_obscurePassword),
        onSubmit: _doLogin,
        onForgotPassword: _onForgotPassword,
      );
    }
    if (_registerStep == 1) {
      return _RegisterStep1Form(
        emailCtrl: _emailCtrl,
        passwordCtrl: _passwordCtrl,
        confirmCtrl: _confirmCtrl,
        obscurePassword: _obscurePassword,
        obscureConfirm: _obscureConfirm,
        onTogglePassword: () => setState(() => _obscurePassword = !_obscurePassword),
        onToggleConfirm: () => setState(() => _obscureConfirm = !_obscureConfirm),
        onSubmit: _onStep1Continue,
      );
    }
    return _RegisterStep2Form(
      prenumeCtrl: _prenumeCtrl,
      specializareCtrl: _specializareCtrl,
      grupaCtrl: _grupaCtrl,
      anul: _anul,
      onAnulChanged: (v) => setState(() => _anul = v),
      onSubmit: _onStep2Submit,
      onBack: _onBack,
    );
  }
}


class _StepIndicator extends StatelessWidget {
  final int step;
  const _StepIndicator({required this.step});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _dot(active: step == 1),
        const SizedBox(width: 8),
        _dot(active: step == 2),
      ],
    );
  }

  Widget _dot({required bool active}) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      width: active ? 20 : 6,
      height: 6,
      decoration: BoxDecoration(
        color: active
            ? AppColors.neonWhite
            : AppColors.neonWhite.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(3),
      ),
    );
  }
}


class _Logo extends StatelessWidget {
  const _Logo();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 80,
      height: 80,
      child: CustomPaint(
        size: const Size(80, 80),
        painter: RigbyLogoPainter(
          progress: 1.0,
          mouthOpen: 0.08,
          deconstructFactor: 0.0,
          shockwaveFactor: 0.0,
          tiltX: 0.0,
          tiltY: 0.0,
          thinkingPhase: 0.0,
          eyeCloseFactor: 0.0,
        ),
      ),
    );
  }
}


class _TabPicker extends StatelessWidget {
  final bool isLogin;
  final ValueChanged<bool> onChanged;

  const _TabPicker({required this.isLogin, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 44,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border, width: 0.5),
      ),
      child: Row(
        children: [
          _Tab(label: 'Intră în cont', selected: isLogin, onTap: () => onChanged(true)),
          _Tab(label: 'Cont nou', selected: !isLogin, onTap: () => onChanged(false)),
        ],
      ),
    );
  }
}

class _Tab extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _Tab({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeInOutCubic,
          margin: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            color: selected
                ? AppColors.neonWhite.withValues(alpha: 0.10)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(11),
            border: selected
                ? Border.all(
                    color: AppColors.neonWhite.withValues(alpha: 0.18),
                    width: 0.5)
                : null,
          ),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                color: selected ? AppColors.neonWhite : AppColors.textMuted,
                fontSize: 12.5,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                letterSpacing: 0.3,
              ),
            ),
          ),
        ),
      ),
    );
  }
}


class _InputField extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final IconData icon;
  final bool obscure;
  final VoidCallback? onToggleObscure;
  final TextInputType keyboardType;
  final TextInputAction textInputAction;
  final VoidCallback? onSubmitted;

  const _InputField({
    required this.controller,
    required this.hint,
    required this.icon,
    this.obscure = false,
    this.onToggleObscure,
    this.keyboardType = TextInputType.text,
    this.textInputAction = TextInputAction.next,
    this.onSubmitted,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border, width: 0.5),
      ),
      child: TextField(
        controller: controller,
        obscureText: obscure,
        keyboardType: keyboardType,
        textInputAction: textInputAction,
        onSubmitted: onSubmitted != null ? (_) => onSubmitted!() : null,
        style: const TextStyle(
          color: AppColors.neonWhite,
          fontSize: 14,
          fontWeight: FontWeight.w400,
        ),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: TextStyle(color: AppColors.textMuted, fontSize: 14),
          prefixIcon: Icon(icon, size: 18, color: AppColors.textMuted),
          suffixIcon: onToggleObscure != null
              ? GestureDetector(
                  onTap: onToggleObscure,
                  child: Icon(
                    obscure
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined,
                    size: 18,
                    color: AppColors.textMuted,
                  ),
                )
              : null,
          border: InputBorder.none,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        ),
        cursorColor: AppColors.neonWhite,
        cursorWidth: 1.5,
      ),
    );
  }
}


class _PrimaryButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  final IconData? trailingIcon;

  const _PrimaryButton({
    required this.label,
    required this.onTap,
    this.trailingIcon,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        height: 52,
        decoration: BoxDecoration(
          color: AppColors.neonWhite,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: AppColors.neonWhite.withValues(alpha: 0.12),
              blurRadius: 20,
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              label,
              style: const TextStyle(
                color: AppColors.background,
                fontSize: 14,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.5,
              ),
            ),
            if (trailingIcon != null) ...[
              const SizedBox(width: 6),
              Icon(trailingIcon, size: 16, color: AppColors.background),
            ],
          ],
        ),
      ),
    );
  }
}


class _YearPicker extends StatelessWidget {
  final int selected;
  final ValueChanged<int> onChanged;

  const _YearPicker({required this.selected, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border, width: 0.5),
      ),
      padding: const EdgeInsets.all(4),
      child: Row(
        children: List.generate(4, (i) {
          final year = i + 1;
          final isSelected = year == selected;
          return Expanded(
            child: GestureDetector(
              onTap: () => onChanged(year),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                height: 40,
                decoration: BoxDecoration(
                  color: isSelected
                      ? AppColors.neonWhite.withValues(alpha: 0.12)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(10),
                  border: isSelected
                      ? Border.all(
                          color: AppColors.neonWhite.withValues(alpha: 0.2),
                          width: 0.5)
                      : null,
                ),
                child: Center(
                  child: Text(
                    'An $year',
                    style: TextStyle(
                      color: isSelected ? AppColors.neonWhite : AppColors.textMuted,
                      fontSize: 12,
                      fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                    ),
                  ),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}


class _GoogleButton extends StatelessWidget {
  final VoidCallback onTap;
  const _GoogleButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        height: 52,
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.border, width: 0.5),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const _GoogleLogo(size: 18),
            const SizedBox(width: 10),
            Text(
              'Continuă cu Google',
              style: TextStyle(
                color: AppColors.neonWhiteDim,
                fontSize: 13.5,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GoogleLogo extends StatelessWidget {
  final double size;
  const _GoogleLogo({required this.size});

  @override
  Widget build(BuildContext context) =>
      CustomPaint(size: Size(size, size), painter: _GoogleLogoPainter());
}

class _GoogleLogoPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final r = size.width / 2;
    const sw = 2.2;
    const pi = 3.14159265;

    void arc(Color color, double start, double sweep) {
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: r - sw / 2),
        start,
        sweep,
        false,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = sw
          ..strokeCap = StrokeCap.round,
      );
    }

    arc(const Color(0xFF4285F4), -pi / 6, pi * 2 / 3);
    arc(const Color(0xFF34A853), pi / 2, pi * 2 / 3);
    arc(const Color(0xFFFBBC05), pi * 7 / 6, pi * 2 / 3);
    arc(const Color(0xFFEA4335), -pi * 5 / 6, pi * 2 / 3);
  }

  @override
  bool shouldRepaint(covariant CustomPainter _) => false;
}


class _LoginForm extends StatelessWidget {
  final TextEditingController emailCtrl;
  final TextEditingController passwordCtrl;
  final bool obscurePassword;
  final VoidCallback onToggleObscure;
  final VoidCallback onSubmit;
  final VoidCallback onForgotPassword;

  const _LoginForm({
    required this.emailCtrl,
    required this.passwordCtrl,
    required this.obscurePassword,
    required this.onToggleObscure,
    required this.onSubmit,
    required this.onForgotPassword,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _InputField(
          controller: emailCtrl,
          hint: 'Adresă email',
          icon: Icons.mail_outline_rounded,
          keyboardType: TextInputType.emailAddress,
        ),
        const SizedBox(height: 12),
        _InputField(
          controller: passwordCtrl,
          hint: 'Parolă',
          icon: Icons.lock_outline_rounded,
          obscure: obscurePassword,
          onToggleObscure: onToggleObscure,
          textInputAction: TextInputAction.done,
          onSubmitted: onSubmit,
        ),
        Align(
          alignment: Alignment.centerRight,
          child: GestureDetector(
            onTap: onForgotPassword,
            child: Padding(
              padding: const EdgeInsets.only(top: 10, bottom: 20),
              child: Text(
                'Ai uitat parola?',
                style: TextStyle(
                  color: AppColors.textMuted,
                  fontSize: 12,
                  decoration: TextDecoration.underline,
                  decorationColor: AppColors.textMuted,
                ),
              ),
            ),
          ),
        ),
        _PrimaryButton(label: 'Intră în cont', onTap: onSubmit),
      ],
    );
  }
}


class _RegisterStep1Form extends StatelessWidget {
  final TextEditingController emailCtrl;
  final TextEditingController passwordCtrl;
  final TextEditingController confirmCtrl;
  final bool obscurePassword;
  final bool obscureConfirm;
  final VoidCallback onTogglePassword;
  final VoidCallback onToggleConfirm;
  final VoidCallback onSubmit;

  const _RegisterStep1Form({
    required this.emailCtrl,
    required this.passwordCtrl,
    required this.confirmCtrl,
    required this.obscurePassword,
    required this.obscureConfirm,
    required this.onTogglePassword,
    required this.onToggleConfirm,
    required this.onSubmit,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _InputField(
          controller: emailCtrl,
          hint: 'Adresă email',
          icon: Icons.mail_outline_rounded,
          keyboardType: TextInputType.emailAddress,
        ),
        const SizedBox(height: 12),
        _InputField(
          controller: passwordCtrl,
          hint: 'Parolă',
          icon: Icons.lock_outline_rounded,
          obscure: obscurePassword,
          onToggleObscure: onTogglePassword,
        ),
        const SizedBox(height: 12),
        _InputField(
          controller: confirmCtrl,
          hint: 'Confirmă parola',
          icon: Icons.lock_outline_rounded,
          obscure: obscureConfirm,
          onToggleObscure: onToggleConfirm,
          textInputAction: TextInputAction.done,
          onSubmitted: onSubmit,
        ),
        const SizedBox(height: 20),
        _PrimaryButton(
          label: 'Continuă',
          onTap: onSubmit,
          trailingIcon: Icons.arrow_forward_rounded,
        ),
      ],
    );
  }
}


class _RegisterStep2Form extends StatelessWidget {
  final TextEditingController prenumeCtrl;
  final TextEditingController specializareCtrl;
  final TextEditingController grupaCtrl;
  final int anul;
  final ValueChanged<int> onAnulChanged;
  final VoidCallback onSubmit;
  final VoidCallback onBack;

  const _RegisterStep2Form({
    required this.prenumeCtrl,
    required this.specializareCtrl,
    required this.grupaCtrl,
    required this.anul,
    required this.onAnulChanged,
    required this.onSubmit,
    required this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Spune-mi despre tine',
          style: TextStyle(
            color: AppColors.neonWhite,
            fontSize: 16,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.3,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Rigby va folosi aceste date pentru a te ajuta mai bine.',
          style: TextStyle(
            color: AppColors.textMuted,
            fontSize: 12,
          ),
        ),
        const SizedBox(height: 20),

        _InputField(
          controller: prenumeCtrl,
          hint: 'Prenume',
          icon: Icons.person_outline_rounded,
        ),
        const SizedBox(height: 12),
        _InputField(
          controller: specializareCtrl,
          hint: 'Specializare (ex: Informatică, Computer Science, Matematică-Informatică)',
          icon: Icons.school_outlined,
        ),
        const SizedBox(height: 16),

        Text(
          'Anul de studiu',
          style: TextStyle(
            color: AppColors.textMuted,
            fontSize: 12,
            letterSpacing: 0.3,
          ),
        ),
        const SizedBox(height: 8),
        _YearPicker(selected: anul, onChanged: onAnulChanged),
        const SizedBox(height: 12),

        _InputField(
          controller: grupaCtrl,
          hint: 'Grupă (ex: 311, 412A)',
          icon: Icons.groups_outlined,
          textInputAction: TextInputAction.done,
          onSubmitted: onSubmit,
        ),
        const SizedBox(height: 20),

        _PrimaryButton(label: 'Creează cont', onTap: onSubmit),
        const SizedBox(height: 14),

        Center(
          child: GestureDetector(
            onTap: onBack,
            child: Text(
              '← Înapoi',
              style: TextStyle(
                color: AppColors.textMuted,
                fontSize: 12.5,
                decoration: TextDecoration.underline,
                decorationColor: AppColors.textMuted,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
