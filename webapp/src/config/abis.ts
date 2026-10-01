// Minimal ABI fragments for the functions/reads the web app actually calls. Mirrors
// mobile/lib/core/blockchain/contract_abis.dart -- keep the two in sync if the contracts change.
// `as const` gives viem/wagmi full type inference on function names and args.

export const feedTokenAbi = [
  {
    type: 'function',
    name: 'balanceOf',
    stateMutability: 'view',
    inputs: [{ name: 'account', type: 'address' }],
    outputs: [{ name: '', type: 'uint256' }],
  },
] as const

export const creatureNftAbi = [
  {
    type: 'function',
    name: 'feedCreature',
    stateMutability: 'nonpayable',
    inputs: [{ name: 'tokenId', type: 'uint256' }],
    outputs: [],
  },
  {
    type: 'function',
    name: 'layEgg',
    stateMutability: 'nonpayable',
    inputs: [{ name: 'tokenId', type: 'uint256' }],
    outputs: [{ name: 'eggTokenId', type: 'uint256' }],
  },
  {
    type: 'function',
    name: 'breedCreatures',
    stateMutability: 'payable',
    inputs: [
      { name: 'parent1', type: 'uint256' },
      { name: 'parent2', type: 'uint256' },
    ],
    outputs: [{ name: 'eggTokenId', type: 'uint256' }],
  },
  {
    type: 'function',
    name: 'approve',
    stateMutability: 'nonpayable',
    inputs: [
      { name: 'to', type: 'address' },
      { name: 'tokenId', type: 'uint256' },
    ],
    outputs: [],
  },
  {
    type: 'function',
    name: 'getHunger',
    stateMutability: 'view',
    inputs: [{ name: 'tokenId', type: 'uint256' }],
    outputs: [{ name: '', type: 'uint8' }],
  },
  { type: 'error', name: 'CreatureNotHungry', inputs: [{ name: 'tokenId', type: 'uint256' }] },
  {
    type: 'error',
    name: 'CreatureUnhappy',
    inputs: [
      { name: 'tokenId', type: 'uint256' },
      { name: 'happiness', type: 'uint8' },
      { name: 'required', type: 'uint8' },
    ],
  },
] as const

export const eggNftAbi = [
  {
    type: 'function',
    name: 'hatchEgg',
    stateMutability: 'nonpayable',
    inputs: [{ name: 'tokenId', type: 'uint256' }],
    outputs: [{ name: 'creatureId', type: 'uint256' }],
  },
  {
    type: 'function',
    name: 'discardRottenEgg',
    stateMutability: 'nonpayable',
    inputs: [{ name: 'tokenId', type: 'uint256' }],
    outputs: [],
  },
  {
    type: 'function',
    name: 'approve',
    stateMutability: 'nonpayable',
    inputs: [
      { name: 'to', type: 'address' },
      { name: 'tokenId', type: 'uint256' },
    ],
    outputs: [],
  },
  {
    type: 'function',
    name: 'tendEgg',
    stateMutability: 'nonpayable',
    inputs: [{ name: 'tokenId', type: 'uint256' }],
    outputs: [],
  },
  {
    type: 'function',
    name: 'getCareLevel',
    stateMutability: 'view',
    inputs: [{ name: 'tokenId', type: 'uint256' }],
    outputs: [{ name: '', type: 'uint8' }],
  },
  {
    type: 'function',
    name: 'speedUpHatch',
    stateMutability: 'payable',
    inputs: [{ name: 'tokenId', type: 'uint256' }],
    outputs: [],
  },
] as const

export const marketplaceAbi = [
  {
    type: 'function',
    name: 'listEgg',
    stateMutability: 'nonpayable',
    inputs: [
      { name: 'nftContract', type: 'address' },
      { name: 'tokenId', type: 'uint256' },
      { name: 'price', type: 'uint256' },
    ],
    outputs: [{ name: 'listingId', type: 'uint256' }],
  },
  {
    type: 'function',
    name: 'buyEgg',
    stateMutability: 'payable',
    inputs: [{ name: 'listingId', type: 'uint256' }],
    outputs: [],
  },
  {
    type: 'function',
    name: 'cancelListing',
    stateMutability: 'nonpayable',
    inputs: [{ name: 'listingId', type: 'uint256' }],
    outputs: [],
  },
] as const

export const battleEscrowAbi = [
  {
    type: 'function',
    name: 'createEscrow',
    stateMutability: 'payable',
    inputs: [{ name: 'challengeId', type: 'uint256' }],
    outputs: [],
  },
  {
    type: 'function',
    name: 'acceptEscrow',
    stateMutability: 'payable',
    inputs: [{ name: 'challengeId', type: 'uint256' }],
    outputs: [],
  },
  {
    type: 'function',
    name: 'cancelEscrow',
    stateMutability: 'nonpayable',
    inputs: [{ name: 'challengeId', type: 'uint256' }],
    outputs: [],
  },
  {
    type: 'function',
    name: 'escrows',
    stateMutability: 'view',
    inputs: [{ name: '', type: 'uint256' }],
    outputs: [
      { name: 'challenger', type: 'address' },
      { name: 'acceptor', type: 'address' },
      { name: 'wagerWei', type: 'uint256' },
      { name: 'status', type: 'uint8' },
    ],
  },
] as const
