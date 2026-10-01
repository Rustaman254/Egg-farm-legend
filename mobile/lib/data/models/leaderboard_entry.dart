class TopBattler {
  final String wallet;
  final int wins;
  final int total;

  const TopBattler({required this.wallet, required this.wins, required this.total});

  factory TopBattler.fromJson(Map<String, dynamic> json) => TopBattler(
        wallet: json['wallet'] as String,
        wins: json['wins'] as int? ?? 0,
        total: json['total'] as int? ?? 0,
      );
}

class TopEarner {
  final String wallet;
  final int sales;
  final String totalWei;

  const TopEarner({required this.wallet, required this.sales, required this.totalWei});

  factory TopEarner.fromJson(Map<String, dynamic> json) => TopEarner(
        wallet: json['wallet'] as String,
        sales: json['sales'] as int? ?? 0,
        totalWei: json['totalWei'] as String? ?? '0',
      );
}
