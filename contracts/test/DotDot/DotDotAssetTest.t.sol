// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "ds-test/test.sol";
import "forge-std/Vm.sol";
import "../helpers/WithPool.sol";
import "../config/BaseTest.t.sol";

import { MockERC20 } from "solmate/test/utils/mocks/MockERC20.sol";
import { DotDotERC4626Test } from "./DotDotLpERC4626Test.sol";
import { DotDotTestConfig, DotDotTestConfigStorage } from "./DotDotTestConfig.sol";
import { AbstractAssetTest } from "../abstracts/AbstractAssetTest.sol";
import { AbstractERC4626Test } from "../abstracts/AbstractERC4626Test.sol";
import { ITestConfigStorage } from "../abstracts/ITestConfigStorage.sol";

// Using 2BRL
// Tested on block 19052824
contract DotDotAssetTest is AbstractAssetTest {
  constructor() forkAtBlock(BSC_MAINNET, 20238373) {
    test = AbstractERC4626Test(address(new DotDotERC4626Test()));
    testConfigStorage = ITestConfigStorage(address(new DotDotTestConfigStorage()));
  }

  function setUpTestContract(bytes calldata testConfig) public override {
    (address masterPriceOracle, address asset) = abi.decode(testConfig, (address, address));

    test.setUpWithPool(MasterPriceOracle(masterPriceOracle), ERC20Upgradeable(asset));

    test.setUp(MockERC20(asset).symbol(), testConfig);
  }

  function testInitializedValues() public override {
    for (uint8 i; i < testConfigStorage.getTestConfigLength(); i++) {
      bytes memory testConfig = testConfigStorage.getTestConfig(i);

      this.setUpTestContract(testConfig);

      (, address asset) = abi.decode(testConfig, (address, address));

      test.testInitializedValues(MockERC20(asset).name(), MockERC20(asset).symbol());
    }
  }

  function testDepositWithIncreasedVaultValue() public override {
    this.runTest(test.testDepositWithIncreasedVaultValue);
  }

  function testDepositWithDecreasedVaultValue() public override {
    this.runTest(test.testDepositWithDecreasedVaultValue);
  }

  function testWithdrawWithIncreasedVaultValue() public override {
    this.runTest(test.testWithdrawWithIncreasedVaultValue);
  }

  function testWithdrawWithDecreasedVaultValue() public override {
    this.runTest(test.testWithdrawWithDecreasedVaultValue);
  }

  function testAccumulatingRewardsOnDeposit() public {
    this.runTest(DotDotERC4626Test(address(test)).testAccumulatingRewardsOnDeposit);
  }

  function testAccumulatingRewardsOnWithdrawal() public {
    this.runTest(DotDotERC4626Test(address(test)).testAccumulatingRewardsOnWithdrawal);
  }

  function testClaimRewards() public {
    this.runTest(DotDotERC4626Test(address(test)).testClaimRewards);
  }
}
