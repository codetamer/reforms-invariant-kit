// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {ThreeOracleBase} from "../src/ThreeOracleBase.sol";
import {LendingPoolAdapter} from "../src/adapters/LendingPoolAdapter.sol";

/// @notice Minimal reference overcollateralized lending pool for 3-oracle invariant testing.
contract ReferenceLendingPool {
    uint256 public totalCash;
    uint256 public totalBorrows;
    uint256 public totalReserves;
    uint256 public totalSupplyClaims;
    mapping(address => uint256) public userCollateral;
    mapping(address => uint256) public userDebt;

    function supply(address user, uint256 amount) external {
        totalCash += amount;
        totalSupplyClaims += amount;
        userCollateral[user] += amount;
    }

    function borrow(address user, uint256 amount) external {
        require(amount <= totalCash, "NO_LIQ");
        require((userDebt[user] + amount) * 100 <= userCollateral[user] * 75, "LTV");
        totalCash -= amount;
        totalBorrows += amount;
        userDebt[user] += amount;
    }

    function repay(address user, uint256 amount) external {
        uint256 debt = userDebt[user];
        uint256 paid = amount > debt ? debt : amount;
        userDebt[user] -= paid;
        totalBorrows -= paid;
        totalCash += paid;
    }

    function canLiquidateOrRepay(address user) external view returns (bool) {
        return userDebt[user] <= totalBorrows;
    }
}

contract LendingFuzzHandler is Test {
    ReferenceLendingPool public pool;
    address[] public actors;

    constructor(ReferenceLendingPool pool_, address[] memory actors_) {
        pool = pool_;
        actors = actors_;
    }

    function supply(uint256 actorSeed, uint256 amount) external {
        address actor = actors[actorSeed % actors.length];
        amount = bound(amount, 100, 1e12);
        pool.supply(actor, amount);
    }

    function borrow(uint256 actorSeed, uint256 amount) external {
        address actor = actors[actorSeed % actors.length];
        uint256 maxBorrow = (pool.userCollateral(actor) * 75) / 100;
        uint256 curDebt = pool.userDebt(actor);
        if (maxBorrow <= curDebt) return;
        uint256 avail = maxBorrow - curDebt;
        uint256 cash = pool.totalCash();
        uint256 cap = avail < cash ? avail : cash;
        if (cap == 0) return;
        amount = bound(amount, 1, cap);
        pool.borrow(actor, amount);
    }

    function repay(uint256 actorSeed, uint256 amount) external {
        address actor = actors[actorSeed % actors.length];
        uint256 debt = pool.userDebt(actor);
        if (debt == 0) return;
        amount = bound(amount, 1, debt);
        pool.repay(actor, amount);
    }
}

contract LendingThreeOracleTest is Test, ThreeOracleBase {
    ReferenceLendingPool public pool;
    LendingPoolAdapter public adapter;
    LendingFuzzHandler public handler;

    function setUp() public {
        pool = new ReferenceLendingPool();
        address[] memory actors = new address[](4);
        actors[0] = address(0xA11CE);
        actors[1] = address(0xB0B);
        actors[2] = address(0xCA5E);
        actors[3] = address(0xDA7E);
        adapter = new LendingPoolAdapter(address(pool), actors);
        handler = new LendingFuzzHandler(pool, actors);
        _setOracleTarget(adapter);
        targetContract(address(handler));
    }
}
