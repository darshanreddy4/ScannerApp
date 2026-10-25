/// Build-time settings. Pass them with `--dart-define` (see README, "Publishing to Google Play").
abstract final class AppConfig {
  /// Real in-app purchases are not built yet. While false, no purchase screen is shown and every
  /// feature is available to everyone, so the app never offers something it cannot deliver.
  static const billingEnabled = bool.fromEnvironment('BILLING_ENABLED');

  /// Package name of the app on Google Play, used for the Rate us and Share links.
  static const androidPackage = 'com.scanvault.scanvault';

  /// Link people get when they share the app or rate it. The default is the Google Play page; set it if you publish elsewhere.
  static const appStoreUrl = String.fromEnvironment('APP_STORE_URL', defaultValue: 'https://play.google.com/store/apps/details?id=$androidPackage');

  /// Public web address of the privacy policy. Google Play requires one; set it before publishing.
  static const privacyPolicyUrl = String.fromEnvironment('PRIVACY_POLICY_URL');

  /// Public web address of the terms and conditions (optional, the in-app copy is always available).
  static const termsUrl = String.fromEnvironment('TERMS_URL');

  /// Contact shown on the privacy, terms and support pages.
  static const supportEmail = String.fromEnvironment('SUPPORT_EMAIL');

  /// Address of the sharing relay (see `relay/` and the README). Empty hides "Anywhere" in QR sharing.
  static const shareRelayUrl = String.fromEnvironment('SHARE_RELAY_URL');

  /// Free users can earn coins by watching rewarded videos and spend them on Premium features.
  static const rewardsEnabled = bool.fromEnvironment('REWARDS_ENABLED', defaultValue: true);

  // AdMob ad units. The defaults are Google's public test IDs, which are fine for development only.
  static const bannerAndroid = String.fromEnvironment('ADMOB_BANNER_ANDROID', defaultValue: 'ca-app-pub-3940256099942544/6300978111');
  static const interstitialAndroid = String.fromEnvironment('ADMOB_INTERSTITIAL_ANDROID', defaultValue: 'ca-app-pub-3940256099942544/1033173712');
  static const rewardedAndroid = String.fromEnvironment('ADMOB_REWARDED_ANDROID', defaultValue: 'ca-app-pub-3940256099942544/5224354917');
  static const rewardedIos = String.fromEnvironment('ADMOB_REWARDED_IOS', defaultValue: 'ca-app-pub-3940256099942544/1712485313');
  static const bannerIos = String.fromEnvironment('ADMOB_BANNER_IOS', defaultValue: 'ca-app-pub-3940256099942544/2934735716');
  static const interstitialIos = String.fromEnvironment('ADMOB_INTERSTITIAL_IOS', defaultValue: 'ca-app-pub-3940256099942544/4411468910');
}
