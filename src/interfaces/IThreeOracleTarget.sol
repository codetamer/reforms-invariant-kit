// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title IThreeOracleTarget
/// @notice Minimal surface required by ThreeOracleBase to check conservation,
///         liveness, and partition invariance across arbitrary DeFi targets.
interface IThreeOracleTarget {
    /// @notice Total real underlying assets held by the protocol.
    function totalBackingAssets() external view returns (uint256);

    /// @notice Total underlying asset claims owed to all users + fee receivers.
    function totalClaimableAssets() external view returns (uint256);

    /// @notice Allowed wei-level rounding tolerance (e.g., actor count).
    function dustTolerance() external view returns (uint256);

    /// @notice Number of active fuzz actors tracked by the handler.
    function actorCount() external view returns (uint256);

    /// @notice Returns whether actor `index` currently holds a live withdrawable claim
    ///         that can exit cleanly without reverting.
    function canActorExit(uint256 index) external returns (bool);

    /// @notice True if a split-execution witness detected strictly profitable split extraction
    ///         exceeding allowed rounding dust.
    function partitionViolationDetected() external view returns (bool);
}
