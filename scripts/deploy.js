const hre = require("hardhat");

// Polymarket on Polygon (https://docs.polymarket.com/resources/contracts)
const CTF = "0x4D97DCd97eC945f40cF65F87097ACe5EA0476045";
const PUSD = "0xC011a7E12a19f7B1f670d46F03B03f3342E82DFB"; // current collateral
// Older markets used USDC.e: 0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174

async function main() {
  const collateral = process.env.COLLATERAL || PUSD;
  const Lens = await hre.ethers.getContractFactory("PolymarketLens");
  const lens = await Lens.deploy(CTF, collateral);
  await lens.waitForDeployment();
  const address = await lens.getAddress();
  console.log(`PolymarketLens deployed to ${address}`);
  console.log(`Verify: npx hardhat verify --network polygon ${address} ${CTF} ${collateral}`);
}

main().catch((e) => {
  console.error(e);
  process.exitCode = 1;
});
