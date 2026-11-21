#!/usr/bin/env python3
"""256-Bit EVM Stateful Multi-Actor Mirror Verifier for Reforms Invariant Kit.

Executes 12,000 randomized stateful transitions across 4 actors on:
  1. Clean ERC-4626 / ERC-7540 Vault Model (verifies all 3 Universal Oracles PASS)
  2. Clean Overcollateralized Lending Pool Model (verifies all 3 Universal Oracles PASS)
  3. 3 Intentional Fault-Injection Targets (verifies each Oracle CATCHES real bugs)
"""

import random
import sys

UINT256_MAX = (1 << 256) - 1
VIRTUAL_SHARES = 10**6
VIRTUAL_ASSETS = 10**6


class VaultModel:
    """Exact 256-bit integer mirror of ReferenceERC4626Vault + ERC-7540 async escrow queue."""

    def __init__(self, bug_mode: str = "clean"):
        self.bug_mode = bug_mode
        self.total_supply = 0
        self.active_assets = 0
        self.escrowed_claims = 0
        self.balances = {i: 0 for i in range(4)}
        self.pending_redeem = {i: 0 for i in range(4)}
        self.claimable_assets = {i: 0 for i in range(4)}
        self.epoch_settled = False
        self.partition_violation = False

    def preview_deposit(self, assets: int) -> int:
        if self.bug_mode == "partition_bug":
            # Bug: rounds UP on deposit shares, allowing split-deposit surplus extraction
            num = assets * (self.total_supply + VIRTUAL_SHARES)
            den = self.active_assets + VIRTUAL_ASSETS
            return (num + den - 1) // den
        return (assets * (self.total_supply + VIRTUAL_SHARES)) // (self.active_assets + VIRTUAL_ASSETS)

    def preview_redeem(self, shares: int) -> int:
        return (shares * (self.active_assets + VIRTUAL_ASSETS)) // (self.total_supply + VIRTUAL_SHARES)

    def deposit(self, actor: int, assets: int) -> None:
        if assets <= 0:
            return
        if assets >= 2:
            half_a = assets // 2
            half_b = assets - half_a
            whole = self.preview_deposit(assets)
            split = self.preview_deposit(half_a) + self.preview_deposit(half_b)
            if split > whole:
                self.partition_violation = True
        shares = self.preview_deposit(assets)
        self.active_assets += assets
        self.total_supply += shares
        self.balances[actor] += shares

    def donate_yield(self, amount: int) -> None:
        if amount > 0:
            self.active_assets += amount

    def request_redeem(self, actor: int, shares: int) -> None:
        shares = min(shares, self.balances[actor])
        if shares <= 0:
            return
        self.balances[actor] -= shares
        self.pending_redeem[actor] += shares
        self.epoch_settled = False

    def settle_epoch(self) -> None:
        for actor in range(4):
            pend = self.pending_redeem[actor]
            if pend == 0:
                continue
            if self.bug_mode == "liveness_bug" and actor == 3:
                # Bug: off-by-one loop skips final actor in epoch settlement -> stuck state
                continue
            assets_out = self.preview_redeem(pend)
            self.pending_redeem[actor] = 0
            self.total_supply -= pend
            self.claimable_assets[actor] += assets_out
            if self.bug_mode != "solvency_bug":
                # Clean ERC-7540: segregate settled claim liabilities out of active_assets into escrow
                self.active_assets -= assets_out
                self.escrowed_claims += assets_out
            # In solvency_bug mode: omits segregation, double-counting claimable assets in share price
        self.epoch_settled = True

    def claim(self, actor: int) -> None:
        amt = self.claimable_assets[actor]
        if amt == 0:
            return
        self.claimable_assets[actor] = 0
        if self.bug_mode == "solvency_bug":
            self.active_assets -= amt
        else:
            self.escrowed_claims -= amt

    def check_oracles(self) -> tuple[bool, str]:
        # Oracle 1: Global Conservation & Solvency
        total_backing = self.active_assets + self.escrowed_claims
        active_claims = self.preview_redeem(self.total_supply) if self.total_supply > 0 else 0
        total_claims = active_claims + sum(self.claimable_assets.values())
        if self.active_assets < 0 or self.escrowed_claims < 0 or (total_backing + 5 < total_claims):
            return False, f"Oracle 1 (Solvency) violated: backing={total_backing}, claims={total_claims}"

        # Oracle 2: Universal Liveness (Zero Stuck State)
        if self.epoch_settled:
            for actor in range(4):
                if self.pending_redeem[actor] > 0:
                    return False, f"Oracle 2 (Liveness) violated: actor {actor} stuck pending={self.pending_redeem[actor]}"

        # Oracle 3: Partition & Split-Execution Invariance
        if self.partition_violation:
            return False, "Oracle 3 (Partition) violated: split deposit yielded strictly more shares than atomic deposit"

        return True, "OK"


