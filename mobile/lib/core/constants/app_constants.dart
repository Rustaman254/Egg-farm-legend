/// Contract addresses and network config, injected at build time via --dart-define so the
/// same code base can point at a fresh testnet deployment without editing source:
///   flutter run --dart-define=FEED_TOKEN_ADDRESS=0x... --dart-define=EGG_NFT_ADDRESS=0x... ...
class ChainConfig {
  ChainConfig._();

  static const rpcUrl = String.fromEnvironment(
    'ARBITRUM_SEPOLIA_RPC_URL',
    defaultValue: 'https://sepolia-rollup.arbitrum.io/rpc',
  );
  // Defaults to Arbitrum Sepolia; override with --dart-define=CHAIN_ID=31337 (and point rpcUrl at
  // a local Anvil node) to test against the same local chain the backend/webapp use in dev.
  static const chainId = int.fromEnvironment('CHAIN_ID', defaultValue: 421614);
  static String get chainHex => '0x${chainId.toRadixString(16)}';
  // CAIP-2 chain identifier WalletConnect namespaces expect (decimal, not hex).
  static const caip2ChainId = 'eip155:$chainId';

  static const feedTokenAddress = String.fromEnvironment('FEED_TOKEN_ADDRESS');
  static const eggNftAddress = String.fromEnvironment('EGG_NFT_ADDRESS');
  static const creatureNftAddress = String.fromEnvironment('CREATURE_NFT_ADDRESS');
  static const marketplaceAddress = String.fromEnvironment('MARKETPLACE_ADDRESS');

  // WalletConnect Cloud project ID (https://cloud.walletconnect.com). Required for pairing.
  static const walletConnectProjectId = String.fromEnvironment('WALLETCONNECT_PROJECT_ID');
}

class ApiConfig {
  ApiConfig._();

  static const baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://10.0.2.2:8080', // Android emulator loopback to host machine
  );
}

class GameConstants {
  GameConstants._();

  static const feedDecimals = 18;
  static const feedCostPerMeal = 5; // FEED, whole units
  static const breedArbCost = 0.01; // ETH-denominated ARB
  static const eggLayCooldownHours = 2;
  static const maxBreedCount = 7;
  static const maxRarity = 5;

  // 8 species per rarity tier (40 total, matching CreatureNFT.sol's SPECIES_PER_TIER). Keep in
  // sync with backend/internal/models.SpeciesNames and webapp/src/config/constants.ts. Each
  // individual egg/creature also gets its own generated nickname on top of this species name --
  // see displayName() below.
  static const speciesNames = [
    // Common: everyday real egg-layers, several animal classes for variety
    'Chicken', 'Duck', 'Quail', 'Goose', 'Turkey', 'Pigeon', 'Frog', 'Butterfly',
    // Uncommon: exotic real animals and genuine oddities
    'Peacock', 'Ostrich', 'Flamingo', 'Platypus', 'Echidna', 'Seahorse', 'Axolotl', 'Cuttlefish',
    // Rare: reptiles, lesser myth, and the first Animora-original species
    'Komodo Dragon', 'Cobra', 'Crocodile', 'Tortoise', 'Cockatrice', 'Flarepaw', 'Aquadew', 'Voltkit',
    // Epic: legendary beasts and evolved-feeling Animora originals
    'Phoenix', 'Griffin', 'Hydra', 'Chimera', 'Wyvern', 'Blazehorn', 'Frostbite', 'Genesplice',
    // Legendary: cosmic/world myth and mystical-tier Animora originals
    'Void Dragon', 'World Serpent', 'Qilin', 'Simurgh', 'Aetheron', 'Nebulisk', 'Chronox', 'Prismara',
  ];

  static const speciesEmoji = [
    '🐔', '🦆', '🐦', '🪿', '🦃', '🕊️', '🐸', '🦋',
    '🦚', '🦤', '🦩', '🦫', '🦔', '🐴🌊', '🦎💗', '🦑',
    '🦎', '🐍', '🐊', '🐢', '🐓🐍', '🔥🐾', '💧✨', '⚡🐾',
    '🐦‍🔥', '🦅🦁', '🐍🐍', '🦁🐐', '🐲', '🔥🐂', '❄️🦊', '🧬👾',
    '🐉🌌', '🌍🐍', '🦄🐉', '🦚🔥', '🌌✨', '🐉✨', '⏳⚙️', '💎🧚',
  ];

  /// "Chicken (Prisma)" -- species is the type, nickname is what makes this individual unique.
  static String displayName(int species, String? nickname) {
    final base = speciesName(species);
    return (nickname == null || nickname.isEmpty) ? base : '$base ($nickname)';
  }

  static String speciesName(int species) {
    if (species < 0 || species >= speciesNames.length) return 'Unknown';
    return speciesNames[species];
  }

  static String speciesEmojiFor(int species) {
    if (species < 0 || species >= speciesEmoji.length) return '❓';
    return speciesEmoji[species];
  }

  static const rarityLabels = ['', 'Common', 'Uncommon', 'Rare', 'Epic', 'Legendary'];
  static const rarityStars = ['', '⭐', '⭐⭐', '⭐⭐⭐', '⭐⭐⭐⭐', '⭐⭐⭐⭐⭐'];
}
