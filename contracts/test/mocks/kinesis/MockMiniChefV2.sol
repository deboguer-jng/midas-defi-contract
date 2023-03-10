// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "./BoringOwnable.sol";
import "./BoringBatchable.sol";
import "./SimpleRewarder.sol";

// MockMiniChefV2 - Based on https://github.com/kinesis-labs/kinesis-contract/blob/main/contracts/rewards/MiniChefV2.sol

contract MockMiniChefV2 is BoringOwnable, BoringBatchable {
  using SafeMath for uint256;
  using SafeMath for uint128;

  /// @notice Info of each MCV2 user.
  /// `amount` LP token amount the user has provided.
  /// `rewardDebt` The amount of SADDLE entitled to the user.
  struct UserInfo {
    uint256 amount;
    int256 rewardDebt;
  }

  /// @notice Info of each MCV2 pool.
  /// `allocPoint` The amount of allocation points assigned to the pool.
  /// Also known as the amount of SADDLE to distribute per block.
  struct PoolInfo {
    uint128 accSaddlePerShare;
    uint64 lastRewardTime;
    uint64 allocPoint;
  }

  /// @notice Address of SADDLE contract.
  IERC20 public immutable SADDLE;

  /// @notice Info of each MCV2 pool.
  PoolInfo[] public poolInfo;
  /// @notice Address of the LP token for each MCV2 pool.
  IERC20[] public lpToken;
  /// @notice Address of each `IRewarder` contract in MCV2.
  IRewarder[] public rewarder;

  /// @notice Info of each user that stakes LP tokens.
  mapping(uint256 => mapping(address => UserInfo)) public userInfo;
  /// @dev Total allocation points. Must be the sum of all allocation points in all pools.
  uint256 public totalAllocPoint;

  uint256 public saddlePerSecond;
  uint256 private constant ACC_SADDLE_PRECISION = 1e12;

  event Deposit(address indexed user, uint256 indexed pid, uint256 amount, address indexed to);
  event Withdraw(address indexed user, uint256 indexed pid, uint256 amount, address indexed to);
  event EmergencyWithdraw(address indexed user, uint256 indexed pid, uint256 amount, address indexed to);
  event Harvest(address indexed user, uint256 indexed pid, uint256 amount);
  event LogPoolAddition(uint256 indexed pid, uint256 allocPoint, IERC20 indexed lpToken, IRewarder indexed rewarder);
  event LogSetPool(uint256 indexed pid, uint256 allocPoint, IRewarder indexed rewarder, bool overwrite);
  event LogUpdatePool(uint256 indexed pid, uint64 lastRewardTime, uint256 lpSupply, uint256 accSaddlePerShare);
  event LogSaddlePerSecond(uint256 saddlePerSecond);

  /// @param _saddle The SADDLE token contract address.
  constructor(IERC20 _saddle) {
    SADDLE = _saddle;
  }

  /// @notice Returns the number of MCV2 pools.
  function poolLength() public view returns (uint256 pools) {
    pools = poolInfo.length;
  }

  /// @notice Add a new LP to the pool. Can only be called by the owner.
  /// DO NOT add the same LP token more than once. Rewards will be messed up if you do.
  /// @param allocPoint AP of the new pool.
  /// @param _lpToken Address of the LP ERC-20 token.
  /// @param _rewarder Address of the rewarder delegate.
  function add(
    uint256 allocPoint,
    IERC20 _lpToken,
    IRewarder _rewarder
  ) public onlyOwner {
    totalAllocPoint = totalAllocPoint.add(allocPoint);
    lpToken.push(_lpToken);
    rewarder.push(_rewarder);

    poolInfo.push(
      PoolInfo({ allocPoint: uint64(allocPoint), lastRewardTime: uint64(block.timestamp), accSaddlePerShare: 0 })
    );
    emit LogPoolAddition(lpToken.length.sub(1), allocPoint, _lpToken, _rewarder);
  }

  /// @notice Update the given pool's SADDLE allocation point and `IRewarder` contract. Can only be called by the owner.
  /// @param _pid The index of the pool. See `poolInfo`.
  /// @param _allocPoint New AP of the pool.
  /// @param _rewarder Address of the rewarder delegate.
  /// @param overwrite True if _rewarder should be `set`. Otherwise `_rewarder` is ignored.
  function set(
    uint256 _pid,
    uint256 _allocPoint,
    IRewarder _rewarder,
    bool overwrite
  ) public onlyOwner {
    totalAllocPoint = totalAllocPoint.sub(poolInfo[_pid].allocPoint).add(_allocPoint);
    poolInfo[_pid].allocPoint = uint64(_allocPoint);
    if (overwrite) {
      rewarder[_pid] = _rewarder;
    }
    emit LogSetPool(_pid, _allocPoint, overwrite ? _rewarder : rewarder[_pid], overwrite);
  }

  /// @notice Sets the saddle per second to be distributed. Can only be called by the owner.
  /// @param _saddlePerSecond The amount of Saddle to be distributed per second.
  function setSaddlePerSecond(uint256 _saddlePerSecond) public onlyOwner {
    saddlePerSecond = _saddlePerSecond;
    emit LogSaddlePerSecond(_saddlePerSecond);
  }

  /// @notice View function to see pending SADDLE on frontend.
  /// @param _pid The index of the pool. See `poolInfo`.
  /// @param _user Address of user.
  /// @return pending SADDLE reward for a given user.
  function pendingSaddle(uint256 _pid, address _user) external view returns (uint256 pending) {
    PoolInfo memory pool = poolInfo[_pid];
    UserInfo storage user = userInfo[_pid][_user];
    uint256 accSaddlePerShare = pool.accSaddlePerShare;
    uint256 lpSupply = lpToken[_pid].balanceOf(address(this));
    if (block.timestamp > pool.lastRewardTime && lpSupply != 0) {
      uint256 time = block.timestamp.sub(pool.lastRewardTime);
      uint256 saddleReward = time.mul(saddlePerSecond).mul(pool.allocPoint) / totalAllocPoint;
      accSaddlePerShare = accSaddlePerShare.add(saddleReward.mul(ACC_SADDLE_PRECISION) / lpSupply);
    }
    pending = uint256(int256(user.amount.mul(accSaddlePerShare) / ACC_SADDLE_PRECISION) - user.rewardDebt);
  }

  /// @notice Update reward variables for all pools. Be careful of gas spending!
  /// @param pids Pool IDs of all to be updated. Make sure to update all active pools.
  function massUpdatePools(uint256[] calldata pids) external {
    uint256 len = pids.length;
    for (uint256 i = 0; i < len; ++i) {
      updatePool(pids[i]);
    }
  }

  /// @notice Update reward variables of the given pool.
  /// @param pid The index of the pool. See `poolInfo`.
  /// @return pool Returns the pool that was updated.
  function updatePool(uint256 pid) public returns (PoolInfo memory pool) {
    pool = poolInfo[pid];
    if (block.timestamp > pool.lastRewardTime) {
      uint256 lpSupply = lpToken[pid].balanceOf(address(this));
      if (lpSupply > 0) {
        uint256 time = block.timestamp.sub(pool.lastRewardTime);
        uint256 saddleReward = time.mul(saddlePerSecond).mul(pool.allocPoint) / totalAllocPoint;
        pool.accSaddlePerShare = uint128(
          pool.accSaddlePerShare.add((saddleReward.mul(ACC_SADDLE_PRECISION) / lpSupply))
        );
      }
      pool.lastRewardTime = uint64(block.timestamp);
      poolInfo[pid] = pool;
      emit LogUpdatePool(pid, pool.lastRewardTime, lpSupply, pool.accSaddlePerShare);
    }
  }

  /// @notice Deposit LP tokens to MCV2 for SADDLE allocation.
  /// @param pid The index of the pool. See `poolInfo`.
  /// @param amount LP token amount to deposit.
  /// @param to The receiver of `amount` deposit benefit.
  function deposit(
    uint256 pid,
    uint256 amount,
    address to
  ) public {
    PoolInfo memory pool = updatePool(pid);
    UserInfo storage user = userInfo[pid][to];

    // Effects
    user.amount = user.amount.add(amount);
    user.rewardDebt = int256(uint256(user.rewardDebt).add(amount.mul(pool.accSaddlePerShare) / ACC_SADDLE_PRECISION));

    // Interactions
    IRewarder _rewarder = rewarder[pid];
    if (address(_rewarder) != address(0)) {
      _rewarder.onSaddleReward(pid, to, to, 0, user.amount);
    }

    lpToken[pid].transferFrom(msg.sender, address(this), amount);

    emit Deposit(msg.sender, pid, amount, to);
  }

  /// @notice Withdraw LP tokens from MCV2.
  /// @param pid The index of the pool. See `poolInfo`.
  /// @param amount LP token amount to withdraw.
  /// @param to Receiver of the LP tokens.
  function withdraw(
    uint256 pid,
    uint256 amount,
    address to
  ) public {
    PoolInfo memory pool = updatePool(pid);
    UserInfo storage user = userInfo[pid][msg.sender];

    // Effects
    user.rewardDebt = int256(uint256(user.rewardDebt).sub(amount.mul(pool.accSaddlePerShare) / ACC_SADDLE_PRECISION));
    user.amount = user.amount.sub(amount);

    // Interactions
    IRewarder _rewarder = rewarder[pid];
    if (address(_rewarder) != address(0)) {
      _rewarder.onSaddleReward(pid, msg.sender, to, 0, user.amount);
    }

    lpToken[pid].transfer(to, amount);

    emit Withdraw(msg.sender, pid, amount, to);
  }

  /// @notice Harvest proceeds for transaction sender to `to`.
  /// @param pid The index of the pool. See `poolInfo`.
  /// @param to Receiver of SADDLE rewards.
  function harvest(uint256 pid, address to) public {
    PoolInfo memory pool = updatePool(pid);
    UserInfo storage user = userInfo[pid][msg.sender];
    int256 accumulatedSaddle = int256(user.amount.mul(pool.accSaddlePerShare) / ACC_SADDLE_PRECISION);
    uint256 _pendingSaddle = uint256(accumulatedSaddle - user.rewardDebt);

    // Effects
    user.rewardDebt = accumulatedSaddle;

    // Interactions
    if (_pendingSaddle != 0) {
      SADDLE.transfer(to, _pendingSaddle);
    }

    IRewarder _rewarder = rewarder[pid];
    if (address(_rewarder) != address(0)) {
      _rewarder.onSaddleReward(pid, msg.sender, to, _pendingSaddle, user.amount);
    }

    emit Harvest(msg.sender, pid, _pendingSaddle);
  }

  /// @notice Withdraw LP tokens from MCV2 and harvest proceeds for transaction sender to `to`.
  /// @param pid The index of the pool. See `poolInfo`.
  /// @param amount LP token amount to withdraw.
  /// @param to Receiver of the LP tokens and SADDLE rewards.
  function withdrawAndHarvest(
    uint256 pid,
    uint256 amount,
    address to
  ) public {
    PoolInfo memory pool = updatePool(pid);
    UserInfo storage user = userInfo[pid][msg.sender];
    int256 accumulatedSaddle = int256(user.amount.mul(pool.accSaddlePerShare) / ACC_SADDLE_PRECISION);
    uint256 _pendingSaddle = uint256(accumulatedSaddle - user.rewardDebt);

    // Effects
    user.rewardDebt = int256(uint256(accumulatedSaddle).sub(amount.mul(pool.accSaddlePerShare) / ACC_SADDLE_PRECISION));
    user.amount = user.amount.sub(amount);

    // Interactions
    SADDLE.transfer(to, _pendingSaddle);

    IRewarder _rewarder = rewarder[pid];
    if (address(_rewarder) != address(0)) {
      _rewarder.onSaddleReward(pid, msg.sender, to, _pendingSaddle, user.amount);
    }

    lpToken[pid].transfer(to, amount);

    emit Withdraw(msg.sender, pid, amount, to);
    emit Harvest(msg.sender, pid, _pendingSaddle);
  }

  /// @notice Withdraw without caring about rewards. EMERGENCY ONLY.
  /// @param pid The index of the pool. See `poolInfo`.
  /// @param to Receiver of the LP tokens.
  function emergencyWithdraw(uint256 pid, address to) public {
    UserInfo storage user = userInfo[pid][msg.sender];
    uint256 amount = user.amount;
    user.amount = 0;
    user.rewardDebt = 0;

    IRewarder _rewarder = rewarder[pid];
    if (address(_rewarder) != address(0)) {
      _rewarder.onSaddleReward(pid, msg.sender, to, 0, 0);
    }

    // Note: transfer can fail or succeed if `amount` is zero.
    lpToken[pid].transfer(to, amount);
    emit EmergencyWithdraw(msg.sender, pid, amount, to);
  }
}
