# Reforms Invariant Kit (`reforms-invariant-kit`)

**MIT-licensed modular Foundry stateful invariant fuzzing kit** built by **Reforms Studio** (`@codetamer`) for Ethereum DeFi protocols (ERC-4626 tokenized vaults, ERC-7540 async redemption vaults, and overcollateralized lending pools).

## Why This Exists

Most protocol test suites check happy-path unit assertions and miss multi-step accounting drift, stuck withdrawal queues, and split-transaction rounding extraction. This kit provides drop-in Foundry adapters implementing **3 Universal Falsification Oracles**:

1. **Oracle 1 — Global Conservation & Solvency:** `backingAssets >= totalClaims + dustTolerance` and zero unbacked share/debt creation across interleaved deposits, withdrawals, donations, yield accrual, and liquidations.
2. **Oracle 2 — Universal Liveness (Zero Stuck State):** Every solvent actor with non-zero shares or fulfilled async claims can exit to zero balance within bounded epoch transitions without hitting reverts, underflows, or trapped dust.
3. **Oracle 3 — Partition & Split-Execution Invariance:** Splitting a single deposit/withdrawal `A` into `k` sub-calls `a_1 + ... + a_k = A` cannot yield strictly more shares or assets than the atomic call beyond `<= k` wei rounding tolerance.

## Repository Structure

```text
reforms-invariant-kit/
├── foundry.toml
├── LICENSE                                  # MIT
├── src/
│   ├── interfaces/IThreeOracleTarget.sol    # Minimal target interface
│   ├── ThreeOracleBase.sol                  # Reusable 3-oracle invariant core
│   └── adapters/
│       ├── ERC4626Adapter.sol               # Synchronous ERC-4626 vault adapter
│       ├── ERC7540AsyncVaultAdapter.sol     # Asynchronous request/claim vault adapter
│       └── LendingPoolAdapter.sol           # Collateralized lending & liquidation adapter
├── test/
│   ├── VaultThreeOracle.t.sol               # Foundry stateful multi-actor vault suite
│   └── LendingThreeOracle.t.sol             # Foundry stateful multi-actor lending suite
├── scripts/
│   └── verify_3_oracles.py                  # 256-bit Python mirror verifier (12,000 steps + fault-injection)
└── .github/workflows/invariants.yml         # CI workflow for Foundry + mirror verifier
```

## Quick Start

### 1. Run the Foundry Invariant Suite (Local)

```bash
forge install foundry-rs/forge-std --no-commit
forge test --match-path "test/*.t.sol" -vvv
```

### 2. Run the 12,000-Step 256-Bit Mirror Verifier & Fault-Injection Suite

No external dependencies required (Python 3.9+ stdlib only):

```bash
python3 scripts/verify_3_oracles.py
```

This runs:
- **12,000 stateful multi-actor steps** across clean ERC-4626/7540 vault and lending pool models (verifying all 3 universal oracles hold).
- **3 intentional fault-injection regressions** (solvency leak via rounding-up withdrawal, stuck ERC-7540 epoch queue, and non-commutative split-deposit extraction) proving each oracle catches real bugs deterministically.

## Integrating Your Protocol

1. Implement `IThreeOracleTarget` (or extend `ERC4626Adapter`, `ERC7540AsyncVaultAdapter`, or `LendingPoolAdapter`) wrapping your protocol's real deployed or target contracts.
2. Register your handler with `targetContract(address(handler))` inside a test inheriting `ThreeOracleBase`.
3. Run `FOUNDRY_PROFILE=ci forge test` in CI on every PR diff.

## Maintainer & Contact

Maintained by **Muhammad Talal Hassan (`@codetamer`)**, Founder of **Reforms Studio** (`talalofficial007@gmail.com`).
Licensed under MIT — free for any Ethereum protocol, auditor, or grant program to fork and extend.
