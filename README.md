# WattLock

**A certificate-backed compute-allocation gate:** a compute-job escrow on Creditcoin CC3 pays only when Attestcoin proves that the exact energy-certificate allocation was terminally reserved on Ethereum Sepolia.

`RESERVE → PROVE → LOCK → SETTLE → BLOCK → VERIFY`

**Live:** [wattlock.vercel.app](https://wattlock.vercel.app) · **Source:** [github.com/Cassxbt/wattlock](https://github.com/Cassxbt/wattlock)

## The failure WattLock prevents

An energy certificate can be allocated to several independent downstream compute-settlement systems when their ledgers do not share enforceable state. A dashboard can report that conflict after the fact; it cannot prevent a payout.

WattLock makes the source reservation terminal, proves it cross-chain through Attestcoin, and releases a fixed CC3 test-CTC escrow only when the proof matches the exact job, buyer, provider, amount, energy quantity, deadline, destination chain, and deployed settlement contract. The certificate expiry is separately checked against that deadline.

Without Attestcoin, the CC3 contract has no trust-minimized way to inspect the Sepolia reservation receipt. The payout path is therefore unavailable.

## How Attestcoin is used

Official packages: `@gluwa/usc-sdk@0.18.0`, `@gluwa/asc-contracts@0.2.1`. Delete this column and `settleWithProof` cannot pay.

| Surface | Call site | Load-bearing job |
| --- | --- | --- |
| `ProofBuilder.waitUntilHeightAttested` / `getProof` | [`script/submit-proof.mjs`](script/submit-proof.mjs) | Builds the source-tx proof after the height is attested |
| `PrecompileChainInfoProvider.getLatestAttestedHeightAndHash` (`0x0FD3`) | [`script/submit-proof.mjs`](script/submit-proof.mjs) | Operator wait only; not inside `WattLockASC` |
| `WattLockASC.settleWithProof` | [`contracts/WattLockASC.sol`](contracts/WattLockASC.sol) | Only payout entry. Wrong `chainKey` reverts `WrongSourceChainKey()` before the verifier |
| `ASCBase.execute` → `0x0FD2.verifyAndEmit` | `@gluwa/asc-contracts` `ASCBase` | Inclusion + continuity. Direct `execute` reverts `DirectExecutionDisabled()` |
| `0x0FD2.calculateTxIndex` | same `ASCBase._computeQueryId` | Query id for replay protection |

Live check: CC3 settle [`0x5285…ac5f`](https://creditcoin-testnet.blockscout.com/tx/0x52853b6220fab2501ef08f9838f9bbe1a5d3dbcb0a0b2a756ed0a3a29853ac5f) logs `TransactionVerified` from `0x0FD2` then pays `1 tCTC`.

## Live testnet proof

| Verdict | Public receipt |
| --- | --- |
| `RESERVE` — certificate is terminally reserved on Sepolia | [Sepolia reservation transaction](https://sepolia.etherscan.io/tx/0x109b096b94b5d4a312bd78fbe2bded62e53a3a6a1270155a7c6e29ff10d95503) |
| `SETTLE` — Attestcoin proof verifies on CC3 and releases `1 tCTC` | [CC3 settlement transaction](https://creditcoin-testnet.blockscout.com/tx/0x52853b6220fab2501ef08f9838f9bbe1a5d3dbcb0a0b2a756ed0a3a29853ac5f) |
| `BLOCK` — duplicate reservation is refused | [Sepolia failed transaction](https://sepolia.etherscan.io/tx/0x9e33281808202cfce95588cc43861ae5434a7d05e7d864753b81b130810407fd) — `CertificateAlreadyReserved()` |
| `BLOCK` — same Attestcoin query cannot pay twice | [CC3 failed `settleWithProof`](https://creditcoin-testnet.blockscout.com/tx/0x13c8302c6aca4a7ce60a284195152a9af0206b4636957a407ad6d7c6f24e0e56) — `Query already processed` |
| `VERIFY` — full addresses, IDs, and outcome | [deployment and evidence record](docs/DEPLOYMENTS.md) |

The allowed path was not simulated: `WattLockASC` verified an Attestcoin proof for the Sepolia reservation in the CC3 settlement transaction, emitted `JobSettled`, transferred the fixed escrow to the provider, and marked the certificate consumed. Attestcoin query id `0x878e33a512eca89f670b0ca875ba27654aa43a27d532bade9c8cd35df7637c18`.

## Architecture

```text
Ethereum Sepolia                                 Creditcoin CC3 Testnet
────────────────                                 ─────────────────────
DemoCertificateIssuer                            WattLockASC
issue certificate                                open and fund exact job
       │                                                │
reserveCertificate(cert, job, allocation hash)          │
       │                                                │
       └── Attestcoin proof of reservation receipt ───► settleWithProof
                                                        │
                                                        ├─ verifies proof natively
                                                        ├─ validates receipt, issuer, event, owner,
                                                        │  energy, expiry, and allocation commitment
                                                        └─ pays fixed provider once, or reverts
```

### Contracts

| Contract | Purpose | Testnet deployment |
| --- | --- | --- |
| `DemoCertificateIssuer` | Testnet model of an external certificate issuer. A certificate owner can make exactly one terminal reservation. | [Sepolia `0xb71f…004a`](https://sepolia.etherscan.io/address/0xb71f79e990629aD3d0aB8a3fd2A8F8a21FE0004a) |
| `WattLockASC` | Holds one fixed CC3 escrow and verifies the Attestcoin-proved source receipt before paying it. | [CC3 `0x4325…ee39`](https://creditcoin-testnet.blockscout.com/address/0x43259Ac2952ae1583BDF0DC4756Eb86ec963ee39) |

The supported source is deliberately narrow: Sepolia (Attestcoin `chainKey = 1`, EVM chain ID `11155111`) to CC3 Testnet (EVM chain ID `102031`). `settleWithProof` rejects any other source chain key before it invokes the official Attestcoin verifier.

## Security and product invariants

- One certificate can be reserved once on the source issuer.
- One funded job has one fixed EOA provider and one fixed test-CTC reward.
- A source reservation must commit to the precise certificate, job, buyer, provider, reward, energy amount, deadline, CC3 chain ID, and `WattLockASC` address.
- CC3 decodes the proved transaction and accepts exactly one successful `CertificateReserved` event from the configured issuer.
- The same destination certificate cannot settle twice; the same Attestcoin query cannot settle twice.
- Escrow payout is atomic: if payment fails, the settlement reverts.
- After the deadline, only the buyer can reclaim an unsettled job.

## Run locally

Requirements: Foundry and Yarn.

```bash
yarn install --frozen-lockfile
yarn build
NO_PROXY='*' forge test --offline
yarn judge:verify
```

`yarn verify` is format + Foundry. `yarn judge:verify` re-reads public Sepolia and CC3 RPCs and **exits 1** if README hashes, the 11-test count, or the `0x0FD2` skip admission drift. It does not call the precompile from Anvil.

The repository contains 11 unit tests covering the allowed settlement and terminal reservation, allocation mismatch, certificate/query replay, receipt/issuer failures, owner/energy/expiry/source checks, zero job IDs, and reclaim behavior. Those tests skip the native `0x0FD2` precompile (`processVerifiedForTest`). The linked CC3 settlement receipt is the live Attestcoin evidence.

## Technical documentation

- [Deployments and public evidence](docs/DEPLOYMENTS.md)
- [Attestcoin protocol chains and environments](https://docs.attestcoin.org/attestcoin-protocol/attestcoin-protocol-chains-environments)
- [Attestcoin guided tutorials](https://docs.attestcoin.org/attestcoin-protocol/guided-tutorials)

## Honest boundary

| Claim | Status |
| --- | --- |
| Cross-chain reservation-gated settlement | Real testnet: Sepolia reservation → Attestcoin proof → CC3 payout |
| Allocation enforcement | Real Sepolia `CertificateAlreadyReserved()`. Real CC3 `Query already processed` on the same proof |
| `/proof` page | Recomputes `queryId` from the live `0x0FD2` log when explorers answer; otherwise `reported, not verified here` |
| Energy-certificate issuer | Demo issuer only; a testnet model of an external issuer |
| Physical renewable generation | Not verified |
| Hourly or geographic energy matching | Not verified |
| Physical compute execution or meter telemetry | Not verified |

WattLock does not claim that a GPU physically ran on renewable electricity. It proves only the cross-chain allocation and settlement rule stated above.

## Submission materials

- Live site: [wattlock.vercel.app](https://wattlock.vercel.app) (`/proof/`, `/demo/` is a replay)
- Demo video: in progress
- Submission deck: in progress

Those materials will use the same public receipt sequence above and will not introduce broader environmental claims.
