// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

interface IEggNFT {
    function layEgg(
        address to,
        uint8 rarity,
        uint8 species,
        uint64 hatchTime,
        uint256 parent1,
        uint256 parent2,
        bool isRotten
    ) external returns (uint256 tokenId);
}
