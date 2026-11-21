// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {ThreeOracleBase} from "../src/ThreeOracleBase.sol";
import {ERC4626Adapter} from "../src/adapters/ERC4626Adapter.sol";

contract MockERC20 {
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        return true;
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        require(balanceOf[msg.sender] >= amount, "BAL");
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        require(balanceOf[from] >= amount, "BAL");
        uint256 allowed = allowance[from][msg.sender];
        if (allowed != type(uint256).max) {
            require(allowed >= amount, "ALLOW");
            allowance[from][msg.sender] = allowed - amount;
        }
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        return true;
    }
}

/// @notice Minimal reference ERC-4626 vault using virtual offset (1e6) to prevent inflation attacks.
contract ReferenceERC4626Vault {
    MockERC20 public immutable underlying;
    uint256 public totalSupply;
    mapping(address => uint256) public balanceOf;
    uint256 private constant VIRTUAL_SHARES = 1e6;
    uint256 private constant VIRTUAL_ASSETS = 1e6;

    constructor(MockERC20 underlying_) {
        underlying = underlying_;
    }

    function asset() external view returns (address) {
        return address(underlying);
    }

    function totalAssets() public view returns (uint256) {
        return underlying.balanceOf(address(this));
    }

    function convertToShares(uint256 assets) public view returns (uint256) {
        return (assets * (totalSupply + VIRTUAL_SHARES)) / (totalAssets() + VIRTUAL_ASSETS);
    }

    function convertToAssets(uint256 shares) public view returns (uint256) {
        return (shares * (totalAssets() + VIRTUAL_ASSETS)) / (totalSupply + VIRTUAL_SHARES);
    }

    function previewDeposit(uint256 assets) external view returns (uint256) {
        return convertToShares(assets);
    }

    function previewRedeem(uint256 shares) external view returns (uint256) {
        return convertToAssets(shares);
    }

    function deposit(uint256 assets, address receiver) external returns (uint256 shares) {
        shares = convertToShares(assets);
        require(underlying.transferFrom(msg.sender, address(this), assets), "XFER_IN");
        totalSupply += shares;
        balanceOf[receiver] += shares;
    }

    function redeem(uint256 shares, address receiver, address owner) external returns (uint256 assets) {
        require(msg.sender == owner, "OWNER");
        require(balanceOf[owner] >= shares, "INSUFFICIENT_SHARES");
        assets = convertToAssets(shares);
        balanceOf[owner] -= shares;
        totalSupply -= shares;
        require(underlying.transfer(receiver, assets), "XFER_OUT");
    }
}

contract VaultFuzzHandler is Test {
    MockERC20 public token;
    ReferenceERC4626Vault public vault;
    ERC4626Adapter public adapter;
    address[] public actors;

    constructor(MockERC20 token_, ReferenceERC4626Vault vault_, ERC4626Adapter adapter_, address[] memory actors_) {
        token = token_;
        vault = vault_;
        adapter = adapter_;
        actors = actors_;
    }

    function deposit(uint256 actorSeed, uint256 assets) external {
        address actor = actors[actorSeed % actors.length];
        uint256 bal = token.balanceOf(actor);
        if (bal < 2) return;
        assets = bound(assets, 1, bal);
        adapter.actDeposit(actorSeed, assets);
        vm.prank(actor);
        vault.deposit(assets, actor);
    }

    function redeem(uint256 actorSeed, uint256 shares) external {
        address actor = actors[actorSeed % actors.length];
        uint256 bal = vault.balanceOf(actor);
        if (bal == 0) return;
        shares = bound(shares, 1, bal);
        vm.prank(actor);
        uint256 out = vault.redeem(shares, actor, actor);
        adapter.recordRedeem(out);
    }

    function donateYield(uint256 amount) external {
        amount = bound(amount, 1, 1e9);
        token.mint(address(vault), amount);
    }
}

/// @title VaultThreeOracleTest
/// @notice Drop-in Foundry stateful invariant test using ThreeOracleBase.
contract VaultThreeOracleTest is Test, ThreeOracleBase {
    MockERC20 public token;
    ReferenceERC4626Vault public vault;
    ERC4626Adapter public adapter;
    VaultFuzzHandler public handler;

    function setUp() public {
        token = new MockERC20();
        vault = new ReferenceERC4626Vault(token);
        address[] memory actors = new address[](4);
        actors[0] = address(0xA11CE);
        actors[1] = address(0xB0B);
        actors[2] = address(0xCA5E);
        actors[3] = address(0xDAVE);

        for (uint256 i = 0; i < actors.length; ++i) {
            token.mint(actors[i], 1e12);
            vm.prank(actors[i]);
            token.approve(address(vault), type(uint256).max);
        }

        adapter = new ERC4626Adapter(address(vault), actors);
        handler = new VaultFuzzHandler(token, vault, adapter, actors);
        _setOracleTarget(adapter);
        targetContract(address(handler));
    }
}
