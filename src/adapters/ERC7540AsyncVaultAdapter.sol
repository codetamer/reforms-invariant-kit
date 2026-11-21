// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IThreeOracleTarget} from "../interfaces/IThreeOracleTarget.sol";

interface IERC7540Minimal {
    function totalAssets() external view returns (uint256);
    function totalSupply() external view returns (uint256);
    function pendingRedeemRequest(uint256 requestId, address controller) external view returns (uint256);
    function claimableRedeemRequest(uint256 requestId, address controller) external view returns (uint256);
    function convertToAssets(uint256 shares) external view returns (uint256);
    function previewRedeem(uint256 shares) external view returns (uint256);
    function isEpochSettled(uint256 requestId) external view returns (bool);
}

/// @title ERC7540AsyncVaultAdapter
/// @notice Tracks asynchronous ERC-7540 redeem queues to catch stuck-epoch liveness bugs
///         and unbacked claimable liabilities across epoch settlements.
contract ERC7540AsyncVaultAdapter is IThreeOracleTarget {
    IERC7540Minimal public immutable vault;
    address[] public actors;
    uint256 public activeEpoch;
    bool public partitionViolation;

    constructor(address vault_, address[] memory actors_) {
        vault = IERC7540Minimal(vault_);
        actors = actors_;
    }

    function advanceEpoch(uint256 nextEpoch) external {
        if (nextEpoch > activeEpoch) {
            activeEpoch = nextEpoch;
        }
    }

    function totalBackingAssets() external view override returns (uint256) {
        return vault.totalAssets();
    }

    function totalClaimableAssets() external view override returns (uint256) {
        uint256 totalClaims = vault.convertToAssets(vault.totalSupply());
        for (uint256 i = 0; i < actors.length; ++i) {
            uint256 claimableShares = vault.claimableRedeemRequest(activeEpoch, actors[i]);
            if (claimableShares > 0) {
                totalClaims += vault.previewRedeem(claimableShares);
            }
        }
        return totalClaims;
    }

    function dustTolerance() external view override returns (uint256) {
        return actors.length * 2 + 1;
    }

    function actorCount() external view override returns (uint256) {
        return actors.length;
    }

    /// @notice Oracle 2 for async queues: once an epoch is settled, zero pending shares may remain stuck.
    function canActorExit(uint256 index) external view override returns (bool) {
        if (!vault.isEpochSettled(activeEpoch)) return true;
        uint256 stuckPending = vault.pendingRedeemRequest(activeEpoch, actors[index]);
        return stuckPending == 0;
    }

    function partitionViolationDetected() external view override returns (bool) {
        return partitionViolation;
    }
}
