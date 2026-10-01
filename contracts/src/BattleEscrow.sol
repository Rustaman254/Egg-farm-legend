// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/// @title BattleEscrow
/// @notice Trustless native-currency (ETH/ARB) escrow for Battle Arena PvP wagers. Combat itself
///         stays off-chain (the backend simulates the duel from each side's real, care-driven
///         stats -- see internal/services/battle) since that's cheap and instant; only the
///         money changing hands needs an on-chain guarantee neither side can renege on. A
///         challengeId here is always the same id as the backend's `battle_challenges.id` row --
///         the backend assigns it first (off-chain), then this contract is the on-chain ledger
///         for whatever wager that particular challenge carries.
/// @dev The RESOLVER_ROLE (the backend's signer) is the only thing that can release a resolved
///      escrow -- it can't touch an *unresolved* one (no wager can be seized/redirected before a
///      duel actually happens), and it can't pick winners the escrow didn't record participants
///      for. It never holds funds itself; every payout goes straight to a challenger, an
///      acceptor, or the treasury.
contract BattleEscrow is AccessControl, ReentrancyGuard {
    bytes32 public constant RESOLVER_ROLE = keccak256("RESOLVER_ROLE");

    enum Status {
        None,
        Open, // challenger has staked, waiting for an acceptor
        Accepted, // both sides have staked, waiting for the backend to resolve the duel
        Resolved,
        Cancelled
    }

    struct Escrow {
        address challenger;
        address acceptor;
        uint256 wagerWei; // what EACH side stakes; the pot is 2x this once accepted
        Status status;
    }

    mapping(uint256 => Escrow) public escrows;

    address public treasury;
    uint16 public rakeBps = 500; // 5% platform rake on the resolved pot, out of the pot itself
    uint16 public constant MAX_RAKE_BPS = 2000; // 20% hard cap -- can't be raised past this

    error EscrowAlreadyExists();
    error EscrowNotOpen();
    error EscrowNotAccepted();
    error NoWager();
    error WrongWagerAmount(uint256 expected, uint256 sent);
    error NotChallenger();
    error InvalidWinner();
    error PayoutFailed();
    error RakeTooHigh();
    error ZeroAddress();

    event EscrowCreated(uint256 indexed challengeId, address indexed challenger, uint256 wagerWei);
    event EscrowAccepted(uint256 indexed challengeId, address indexed acceptor);
    event EscrowResolved(uint256 indexed challengeId, address indexed winner, uint256 payoutWei, uint256 feeWei);
    event EscrowCancelled(uint256 indexed challengeId, address indexed challenger, uint256 refundWei);

    constructor(address admin, address resolver, address treasury_) {
        if (admin == address(0) || resolver == address(0) || treasury_ == address(0)) revert ZeroAddress();
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(RESOLVER_ROLE, resolver);
        treasury = treasury_;
    }

    /// @notice Challenger stakes their wager for a challenge the backend has already assigned an
    ///         id to. Reverts if this id already has an escrow (a challenge can only ever be
    ///         wagered once) or if no ETH was sent.
    function createEscrow(uint256 challengeId) external payable nonReentrant {
        if (escrows[challengeId].status != Status.None) revert EscrowAlreadyExists();
        if (msg.value == 0) revert NoWager();

        escrows[challengeId] = Escrow({challenger: msg.sender, acceptor: address(0), wagerWei: msg.value, status: Status.Open});
        emit EscrowCreated(challengeId, msg.sender, msg.value);
    }

    /// @notice Acceptor matches the challenger's exact stake. Both sides' funds now sit in this
    ///         contract until RESOLVER_ROLE resolves the duel.
    function acceptEscrow(uint256 challengeId) external payable nonReentrant {
        Escrow storage e = escrows[challengeId];
        if (e.status != Status.Open) revert EscrowNotOpen();
        if (msg.value != e.wagerWei) revert WrongWagerAmount(e.wagerWei, msg.value);

        e.acceptor = msg.sender;
        e.status = Status.Accepted;
        emit EscrowAccepted(challengeId, msg.sender);
    }

    /// @notice Releases a resolved duel's pot (minus the platform rake) to whichever side the
    ///         backend's off-chain combat simulation determined won. Only callable once, only by
    ///         the backend's resolver signer, only for an escrow both sides actually funded.
    function resolve(uint256 challengeId, address winner) external onlyRole(RESOLVER_ROLE) nonReentrant {
        Escrow storage e = escrows[challengeId];
        if (e.status != Status.Accepted) revert EscrowNotAccepted();
        if (winner != e.challenger && winner != e.acceptor) revert InvalidWinner();

        e.status = Status.Resolved;
        uint256 pot = e.wagerWei * 2;
        uint256 fee = (pot * rakeBps) / 10000;
        uint256 payout = pot - fee;

        (bool sentToWinner,) = payable(winner).call{value: payout}("");
        if (!sentToWinner) revert PayoutFailed();
        if (fee > 0) {
            (bool sentToTreasury,) = payable(treasury).call{value: fee}("");
            if (!sentToTreasury) revert PayoutFailed();
        }
        emit EscrowResolved(challengeId, winner, payout, fee);
    }

    /// @notice Refunds an unaccepted escrow -- either the challenger backing out, or the backend
    ///         reaping an expired challenge the same way it already expires unwagered ones.
    function cancelEscrow(uint256 challengeId) external nonReentrant {
        Escrow storage e = escrows[challengeId];
        if (e.status != Status.Open) revert EscrowNotOpen();
        if (msg.sender != e.challenger && !hasRole(RESOLVER_ROLE, msg.sender)) revert NotChallenger();

        e.status = Status.Cancelled;
        uint256 refund = e.wagerWei;
        (bool sent,) = payable(e.challenger).call{value: refund}("");
        if (!sent) revert PayoutFailed();
        emit EscrowCancelled(challengeId, e.challenger, refund);
    }

    function setTreasury(address treasury_) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (treasury_ == address(0)) revert ZeroAddress();
        treasury = treasury_;
    }

    function setRakeBps(uint16 bps) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (bps > MAX_RAKE_BPS) revert RakeTooHigh();
        rakeBps = bps;
    }
}
