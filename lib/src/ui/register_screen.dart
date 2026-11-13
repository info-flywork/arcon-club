part of 'login_screen.dart';

/// ARCON Club kayıt ekranı: girişle aynı siyah-beyaz dil. Webdeki kayıtla aynı kurallar
/// (kullanıcı adı 3–30, geçerli e-posta, şifre en az 6); hesap yönetici onayıyla açılır.
/// Başarıda "Girişe dön" kullanıcı adını giriş ekranına geri verir.
class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key, required this.session});

  final SessionController session;

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _form = GlobalKey<FormState>();
  final _username = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _password2 = TextEditingController();
  bool _busy = false;
  bool _obscure = true;
  String? _error;
  String? _success;

  static final _emailRe = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
  static const _allowedEmailDomain = 'arcon-kozmetik.com.tr';

  @override
  void dispose() {
    _username.dispose();
    _email.dispose();
    _password.dispose();
    _password2.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy || !_form.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final msg = await widget.session.api.register(username: _username.text.trim(), email: _email.text.trim(), password: _password.text);
      if (mounted) setState(() => _success = msg);
    } on ArconApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = ArconMono.of(context);
    final pad = MediaQuery.paddingOf(context);
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: c.dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
      child: Scaffold(
        backgroundColor: c.bg,
        body: Stack(
          children: [
            CustomScrollView(
              physics: const ClampingScrollPhysics(),
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              slivers: [
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(24, pad.top + 12, 24, pad.bottom + 16),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 460),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _topBar(c),
                            const SizedBox(height: 28),
                            AnimatedSwitcher(
                              duration: const Duration(milliseconds: 280),
                              switchInCurve: Curves.easeOutCubic,
                              child: _success == null
                                  ? KeyedSubtree(key: const ValueKey('form'), child: _formView(c))
                                  : KeyedSubtree(key: const ValueKey('done'), child: _doneView(c)),
                            ),
                            const Spacer(),
                            const SizedBox(height: 24),
                            _Steps(c: c, done: _success != null),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            Positioned(
              left: 0,
              right: 0,
              top: 0,
              height: pad.top,
              child: ColoredBox(color: c.bg),
            ),
          ],
        ),
      ),
    );
  }

  Widget _topBar(ArconMono c) {
    return Row(
      children: [
        Material(
          color: c.field,
          shape: CircleBorder(side: BorderSide(color: c.line)),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: () => Navigator.of(context).maybePop(),
            child: SizedBox(
              width: 42,
              height: 42,
              child: Icon(Icons.arrow_back_rounded, size: 20, color: c.ink, semanticLabel: 'Geri'),
            ),
          ),
        ),
        const Spacer(),
        ArconClubMark(c: c, color: c.ink),
      ],
    );
  }

  Widget _formView(ArconMono c) {
    final kb = c.dark ? Brightness.dark : Brightness.light;
    return Form(
      key: _form,
      child: AutofillGroup(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Hesap oluştur', style: c.text(30, weight: FontWeight.w800, height: 1.1, spacing: -0.9)),
            const SizedBox(height: 8),
            Text('Birkaç bilgiyle ARCON CLUB\'a katıl.', style: c.text(14.5, color: c.muted, height: 1.5)),
            const SizedBox(height: 24),
            if (_error != null) ...[c.errorBox(_error!), const SizedBox(height: 16)],
            c.label('Kullanıcı adı'),
            TextFormField(
              controller: _username,
              autofillHints: const [AutofillHints.newUsername],
              keyboardAppearance: kb,
              autocorrect: false,
              textInputAction: TextInputAction.next,
              style: c.text(15, weight: FontWeight.w500),
              cursorColor: c.ink,
              decoration: c.input('örn. anilcan', Icons.person_outline_rounded),
              validator: (v) {
                final t = v?.trim() ?? '';
                if (t.isEmpty) return 'Kullanıcı adı gerekli';
                if (t.length < 3 || t.length > 30) return 'Kullanıcı adı 3–30 karakter olmalı';
                return null;
              },
            ),
            const SizedBox(height: 14),
            c.label('E-posta'),
            TextFormField(
              controller: _email,
              autofillHints: const [AutofillHints.email],
              keyboardType: TextInputType.emailAddress,
              keyboardAppearance: kb,
              autocorrect: false,
              textInputAction: TextInputAction.next,
              style: c.text(15, weight: FontWeight.w500),
              cursorColor: c.ink,
              decoration: c.input('adsoyad@$_allowedEmailDomain', Icons.mail_outline_rounded),
              validator: (v) {
                final t = v?.trim() ?? '';
                if (t.isEmpty) return 'E-posta gerekli';
                if (!_emailRe.hasMatch(t)) return 'Geçerli bir e-posta girin';
                if (!t.toLowerCase().endsWith('@$_allowedEmailDomain')) {
                  return 'Sadece @$_allowedEmailDomain adresleri kabul edilir';
                }
                return null;
              },
            ),
            const SizedBox(height: 14),
            c.label('Şifre'),
            TextFormField(
              controller: _password,
              obscureText: _obscure,
              autofillHints: const [AutofillHints.newPassword],
              keyboardAppearance: kb,
              textInputAction: TextInputAction.next,
              style: c.text(15, weight: FontWeight.w500),
              cursorColor: c.ink,
              decoration: c.input(
                'En az 6 karakter',
                Icons.lock_outline_rounded,
                suffix: IconButton(
                  tooltip: _obscure ? 'Şifreyi göster' : 'Şifreyi gizle',
                  icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined, color: c.muted, size: 20),
                  onPressed: () => setState(() => _obscure = !_obscure),
                ),
              ),
              validator: (v) {
                if (v == null || v.isEmpty) return 'Şifre gerekli';
                if (v.length < 6) return 'Şifre en az 6 karakter olmalı';
                return null;
              },
            ),
            const SizedBox(height: 14),
            c.label('Şifre tekrar'),
            TextFormField(
              controller: _password2,
              obscureText: _obscure,
              autofillHints: const [AutofillHints.newPassword],
              keyboardAppearance: kb,
              textInputAction: TextInputAction.done,
              onFieldSubmitted: (_) => _submit(),
              style: c.text(15, weight: FontWeight.w500),
              cursorColor: c.ink,
              decoration: c.input('Şifreni tekrar yaz', Icons.lock_reset_rounded),
              validator: (v) => v != _password.text ? 'Şifreler aynı değil' : null,
            ),
            const SizedBox(height: 22),
            c.primaryButton('Kayıt Ol', busy: _busy, onPressed: _submit),
            const SizedBox(height: 18),
            c.linkRow('Zaten hesabın var mı? ', 'Giriş yap', () => Navigator.of(context).maybePop()),
          ],
        ),
      ),
    );
  }

  Widget _doneView(ArconMono c) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(color: c.ink, borderRadius: BorderRadius.circular(18)),
            child: Icon(Icons.check_rounded, size: 34, color: c.bg),
          ),
        ),
        const SizedBox(height: 22),
        Text('Kaydın alındı', style: c.text(30, weight: FontWeight.w800, height: 1.1, spacing: -0.9)),
        const SizedBox(height: 10),
        Text(_success!, style: c.text(14.5, color: c.muted, height: 1.5)),
        const SizedBox(height: 18),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: c.field,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: c.line),
          ),
          child: Row(
            children: [
              Icon(Icons.person_outline_rounded, size: 20, color: c.muted),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'KULLANICI ADIN',
                      style: c.text(10, weight: FontWeight.w700, color: c.muted, spacing: 1),
                    ),
                    const SizedBox(height: 2),
                    Text(_username.text.trim(), style: c.text(15, weight: FontWeight.w600)),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        c.primaryButton('Girişe dön', busy: false, onPressed: () => Navigator.of(context).pop(_username.text.trim())),
      ],
    );
  }
}

