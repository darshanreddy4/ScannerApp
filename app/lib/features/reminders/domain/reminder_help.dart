/// What to tell the owner of a phone whose maker is known to stop apps in the background, and whether the maker has its own screen for it.
class ReminderHelp {
  const ReminderHelp({required this.maker, required this.hint, required this.hasMakerScreen});

  /// The maker's name for the button, empty for a phone with no special advice.
  final String maker;
  final String hint;
  final bool hasMakerScreen;
}

const _generic = 'Allow Doculoom to start by itself and to run in the background.';

/// Advice by maker. Xiaomi, Oppo, Vivo, Huawei and some other makers add a second layer of battery saving on top of Android, and it can
/// stop alarms of an app that is not allowed.
ReminderHelp reminderHelpFor(String maker) {
  final m = maker.toLowerCase().trim();
  ReminderHelp known(String name, String hint) => ReminderHelp(maker: name, hint: hint, hasMakerScreen: true);
  if (m.contains('xiaomi') || m.contains('redmi') || m.contains('poco')) {
    return known('Xiaomi', 'Turn on Autostart for Doculoom, and in its battery settings choose No restrictions.');
  }
  if (m.contains('oppo') || m.contains('realme') || m.contains('oneplus')) {
    return known(
      m.contains('realme') ? 'Realme' : (m.contains('oneplus') ? 'OnePlus' : 'Oppo'),
      'Allow auto-launch and background activity for Doculoom, and do not let battery saving close it.',
    );
  }
  if (m.contains('vivo') || m.contains('iqoo')) {
    return known('Vivo', 'Allow Doculoom to start by itself and to run in the background, and allow high background power use.');
  }
  if (m.contains('huawei') || m.contains('honor')) {
    return known(
      m.contains('honor') ? 'Honor' : 'Huawei',
      'Set Doculoom to manage manually, and allow auto-launch, secondary launch and running in the background.',
    );
  }
  if (m.contains('samsung')) {
    return known('Samsung', 'Make sure Doculoom is not in Sleeping apps or Deep sleeping apps, and set its battery use to Unrestricted.');
  }
  if (m.contains('asus') ||
      m.contains('tecno') ||
      m.contains('infinix') ||
      m.contains('itel') ||
      m.contains('transsion') ||
      m.contains('lenovo') ||
      m.contains('meizu') ||
      m.contains('letv')) {
    return known(m.contains('asus') ? 'Asus' : (m.contains('lenovo') ? 'Lenovo' : (m.contains('meizu') ? 'Meizu' : 'Tecno, Infinix or Itel')), _generic);
  }
  return const ReminderHelp(maker: '', hint: _generic, hasMakerScreen: false);
}