class LendingModel:
    """Exact 256-bit integer mirror of ReferenceLendingPool."""

    def __init__(self):
        self.total_cash = 0
        self.total_borrows = 0
        self.total_reserves = 0
        self.total_supply_claims = 0
        self.collateral = {i: 0 for i in range(4)}
        self.debt = {i: 0 for i in range(4)}

    def supply(self, actor: int, amount: int) -> None:
        self.total_cash += amount
        self.total_supply_claims += amount
        self.collateral[actor] += amount

    def borrow(self, actor: int, amount: int) -> None:
        max_borrow = (self.collateral[actor] * 75) // 100 - self.debt[actor]
        amt = min(amount, max_borrow, self.total_cash)
        if amt <= 0:
            return
        self.total_cash -= amt
        self.total_borrows += amt
        self.debt[actor] += amt

    def repay(self, actor: int, amount: int) -> None:
        paid = min(amount, self.debt[actor])
        if paid <= 0:
            return
        self.debt[actor] -= paid
        self.total_borrows -= paid
        self.total_cash += paid

    def accrue_interest(self, bps: int) -> None:
        if self.total_borrows == 0:
            return
        for actor in range(4):
            if self.debt[actor] > 0:
                interest = (self.debt[actor] * bps) // 10_000
                self.debt[actor] += interest
                self.total_borrows += interest
                reserve_cut = interest // 10
                self.total_reserves += reserve_cut
                self.total_supply_claims += interest - reserve_cut

    def check_oracles(self) -> tuple[bool, str]:
        backing = self.total_cash + self.total_borrows
        claims = self.total_supply_claims + self.total_reserves
        if backing + 5 < claims:
            return False, f"Lending Oracle 1 violated: backing={backing}, claims={claims}"
        if sum(self.debt.values()) != self.total_borrows:
            return False, "Lending Oracle 2 violated: debt accounting desync"
        return True, "OK"


def run_vault_campaign(bug_mode: str, steps: int, seed: int) -> tuple[bool, str, int]:
    rng = random.Random(seed)
    model = VaultModel(bug_mode=bug_mode)
    for step in range(1, steps + 1):
        op = rng.choice(["deposit", "deposit", "yield", "request", "settle", "claim"])
        actor = rng.randint(0, 3)
        if op == "deposit":
            model.deposit(actor, rng.randint(1, 10**9))
        elif op == "yield":
            model.donate_yield(rng.randint(1, 10**6))
        elif op == "request":
            bal = model.balances[actor]
            if bal > 0:
                model.request_redeem(actor, rng.randint(1, bal))
        elif op == "settle":
            model.settle_epoch()
        elif op == "claim":
            model.claim(actor)

        ok, msg = model.check_oracles()
        if not ok:
            return False, msg, step
    return True, f"PASS ({steps} steps, 0 violations)", steps


def run_lending_campaign(steps: int, seed: int) -> tuple[bool, str]:
    rng = random.Random(seed)
    model = LendingModel()
    for _ in range(steps):
        op = rng.choice(["supply", "borrow", "repay", "interest"])
        actor = rng.randint(0, 3)
        if op == "supply":
            model.supply(actor, rng.randint(100, 10**9))
        elif op == "borrow":
            model.borrow(actor, rng.randint(1, 10**8))
        elif op == "repay":
            model.repay(actor, rng.randint(1, 10**8))
        elif op == "interest":
            model.accrue_interest(rng.randint(1, 25))
        ok, msg = model.check_oracles()
        if not ok:
            return False, msg
    return True, f"PASS ({steps} steps, 0 violations)"


def main() -> int:
    print("=== Reforms Invariant Kit: 256-Bit 3-Oracle Mirror Verifier ===")
    ok_v, msg_v, _ = run_vault_campaign("clean", steps=12000, seed=42)
    print(f"[Clean ERC-4626/7540 Vault]    {msg_v}")
    assert ok_v, msg_v

    ok_l, msg_l = run_lending_campaign(steps=12000, seed=99)
    print(f"[Clean Lending Pool]           {msg_l}")
    assert ok_l, msg_l

    # Fault-injection regressions: each MUST be caught
    for bug_mode, expected_oracle in [
        ("solvency_bug", "Oracle 1"),
        ("liveness_bug", "Oracle 2"),
        ("partition_bug", "Oracle 3"),
    ]:
        ok_b, msg_b, step_b = run_vault_campaign(bug_mode, steps=2000, seed=7)
        assert not ok_b and expected_oracle in msg_b, f"Fault injection failed for {bug_mode}: {msg_b}"
        print(f"[Fault Injection: {bug_mode:13s}] CAUGHT at step {step_b} -> {msg_b}")

    print("ALL VERIFICATION & FAULT-INJECTION CHECKS PASSED.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
