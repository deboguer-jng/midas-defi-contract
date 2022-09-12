// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "ds-test/test.sol";
import "forge-std/Vm.sol";
import "../helpers/WithPool.sol";
import "../config/BaseTest.t.sol";

import { MidasERC4626, StellaLpERC4626, IStellaDistributorV2 } from "../../midas/strategies/StellaLpERC4626.sol";
import { ERC20 } from "solmate/tokens/ERC20.sol";
import { ERC20Upgradeable } from "openzeppelin-contracts-upgradeable/contracts/token/ERC20/ERC20Upgradeable.sol";
import { FlywheelCore, IFlywheelRewards } from "flywheel-v2/FlywheelCore.sol";
import { FuseFlywheelDynamicRewardsPlugin } from "fuse-flywheel/rewards/FuseFlywheelDynamicRewardsPlugin.sol";
import { IFlywheelBooster } from "flywheel-v2/interfaces/IFlywheelBooster.sol";
import { Authority } from "solmate/auth/Auth.sol";
import { FixedPointMathLib } from "../../utils/FixedPointMathLib.sol";
import { AbstractERC4626Test } from "../abstracts/AbstractERC4626Test.sol";
import { MidasFlywheelCore } from "../../midas/strategies/flywheel/MidasFlywheelCore.sol";

struct RewardsCycle {
  uint32 start;
  uint32 end;
  uint192 reward;
}

