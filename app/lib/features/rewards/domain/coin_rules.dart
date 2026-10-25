/// How the coin economy works. Coins have no cash value and live only on this phone.
abstract final class CoinRules {
  /// Coins earned for watching one rewarded video to the end.
  static const rewardPerAd = 10;

  /// Videos that can be watched for coins per calendar day; null means no limit. Set a number here to add a limit later.
  static const int? dailyAdCap = null;
}

/// Features that cost coins for Free users. Premium users use them without coins.
enum CoinFeature {
  editSavedDocument(5, 'Edit pages'),
  qrShare(2, 'Share with a QR code');

  const CoinFeature(this.cost, this.label);
  final int cost;
  final String label;
}
