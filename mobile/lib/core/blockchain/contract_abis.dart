/// Minimal ABI fragments for the functions the app actually calls from the player's own
/// wallet (mint/view-only backend calls like mintReward live server-side, not here).
/// Kept as raw JSON strings rather than bundled assets so there's no asset-loading step.
class ContractAbis {
  ContractAbis._();

  static const feedToken = '''
  [
    {"type":"function","name":"balanceOf","stateMutability":"view",
     "inputs":[{"name":"account","type":"address"}],
     "outputs":[{"name":"","type":"uint256"}]},
    {"type":"function","name":"approve","stateMutability":"nonpayable",
     "inputs":[{"name":"spender","type":"address"},{"name":"amount","type":"uint256"}],
     "outputs":[{"name":"","type":"bool"}]}
  ]
  ''';

  static const creatureNft = '''
  [
    {"type":"function","name":"purchaseCreature","stateMutability":"payable",
     "inputs":[{"name":"rarityTier","type":"uint8"}],
     "outputs":[{"name":"tokenId","type":"uint256"}]},
    {"type":"function","name":"feedCreature","stateMutability":"nonpayable",
     "inputs":[{"name":"tokenId","type":"uint256"}],"outputs":[]},
    {"type":"function","name":"layEgg","stateMutability":"nonpayable",
     "inputs":[{"name":"tokenId","type":"uint256"}],
     "outputs":[{"name":"eggTokenId","type":"uint256"}]},
    {"type":"function","name":"breedCreatures","stateMutability":"payable",
     "inputs":[{"name":"parent1","type":"uint256"},{"name":"parent2","type":"uint256"}],
     "outputs":[{"name":"eggTokenId","type":"uint256"}]},
    {"type":"function","name":"approve","stateMutability":"nonpayable",
     "inputs":[{"name":"to","type":"address"},{"name":"tokenId","type":"uint256"}],"outputs":[]},
    {"type":"function","name":"getHunger","stateMutability":"view",
     "inputs":[{"name":"tokenId","type":"uint256"}],"outputs":[{"name":"","type":"uint8"}]}
  ]
  ''';

  static const eggNft = '''
  [
    {"type":"function","name":"hatchEgg","stateMutability":"nonpayable",
     "inputs":[{"name":"tokenId","type":"uint256"}],
     "outputs":[{"name":"creatureId","type":"uint256"}]},
    {"type":"function","name":"discardRottenEgg","stateMutability":"nonpayable",
     "inputs":[{"name":"tokenId","type":"uint256"}],"outputs":[]},
    {"type":"function","name":"approve","stateMutability":"nonpayable",
     "inputs":[{"name":"to","type":"address"},{"name":"tokenId","type":"uint256"}],"outputs":[]}
  ]
  ''';

  static const marketplace = '''
  [
    {"type":"function","name":"listEgg","stateMutability":"nonpayable",
     "inputs":[{"name":"nftContract","type":"address"},{"name":"tokenId","type":"uint256"},{"name":"price","type":"uint256"}],
     "outputs":[{"name":"listingId","type":"uint256"}]},
    {"type":"function","name":"buyEgg","stateMutability":"payable",
     "inputs":[{"name":"listingId","type":"uint256"}],"outputs":[]},
    {"type":"function","name":"cancelListing","stateMutability":"nonpayable",
     "inputs":[{"name":"listingId","type":"uint256"}],"outputs":[]}
  ]
  ''';
}
