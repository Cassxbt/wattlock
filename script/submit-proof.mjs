import { Contract, JsonRpcProvider, Wallet } from "ethers";
import { chainInfo, proofProvider } from "@gluwa/usc-sdk";

const required = [
  "CREDITCOIN_RPC_URL",
  "SOURCE_CHAIN_RPC_URL",
  "PROOF_BUILDER_URL",
  "WATTLOCK_ADDRESS",
  "WALLET_PRIVATE_KEY",
  "SOURCE_TX_HASH",
];

for (const name of required) {
  if (!process.env[name]) throw new Error(`${name} is required`);
}

const chainKey = Number(process.env.SOURCE_CHAIN_KEY ?? "1");
const sourceProvider = new JsonRpcProvider(process.env.SOURCE_CHAIN_RPC_URL);
const cc3Provider = new JsonRpcProvider(process.env.CREDITCOIN_RPC_URL);
const wallet = new Wallet(process.env.WALLET_PRIVATE_KEY, cc3Provider);
const wattLock = new Contract(
  process.env.WATTLOCK_ADDRESS,
  [
    "function settleWithProof(uint64,uint64,bytes,bytes32,(bytes32,bool)[],bytes32,bytes32[]) returns (bool)",
    "event JobSettled(bytes32 indexed jobId,bytes32 indexed certificateId,bytes32 indexed queryId,address provider,uint128 reward,bytes32 allocationHash)",
  ],
  wallet,
);

const sourceReceipt = await sourceProvider.waitForTransaction(process.env.SOURCE_TX_HASH, 1, 120_000);
if (!sourceReceipt?.blockNumber) throw new Error("Source reservation transaction is not mined");

const proofBuilder = new proofProvider.service.ProofBuilder(chainKey, process.env.PROOF_BUILDER_URL);
const chainInfoProvider = new chainInfo.PrecompileChainInfoProvider(cc3Provider);
const latest = await chainInfoProvider.getLatestAttestedHeightAndHash(chainKey);

console.log(`Source reservation block: ${sourceReceipt.blockNumber}`);
console.log(`Latest attested block: ${latest.height}`);

await proofBuilder.waitUntilHeightAttested(chainKey, sourceReceipt.blockNumber, 15_000, 1_200_000);
const proofResult = await proofBuilder.getProof(process.env.SOURCE_TX_HASH);
if (!proofResult.success || !proofResult.data) {
  throw new Error(`Proof generation failed: ${proofResult.error ?? "no proof data returned"}`);
}
const proof = proofResult.data;
const siblings = proof.merkleProof.siblings.map((sibling) => [sibling.hash ?? sibling.digest, sibling.isLeft]);

const args = [
  proof.chainKey,
  proof.headerNumber,
  proof.txBytes,
  proof.merkleProof.root,
  siblings,
  proof.continuityProof.lowerEndpointDigest,
  proof.continuityProof.roots,
];

const estimatedGas = await wattLock.settleWithProof.estimateGas(...args);
const gasLimit = (estimatedGas * 135n) / 100n;
console.log(`Proof generated. Estimated gas: ${estimatedGas}; gas limit: ${gasLimit}`);

const transaction = await wattLock.settleWithProof(...args, { gasLimit });
console.log(`Proof submission: ${transaction.hash}`);
const receipt = await transaction.wait();

const settled = receipt.logs
  .map((log) => {
    try {
      return wattLock.interface.parseLog(log);
    } catch {
      return null;
    }
  })
  .find((event) => event?.name === "JobSettled");

if (!settled) throw new Error("CC3 transaction mined without JobSettled");

console.log(
  JSON.stringify(
    {
      sourceTransaction: process.env.SOURCE_TX_HASH,
      proofTransaction: transaction.hash,
      jobId: settled.args.jobId,
      certificateId: settled.args.certificateId,
      queryId: settled.args.queryId,
      provider: settled.args.provider,
      reward: settled.args.reward.toString(),
      allocationHash: settled.args.allocationHash,
    },
    null,
    2,
  ),
);
