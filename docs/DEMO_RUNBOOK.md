# WattLock Demo Runbook

## Proof surface

Use a **proof-first demo**. WattLock's central claim is a cross-chain settlement invariant, so the recording must prioritize live receipts and the blocked reuse over feature-tour polish.

Target runtime: 3 minutes 10 seconds. Record at 16:9 and 1080p. Keep the WattLock proof page, Sepolia Etherscan, CC3 Blockscout, and the repository README ready in separate tabs before starting.

## Proof spec

```text
Failure: The same energy certificate can be allocated to multiple compute-settlement claims when source and settlement systems do not share enforceable state.
Mechanism: WattLock is a certificate-backed compute-allocation gate: RESERVE -> PROVE -> LOCK -> SETTLE -> BLOCK -> VERIFY.
Sponsor role: Attestcoin proves the Sepolia reservation receipt inside the CC3 settlement transaction. Without it, the CC3 escrow cannot be released.
Happy path: A terminal Sepolia reservation is proved and releases one exact CC3 job escrow to its fixed provider.
Refusal: The same certificate cannot be reserved twice. The live source retry reverts with CertificateAlreadyReserved().
Receipt: Sepolia reservation transaction 0x109b...5503, CC3 proof-submission-and-settlement transaction 0x5285...ac5f, and Sepolia rejection transaction 0x9e33...07fd.
Truth boundary: The issuer and certificate are testnet models. The proof and escrow payout are real testnet. WattLock does not prove physical generation, geographic or hourly matching, compute execution, or telemetry.
```

## Recording sequence

| Time | Screen action | Narration and on-screen caption |
| --- | --- | --- |
| 0:00-0:08 | Show a plain title card with the failure. | **One certificate can unlock multiple compute claims.** |
| 0:08-0:20 | Open `/verify/` at the verdict. | “WattLock makes that allocation terminal before a compute escrow can settle.” Caption: **Certificate-backed compute allocation gate.** |
| 0:20-0:44 | Scroll to the four evidence receipts. Open the funded-job link in a new tab only if the transaction details are legible. | “This job is funded with one fixed tCTC reward for one fixed provider. It has one allocation commitment.” |
| 0:44-1:08 | Open the Sepolia `CertificateReserved` transaction. Highlight the configured issuer and the `CertificateReserved` log. | “The certificate owner made one terminal reservation on Sepolia. Its event binds the certificate to this exact allocation.” Caption: **Reserve on Sepolia.** |
| 1:08-1:38 | Return to the proof page and open the CC3 settlement transaction. Highlight `JobSettled`, the query ID, provider, and payout. | “Attestcoin proved that Sepolia receipt inside this CC3 call. WattLock decoded the proved receipt, validated the issuer and commitment, then released the escrow.” Caption: **Attestcoin gates the payout.** |
| 1:38-2:03 | Show the bound IDs section on `/verify/`, then the CC3 contract address. | “The proof is not a generic green badge. It is bound to the certificate, job, buyer, provider, reward, energy amount, deadline, CC3 chain, and settlement contract.” |
| 2:03-2:28 | Open the failed Sepolia retry. Show status failed and the `CertificateAlreadyReserved()` error. | “Now try to reuse the same certificate. The source issuer blocks it before any second allocation can exist.” Caption: **Reuse blocked on-chain.** |
| 2:28-2:50 | Return to the evidence-boundary section. | “What is real is the Sepolia reservation, Attestcoin proof, CC3 verification, payout, and terminal rejection. We do not claim physical renewable generation or compute telemetry.” |
| 2:50-3:10 | Show README top and the proof page once more. | “WattLock is a DePIN settlement control: reserve once, prove once, settle once. The live receipts and source are linked here.” Caption: **Live testnet proof. GitHub. DePIN track.** |

## Capture checklist

- [ ] Confirm every displayed transaction hash, address, amount, and query ID against `docs/DEPLOYMENTS.md` immediately before recording.
- [ ] Use the real `/verify/` page and explorers, not a slide or recreated transaction view.
- [ ] Keep the actual `CertificateAlreadyReserved()` refusal in the final cut.
- [ ] State “testnet” whenever showing the payout or certificate.
- [ ] Burn in short captions. The video must remain understandable muted.
- [ ] Remove page loads, typing, dead cursor movement, and any service delay. Do not cut around a failed proof.
- [ ] Review once muted, once at 1.25x, and once as a hostile judge.

## Never say

- “WattLock proves green compute.”
- “WattLock verifies renewable generation.”
- “WattLock integrates a production REC registry.”
- “The failed Sepolia retry is a failed CC3 proof.”

The truthful claim is narrower and stronger: WattLock enforces a real testnet certificate-allocation rule across Sepolia and CC3 before releasing an exact compute-job escrow.
