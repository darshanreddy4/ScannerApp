/// How the coin economy works. Coins have no cash value, cannot be moved to another person and live only on this phone.
abstract final class CoinRules {
  /// Coins earned for watching one rewarded video to the end.
  static const rewardPerAd = 10;

  /// Coins given the first time the app is used each day.
  static const dailyCoins = 3;

  /// Videos that can be watched for coins per calendar day; null means no limit.
  static const int? dailyAdCap = null;

  /// After paying for a tool, the same tool stays open for this long, so stepping out and back in is not charged twice.
  static const reopenGrace = Duration(minutes: 10);
}

/// What a tool costs. Scanning, saving, viewing, searching and sharing a PDF are never priced.
enum CoinTier {
  free(0),
  light(1),
  heavy(5);

  const CoinTier(this.cost);
  final int cost;
}

/// A tool or feature that costs coins for Free users. Premium users, and anyone with a pass, use it without coins.
class CoinFeature {
  const CoinFeature(this.id, this.label, this.tier, {this.reopenFree = true});

  final String id;
  final String label;
  final CoinTier tier;

  /// Whether paying for it keeps it open for [CoinRules.reopenGrace]; false for a cost that is per action, such as each new share.
  final bool reopenFree;

  int get cost => tier.cost;

  /// A light tool has one free use each day.
  bool get hasFreeDailyUse => tier == CoinTier.light;

  static const editSavedDocument = CoinFeature('edit-saved', 'Edit pages', CoinTier.heavy);
  static const qrShare = CoinFeature('qr-share', 'Share with a QR code', CoinTier.light, reopenFree: false);
  static const specialFilters = CoinFeature('special-filters', 'Special filters', CoinTier.light);
  static const readText = CoinFeature('ocr', 'OCR and translate', CoinTier.light);

  /// A tool from the Tools screen, named by its title.
  factory CoinFeature.tool(String title, CoinTier tier) => CoinFeature('tool:$title', title, tier);

  @override
  bool operator ==(Object other) => other is CoinFeature && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

/// Watching a fixed number of rewarded videos opens every tool and hides interstitial ads for a while.
class PassTier {
  const PassTier(this.minutes, this.videos);
  final int minutes;
  final int videos;

  Duration get duration => Duration(minutes: minutes);

  String get label => minutes < 60 ? '$minutes minutes' : (minutes == 60 ? '1 hour' : '${minutes ~/ 60} hours');

  @override
  bool operator ==(Object other) => other is PassTier && other.minutes == minutes;

  @override
  int get hashCode => minutes;
}

const passTiers = <PassTier>[PassTier(30, 5), PassTier(120, 12), PassTier(360, 20), PassTier(1440, 23)];

/// The filters that come with every scan and stay free; the others cost a coin.
const freeFilterNames = {'original', 'auto', 'magicColor', 'documentBw', 'grayscale'};
