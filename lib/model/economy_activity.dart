enum EconomyEvent {
  wheelOpened('Wheel opens'),
  wheelFree('Free spins'),
  wheelRequested('Wheel video requests'),
  wheelVerified('Verified wheel spins'),
  researchBought('Research ranks purchased'),
  researchAffordable('Affordable next ranks seen'),
  researchUnavailable('Unaffordable next ranks seen'),
  themeBought('Themes purchased'),
  boostBought('Boosts purchased'),
  crateCollected('Crates collected'),
  noteCompleted('Field Notes objectives completed'),
  trailMilestone('Expedition milestones'),
  trailAbandoned('Expeditions abandoned');

  const EconomyEvent(this.label);
  final String label;
}

final class EconomyActivity {
  EconomyActivity(Map data)
    : counts = Map<String, int>.from(data['counts'] as Map? ?? {}),
      prizes = Map<String, int>.from(data['prizes'] as Map? ?? {}),
      balances = Map<String, int>.from(data['balances'] as Map? ?? {});

  final Map<String, int> counts, prizes, balances;

  void event(EconomyEvent event, int balance, [int count = 1]) {
    if (count <= 0) return;
    counts.update(event.name, (value) => value + count, ifAbsent: () => count);
    final band = switch (balance) {
      < 100 => '0–99',
      < 1000 => '100–999',
      < 10000 => '1,000–9,999',
      _ => '10,000+',
    };
    balances.update(band, (value) => value + 1, ifAbsent: () => 1);
  }

  void prize(String label, int count) =>
      prizes.update(label, (value) => value + count, ifAbsent: () => count);

  Map<String, Object> toJson() => {
    'counts': counts,
    'prizes': prizes,
    'balances': balances,
  };
}
