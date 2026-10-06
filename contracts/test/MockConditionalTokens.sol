// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @dev Simplified stand-in for Gnosis CTF, used only in tests.
contract MockConditionalTokens {
    mapping(bytes32 => uint256) public getOutcomeSlotCount;
    mapping(bytes32 => uint256[]) internal _numerators;
    mapping(bytes32 => uint256) public payoutDenominator;
    mapping(address => mapping(uint256 => uint256)) public balanceOf;

    function prepareCondition(address oracle, bytes32 questionId, uint256 slots) external returns (bytes32 id) {
        id = keccak256(abi.encodePacked(oracle, questionId, slots));
        getOutcomeSlotCount[id] = slots;
        _numerators[id] = new uint256[](slots);
    }

    function reportPayouts(bytes32 conditionId, uint256[] calldata payouts) external {
        uint256 den;
        for (uint256 i; i < payouts.length; ++i) {
            _numerators[conditionId][i] = payouts[i];
            den += payouts[i];
        }
        payoutDenominator[conditionId] = den;
    }

    function payoutNumerators(bytes32 conditionId, uint256 index) external view returns (uint256) {
        return _numerators[conditionId][index];
    }

    function getCollectionId(bytes32 parent, bytes32 conditionId, uint256 indexSet) public pure returns (bytes32) {
        return keccak256(abi.encodePacked(parent, conditionId, indexSet));
    }

    function getPositionId(address collateralToken, bytes32 collectionId) public pure returns (uint256) {
        return uint256(keccak256(abi.encodePacked(collateralToken, collectionId)));
    }

    function mint(address to, uint256 id, uint256 amount) external {
        balanceOf[to][id] += amount;
    }

    function balanceOfBatch(address[] calldata owners, uint256[] calldata ids)
        external
        view
        returns (uint256[] memory out)
    {
        out = new uint256[](owners.length);
        for (uint256 i; i < owners.length; ++i) out[i] = balanceOf[owners[i]][ids[i]];
    }
}
