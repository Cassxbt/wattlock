import { keccak256, concat, zeroPadValue, toBeHex } from "https://cdn.jsdelivr.net/npm/ethers@6.17.0/+esm";

const TOPIC_VERIFIED = keccak256(new TextEncoder().encode("TransactionVerified(uint64,uint64,uint64)"));
const TOPIC_SETTLED = keccak256(
  new TextEncoder().encode("JobSettled(bytes32,bytes32,bytes32,address,uint128,bytes32)"),
);

const STATES = {
  recomputed: {
    eyebrow: "recomputed",
    title: "Chain matches",
    body: "Public explorers agree with the published hashes. This page hashed queryId from the 0x0FD2 log.",
  },
  failed: {
    eyebrow: "failed",
    title: "Mismatch",
    body: "A live check disagreed with the published record. Treat this page as false until the explorers match.",
  },
  "not deployed here": {
    eyebrow: "not deployed here",
    title: "Wrong contract",
    body: "A receipt did not land on the published WattLockASC or Block Prover address.",
  },
  "reported, not verified here": {
    eyebrow: "reported, not verified here",
    title: "Explorer unreachable",
    body: "This browser could not re-query the chain. The hashes below are still the published receipts.",
  },
};

function queryIdFromProof(chainKey, height, txIndex) {
  return keccak256(
    concat([
      zeroPadValue(toBeHex(chainKey), 32),
      zeroPadValue(toBeHex(height), 8),
      zeroPadValue(toBeHex(txIndex), 32),
    ]),
  );
}

function topicUint(topic) {
  return BigInt(topic);
}

async function getJson(urls) {
  let lastError = null;
  for (const url of urls) {
    try {
      const response = await fetch(url, { headers: { Accept: "application/json" } });
      if (!response.ok) {
        lastError = new Error(`${response.status} ${url}`);
        continue;
      }
      return await response.json();
    } catch (error) {
      lastError = error;
    }
  }
  throw lastError ?? new Error("fetch failed");
}

function txStatus(tx) {
  const status = String(tx.status ?? "").toLowerCase();
  const result = String(tx.result ?? "").toLowerCase();
  if (status === "ok" || result === "success") return "success";
  if (status === "error" || result === "error" || result === "reverted") return "failed";
  return "unknown";
}

function logAddress(log) {
  const address = log.address;
  if (typeof address === "string") return address.toLowerCase();
  return (address?.hash || "").toLowerCase();
}

function setVerdict(el, state, detail) {
  const copy = STATES[state];
  el.dataset.state = state;
  el.classList.toggle("is-failed", state === "failed");
  el.classList.toggle("is-pending", state === "reported, not verified here");
  el.querySelector("[data-verdict-eyebrow]").textContent = copy.eyebrow;
  el.querySelector("[data-verdict-title]").textContent = copy.title;
  el.querySelector("[data-verdict-body]").textContent = detail ? `${copy.body} ${detail}` : copy.body;
}

function setChecks(list, rows) {
  list.innerHTML = rows
    .map(
      ([state, label]) =>
        `<li data-check-state="${state}"><span>${state}</span><span>${label}</span></li>`,
    )
    .join("");
}

async function run() {
  const root = document.querySelector("[data-proof-root]");
  const list = document.querySelector("[data-proof-checks]");
  if (!root || !list) return;

  const wattlock = root.dataset.wattlock.toLowerCase();
  const prover = root.dataset.prover.toLowerCase();
  const expectedQuery = (new URLSearchParams(location.search).get("queryId") || root.dataset.queryId).toLowerCase();
  const settleHash = root.dataset.settle;
  const refuseCc3 = root.dataset.cc3Refuse;
  const refuseSepolia = root.dataset.sepoliaRefuse;
  const cc3 = ["/api/cc3", "https://creditcoin-testnet.blockscout.com/api/v2"];
  const sepolia = ["/api/sepolia", "https://eth-sepolia.blockscout.com/api/v2"];

  const rows = [];
  const mark = (state, label) => {
    rows.push([state, label]);
    return state;
  };

  try {
    const settle = await getJson(cc3.map((base) => `${base}/transactions/${settleHash}`));
    const to = (settle.to?.hash || settle.to || "").toLowerCase();
    if (to !== wattlock) {
      mark("not deployed here", `Settle to ${to || "unknown"}, expected WattLockASC`);
      setChecks(list, rows);
      setVerdict(root, "not deployed here");
      return;
    }
    if (txStatus(settle) !== "success") {
      mark("failed", "Published settle receipt is not success");
      setChecks(list, rows);
      setVerdict(root, "failed");
      return;
    }
    mark("recomputed", "CC3 settle is success on WattLockASC");

    const logs = await getJson(cc3.map((base) => `${base}/transactions/${settleHash}/logs`));
    const items = logs.items || logs || [];
    const verified = items.find(
      (log) => logAddress(log) === prover && (log.topics?.[0] || "").toLowerCase() === TOPIC_VERIFIED.toLowerCase(),
    );
    const settled = items.find(
      (log) => logAddress(log) === wattlock && (log.topics?.[0] || "").toLowerCase() === TOPIC_SETTLED.toLowerCase(),
    );
    if (!verified || !settled) {
      mark("failed", "Missing 0x0FD2 TransactionVerified or JobSettled");
      setChecks(list, rows);
      setVerdict(root, "failed");
      return;
    }

    const chainKey = topicUint(verified.topics[1]);
    const height = topicUint(verified.topics[2]);
    const txIndex = topicUint(verified.data);
    const recomputed = queryIdFromProof(chainKey, height, txIndex).toLowerCase();
    const logged = (settled.topics[3] || "").toLowerCase();
    if (recomputed !== logged || recomputed !== expectedQuery) {
      mark("failed", `queryId ${recomputed} ≠ published ${expectedQuery}`);
      setChecks(list, rows);
      setVerdict(root, "failed");
      return;
    }
    mark(
      "recomputed",
      `queryId ${recomputed.slice(0, 10)}… from chainKey ${chainKey} height ${height} txIndex ${txIndex}`,
    );

    const sepoliaTx = await getJson(sepolia.map((base) => `${base}/transactions/${refuseSepolia}`));
    if (txStatus(sepoliaTx) !== "failed") {
      mark("failed", "Sepolia reuse receipt is not a revert");
      setChecks(list, rows);
      setVerdict(root, "failed");
      return;
    }
    mark("recomputed", "Sepolia CertificateAlreadyReserved receipt failed as published");

    const cc3Tx = await getJson(cc3.map((base) => `${base}/transactions/${refuseCc3}`));
    const cc3To = (cc3Tx.to?.hash || cc3Tx.to || "").toLowerCase();
    if (cc3To !== wattlock) {
      mark("not deployed here", "CC3 refuse is not WattLockASC");
      setChecks(list, rows);
      setVerdict(root, "not deployed here");
      return;
    }
    if (txStatus(cc3Tx) !== "failed") {
      mark("failed", "CC3 query-replay receipt is not a revert");
      setChecks(list, rows);
      setVerdict(root, "failed");
      return;
    }
    mark("recomputed", "CC3 Query already processed receipt failed as published");

    setChecks(list, rows);
    setVerdict(root, "recomputed");
  } catch (error) {
    mark("reported, not verified here", error.message || "fetch failed");
    setChecks(list, rows);
    setVerdict(root, "reported, not verified here");
  }
}

run();
