class Listing {
  final int listingId;
  final String nftContract;
  final int tokenId;
  final String kind; // "egg" | "creature"
  final String sellerAddress;
  final String priceWei;
  final bool isActive;
  final DateTime listedAt;

  const Listing({
    required this.listingId,
    required this.nftContract,
    required this.tokenId,
    required this.kind,
    required this.sellerAddress,
    required this.priceWei,
    required this.isActive,
    required this.listedAt,
  });

  double get priceInArb {
    final wei = BigInt.tryParse(priceWei) ?? BigInt.zero;
    return wei / BigInt.from(10).pow(18);
  }

  factory Listing.fromJson(Map<String, dynamic> json) {
    return Listing(
      listingId: json['listingId'] as int,
      nftContract: json['nftContract'] as String,
      tokenId: json['tokenId'] as int,
      kind: json['kind'] as String,
      sellerAddress: json['sellerAddress'] as String,
      priceWei: json['priceWei'] as String,
      isActive: json['isActive'] as bool,
      listedAt: DateTime.parse(json['listedAt'] as String),
    );
  }
}

/// Helper for converting a human-entered ARB price (e.g. "0.15") to the wei BigInt the
/// Marketplace contract expects, without floating-point rounding error.
BigInt arbToWei(String arbAmount) {
  final parts = arbAmount.trim().split('.');
  final whole = BigInt.tryParse(parts[0].isEmpty ? '0' : parts[0]) ?? BigInt.zero;

  var fraction = BigInt.zero;
  if (parts.length > 1) {
    final fractionDigits = parts[1].length > 18 ? parts[1].substring(0, 18) : parts[1].padRight(18, '0');
    fraction = BigInt.tryParse(fractionDigits) ?? BigInt.zero;
  }
  return whole * BigInt.from(10).pow(18) + fraction;
}
