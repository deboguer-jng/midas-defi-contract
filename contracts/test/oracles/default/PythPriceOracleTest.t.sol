// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.0;

import "ds-test/test.sol";
import "forge-std/Vm.sol";
import "../../../oracles/default/PythPriceOracle.sol";
import "../../config/BaseTest.t.sol";

contract PythOraclesTest is BaseTest {
  PythPriceOracle oracle;

  function setUp() public {
    oracle = PythPriceOracle(ap.getAddress("PythPriceOracle"));
  }

  function testPriceFeed(address testedTokenAddress, address aggregatorAddress) internal returns (uint256 price) {
    address[] memory underlyings = new address[](1);
    underlyings[0] = testedTokenAddress;
    AggregatorV3Interface[] memory aggregators = new AggregatorV3Interface[](1);
    AggregatorV3Interface feed = AggregatorV3Interface(aggregatorAddress);
    aggregators[0] = feed;

    vm.prank(oracle.admin());
    oracle.setPriceFeeds(underlyings, aggregators, PythPriceOracleV2.FeedBaseCurrency.USD);

    price = oracle.price(testedTokenAddress);
  }

  function testJBRLPrice() public shouldRun(forChains(BSC_MAINNET)) {
    address jBRLAddress = 0x316622977073BBC3dF32E7d2A9B3c77596a0a603;
    address jBRLAggregatorAddress = 0x5cb1Cb3eA5FB46de1CE1D0F3BaDB3212e8d8eF48;

    assert(testPriceFeed(jBRLAddress, jBRLAggregatorAddress) > 0);
  }
}
