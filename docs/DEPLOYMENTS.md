# WattLock — Testnet Evidence

> Updated 2026-09-09. All records below are public-testnet evidence. No mainnet assets, production energy certificates, or physical-compute claims are involved.

## Networks

| Role | Network | Identifier |
| --- | --- | --- |
| Source certificate reservation | Ethereum Sepolia | EVM chain ID `11155111`; Attestcoin source chain key `1` |
| Proof-gated settlement | Creditcoin CC3 Testnet | EVM chain ID `102031` |

The CC3 testnet network details and Blockscout explorer are published by [Creditcoin](https://docs.creditcoin.org/environments/testnet). Attestcoin verifies the Sepolia transaction inside the CC3 settlement call; WattLock then validates the decoded receipt and reservation event before releasing the job escrow.

## Deployed contracts

| Contract | Network | Address | Deployment receipt |
| --- | --- | --- | --- |
| `DemoCertificateIssuer` | Sepolia | [`0xb71f79e990629aD3d0aB8a3fd2A8F8a21FE0004a`](https://sepolia.etherscan.io/address/0xb71f79e990629aD3d0aB8a3fd2A8F8a21FE0004a) | [`0x7101…a6fd9`](https://sepolia.etherscan.io/tx/0x7101bda732a58f374cd92a992415685f513ce2af6b81bc4b9c9a5facc07a6fd9) |
| `WattLockASC` | CC3 Testnet | [`0x43259Ac2952ae1583BDF0DC4756Eb86ec963ee39`](https://creditcoin-testnet.blockscout.com/address/0x43259Ac2952ae1583BDF0DC4756Eb86ec963ee39) | [`0x882d…1d73e`](https://creditcoin-testnet.blockscout.com/tx/0x882db9d14579d6f26f17a4776a0983eb2f2b5bc37ca3cfece43e9f2f15d1d73e) |

`WattLockASC` was initialized with the Sepolia issuer above, Attestcoin chain key `1`, and Sepolia EVM chain ID `11155111`.

### Reproducible build provenance

The deployment artifacts are built from the Solidity sources in this repository with `solc 0.8.30`, optimizer enabled (`200` runs), `via_ir = true`, and `evm_version = shanghai`; the exact settings are recorded in [`foundry.toml`](../foundry.toml). The constructor arguments are:

```text
DemoCertificateIssuer(initialOwner = testnet buyer address)
WattLockASC(issuer = 0xb71f79e990629aD3d0aB8a3fd2A8F8a21FE0004a, sourceChainKey = 1, sourceEvmChainId = 11155111)
```

Explorer source verification (Blockscout, matching this repo's `solc 0.8.30` / optimizer 200 / `via_ir` / shanghai build):

- `WattLockASC` on CC3: [verified](https://creditcoin-testnet.blockscout.com/address/0x43259Ac2952ae1583BDF0DC4756Eb86ec963ee39?tab=contract)
- `DemoCertificateIssuer` on Sepolia Blockscout: [verified](https://eth-sepolia.blockscout.com/address/0xb71f79e990629aD3d0aB8a3fd2A8F8a21FE0004a?tab=contract)

Etherscan Sepolia verification is not claimed here.

## Allowed flow — proved and settled

| Evidence | Receipt |
| --- | --- |
| Certificate issued (`1000 Wh`, test-only) | [`0xfc0f…be2c`](https://sepolia.etherscan.io/tx/0xfc0f67ada9aee06db6ad4746cfd76d761ad9f09f03d6046e3b8aba20a261be2c) |
| CC3 job funded (`1 tCTC`, fixed EOA provider) | [`0x434c…e426`](https://creditcoin-testnet.blockscout.com/tx/0x434ca704b4e27e83def17ae20cebc0130489c3798047405e4c3d052fb050e426) |
| Sepolia terminal `CertificateReserved` event | [`0x109b…5503`](https://sepolia.etherscan.io/tx/0x109b096b94b5d4a312bd78fbe2bded62e53a3a6a1270155a7c6e29ff10d95503) |
| Attestcoin-verified CC3 settlement and provider payout | [`0x5285…ac5f`](https://creditcoin-testnet.blockscout.com/tx/0x52853b6220fab2501ef08f9838f9bbe1a5d3dbcb0a0b2a756ed0a3a29853ac5f) |

### Bound allocation

| Field | Value |
| --- | --- |
| Certificate ID | `0xf23816a6a24e533affcc21f1e4ccf286d7bbe5787d037fd9749c25c018b30a72` |
| Job ID | `0x6cd13eae3506378c6afdea977dff133333a3ccc01301c1e70b5f9f198c25713b` |
| Allocation commitment | `0x58156ff55f44eaf683558931423f7de650eb40327750b8ddf6ddf7781fd95349` |
| Attestcoin query ID | `0x878e33a512eca89f670b0ca875ba27654aa43a27d532bade9c8cd35df7637c18` |
| Reward | `1 tCTC` (`1000000000000000000` wei) |
| Provider | `0x000000000000000000000000000000000000cafE` |

The successful CC3 transaction emitted `JobSettled`, transferred the full fixed escrow to the provider, marked the job `Settled`, and marked the certificate consumed. The proof was generated with the official Attestcoin CC3 proof-builder service after the source block was attested.

## Blocked reuse

The same source certificate was submitted for reservation again. Sepolia rejected it with the `CertificateAlreadyReserved()` custom error.

- Failed source transaction: [`0x9e33…07fd`](https://sepolia.etherscan.io/tx/0x9e33281808202cfce95588cc43861ae5434a7d05e7d864753b81b130810407fd)
- Revert selector: `0x8ef5dd6b` (`CertificateAlreadyReserved()`)

This is the live terminal-lock evidence on Sepolia.

The same Attestcoin proof of that reservation was submitted again to `WattLockASC.settleWithProof` on CC3. The destination transaction reverted with `Query already processed` (`ASCBase` replay of query id `0x878e…7c18`).

- Failed CC3 settlement: [`0x13c8…0e56`](https://creditcoin-testnet.blockscout.com/tx/0x13c8302c6aca4a7ce60a284195152a9af0206b4636957a407ad6d7c6f24e0e56)
- Selector: `0xfca7679d` (`settleWithProof`)
- Status: reverted (receipt status `0`)
- Proof rebuilt with the official testnet proof builder (`https://proof-gen-api.cc3-testnet.creditcoin.network/`) against source tx `0x109b…5503`

## Reproduce the boundary precisely

WattLock proves a narrow statement: a testnet `DemoCertificateIssuer` recorded one immutable certificate reservation tied to this exact CC3 job commitment, and a CC3 contract released its exact testnet escrow only after an Attestcoin proof of that source transaction passed.

It does **not** prove real renewable generation, a production REC registry record, hourly or geographic matching, physical compute execution, or hardware telemetry.
