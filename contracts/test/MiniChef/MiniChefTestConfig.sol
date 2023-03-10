// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import { ITestConfigStorage } from "../abstracts/ITestConfigStorage.sol";

struct MiniChefTestConfig {
  address asset;
  address[] rewardTokens;
  uint256 poolId;
}

contract MiniChefTestConfigStorage is ITestConfigStorage {
  MiniChefTestConfig[] internal testConfigs;

  constructor() {
    // WEVMOS/JUNO

    address[] memory rewardTokens = new address[](1);
    rewardTokens[0] = 0xD4949664cD82660AaE99bEdc034a0deA8A0bd517;

    testConfigs.push(MiniChefTestConfig(0x4Aa9c250874C2d14D0d686833e7b3C5c1837c36c, rewardTokens, 20));
  }

  function getTestConfig(uint256 i) public view returns (bytes memory) {
    return abi.encode(testConfigs[i].asset, testConfigs[i].rewardTokens, testConfigs[i].poolId);
  }

  function getTestConfigLength() public view returns (uint256) {
    return testConfigs.length;
  }
}
