// Usage:
//   LENS=0x... WALLET=0x... SLUGS=market-slug-1,market-slug-2 npm run check
// Market slugs are the last part of a Polymarket URL: polymarket.com/event/<event>/<market-slug>
const hre = require("hardhat");

const GAMMA = "https://gamma-api.polymarket.com/markets";

async function fetchMarket(slug) {
  const res = await fetch(`${GAMMA}?slug=${encodeURIComponent(slug)}`);
  if (!res.ok) throw new Error(`Gamma API ${res.status} for ${slug}`);
  const [m] = await res.json();
  if (!m) throw new Error(`Market not found: ${slug}`);
  const [yesId, noId] = JSON.parse(m.clobTokenIds);
  return { question: m.question, conditionId: m.conditionId, yesId, noId };
}

async function main() {
  const { LENS, WALLET, SLUGS } = process.env;
  if (!LENS || !WALLET || !SLUGS) throw new Error("Set LENS, WALLET and SLUGS env vars");

  const lens = await hre.ethers.getContractAt("PolymarketLens", LENS);
  const fmt = (v) => hre.ethers.formatUnits(v, 6);
  let totalRedeemable = 0n;

  for (const slug of SLUGS.split(",").map((s) => s.trim())) {
    const m = await fetchMarket(slug);
    const p = await lens.getUserPositionByTokens(WALLET, m.conditionId, m.yesId, m.noId);
    totalRedeemable += p.redeemable;
    console.log(`\n${m.question}`);
    console.log(`  YES: ${fmt(p.yesBalance)}  NO: ${fmt(p.noBalance)}  resolved: ${p.resolved}`);
    if (p.resolved) console.log(`  redeemable: ${fmt(p.redeemable)} USD`);
    else if (p.mergeable > 0n) console.log(`  mergeable back to collateral: ${fmt(p.mergeable)} USD`);
  }
  console.log(`\nTotal redeemable: ${fmt(totalRedeemable)} USD`);
}

main().catch((e) => {
  console.error(e);
  process.exitCode = 1;
});
