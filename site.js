const WattLockSite = (() => {
  const base = location.pathname.match(/^\/wattlock(?=\/|$)/) ? "/wattlock" : "";
  const nav = [
    ["Mechanism", `${base}/how-it-works/`],
    ["Replay", `${base}/demo/`],
    ["Proof", `${base}/proof/`],
    ["FAQ", `${base}/faq/`],
  ];

  function ensureFonts() {
    if (document.querySelector("[data-geist-fonts]")) return;
    const fonts = document.createElement("link");
    fonts.rel = "stylesheet";
    fonts.setAttribute("data-geist-fonts", "");
    fonts.href =
      "https://cdn.jsdelivr.net/npm/@fontsource-variable/geist@5.2.5/index.css";
    const mono = document.createElement("link");
    mono.rel = "stylesheet";
    mono.href = "https://cdn.jsdelivr.net/npm/@fontsource-variable/geist-mono@5.2.5/index.css";
    document.head.append(fonts, mono);
  }

  function mountChrome(active) {
    ensureFonts();
    const header = document.querySelector("[data-site-header]");
    const footer = document.querySelector("[data-site-footer]");

    if (header) {
      const activeFor = (label) =>
        active === label ||
        (active === "Play demo" && label === "Replay") ||
        (active === "How it works" && label === "Mechanism");
      header.innerHTML = `
        <a class="brand" href="${base}/" aria-label="WattLock home"><span class="brand-mark">W</span>WattLock</a>
        <nav aria-label="Main navigation">
          ${nav.map(([label, href]) => `<a class="${activeFor(label) ? "is-active" : ""}" href="${href}">${label}</a>`).join("")}
        </nav>
        <a class="nav-cta" href="${base}/proof/">Inspect proof</a>`;
    }

    if (footer) {
      footer.innerHTML = `
        <div>
          <a class="brand" href="${base}/"><span class="brand-mark">W</span>WattLock</a>
          <p>Certificate-backed compute allocation on Creditcoin.</p>
          <p class="footer-note">Sepolia to Attestcoin to CC3 testnet. Demo is a replay.</p>
        </div>
        <div class="footer-links">
          <a href="${base}/proof/">Proof</a>
          <a href="${base}/demo/">Replay</a>
          <a href="${base}/how-it-works/">Mechanism</a>
          <a href="${base}/faq/">FAQ</a>
        </div>
        <div class="footer-links">
          <a href="https://github.com/Cassxbt/wattlock">GitHub</a>
          <a href="https://creditcoin-testnet.blockscout.com/address/0x43259Ac2952ae1583BDF0DC4756Eb86ec963ee39?tab=contract">WattLockASC</a>
          <a href="https://wattlock.vercel.app/proof/">Live proof</a>
        </div>`;
    }
  }

  function mountDemo() {
    const panel = document.querySelector("[data-demo-panel]");
    if (!panel) return;

    const allowed = [
      ["1", "Reserve", "CertificateReserved emitted on Sepolia", "complete"],
      ["2", "Prove", "Attestcoin proves the source receipt", "complete"],
      ["3", "Lock", "Allocation commitment matches the funded job", "complete"],
      ["4", "Settle", "1 tCTC released to the fixed provider", "settled"],
    ];
    const blocked = [
      ["1", "Reserve", "Duplicate certificate submitted", "complete"],
      ["2", "Block", "CertificateAlreadyReserved()", "blocked"],
    ];

    function render(mode, running = false) {
      const stages = mode === "allowed" ? allowed : blocked;
      panel.innerHTML = `
        <div class="demo-kicker"><span>REPLAY</span><span>${mode === "allowed" ? "Allowed allocation" : "Duplicate attack"} · ${running ? "Replaying…" : "not a live transaction"}</span></div>
        <div class="demo-steps">
          ${stages.map(([number, title, detail, state], index) => `<article class="demo-step ${state} ${running ? "is-running" : ""}" style="--delay:${index * 180}ms"><span>${number}</span><div><h3>${title}</h3><p>${detail}</p></div><strong>${state === "blocked" ? "Blocked" : state === "settled" ? "Reported settle" : "Verified"}</strong></article>`).join("")}
        </div>
        <p class="demo-boundary">This is a guided replay of the linked testnet receipts. It does not request a wallet or spend funds.</p>`;
    }

    document.querySelectorAll("[data-demo-mode]").forEach((button) => {
      button.addEventListener("click", () => {
        const mode = button.dataset.demoMode;
        document.querySelectorAll("[data-demo-mode]").forEach((item) => item.setAttribute("aria-pressed", String(item === button)));
        render(mode, true);
        window.setTimeout(() => render(mode, false), mode === "allowed" ? 950 : 560);
      });
    });
    render("allowed");
  }

  return { mountChrome, mountDemo };
})();
