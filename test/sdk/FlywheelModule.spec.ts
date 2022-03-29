import { expect } from "chai";
import { deployments, ethers } from "hardhat";
import Fuse from "../../src/Fuse";
import { CErc20, EIP20Interface } from "../../typechain";
import { setUpPriceOraclePrices, tradeNativeForAsset } from "../utils";
import * as collateralHelpers from "../utils/collateral";
import * as poolHelpers from "../utils/pool";
import * as timeHelpers from "../utils/time";
import { constants } from "ethers";

describe("FlywheelModule", function () {
  let poolAAddress: string;
  let poolBAddress: string;
  let sdk: Fuse;
  let erc20OneCToken: CErc20;
  let erc20TwoCToken: CErc20;

  let erc20OneUnderlying: EIP20Interface;
  let erc20TwoUnderlying: EIP20Interface;

  let chainId: number;

  this.beforeEach(async () => {
    ({ chainId } = await ethers.provider.getNetwork());
    if (chainId === 1337) {
      await deployments.fixture();
    }
    await setUpPriceOraclePrices();
    const { deployer } = await ethers.getNamedSigners();

    sdk = new Fuse(ethers.provider, chainId);

    [poolAAddress] = await poolHelpers.createPool({ signer: deployer, poolName: "PoolA-RewardsDistributor-Test" });
    [poolBAddress] = await poolHelpers.createPool({ signer: deployer, poolName: "PoolB-RewardsDistributor-Test" });

    const assetsA = await poolHelpers.getPoolAssets(poolAAddress, sdk.contracts.FuseFeeDistributor.address);
    const deployedAssetsA = await poolHelpers.deployAssets(assetsA.assets, deployer);

    const [erc20One, erc20Two] = assetsA.assets.filter((a) => a.underlying !== constants.AddressZero);

    const deployedErc20One = deployedAssetsA.find((a) => a.underlying === erc20One.underlying);
    const deployedErc20Two = deployedAssetsA.find((a) => a.underlying === erc20Two.underlying);

    erc20OneCToken = (await ethers.getContractAt("CErc20", deployedErc20One.assetAddress)) as CErc20;
    erc20TwoCToken = (await ethers.getContractAt("CErc20", deployedErc20Two.assetAddress)) as CErc20;

    erc20OneUnderlying = (await ethers.getContractAt("EIP20Interface", erc20One.underlying)) as EIP20Interface;
    erc20TwoUnderlying = (await ethers.getContractAt("EIP20Interface", erc20Two.underlying)) as EIP20Interface;

    if (chainId !== 1337) {
      await tradeNativeForAsset({ account: "alice", token: erc20Two.underlying, amount: "500" });
      await tradeNativeForAsset({ account: "deployer", token: erc20Two.underlying, amount: "500" });
    }
  });

  it.only("1 Pool, 1 Flywheel", async function () {
    const { deployer, alice } = await ethers.getNamedSigners();
    const rewardToken = erc20OneUnderlying;
    const market = erc20OneCToken;
    const marketTwo = erc20TwoCToken;

    console.log({ rewardToken: rewardToken.address, market: market.address, marketTwo: marketTwo.address });

    const fwCore = await sdk.deployFlywheelCore(rewardToken.address, {
      from: deployer.address,
    });
    const fwStaticRewards = await sdk.deployFlywheelStaticRewards(rewardToken.address, fwCore.address, {
      from: deployer.address,
    });

    await sdk.setFlywheelRewards(fwCore.address, fwStaticRewards.address, { from: deployer.address });
    await sdk.addFlywheelCoreToComptroller(fwCore.address, poolAAddress, { from: deployer.address });

    // Funding Static Rewards
    await rewardToken.transfer(fwStaticRewards.address, ethers.utils.parseUnits("100", 18), { from: deployer.address });
    expect(await rewardToken.balanceOf(fwStaticRewards.address)).to.not.eq(0);

    await collateralHelpers.addCollateral(poolAAddress, alice, await market.callStatic.symbol(), "100", true);
    expect(await market.functions.totalSupply()).to.not.eq(0);

    await collateralHelpers.addCollateral(poolAAddress, alice, await erc20TwoCToken.callStatic.symbol(), "100", true);
    expect(await erc20TwoCToken.functions.totalSupply()).to.not.eq(0);

    // Setup Rewards, enable and set RewardInfo
    await sdk.addMarketForRewardsToFlywheelCore(fwCore.address, market.address, { from: deployer.address });
    await sdk.setStaticRewardInfo(
      fwStaticRewards.address,
      market.address,
      {
        rewardsEndTimestamp: 0,
        rewardsPerSecond: ethers.utils.parseUnits("0.000001", 18),
      },
      { from: deployer.address }
    );

    // Setup Rewards, enable and set RewardInfo
    await sdk.addMarketForRewardsToFlywheelCore(fwCore.address, marketTwo.address, { from: deployer.address });
    await sdk.setStaticRewardInfo(
      fwStaticRewards.address,
      marketTwo.address,
      {
        rewardsEndTimestamp: 0,
        rewardsPerSecond: ethers.utils.parseUnits("0.000002", 18),
      },
      { from: deployer.address }
    );
    console.log("Setup RewardInfo ✅");

    await timeHelpers.advanceDays(1);

    const marketRewards = await sdk.getFlywheelMarketRewardsByPools([poolAAddress, poolBAddress], {
      from: alice.address,
    });
    const marketRewardsPoolA = await sdk.getFlywheelMarketRewardsByPool(poolAAddress, {
      from: alice.address,
    });
    console.dir({ marketRewards, marketRewardsPoolA }, { depth: null });
    const claimableRewards = await sdk.getFlywheelClaimableRewards(alice.address, {
      from: alice.address,
    });
    console.dir({ claimableRewards }, { depth: null });

    const claimableRewardsForPool = await sdk.getFlywheelClaimableRewardsForPool(poolAAddress, alice.address, {
      from: alice.address,
    });
    console.dir({ claimableRewardsForPool }, { depth: null });
    const [comptrollerIndexes, comptrollers, rewardsDistributors] =
      await sdk.contracts.FusePoolLensSecondary.getRewardsDistributorsBySupplier(alice.address, {
        from: alice.address,
      });

    // const uniqueRewardsDistributors = rewardsDistributors
    //   .reduce((acc, curr) => [...acc, ...curr], []) // Flatten Array
    //   .filter((value, index, self) => self.indexOf(value) === index); // Unique Array
    // const sdkres = await sdk.contracts.FusePoolLensSecondary.callStatic.getUnclaimedRewardsByDistributors(
    //   alice.address,
    //   uniqueRewardsDistributors,
    //   {
    //     from: alice.address,
    //   }
    // );
    // const flywheelLensRouter = sdk.contracts.FuseFlywheelLensRouter;
    // flywheelLensRouter.functions.getUnclaimedRewardsByMarkets();
  });
});
