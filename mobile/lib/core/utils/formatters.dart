/// Shared display helpers for the read-only stats screens (Dex/Leaderboard/Activity), which all
/// render wei-denominated amounts, wallet addresses, and relative timestamps the same way the
/// webapp does (see webapp/src/pages/ActivityPage.tsx).
String shortAddress(String address) {
  if (address.length < 10) return address;
  return '${address.substring(0, 6)}...${address.substring(address.length - 4)}';
}

double weiToWhole(String wei) {
  final value = BigInt.tryParse(wei) ?? BigInt.zero;
  return value / BigInt.from(10).pow(18);
}

String timeAgo(String iso) {
  final time = DateTime.tryParse(iso);
  if (time == null) return '';
  final seconds = DateTime.now().difference(time).inSeconds.clamp(0, 1 << 31);
  if (seconds < 60) return 'just now';
  if (seconds < 3600) return '${seconds ~/ 60}m ago';
  if (seconds < 86400) return '${seconds ~/ 3600}h ago';
  return '${seconds ~/ 86400}d ago';
}
