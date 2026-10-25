class CoinSnapshot {
  const CoinSnapshot({this.balance = 0, this.adsToday = 0});
  final int balance;

  /// Rewarded videos already watched for coins today.
  final int adsToday;
}

abstract interface class CoinWallet {
  Future<CoinSnapshot> read();

  /// Adds coins for a completed rewarded video and counts it against today's limit.
  Future<CoinSnapshot> earnFromAd(int coins);

  /// Takes [coins] if the balance covers them. Returns false, and changes nothing, otherwise.
  Future<bool> spend(int coins);

  /// Gives back [coins] that were spent on something that did not happen. Not counted as a video.
  Future<void> refund(int coins);
}