/// Alttaki süreç şeridi: Kayıt → Onay → Giriş.
class _Steps extends StatelessWidget {
  const _Steps({required this.c, required this.done});
  final ArconMono c;
  final bool done;

  @override
  Widget build(BuildContext context) {
    const steps = [('Kayıt ol', 'Bilgilerini gir'), ('Onay', 'Hesabın açılır'), ('Giriş', 'Uygulamayı kullan')];
    final active = done ? 1 : 0;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      decoration: BoxDecoration(
        color: c.field,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: c.line),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < steps.length; i++) ...[
            if (i > 0)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: SizedBox(width: 14, child: Divider(height: 1, thickness: 1, color: c.line)),
              ),
            Expanded(child: _step(i, steps[i].$1, steps[i].$2, i < active, i == active)),
          ],
        ],
      ),
    );
  }

  Widget _step(int i, String title, String sub, bool complete, bool current) {
    final filled = complete || current;
    return Column(
      children: [
        Container(
          width: 26,
          height: 26,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: filled ? c.ink : Colors.transparent,
            shape: BoxShape.circle,
            border: Border.all(color: filled ? c.ink : c.line, width: 1.2),
          ),
          child: complete
              ? Icon(Icons.check_rounded, size: 15, color: c.bg)
              : Text(
                  '${i + 1}',
                  style: c.text(11.5, weight: FontWeight.w700, color: filled ? c.bg : c.muted, height: 1),
                ),
        ),
        const SizedBox(height: 8),
        Text(
          title,
          textAlign: TextAlign.center,
          style: c.text(11.5, weight: FontWeight.w700, height: 1.2),
        ),
        const SizedBox(height: 2),
        Text(
          sub,
          textAlign: TextAlign.center,
          style: c.text(10, color: c.muted, height: 1.25),
        ),
      ],
    );
  }
}
