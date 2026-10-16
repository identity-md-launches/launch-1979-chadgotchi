# ChadGotchi (CHAD)

A fixed-supply ERC-20 for an IdentityMD custom token launch on Ethereum mainnet.

| Parameter | Value |
|---|---|
| Solidity contract | `ChadGotchi` (`src/ChadGotchi.sol`) |
| `name()` | `ChadGotchi` |
| `symbol()` | `CHAD` |
| `decimals()` | `18` |
| `totalSupply()` | `1_000_000_000 * 10**18` = `1000000000000000000000000000` minor units |
| Constructor arguments | none |
| Minted to | `msg.sender` of the constructor, once |
| Owner / admin roles | none |
| Compiler | solc `0.8.26`, optimizer on (200 runs), `evm_version = cancun`, `bytecode_hash = "none"`, `cbor_metadata = false` |

## What the token does

- The constructor mints the whole supply to `msg.sender` and emits `Transfer(0, deployer, supply)`
  and `SupplyMinted(deployer, supply)`. There is no other mint path: `totalSupply()` can never
  grow after deployment.
- It is OpenZeppelin v5.4.0 `ERC20` with no extensions. Transfers, approvals and `transferFrom`
  behave exactly as the standard: no tax, burn-on-transfer, reflection, blocklist, pause, cooldown,
  max-wallet or max-transaction rule. Every transfer delivers exactly the amount asked for.
- There is no owner, minter, pauser or upgrade mechanism, no `fallback`, no `receive`, no
  `DELEGATECALL`, `CALLCODE` or `SELFDESTRUCT` in the runtime. Nobody can move or freeze a
  holder's balance except the holder (or a spender the holder approved).
- Nothing can burn tokens on a holder's behalf. A holder may still send tokens to an address nobody
  controls, which the standard allows; `transfer(address(0), ...)` reverts.

## Assumptions

- The launch chain is Ethereum (chain id 1) and the token pairs with IMD
  (`0xd34a99bc0f67ae1bbd63c660e6d0b0dd03e263b7`) in a Uniswap v4 pool; those are launch facts and
  the token does not reference them.
- The deployer is the IdentityMD ProjectFactory. Because the constructor mints to `msg.sender`, the
  factory receives the entire supply and distributes it: 10% to the launch's MerkleDistributor
  (the swarm share), 80% (`poolBps = 8000`) to seed the pool, and the remaining 10% to the
  requester's `remainderTo` address `0xCe34A5aE98F51b499B92063a7a83d49B26ee5b14`. The token
  itself reserves, allocates or exempts nothing; the exact-amount transfer rule is what makes
  each of those flows arrive whole.
- The constructor calls no other contract and reads nothing from the chain, so it deploys on an
  empty chain and under CREATE2 unchanged.
- Deploying the contract anywhere else (for example with the included script) gives the whole
  supply to whoever broadcasts the deployment. That is the intended behaviour, not an
  oversight: there is no second recipient to configure.

## Deployment parameters

The contract has **no constructor arguments** and **no open numeric choices**: name, symbol,
decimals and supply are compile-time constants, each exposed as a public constant
(`TOKEN_NAME`, `TOKEN_SYMBOL`, `DECIMALS`, `SUPPLY_WHOLE_TOKENS`, `TOTAL_SUPPLY`).

The IdentityMD launch deploys the token from the built bytecode. The manifest step (which writes
`launch.json`, not this repository) will record:

- `token.contract`: `ChadGotchi`
- `token.name` / `token.symbol` / `token.decimals`: `ChadGotchi` / `CHAD` / `18`
- `token.constructorArgs`: `[]`
- `token.totalSupply`: `1000000000000000000000000000`
- no application contracts

For a non-IdentityMD deployment, `script/DeployChadGotchi.s.sol` exposes `deploy()` (tested
directly) and a `run()` entry point that broadcasts it. The broadcasting account receives the
supply. The script reads no environment variables itself.

## After launch

Nothing to configure. The token has no owner-settable values, no setters and no admin functions.
The only post-launch responsibility is the holder's own: keep custody of the keys that hold CHAD.

## Operational responsibilities and trust assumptions

- **Immutability.** The contract is not upgradeable and has no admin. Bugs cannot be patched in
  place; a fix would be a new token. This is deliberate for a plain fixed-supply token.
- **No censorship vector.** With no pause or blocklist there is no key that can freeze users, and
  no key to lose or have stolen.
- **Supply integrity.** The supply is fixed at deploy. Market cap derived from it (the launch
  opens at a 3,500 IMD cap for the whole supply) cannot be diluted by a later mint.
- **Source verification.** Verifying the source on a block explorer after the launch belongs to
  the network's deployer and launch policy. Because `bytecode_hash = "none"` and
  `cbor_metadata = false`, verification must use the same compiler settings in `foundry.toml`.
- **Audit status.** Tests passing is not an audit. The contract is OpenZeppelin's audited `ERC20`
  plus a constructor and a `decimals()` override; an independent adversarial review is still the
  release gate for any contract holding value.

## Security checklist (eth-security)

Checked against the pinned `eth-security` reference:

- Access control: no privileged functions exist.
- Reentrancy: no external calls; CEI is trivially satisfied.
- Decimals: fixed at 18 and asserted in tests.
- Integer math: only the constant supply product, computed at compile time.
- Input validation: zero-address sender/receiver/spender revert via OpenZeppelin's custom errors.
- Events: `Transfer`, `Approval`, and `SupplyMinted` cover every state change.
- No infinite approvals granted by the contract; users control their own allowances.
- No proxies, no delegatecall, no signatures.
- Tools run: `forge build`, `forge test` (33 tests, including fuzz tests under the verifier's
  seed), `forge fmt --check`. Slither and Mythril were not available in this environment.

## Layout

```
foundry.toml                  compiler pins and profile (solc 0.8.26, bytecode_hash none)
remappings.txt                forge-std and @openzeppelin/contracts remappings
src/ChadGotchi.sol            the token
script/DeployChadGotchi.s.sol reviewable deploy helper for non-IdentityMD deployments
test/ChadGotchi.t.sol         ERC-20 behaviour: success, failure and fuzz tests
test/ChadGotchiLaunchFloor.t.sol
                              local mirror of the custom-token launch floor (CREATE2 from a
                              factory probe, exact launch flows, no mint / admin / freeze paths,
                              no DELEGATECALL/SELFDESTRUCT, no metadata hash)
lib/forge-std                 forge-std v1.11.0, vendored as plain files (MIT / Apache-2.0)
lib/openzeppelin-contracts    the ERC20 subset of OpenZeppelin Contracts v5.4.0 (MIT)
```

## Running the checks

```
forge build
forge test
forge fmt --check
```

The fuzz tests also pass with the verifier's seed:

```
FOUNDRY_FUZZ_SEED=0xc03abdcd61ecdd27b02abc965369125dd2d3ec6f4caaf129583b4936c1ddcf25 forge test
```
