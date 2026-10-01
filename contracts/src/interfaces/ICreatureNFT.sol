// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

interface ICreatureNFT {
    /// @param startingHappiness Set by EggNFT based on how well the egg was cared for during
    ///        incubation (see EggNFT.CARE_HAPPINESS_BONUS_THRESHOLD) -- a perfectly-tended egg
    ///        hatches into a happier creature than one that was neglected down to the wire.
    function mintFromEgg(address to, uint8 species, uint8 rarity, uint8 startingHappiness)
        external
        returns (uint256 creatureId);
    function ownerOf(uint256 tokenId) external view returns (address);
    function getRarity(uint256 tokenId) external view returns (uint8);
    function getBreedCount(uint256 tokenId) external view returns (uint16);
    function isAlive(uint256 tokenId) external view returns (bool);
}
