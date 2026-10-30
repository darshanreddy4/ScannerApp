class CoinSnapshot {
  const CoinSnapshot({this.balance = 0, this.adsToday = 0, this.passUntil, this.passMinutes, this.passProgress = 0});
  final int balance;

  /// Rewarded videos already watched for coins today.
  final int adsToday;

  /// When the running pass ends, or null when there is none.
  final DateTime? passUntil;

  /// The pass that videos are being counted for today, and how many were watched so far.
  final int? passMinutes;
  final int passProgress;
}

abstract interface class CoinWallet {
  Future<CoinSnapshot> read();

  /// Adds coins for a completed rewarded video and counts it against today's limit.
  Future<CoinSnapshot> earnFromAd(int coins);

  /// Takes [coins] if the balance covers them. Returns false, and changes nothing, otherwise.
  Future<bool> spend(int coins);

  /// Gives back [coins] that were spent on something that did not happen. Not counted as a video.
  Future<void> refund(int coins);

  /// Adds the day's free [coins] once; returns how many were added, 0 when they were already given today.
  Future<int> claimDaily(int coins);

  /// Counts a watched video for the pass of [minutes] ([needed] videos). When the last one is watched the pass starts, or
  /// grows when one is already running, and the count starts again.
  Future<CoinSnapshot> countPassVideo({required int minutes, required int needed, required Duration length});

  /// True, and used up, when the tool [id] has not yet had its free use today.
  Future<bool> useFreeDaily(String id);
}