// Tested on block 19052824
contract StellaERC4626Test is AbstractERC4626Test {
  using FixedPointMathLib for uint256;

  IStellaDistributorV2 distributor = IStellaDistributorV2(0xF3a5454496E26ac57da879bf3285Fa85DEBF0388); // what you deposit the LP into

  MidasFlywheelCore[] flywheels;
  FuseFlywheelDynamicRewardsPlugin[] rewards;

  uint256 poolId;
  address marketAddress;
  ERC20 marketKey;
  ERC20Upgradeable[] rewardsToken;

  constructor() WithPool() {}

  function setUp(string memory _testPreFix, bytes calldata testConfig) public override {
    setUpPool("stella-test ", false, 0.1e18, 1.1e18);
    sendUnderlyingToken(depositAmount, address(this));
    (address asset, uint256 _poolId, address[] memory _rewardTokens) = abi.decode(
      testConfig,
      (address, uint256, address[])
    );

    testPreFix = _testPreFix;
    poolId = _poolId;

    for (uint256 i = 0; i < _rewardTokens.length; i += 1) {
      MidasFlywheelCore _flywheel = new MidasFlywheelCore();
      _flywheel.initialize(
        ERC20(_rewardTokens[i]),
        IFlywheelRewards(address(0)),
        IFlywheelBooster(address(0)),
        address(this)
      );
      FuseFlywheelDynamicRewardsPlugin _reward = new FuseFlywheelDynamicRewardsPlugin(
        FlywheelCore(address(_flywheel)),
        1
      );
      flywheels.push(_flywheel);
      rewards.push(_reward);
      _flywheel.setFlywheelRewards(_reward);

      rewardsToken.push(ERC20Upgradeable(_rewardTokens[i]));
    }

    StellaLpERC4626 stellaLpERC4626 = new StellaLpERC4626();
    stellaLpERC4626.initialize(
      ERC20Upgradeable(address(underlyingToken)),
      flywheels,
      IStellaDistributorV2(address(distributor)),
      poolId,
      address(this),
      rewardsToken
    );

    plugin = stellaLpERC4626;

    // Just set it explicitly to 0. Just wanted to make clear that this is not forgotten but expected to be 0
    initialStrategyBalance = getStrategyBalance();
    initialStrategySupply = 0;

    deployCErc20PluginRewardsDelegate(address(plugin), 0.9e18);
    marketAddress = address(comptroller.cTokensByUnderlying(address(underlyingToken)));
    CErc20PluginRewardsDelegate cToken = CErc20PluginRewardsDelegate(marketAddress);
    cToken._setImplementationSafe(address(cErc20PluginRewardsDelegate), false, abi.encode(address(plugin)));
    assertEq(address(cToken.plugin()), address(plugin));

    marketKey = ERC20(marketAddress);

    for (uint256 i = 0; i < _rewardTokens.length; i += 1) {
      cToken.approve(address(_rewardTokens[i]), address(rewards[i]));
      flywheels[i].addStrategyForRewards(marketKey);
    }

    StellaLpERC4626(address(plugin)).setRewardDestination(marketAddress);
  }

  function increaseAssetsInVault() public override {
    sendUnderlyingToken(1000e18, address(distributor));
  }

  function decreaseAssetsInVault() public override {
    vm.prank(0x5B74C99AA2356B4eAa7B85dC486843eDff8Dfdbe); //lpStaker
    underlyingToken.transfer(address(1), 200e18); // transfer doesnt work
  }

  // figure out how to get balance of plugin in LP staker contract
  // make sure it is not balance of underlying, rather balance of shares
  function getDepositShares() public view override returns (uint256) {
    (uint256 amount, , , ) = distributor.userInfo(poolId, address(plugin));
    return amount;
  }

  function getStrategyBalance() public view override returns (uint256) {
    return distributor.poolTotalLp(poolId);
  }

  function getExpectedDepositShares() public view override returns (uint256) {
    return depositAmount;
  }

  function testInitializedValues(string memory assetName, string memory assetSymbol)
    public
    override
    shouldRun(forChains(BSC_MAINNET))
  {
    assertEq(
      plugin.name(),
      string(abi.encodePacked("Midas ", assetName, " Vault")),
      string(abi.encodePacked("!name ", testPreFix))
    );
    assertEq(
      plugin.symbol(),
      string(abi.encodePacked("mv", assetSymbol)),
      string(abi.encodePacked("!symbol ", testPreFix))
    );
    assertEq(address(plugin.asset()), address(underlyingToken), string(abi.encodePacked("!asset ", testPreFix)));
    assertEq(
      address(StellaLpERC4626(address(plugin)).distributor()),
      address(distributor),
      string(abi.encodePacked("!distributor ", testPreFix))
    );
  }

  function testAccumulatingRewardsOnDeposit() public {
    deposit(address(this), depositAmount / 2);

    vm.warp(block.timestamp + 150);
    vm.roll(10);

    (
      address[] memory addresses,
      string[] memory symbols,
      uint256[] memory decimals,
      uint256[] memory amounts
    ) = distributor.pendingTokens(poolId, address(plugin));

    deposit(address(this), depositAmount / 2);

    for (uint256 i = 0; i < addresses.length; i += 1) {
      uint256 actualAmount = ERC20(addresses[i]).balanceOf(address(plugin));
      assertEq(actualAmount, amounts[i], string(abi.encodePacked("!rewardBal ", symbols[i], testPreFix)));
    }
  }

  function testAccumulatingRewardsOnWithdrawal() public {
    deposit(address(this), depositAmount);

    vm.warp(block.timestamp + 150);
    vm.roll(10);

    (
      address[] memory addresses,
      string[] memory symbols,
      uint256[] memory decimals,
      uint256[] memory amounts
    ) = distributor.pendingTokens(poolId, address(plugin));

    plugin.withdraw(poolId, address(this), address(this));

    for (uint256 i = 0; i < addresses.length; i += 1) {
      uint256 actualAmount = ERC20(addresses[i]).balanceOf(address(plugin));
      assertEq(actualAmount, amounts[i], string(abi.encodePacked("!rewardBal ", symbols[i], testPreFix)));
    }
  }

  function testClaimRewards() public {
    // Deposit funds, Rewards are 0
    vm.startPrank(address(this));
    underlyingToken.approve(marketAddress, depositAmount);
    CErc20(marketAddress).mint(depositAmount);
    vm.stopPrank();

    for (uint256 i = 0; i < rewards.length; i += 1) {
      (uint32 start, uint32 end, uint192 reward) = rewards[i].rewardsCycle(ERC20(address(marketAddress)));

      // Rewards can be transfered in the next cycle
      assertEq(end, 0, string(abi.encodePacked("!End ", testPreFix)));

      // Reward amount is still 0
      assertEq(reward, 0, string(abi.encodePacked("!Reward ", testPreFix)));

      vm.warp(block.timestamp + 150);
      vm.roll(10);

      // Call accrue as proxy for withdraw/deposit to claim rewards
      flywheels[i].accrue(ERC20(marketAddress), address(this));

      (
        address[] memory addresses,
        string[] memory symbols,
        uint256[] memory decimals,
        uint256[] memory amounts
      ) = distributor.pendingTokens(poolId, address(plugin));
      uint256 pendingIndex = 0;

      for (uint256 j = 0; j < addresses.length; j += 1) {
        if (addresses[j] == address(rewardsToken[i])) {
          pendingIndex = j;
        }
      }

      // Claim Rewards for the user
      flywheels[i].claimRewards(address(this));

      assertEq(
        rewardsToken[i].balanceOf(address(this)),
        amounts[pendingIndex],
        string(abi.encodePacked("!Bal User ", testPreFix))
      );
      assertEq(
        rewardsToken[i].balanceOf(address(flywheels[i])),
        0,
        string(abi.encodePacked("!Bal Flywheel ", testPreFix))
      );
    }
  }
}
