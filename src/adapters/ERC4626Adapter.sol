// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IThreeOracleTarget} from "../interfaces/IThreeOracleTarget.sol";

interface IERC4626Minimal {
    function asset() external view returns (address);
    function totalAssets() external view returns (uint256);
    function totalSupply() external view returns (uint256);
    function balanceOf(address owner) external view returns (uint256);
    function convertToAssets(uint256 shares) external view returns (uint256);
    function previewDeposit(uint256 assets) external view returns (uint256);
    function previewRedeem(uint256 shares) external view returns (uint256);
    function deposit(uint256 assets, address receiver) external returns (uint256);
    function redeem(uint256 shares, address receiver, address owner) external returns (uint256);
}

interface IERC20Minimal {
    function balanceOf(address account) external view returns (uint256);
    function approve(address spender, uint256 value) external returns (bool);
}

/// @title ERC4626Adapter
/// @notice Stateful multi-actor handler & 3-oracle adapter for any ERC-4626 vault.
contract ERC4626Adapter is IThreeOracleTarget {
    IERC4626Minimal public immutable vault;
    IERC20Minimal public immutable underlying;
    address[] public actors;
    bool public partitionViolation;

    uint256 public ghostDeposited;
    uint256 public ghostWithdrawn;

    constructor(address vault_, address[] memory actors_) {
        vault = IERC4626Minimal(vault_);
        underlying = IERC20Minimal(vault.asset());
        actors = actors_;
    }

    /// @notice Bounded multi-actor deposit with inline split-execution check (Oracle 3).
    function actDeposit(uint256 actorSeed, uint256 assets) external {
        address actor = actors[actorSeed % actors.length];
        uint256 bal = underlying.balanceOf(actor);
        if (bal < 2) return;
        assets = (assets % bal) + 1;

        // Oracle 3 witness: compare atomic previewDeposit(assets) vs 2-way split
        if (assets >= 2) {
            uint256 halfA = assets / 2;
            uint256 halfB = assets - halfA;
            uint256 wholeShares = vault.previewDeposit(assets);
            uint256 splitShares = vault.previewDeposit(halfA) + vault.previewDeposit(halfB);
            // Splitting must never mint strictly more shares than atomic deposit rounding
            if (splitShares > wholeShares) {
                partitionViolation = true;
            }
        }

        // Caller (Foundry vm.prank in test harness) executes deposit
        ghostDeposited += assets;
    }

    /// @notice Tracks redemption accounting for ghost-state reconciliation.
    function recordRedeem(uint256 assetsOut) external {
        ghostWithdrawn += assetsOut;
    }

    function totalBackingAssets() external view override returns (uint256) {
        return underlying.balanceOf(address(vault));
    }

    function totalClaimableAssets() external view override returns (uint256) {
        uint256 supply = vault.totalSupply();
        if (supply == 0) return 0;
        return vault.convertToAssets(supply);
    }

    function dustTolerance() external view override returns (uint256) {
        return actors.length + 1;
    }

    function actorCount() external view override returns (uint256) {
        return actors.length;
    }

    function canActorExit(uint256 index) external view override returns (bool) {
        address actor = actors[index];
        uint256 shares = vault.balanceOf(actor);
        if (shares == 0) return true;
        uint256 previewOut = vault.previewRedeem(shares);
        return previewOut <= underlying.balanceOf(address(vault));
    }

    function partitionViolationDetected() external view override returns (bool) {
        return partitionViolation;
    }
}
