const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("PolymarketLens", function () {
  let ctf, lens, user, oracle, collateral;
  const q1 = ethers.id("Will ETH close above $5k?");
  const q2 = ethers.id("Will it rain in Kyiv tomorrow?");
  const USDC = (n) => ethers.parseUnits(String(n), 6);

  async function prepare(q, slots = 2) {
    await ctf.prepareCondition(oracle.address, q, slots);
    return lens.getConditionId(oracle.address, q, slots);
  }

  beforeEach(async () => {
    [user, oracle] = await ethers.getSigners();
    collateral = ethers.Wallet.createRandom().address;
    ctf = await (await ethers.getContractFactory("MockConditionalTokens")).deploy();
    lens = await (await ethers.getContractFactory("PolymarketLens")).deploy(await ctf.getAddress(), collateral);
  });

  it("computes the same conditionId as CTF", async () => {
    const expected = ethers.solidityPackedKeccak256(["address", "bytes32", "uint256"], [oracle.address, q1, 2]);
    expect(await prepare(q1)).to.equal(expected);
  });

  it("returns empty data for unknown conditions", async () => {
    const m = await lens.getMarket(ethers.ZeroHash);
    expect(m.outcomeSlotCount).to.equal(0n);
    const p = await lens.getUserPosition(user.address, ethers.ZeroHash);
    expect(p.yesBalance).to.equal(0n);
  });

  it("reverts on non-binary markets", async () => {
    const cid = await prepare(q1, 3);
    await expect(lens.getMarket(cid)).to.be.revertedWithCustomError(lens, "NotBinaryMarket");
  });

  it("shows balances and mergeable amount before resolution", async () => {
    const cid = await prepare(q1);
    const [yes, no] = await lens.getPositionIds(cid);
    await ctf.mint(user.address, yes, USDC(100));
    await ctf.mint(user.address, no, USDC(40));

    const p = await lens.getUserPosition(user.address, cid);
    expect(p.yesBalance).to.equal(USDC(100));
    expect(p.noBalance).to.equal(USDC(40));
    expect(p.resolved).to.equal(false);
    expect(p.mergeable).to.equal(USDC(40));
    expect(p.redeemable).to.equal(0n);
  });

  it("calculates redeemable amount after YES wins", async () => {
    const cid = await prepare(q1);
    const [yes, no] = await lens.getPositionIds(cid);
    await ctf.mint(user.address, yes, USDC(100));
    await ctf.mint(user.address, no, USDC(40));
    await ctf.reportPayouts(cid, [1, 0]);

    const p = await lens.getUserPosition(user.address, cid);
    expect(p.resolved).to.equal(true);
    expect(p.redeemable).to.equal(USDC(100));
    expect(p.mergeable).to.equal(0n);
  });

  it("handles 50/50 resolution", async () => {
    const cid = await prepare(q1);
    const [yes, no] = await lens.getPositionIds(cid);
    await ctf.mint(user.address, yes, USDC(100));
    await ctf.mint(user.address, no, USDC(40));
    await ctf.reportPayouts(cid, [1, 1]);
    expect((await lens.getUserPosition(user.address, cid)).redeemable).to.equal(USDC(70));
  });

  it("works with explicit token ids (any collateral)", async () => {
    const cid = await prepare(q1);
    const yesId = 111n, noId = 222n;
    await ctf.mint(user.address, noId, USDC(25));
    await ctf.reportPayouts(cid, [0, 1]);
    const p = await lens.getUserPositionByTokens(user.address, cid, yesId, noId);
    expect(p.noBalance).to.equal(USDC(25));
    expect(p.redeemable).to.equal(USDC(25));
  });

  it("aggregates many markets and filters redeemable ones", async () => {
    const c1 = await prepare(q1);
    const c2 = await prepare(q2);
    const [y1] = await lens.getPositionIds(c1);
    const [y2, n2] = await lens.getPositionIds(c2);
    await ctf.mint(user.address, y1, USDC(10));
    await ctf.mint(user.address, y2, USDC(5));
    await ctf.mint(user.address, n2, USDC(8));
    await ctf.reportPayouts(c1, [1, 0]);

    const [list, totalRedeemable, totalMergeable] = await lens.getUserPositions(user.address, [c1, c2]);
    expect(list.length).to.equal(2);
    expect(totalRedeemable).to.equal(USDC(10));
    expect(totalMergeable).to.equal(USDC(5));
    expect(await lens.getRedeemableConditions(user.address, [c1, c2])).to.deep.equal([c1]);
  });
});
