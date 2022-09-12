// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.0;

import "../../../oracles/MasterPriceOracle.sol";
import "../../../oracles/default/UniswapTwapPriceOracleV2Root.sol";
import "../../../oracles/default/UniswapTwapPriceOracleV2Factory.sol";
import "../../../external/uniswap/IUniswapV2Factory.sol";
import "../../config/BaseTest.t.sol";
import { UniswapTwapPriceOracleV2Resolver } from "../../../oracles/default/UniswapTwapPriceOracleV2Resolver.sol";

contract UniswapTwapOracleV2ResolverTest is BaseTest {
  UniswapTwapPriceOracleV2Root twapPriceOracleRoot;
  UniswapTwapPriceOracleV2Resolver resolver;
  IUniswapV2Factory uniswapV2Factory;
  MasterPriceOracle mpo;

  struct Observation {
    uint32 timestamp;
    uint256 price0Cumulative;
    uint256 price1Cumulative;
  }

  function setUp() public {
    uniswapV2Factory = IUniswapV2Factory(ap.getAddress("IUniswapV2Factory"));
    mpo = MasterPriceOracle(ap.getAddress("MasterPriceOracle"));
  }

  function getTokenTwapPrice(address tokenAddress) internal returns (uint256) {
    // return the price denominated in W_NATIVE
    return mpo.price(tokenAddress);
  }

  function testUniswapTwapResolve() public shouldRun(forChains(MOONBEAM_MAINNET)) {
    UniswapTwapPriceOracleV2Resolver resolver = UniswapTwapPriceOracleV2Resolver(0x6B98340336cE524835F14d354a36ad880Ef30782);
    address[] memory pairs1 = new address[](2);
    address[] memory baseTokens = new address[](2);
    uint256[] memory minPeriods = new uint256[](2);
    uint256[] memory deviationThresholds = new uint256[](2);
    pairs1[0] = 0x7F5Ac0FC127bcf1eAf54E3cd01b00300a0861a62;
    pairs1[1] = 0xd47BeC28365a82C0C006f3afd617012B02b129D6;
    baseTokens[0] = 0xAcc15dC74880C9944775448304B263D191c6077F;
    baseTokens[1] = 0xAcc15dC74880C9944775448304B263D191c6077F;
    minPeriods[0] = 1800;
    minPeriods[1] = 1800;
    deviationThresholds[0] = 50000000000000000;
    deviationThresholds[0] = 50000000000000000;

    bool[] memory res = twapPriceOracleRoot.workable(pairs1, baseTokens, minPeriods, deviationThresholds);

    address[] memory pairs = resolver.getWorkablePairs();
    for (uint256 i = 0; i < pairs.length; i += 1) {
      if (res[i]) {
        emit log("true");
      } else {
        emit log("false");
      }
      emit log_address(pairs[i]);
    }
  }

  // BUSD DAI
  function testBusdDaiPriceUpdate() public shouldRun(forChains(BSC_MAINNET)) {
    UniswapTwapPriceOracleV2Resolver.PairConfig[] memory pairs = new UniswapTwapPriceOracleV2Resolver.PairConfig[](0);
    resolver = new UniswapTwapPriceOracleV2Resolver(pairs, twapPriceOracleRoot);
    twapPriceOracleRoot = UniswapTwapPriceOracleV2Root(0x81D71C46615320Ba4fbbD9fDFA6310ef93A92f31); // TODO: add to ap
    address WBNB_BUSD = 0x58F876857a02D6762E0101bb5C46A8c1ED44Dc16; // WBNB-BUSD
    address WBNB_DAI = 0xc7c3cCCE4FA25700fD5574DA7E200ae28BBd36A3; // WBNB-DAI
    address wbnb = 0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c; // WBNB

    UniswapTwapPriceOracleV2Resolver.PairConfig memory pairConfig = UniswapTwapPriceOracleV2Resolver.PairConfig({
      pair: WBNB_BUSD,
      baseToken: wbnb,
      minPeriod: 1800,
      deviationThreshold: 50000000000000000
    });

    resolver.addPair(pairConfig);
    pairConfig = UniswapTwapPriceOracleV2Resolver.PairConfig({
      pair: WBNB_DAI,
      baseToken: wbnb,
      minPeriod: 1800,
      deviationThreshold: 50000000000000000
    });
    resolver.addPair(pairConfig);

    address[] memory workablePairs = resolver.getWorkablePairs();
    emit log_named_bytes("workablePairs: ", abi.encode(workablePairs));
    (bool canExec, bytes memory execPayload) = resolver.checker();
    emit log_named_bytes("execPayload: ", execPayload);
    assertTrue(canExec);
    assertEq(abi.encodeWithSelector(resolver.updatePairs.selector, workablePairs), execPayload);

    resolver.updatePairs(workablePairs);

    assertTrue(getTokenTwapPrice(WBNB_BUSD) > 0);
    assertTrue(getTokenTwapPrice(WBNB_DAI) > 0);
  }

  function testStellaWglmrPriceUpdate() public shouldRun(forChains(MOONBEAM_MAINNET)) {
    twapPriceOracleRoot = UniswapTwapPriceOracleV2Root(0x7645f0A9F814286857E937cB1b3fa9659B03385b); // TODO: add to ap

    address STELLA_WGLMR = 0x7F5Ac0FC127bcf1eAf54E3cd01b00300a0861a62; // STELLA/WGLMR
    address CELR_WGLMR = 0xd47BeC28365a82C0C006f3afd617012B02b129D6; // CELR/WGLMR
    address wglmr = 0xAcc15dC74880C9944775448304B263D191c6077F; // WBNB
    uint observationCount = twapPriceOracleRoot.observationCount(STELLA_WGLMR);
    emit log_named_uint("STELLA_WGLMR observationCount: ", observationCount);
    (uint32 timestamp, uint256 price0Cumulative, uint256 price1Cumulative) = twapPriceOracleRoot.observations(STELLA_WGLMR, 2);
    emit log_named_uint("STELLA_WGLMR observations timestamp: ", timestamp);
    emit log_named_bytes("STELLA_WGLMR observations timestamp diff: ", abi.encode(block.timestamp - timestamp > 15 minutes));
    emit log_named_uint("STELLA_WGLMR observations price0Cumulative: ", price0Cumulative);
    emit log_named_uint("STELLA_WGLMR observations price1Cumulative: ", price1Cumulative);

    resolver = UniswapTwapPriceOracleV2Resolver(0x46Ae511521f2AceCa553bBB92fCf43BD57a41816);

    UniswapTwapPriceOracleV2Resolver.PairConfig memory pairConfig = UniswapTwapPriceOracleV2Resolver.PairConfig({
      pair: STELLA_WGLMR,
      baseToken: wglmr,
      minPeriod: 1800,
      deviationThreshold: 50000000000000000
    });

    // resolver.addPair(pairConfig);
    pairConfig = UniswapTwapPriceOracleV2Resolver.PairConfig({
      pair: CELR_WGLMR,
      baseToken: wglmr,
      minPeriod: 1800,
      deviationThreshold: 50000000000000000
    });
    // resolver.addPair(pairConfig);

    address[] memory workablePairs = resolver.getWorkablePairs();
    emit log_named_uint("workablePairs: ", workablePairs.length);
    for (uint256 i = 0; i < workablePairs.length; i++) {
      emit log_named_address("workablePairs: ", workablePairs[i]);
    }
    (bool canExec, bytes memory execPayload) = resolver.checker();
    emit log_named_bytes("canExec: ", abi.encode(canExec));
    emit log_named_bytes("execPayload: ", execPayload);
    assertTrue(canExec);
    assertEq(abi.encodeWithSelector(resolver.updatePairs.selector, workablePairs), execPayload);

    resolver.updatePairs(workablePairs);

    // assertTrue(getTokenTwapPrice(STELLA_WGLMR) > 0);
    // assertTrue(getTokenTwapPrice(CELR_WGLMR) > 0);
  }
}
