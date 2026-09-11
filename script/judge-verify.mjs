import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { JsonRpcProvider, keccak256, concat, zeroPadValue, toBeHex, toUtf8Bytes } from "ethers";

const root = join(dirname(fileURLToPath(import.meta.url)), "..");
const readme = readFileSync(join(root, "README.md"), "utf8");
const tests = readFileSync(join(root, "test/WattLock.t.sol"), "utf8");
const proofHtml = readFileSync(join(root, "proof/index.html"), "utf8");

const WATTLOCK = "0x43259ac2952ae1583bdf0dc4756eb86ec963ee39";
const PROVER = "0x0000000000000000000000000000000000000fd2";
const SETTLE = "0x52853b6220fab2501ef08f9838f9bbe1a5d3dbcb0a0b2a756ed0a3a29853ac5f";
const CC3_REFUSE = "0x13c8302c6aca4a7ce60a284195152a9af0206b4636957a407ad6d7c6f24e0e56";
const SEPOLIA_RESERVE = "0x109b096b94b5d4a312bd78fbe2bded62e53a3a6a1270155a7c6e29ff10d95503";
const SEPOLIA_REFUSE = "0x9e33281808202cfce95588cc43861ae5434a7d05e7d864753b81b130810407fd";
const QUERY = "0x878e33a512eca89f670b0ca875ba27654aa43a27d532bade9c8cd35df7637c18";
const TOPIC_VERIFIED = keccak256(toUtf8Bytes("TransactionVerified(uint64,uint64,uint64)"));
const TOPIC_SETTLED = keccak256(toUtf8Bytes("JobSettled(bytes32,bytes32,bytes32,address,uint128,bytes32)"));

const failures = [];
const fail = (message) => {
  failures.push(message);
  console.error(`FAIL  ${message}`);
};
const pass = (message) => console.log(`ok    ${message}`);

function requireIn(haystack, needle, label) {
  if (!haystack.toLowerCase().includes(needle.toLowerCase())) fail(`missing ${label}`);
  else pass(`README/HTML contains ${label}`);
}

function queryIdFromProof(chainKey, height, txIndex) {
  return keccak256(
    concat([
      zeroPadValue(toBeHex(chainKey), 32),
      zeroPadValue(toBeHex(height), 8),
      zeroPadValue(toBeHex(txIndex), 32),
    ]),
  );
}

function provider(url, chainId) {
  return new JsonRpcProvider(url, chainId, { staticNetwork: true });
}

const testCount = [...tests.matchAll(/function test[A-Za-z0-9_]+\(/g)].length;
const claimed = Number((readme.match(/contains (\d+) unit tests/) || [])[1]);
if (claimed !== testCount) fail(`README claims ${claimed} tests, suite has ${testCount}`);
else pass(`test count ${testCount}`);
if (!tests.includes("processVerifiedForTest")) fail("suite no longer skips 0x0FD2 via processVerifiedForTest");
else pass("harness still uses processVerifiedForTest");
if (!readme.includes("skip the native `0x0FD2`")) fail("README no longer admits the 0x0FD2 skip");
else pass("README admits 0x0FD2 skip");
if (!readme.includes("Operator wait only")) fail("README claims on-chain 0x0FD3");
else pass("0x0FD3 is operator wait only");
if (readme.includes("JUDGING_AND_DECISIONS.md")) fail("README links gitignored planning doc");
else pass("no planning-doc link");

for (const [label, hash] of [
  ["settle", SETTLE],
  ["cc3 refuse", CC3_REFUSE],
  ["sepolia reserve", SEPOLIA_RESERVE],
  ["sepolia refuse", SEPOLIA_REFUSE],
  ["queryId", QUERY],
]) {
  requireIn(readme, hash, label);
  requireIn(proofHtml, hash, `proof ${label}`);
}

const cc3 = provider(process.env.CREDITCOIN_RPC_URL || "https://rpc.cc3-testnet.creditcoin.network", 102031);
const sepolia = provider(
  process.env.SOURCE_CHAIN_RPC_URL ||
    process.env.SEPOLIA_RPC_URL ||
    "https://eth-sepolia.blockscout.com/api/eth-rpc",
  11155111,
);

async function receipt(p, hash, label) {
  const rec = await p.getTransactionReceipt(hash);
  if (!rec) {
    fail(`${label} receipt missing`);
    return null;
  }
  pass(`${label} mined block ${rec.blockNumber} status ${rec.status}`);
  return rec;
}

const settle = await receipt(cc3, SETTLE, "CC3 settle");
const cc3Refuse = await receipt(cc3, CC3_REFUSE, "CC3 refuse");
const sepoliaRefuse = await receipt(sepolia, SEPOLIA_REFUSE, "Sepolia refuse");
const sepoliaReserve = await receipt(sepolia, SEPOLIA_RESERVE, "Sepolia reserve");

if (settle) {
  if (settle.status !== 1) fail("CC3 settle is not success");
  if ((settle.to || "").toLowerCase() !== WATTLOCK) fail("CC3 settle not sent to WattLockASC");
  const verified = settle.logs.find(
    (log) => log.address.toLowerCase() === PROVER && log.topics[0] === TOPIC_VERIFIED,
  );
  const settled = settle.logs.find(
    (log) => log.address.toLowerCase() === WATTLOCK && log.topics[0] === TOPIC_SETTLED,
  );
  if (!verified || !settled) fail("settle missing 0x0FD2 or JobSettled");
  else {
    const chainKey = BigInt(verified.topics[1]);
    const height = BigInt(verified.topics[2]);
    const txIndex = BigInt(verified.data);
    const recomputed = queryIdFromProof(chainKey, height, txIndex).toLowerCase();
    const logged = settled.topics[3].toLowerCase();
    if (recomputed !== QUERY || logged !== QUERY) fail(`queryId drift ${recomputed} / ${logged}`);
    else pass(`queryId recomputed ${recomputed}`);
    if (sepoliaReserve && (BigInt(sepoliaReserve.blockNumber) !== height || BigInt(sepoliaReserve.index) !== txIndex)) {
      fail("0x0FD2 height/index does not match Sepolia reserve receipt");
    } else if (sepoliaReserve) pass("0x0FD2 points at the Sepolia reserve tx");
  }
}

if (cc3Refuse) {
  if (cc3Refuse.status !== 0) fail("CC3 refuse is not a revert");
  if ((cc3Refuse.to || "").toLowerCase() !== WATTLOCK) fail("CC3 refuse not WattLockASC");
  else pass("CC3 refuse reverted on WattLockASC");
}
if (sepoliaRefuse) {
  if (sepoliaRefuse.status !== 0) fail("Sepolia refuse is not a revert");
  else pass("Sepolia refuse reverted");
}

if (failures.length) {
  console.error(`\njudge:verify failed (${failures.length})`);
  process.exit(1);
}
console.log("\njudge:verify passed");
