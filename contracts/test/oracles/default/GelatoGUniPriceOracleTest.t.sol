// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.0;

import { BaseTest } from "../../config/BaseTest.t.sol";
import { GelatoGUniPriceOracle } from "../../../oracles/default/GelatoGUniPriceOracle.sol";
import { MasterPriceOracle } from "../../../oracles/MasterPriceOracle.sol";

contract GelatoGUniPriceOracleTest is BaseTest {
  GelatoGUniPriceOracle private oracle;
  MasterPriceOracle mpo;

  function afterForkSetUp() internal override {
    mpo = MasterPriceOracle(ap.getAddress("MasterPriceOracle"));
    oracle = new GelatoGUniPriceOracle(ap.getAddress("wtoken"));
  }

  function testPriceGelatoGUni() public forkAtBlock(POLYGON_MAINNET, 32016397) {
    address PAR_USDC_ARRAKIS_VAULT = 0xC1DF4E2fd282e39346422e40C403139CD633Aacd;
    address WBTC_WETH_ARRAKIS_VAULT = 0x590217ef04BcB96FF6Da991AB070958b8F9E77f0;

    vm.prank(address(mpo));
    uint256 price_PAR_USDC = oracle.price(PAR_USDC_ARRAKIS_VAULT);

    vm.prank(address(mpo));
    uint256 price_WBTC_WETH = oracle.price(WBTC_WETH_ARRAKIS_VAULT);

    assertEq(price_PAR_USDC, 78039149688749857849871);
    assertEq(price_WBTC_WETH, 448601424267609461887094567);
    assertGt(price_WBTC_WETH, price_PAR_USDC);
  }
}
