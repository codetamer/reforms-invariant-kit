// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IThreeOracleTarget} from "../interfaces/IThreeOracleTarget.sol";

interface ILendingPoolMinimal {
    function totalCash() external view returns (uint256);
    function totalBorrows() external view returns (uint256);
    function totalReserves() external view returns (uint256);
    function totalSupplyClaims() external view returns (uint256);
    function userCollateral(address user) external view returns (uint256);
    function userDebt(address user) external view returns (uint256);
    function canLiquidateOrRepay(address user) external view returns (bool);
}

/// @title LendingPoolAdapter
/// @notice 3-oracle adapter for overcollateralized lending pools: verifies cash + borrows >= claims + reserves
///         and ensures every underwater or healthy borrower retains a clean repay/liquidation exit.
contract LendingPoolAdapter is IThreeOracleTarget {
    ILendingPoolMinimal public immutable pool;
    address[] public actors;
    bool public partitionViolation;

    constructor(address pool_, address[] memory actors_) {
        pool = ILendingPoolMinimal(pool_);
        actors = actors_;
    }

    function flagPartitionViolation() external {
        partitionViolation = true;
    }

    function totalBackingAssets() external view override returns (uint256) {
        return pool.totalCash() + pool.totalBorrows();
    }

    function totalClaimableAssets() external view override returns (uint256) {
        return pool.totalSupplyClaims() + pool.totalReserves();
    }

    function dustTolerance() external view override returns (uint256) {
        return actors.length + 1;
    }

    function actorCount() external view override returns (uint256) {
        return actors.length;
    }

    function canActorExit(uint256 index) external view override returns (bool) {
        address actor = actors[index];
        if (pool.userDebt(actor) == 0) return true;
        return pool.canLiquidateOrRepay(actor);
    }

    function partitionViolationDetected() external view override returns (bool) {
        return partitionViolation;
    }
}
