// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @notice Minimal interface of Gnosis Conditional Tokens (CTF), used by Polymarket on Polygon.
interface IConditionalTokens {
    function getOutcomeSlotCount(bytes32 conditionId) external view returns (uint256);
    function payoutNumerators(bytes32 conditionId, uint256 index) external view returns (uint256);
    function payoutDenominator(bytes32 conditionId) external view returns (uint256);
    function getCollectionId(bytes32 parentCollectionId, bytes32 conditionId, uint256 indexSet)
        external
        view
        returns (bytes32);
    function getPositionId(address collateralToken, bytes32 collectionId) external pure returns (uint256);
    function balanceOf(address owner, uint256 id) external view returns (uint256);
    function balanceOfBatch(address[] calldata owners, uint256[] calldata ids)
        external
        view
        returns (uint256[] memory);
}

/// @title PolymarketLens
/// @notice Read-only helper for Polymarket binary (YES/NO) markets on Polygon.
///         In one call it returns a wallet's YES/NO balances, market resolution status,
///         how much collateral can be redeemed after resolution and how much can be
///         merged back into collateral before resolution.
/// @dev Holds no funds and has no state-changing functions, so it is safe to deploy and use.
///      Works with standard CTF markets (collateral = USDC.e). For neg-risk markets deploy a
///      second instance with the NegRiskAdapter's wrapped collateral as `collateral`.
contract PolymarketLens {
    IConditionalTokens public immutable ctf;
    address public immutable collateral;

    uint256 private constant YES_INDEX_SET = 1; // 0b01 -> outcome 0
    uint256 private constant NO_INDEX_SET = 2; // 0b10 -> outcome 1

    struct MarketInfo {
        bytes32 conditionId;
        uint256 yesPositionId;
        uint256 noPositionId;
        uint256 outcomeSlotCount; // 0 = condition not prepared
        bool resolved;
        uint256 yesPayout; // payout numerator for YES (0 if unresolved)
        uint256 noPayout; // payout numerator for NO (0 if unresolved)
        uint256 payoutDenominator;
    }

    struct UserPosition {
        bytes32 conditionId;
        uint256 yesBalance;
        uint256 noBalance;
        bool resolved;
        uint256 redeemable; // collateral claimable via redeemPositions (resolved only)
        uint256 mergeable; // min(yes, no): collateral recoverable via mergePositions (unresolved only)
    }

    error NotBinaryMarket(bytes32 conditionId, uint256 outcomeSlotCount);

    constructor(address _ctf, address _collateral) {
        ctf = IConditionalTokens(_ctf);
        collateral = _collateral;
    }

    // ---------------------------------------------------------------------
    // Ids
    // ---------------------------------------------------------------------

    /// @notice Same formula as CTF.getConditionId.
    function getConditionId(address oracle, bytes32 questionId, uint256 outcomeSlotCount)
        external
        pure
        returns (bytes32)
    {
        return keccak256(abi.encodePacked(oracle, questionId, outcomeSlotCount));
    }

    /// @notice ERC1155 token ids of the YES and NO shares for a condition.
    function getPositionIds(bytes32 conditionId) public view returns (uint256 yesId, uint256 noId) {
        yesId = ctf.getPositionId(collateral, ctf.getCollectionId(bytes32(0), conditionId, YES_INDEX_SET));
        noId = ctf.getPositionId(collateral, ctf.getCollectionId(bytes32(0), conditionId, NO_INDEX_SET));
    }

    // ---------------------------------------------------------------------
    // Market
    // ---------------------------------------------------------------------

    function getMarket(bytes32 conditionId) public view returns (MarketInfo memory m) {
        m.conditionId = conditionId;
        m.outcomeSlotCount = ctf.getOutcomeSlotCount(conditionId);
        if (m.outcomeSlotCount == 0) return m; // unknown condition
        if (m.outcomeSlotCount != 2) revert NotBinaryMarket(conditionId, m.outcomeSlotCount);

        (m.yesPositionId, m.noPositionId) = getPositionIds(conditionId);
        m.payoutDenominator = ctf.payoutDenominator(conditionId);
        m.resolved = m.payoutDenominator != 0;
        if (m.resolved) {
            m.yesPayout = ctf.payoutNumerators(conditionId, 0);
            m.noPayout = ctf.payoutNumerators(conditionId, 1);
        }
    }

    function getMarkets(bytes32[] calldata conditionIds) external view returns (MarketInfo[] memory out) {
        out = new MarketInfo[](conditionIds.length);
        for (uint256 i; i < conditionIds.length; ++i) {
            out[i] = getMarket(conditionIds[i]);
        }
    }

    // ---------------------------------------------------------------------
    // User
    // ---------------------------------------------------------------------

    /// @notice Position computed from `conditionId` using this lens' default collateral.
    function getUserPosition(address user, bytes32 conditionId) public view returns (UserPosition memory p) {
        MarketInfo memory m = getMarket(conditionId);
        return _position(user, m, m.yesPositionId, m.noPositionId);
    }

    /// @notice Position using explicit ERC1155 token ids (Polymarket API field `clobTokenIds`:
    ///         first = YES, second = NO). Works for any collateral (USDC.e, pUSD, neg-risk).
    function getUserPositionByTokens(address user, bytes32 conditionId, uint256 yesTokenId, uint256 noTokenId)
        public
        view
        returns (UserPosition memory p)
    {
        return _position(user, getMarket(conditionId), yesTokenId, noTokenId);
    }

    function _position(address user, MarketInfo memory m, uint256 yesId, uint256 noId)
        internal
        view
        returns (UserPosition memory p)
    {
        p.conditionId = m.conditionId;
        if (m.outcomeSlotCount == 0) return p;

        address[] memory owners = new address[](2);
        uint256[] memory ids = new uint256[](2);
        owners[0] = user;
        owners[1] = user;
        ids[0] = yesId;
        ids[1] = noId;
        uint256[] memory bals = ctf.balanceOfBatch(owners, ids);

        p.yesBalance = bals[0];
        p.noBalance = bals[1];
        p.resolved = m.resolved;

        if (m.resolved) {
            p.redeemable = (p.yesBalance * m.yesPayout + p.noBalance * m.noPayout) / m.payoutDenominator;
        } else {
            p.mergeable = p.yesBalance < p.noBalance ? p.yesBalance : p.noBalance;
        }
    }

    /// @notice Positions of one wallet across many markets. Unknown conditions return zeros.
    function getUserPositions(address user, bytes32[] calldata conditionIds)
        external
        view
        returns (UserPosition[] memory out, uint256 totalRedeemable, uint256 totalMergeable)
    {
        out = new UserPosition[](conditionIds.length);
        for (uint256 i; i < conditionIds.length; ++i) {
            out[i] = getUserPosition(user, conditionIds[i]);
            totalRedeemable += out[i].redeemable;
            totalMergeable += out[i].mergeable;
        }
    }

    /// @notice Returns only the condition ids (from the given list) where the user has something to redeem.
    function getRedeemableConditions(address user, bytes32[] calldata conditionIds)
        external
        view
        returns (bytes32[] memory ready)
    {
        bytes32[] memory tmp = new bytes32[](conditionIds.length);
        uint256 n;
        for (uint256 i; i < conditionIds.length; ++i) {
            if (getUserPosition(user, conditionIds[i]).redeemable > 0) tmp[n++] = conditionIds[i];
        }
        ready = new bytes32[](n);
        for (uint256 i; i < n; ++i) ready[i] = tmp[i];
    }
}
