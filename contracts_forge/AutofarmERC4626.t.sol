// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.4.23;

import "ds-test/test.sol";
import "forge-std/stdlib.sol";
import "forge-std/Vm.sol";

import { AutofarmERC4626, IAutofarmV2 } from "../contracts/compound/strategies/AutofarmERC4626.sol";
import { ERC20 } from "@rari-capital/solmate/src/tokens/ERC20.sol";
import { MockERC20 } from "@rari-capital/solmate/src/test/utils/mocks/MockERC20.sol";
import { MockStrategy } from "./mocks/autofarm/MockStrategy.sol";
import { MockAutofarmV2 } from "./mocks/autofarm/MockAutofarmV2.sol";
import { IStrategy } from "./mocks/autofarm/IStrategy.sol";
import { FlywheelCore } from "../contracts/flywheel/FlywheelCore.sol";
import { FlywheelDynamicRewards } from "../contracts/flywheel/rewards/FlywheelDynamicRewards.sol";
import { IFlywheelBooster } from "../contracts/flywheel/interfaces/IFlywheelBooster.sol";
import { IFlywheelCore } from "../contracts/flywheel/interfaces/IFlywheelCore.sol";
import { Authority } from "@rari-capital/solmate/src/auth/Auth.sol";

contract AutofarmERC4626Test is DSTest {
  using stdStorage for StdStorage;

  Vm public constant vm = Vm(HEVM_ADDRESS);

  StdStorage stdstore;

  AutofarmERC4626 autofarmERC4626;
  FlywheelCore flywheel;
  FlywheelDynamicRewards flywheelRewards;

  MockERC20 testToken;
  MockERC20 autoToken;
  MockStrategy mockStrategy;
  MockAutofarmV2 mockAutofarm;

  uint256 depositAmount = 100e18;
  ERC20 marketKey;
  address tester = 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266;

  function setUp() public {
    testToken = new MockERC20("TestToken", "TST", 18);
    autoToken = new MockERC20("autoToken", "AUTO", 18);
    mockAutofarm = new MockAutofarmV2(address(autoToken));
    mockStrategy = new MockStrategy(address(testToken), address(mockAutofarm));

    flywheel = new FlywheelCore(
      autoToken,
      FlywheelDynamicRewards(address(0)),
      IFlywheelBooster(address(0)),
      address(this),
      Authority(address(0))
    );

    flywheelRewards = new FlywheelDynamicRewards(autoToken, address(flywheel));
    flywheel.setFlywheelRewards(flywheelRewards);

    autofarmERC4626 = new AutofarmERC4626(
      testToken,
      "TestVault",
      "TSTV",
      0,
      autoToken,
      IAutofarmV2(address(mockAutofarm)),
      IFlywheelCore(address(flywheel))
    );
    marketKey = ERC20(address(autofarmERC4626));
    flywheel.addStrategyForRewards(marketKey);

    // Add mockStrategy to Autofarm
    mockAutofarm.add(ERC20(address(testToken)), 1, address(mockStrategy));
  }

  function testInitializedValues() public {
    assertEq(autofarmERC4626.name(), "TestVault");
    assertEq(autofarmERC4626.symbol(), "TSTV");
    assertEq(address(autofarmERC4626.asset()), address(testToken));
    assertEq(address(autofarmERC4626.autofarm()), address(mockAutofarm));
    assertEq(address(marketKey), address(autofarmERC4626));
    assertEq(testToken.allowance(address(autofarmERC4626), address(mockAutofarm)), type(uint256).max);
    assertEq(autoToken.allowance(address(autofarmERC4626), address(flywheelRewards)), type(uint256).max);
  }

  function deposit() public {
    testToken.mint(address(this), depositAmount);
    testToken.approve(address(autofarmERC4626), depositAmount);
    autofarmERC4626.deposit(depositAmount, address(this));
  }

  function testDeposit() public {
    deposit();
    //Test that the actual transfers worked
    assertEq(testToken.balanceOf(address(this)), 0);
    assertEq(testToken.balanceOf(address(mockAutofarm)), 0);
    assertEq(testToken.balanceOf(address(mockStrategy)), depositAmount);

    // //Test that the balance view calls work
    assertEq(autofarmERC4626.totalAssets(), depositAmount);
    assertEq(autofarmERC4626.balanceOfUnderlying(address(this)), depositAmount);

    // Test that we minted the correct amount of token
    assertEq(autofarmERC4626.balanceOf(address(this)), depositAmount);
  }

  function testWithdraw() public {
    deposit();
    autofarmERC4626.withdraw(depositAmount, address(this), address(this));

    //Test that the actual transfers worked
    assertEq(testToken.balanceOf(address(this)), depositAmount);
    assertEq(testToken.balanceOf(address(mockAutofarm)), 0);
    assertEq(testToken.balanceOf(address(mockStrategy)), 0);

    // //Test that we burned the correct amount of token
    assertEq(autofarmERC4626.balanceOf(address(this)), 0);
  }

  function testAccumulatingAutoRewardsOnDeposit() public {
    vm.roll(1);
    deposit();
    assertEq(autoToken.balanceOf(address(mockAutofarm)), 0);
    assertEq(autoToken.balanceOf(address(autofarmERC4626)), 0);
    assertEq(autoToken.balanceOf(address(flywheel)), 0);
    assertEq(autoToken.balanceOf(address(flywheelRewards)), 0);

    vm.roll(2);
    deposit();
    flywheel.accrue(ERC20(autofarmERC4626), address(this));
    assertEq(autoToken.balanceOf(address(mockAutofarm)), 0);
    assertEq(autoToken.balanceOf(address(autofarmERC4626)), 0);
    assertEq(autoToken.balanceOf(address(flywheel)), 0);
    assertEq(autoToken.balanceOf(address(flywheelRewards)), 8e15);
  }

  function testAccumulatingAutoRewardsOnWithdrawal() public {
    vm.roll(1);
    deposit();

    vm.roll(3);
    autofarmERC4626.withdraw(1, address(this), address(this));
    flywheel.accrue(ERC20(autofarmERC4626), address(this));
    assertEq(autoToken.balanceOf(address(mockAutofarm)), 0);
    assertEq(autoToken.balanceOf(address(autofarmERC4626)), 0);
    assertEq(autoToken.balanceOf(address(flywheel)), 0);
    assertEq(autoToken.balanceOf(address(flywheelRewards)), 16e15);
  }

  function testClaimRewards() public {
    vm.roll(1);
    deposit();
    vm.roll(3);
    autofarmERC4626.withdraw(1, address(this), address(this));
    flywheel.accrue(ERC20(autofarmERC4626), address(this));
    flywheel.claimRewards(address(this));
    assertEq(autoToken.balanceOf(address(this)), 15999999999999999);
  }

  function testClaimForMultipleUser() public {
    vm.roll(1);
    deposit();
    vm.startPrank(tester);
    testToken.mint(tester, depositAmount);
    testToken.approve(address(autofarmERC4626), depositAmount);
    autofarmERC4626.deposit(depositAmount, tester);
    vm.stopPrank();

    vm.roll(3);
    autofarmERC4626.withdraw(1, address(this), address(this));
    flywheel.accrue(ERC20(autofarmERC4626), address(this), tester);
    flywheel.claimRewards(address(this));
    flywheel.claimRewards(tester);
    assertEq(autoToken.balanceOf(address(this)), 7999999999999999);
    assertEq(autoToken.balanceOf(address(this)), 7999999999999999);
  }
}
