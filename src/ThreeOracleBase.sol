// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IThreeOracleTarget} from "./interfaces/IThreeOracleTarget.sol";

/// @title ThreeOracleBase
/// @notice Reusable Foundry invariant base enforcing Reforms Studio's 3 Universal Oracles:
///         1. Global Conservation & Solvency
///         2. Universal Liveness (Zero Stuck State)
///         3. Partition & Split-Execution Invariance
abstract contract ThreeOracleBase {
    IThreeOracleTarget public oracleTarget;

    error SolvencyViolation(uint256 backing, uint256 claims, uint256 tolerance);
    error LivenessViolation(uint256 actorIndex);
    error PartitionViolation();

    function _setOracleTarget(IThreeOracleTarget target_) internal {
        oracleTarget = target_;
    }

    /// @notice Oracle 1: Backing assets must cover all claimable obligations within dust tolerance.
    function invariant_oracle1_globalConservationAndSolvency() public view {
        uint256 backing = oracleTarget.totalBackingAssets();
        uint256 claims = oracleTarget.totalClaimableAssets();
        uint256 tol = oracleTarget.dustTolerance();
        if (backing + tol < claims) {
            revert SolvencyViolation(backing, claims, tol);
        }
    }

    /// @notice Oracle 2: Every tracked actor with a live position must retain a non-reverting exit path.
    function invariant_oracle2_universalLivenessZeroStuckState() public {
        uint256 count = oracleTarget.actorCount();
        for (uint256 i = 0; i < count; ++i) {
            if (!oracleTarget.canActorExit(i)) {
                revert LivenessViolation(i);
            }
        }
    }

    /// @notice Oracle 3: Splitting an action into k sub-calls must not extract surplus value beyond k wei.
    function invariant_oracle3_partitionAndSplitInvariance() public view {
        if (oracleTarget.partitionViolationDetected()) {
            revert PartitionViolation();
        }
    }
}
