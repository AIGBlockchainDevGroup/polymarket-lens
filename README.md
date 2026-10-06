# Polymarket Lens

A read-only smart contract for **Polymarket** on **Polygon**. One call shows a wallet's YES/NO shares, whether the market is resolved, how much can be **redeemed** after resolution, and how much can be **merged** back into collateral before it.

The contract holds no funds and has no write functions, so it is safe to deploy and call from any frontend, bot or script.

## Why

Polymarket positions are ERC‑1155 tokens in Gnosis Conditional Tokens (CTF). Checking a portfolio normally takes several RPC calls per market plus manual payout math. `PolymarketLens` does it in a single `eth_call`, including batches across many markets.

## Functions

| Function | What it returns |
| --- | --- |
| `getConditionId(oracle, questionId, slots)` | Condition id, same formula as CTF |
| `getPositionIds(conditionId)` | YES / NO token ids for the default collateral |
| `getMarket(conditionId)` / `getMarkets(ids[])` | Outcome count, resolution status, payouts |
| `getUserPosition(user, conditionId)` | Balances, `redeemable`, `mergeable` |
| `getUserPositionByTokens(user, conditionId, yesId, noId)` | Same, using token ids from the Polymarket API (works with any collateral) |
| `getUserPositions(user, ids[])` | Positions across markets + totals |
| `getRedeemableConditions(user, ids[])` | Only the markets where the wallet has winnings to claim |

## Addresses (Polygon, chain id 137)

| Contract | Address |
| --- | --- |
| Conditional Tokens | `0x4D97DCd97eC945f40cF65F87097ACe5EA0476045` |
| pUSD (current collateral) | `0xC011a7E12a19f7B1f670d46F03B03f3342E82DFB` |
| USDC.e (older markets) | `0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174` |

Source: [Polymarket docs](https://docs.polymarket.com/resources/contracts). If you are unsure which collateral a market uses, prefer `getUserPositionByTokens` with the `clobTokenIds` from the Gamma API.

## Quick start

```bash
npm install
npm test
```

## Deploy to Polygon

```bash
cp .env.example .env   # fill PRIVATE_KEY (a fresh wallet with a little POL for gas)
npm run deploy:polygon
npx hardhat verify --network polygon <LENS_ADDRESS> <CTF> <COLLATERAL>
```

## Check a wallet

```bash
LENS=0xYourLens WALLET=0xYourWallet SLUGS=some-market-slug,another-slug npm run check
```

The slug is the last part of a Polymarket market URL.

## Project layout

```
contracts/PolymarketLens.sol              main contract
contracts/test/MockConditionalTokens.sol  CTF mock for tests
test/PolymarketLens.test.js               Hardhat tests
scripts/deploy.js                         deployment
scripts/check-positions.js                read positions via Gamma API + lens
```

## Limitations

- Binary (2-outcome) markets only; other conditions revert with `NotBinaryMarket`.
- Neg-risk markets: use `getUserPositionByTokens` with the market's token ids.
- Values are in collateral units with 6 decimals.

## License

MIT
