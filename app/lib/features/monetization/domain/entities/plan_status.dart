enum PlanStatus {
  free,
  premium;

  bool get showsAds => this == PlanStatus.free;
}
