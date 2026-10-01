// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {IERC721Receiver} from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/// @title Marketplace
/// @notice Secondary market for EggNFT and CreatureNFT. Sellers escrow their NFT into this
///         contract on listing; buyers pay in native ARB. A 2.5% platform fee is taken on sale.
///         The Go backend indexer listens to Listed/Sold/Cancelled events and mirrors them into
///         Postgres for fast querying by the Flutter app.
contract Marketplace is Ownable, ReentrancyGuard, IERC721Receiver {
    uint16 public constant FEE_BPS = 250; // 2.5%
    uint16 public constant BPS_DENOMINATOR = 10_000;

    struct Listing {
        address seller;
        address nftContract;
        uint256 tokenId;
        uint256 price; // in wei (ARB)
        bool active;
    }

    uint256 private _nextListingId = 1;
    mapping(uint256 => Listing) public listings;
    mapping(address => bool) public allowedContracts;

    event ContractAllowed(address indexed nftContract, bool allowed);
    event Listed(uint256 indexed listingId, address indexed seller, address indexed nftContract, uint256 tokenId, uint256 price);
    event Sold(uint256 indexed listingId, address indexed buyer, address indexed seller, uint256 price, uint256 fee);
    event Cancelled(uint256 indexed listingId);

    error ContractNotAllowed();
    error NotSeller();
    error ListingNotActive();
    error InsufficientPayment(uint256 required, uint256 sent);
    error PriceMustBePositive();

    constructor(address admin) Ownable(admin) {}

    function setAllowedContract(address nftContract, bool allowed) external onlyOwner {
        allowedContracts[nftContract] = allowed;
        emit ContractAllowed(nftContract, allowed);
    }

    /// @notice List an egg or creature for sale. Transfers the NFT into escrow.
    ///         Caller must have approved this contract first (approve/setApprovalForAll).
    function listEgg(address nftContract, uint256 tokenId, uint256 price) external nonReentrant returns (uint256 listingId) {
        if (!allowedContracts[nftContract]) revert ContractNotAllowed();
        if (price == 0) revert PriceMustBePositive();

        IERC721(nftContract).safeTransferFrom(msg.sender, address(this), tokenId);

        listingId = _nextListingId++;
        listings[listingId] = Listing({
            seller: msg.sender,
            nftContract: nftContract,
            tokenId: tokenId,
            price: price,
            active: true
        });

        emit Listed(listingId, msg.sender, nftContract, tokenId, price);
    }

    function buyEgg(uint256 listingId) external payable nonReentrant {
        Listing storage listing = listings[listingId];
        if (!listing.active) revert ListingNotActive();
        if (msg.value < listing.price) revert InsufficientPayment(listing.price, msg.value);

        listing.active = false;

        uint256 fee = (listing.price * FEE_BPS) / BPS_DENOMINATOR;
        uint256 sellerProceeds = listing.price - fee;

        IERC721(listing.nftContract).safeTransferFrom(address(this), msg.sender, listing.tokenId);

        (bool paidSeller,) = listing.seller.call{value: sellerProceeds}("");
        require(paidSeller, "seller payment failed");
        (bool paidOwner,) = owner().call{value: fee}("");
        require(paidOwner, "fee payment failed");

        if (msg.value > listing.price) {
            (bool refunded,) = msg.sender.call{value: msg.value - listing.price}("");
            require(refunded, "refund failed");
        }

        emit Sold(listingId, msg.sender, listing.seller, listing.price, fee);
    }

    function cancelListing(uint256 listingId) external nonReentrant {
        Listing storage listing = listings[listingId];
        if (!listing.active) revert ListingNotActive();
        if (listing.seller != msg.sender) revert NotSeller();

        listing.active = false;
        IERC721(listing.nftContract).safeTransferFrom(address(this), msg.sender, listing.tokenId);

        emit Cancelled(listingId);
    }

    function getListing(uint256 listingId) external view returns (Listing memory) {
        return listings[listingId];
    }

    function onERC721Received(address, address, uint256, bytes calldata) external pure override returns (bytes4) {
        return IERC721Receiver.onERC721Received.selector;
    }
}
