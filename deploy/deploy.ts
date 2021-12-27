import { HardhatRuntimeEnvironment } from "hardhat/types";
import { DeployFunction } from "hardhat-deploy/types";
import { ethers } from "hardhat";

/**
 * Hardhat task defining the contract deployments for nxtp
 *
 * @param hre Hardhat environment to deploy to
 */
const func: DeployFunction = async ({ ethers, getNamedAccounts, deployments }): Promise<void> => {
  const { bob, alice, deployer } = await getNamedAccounts();
  console.log("deployer: ", deployer);
  let dep = await deployments.deterministic("Comptroller", {
    from: deployer,
    salt: ethers.utils.keccak256(deployer),
    args: [],
    log: true,
  });

  const comp = await dep.deploy();
  console.log("Comptroller: ", comp.address);

  dep = await deployments.deterministic("FusePoolDirectory", {
    from: deployer,
    salt: ethers.utils.keccak256(deployer),
    args: [],
    log: true,
  });
  const fpd = await dep.deploy();
  console.log("FusePoolDirectory: ", fpd.address);
  const fusePoolDirectory = await ethers.getContract("FusePoolDirectory", deployer);
  let tx = await fusePoolDirectory.initialize(true, [deployer, alice, bob]);
  await tx.wait();

  dep = await deployments.deterministic("FuseSafeLiquidator", {
    from: deployer,
    salt: ethers.utils.keccak256(deployer),
    args: [],
    log: true,
  });
  const fsl = await dep.deploy();
  console.log("FuseSafeLiquidator: ", fsl.address);

  dep = await deployments.deterministic("FuseFeeDistributor", {
    from: deployer,
    salt: ethers.utils.keccak256(deployer),
    args: [],
    log: true,
  });
  const ffd = await dep.deploy();
  console.log("FuseFeeDistributor: ", ffd.address);
  const fuseFeeDistributor = await ethers.getContract("FuseFeeDistributor", deployer);
  await fuseFeeDistributor.initialize(ethers.utils.parseEther("0.1"));
  await fuseFeeDistributor._setPoolLimits(
    ethers.utils.parseEther("1"),
    ethers.constants.MaxUint256,
    ethers.constants.MaxUint256
  );

  dep = await deployments.deterministic("FusePoolLens", {
    from: deployer,
    salt: ethers.utils.keccak256(deployer),
    args: [],
    log: true,
  });
  const fpl = await dep.deploy();
  console.log("FusePoolLens: ", fpl.address);
  const fusePoolLens = await ethers.getContract("FusePoolLens", deployer);
  await fusePoolLens.initialize(fusePoolDirectory.address);

  dep = await deployments.deterministic("FusePoolLensSecondary", {
    from: deployer,
    salt: ethers.utils.keccak256(deployer),
    args: [],
    log: true,
  });
  const fpls = await dep.deploy();
  console.log("FusePoolLensSecondary: ", fpls.address);
  const fusePoolLensSecondary = await ethers.getContract("FusePoolLensSecondary", deployer);
  await fusePoolLensSecondary.initialize(fusePoolDirectory.address);

  dep = await deployments.deterministic("JumpRateModel", {
    from: deployer,
    salt: ethers.utils.keccak256(deployer),
    args: [
      "20000000000000000", // baseRatePerYear
      "200000000000000000", // multiplierPerYear
      "2000000000000000000", //jumpMultiplierPerYear
      "900000000000000000", // kink
    ],
    log: true,
  });
  const jrm = await dep.deploy();
  console.log("JumpRateModel: ", jrm.address);

  dep = await deployments.deterministic("CErc20Delegate", {
    from: deployer,
    salt: ethers.utils.keccak256(deployer),
    args: [],
    log: true,
  });
  const erc20Del = await dep.deploy();
  console.log("CErc20Delegate: ", erc20Del.address);

  dep = await deployments.deterministic("CEtherDelegate", {
    from: deployer,
    salt: ethers.utils.keccak256(deployer),
    args: [],
    log: true,
  });
  const ethDel = await dep.deploy();
  console.log("CEtherDelegate: ", ethDel.address);

  dep = await deployments.deterministic("MasterPriceOracle", {
    from: deployer,
    salt: ethers.utils.keccak256(deployer),
    args: [],
    log: true,
  });
  const masterPO = await dep.deploy();
  console.log("MasterPriceOracle: ", masterPO.address);

  dep = await deployments.deterministic("MockPriceOracle", {
    from: bob,
    salt: ethers.utils.keccak256(deployer),
    args: [100],
    log: true,
  });
  const mockPO = await dep.deploy();
  console.log("MockPriceOracle: ", mockPO.address);

  const masterPriceOracle = await ethers.getContract("MasterPriceOracle", deployer);
  const mockPriceOracle = await ethers.getContract("MockPriceOracle", deployer);

  const underlyings = [
    "0x7Fc66500c84A76Ad7e9c93437bFc5Ac33E2DDaE9", // AAVE
    "0x8a12Be339B0cD1829b91Adc01977caa5E9ac121e", // CRV
    "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48", // USDC
  ];

  tx = await masterPriceOracle.initialize(
    underlyings,
    Array(3).fill(mockPriceOracle.address),
    mockPriceOracle.address,
    deployer,
    true
  );
  await tx.wait();
};
export default func;
