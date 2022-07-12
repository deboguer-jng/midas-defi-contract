// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.0;

import "./CErc20.sol";
import "./CDelegateInterface.sol";

/**
 * @title Compound's CErc20Delegate Contract
 * @notice CTokens which wrap an EIP-20 underlying and are delegated to
 * @author Compound
 */
contract CErc20Delegate is CDelegateInterface, CErc20 {
  /**
   * @notice Construct an empty delegate
   */
  constructor() {}

  /**
   * @notice Called by the delegator on a delegate to initialize it for duty
   * @param data The encoded bytes data for any initialization
   */
  function _becomeImplementation(bytes memory data) public virtual override {
    require(hasAdminRights(), "only admins can call _becomeImplementation");

    // Make sure admin storage is set up correctly
    __adminHasRights = true;
    __fuseAdminHasRights = true;
  }

  /**
   * @notice Called by the delegator on a delegate to forfeit its responsibility
   */
  function _resignImplementation() internal virtual {
    // Shh -- we don't ever want this hook to be marked pure
    if (false) {
      implementation = address(0);
    }
  }

  /**
   * @dev Internal function to update the implementation of the delegator
   * @param implementation_ The address of the new implementation for delegation
   * @param allowResign Flag to indicate whether to call _resignImplementation on the old implementation
   * @param becomeImplementationData The encoded bytes data to be passed to _becomeImplementation
   */
  function _setImplementationInternal(
    address implementation_,
    bool allowResign,
    bytes memory becomeImplementationData
  ) internal {
    // Check whitelist
    require(
      IFuseFeeDistributor(fuseAdmin).cErc20DelegateWhitelist(implementation, implementation_, allowResign),
      "!impl"
    );

    // Call _resignImplementation internally (this delegate's code)
    if (allowResign) _resignImplementation();

    // Get old implementation
    address oldImplementation = implementation;

    // Store new implementation
    implementation = implementation_;

    if (oldImplementation == address(0)) {
      // no need to delegate when initializing
      _becomeImplementation(becomeImplementationData);
    } else {
      // Call _becomeImplementation externally (delegating to new delegate's code)
      delegateTo(
        implementation_,
        abi.encodeWithSignature("_becomeImplementation(bytes)", becomeImplementationData)
      );
    }

    // Emit event
    emit NewImplementation(oldImplementation, implementation);
  }

  /**
   * @notice Called by the admin to update the implementation of the delegator
   * @param implementation_ The address of the new implementation for delegation
   * @param allowResign Flag to indicate whether to call _resignImplementation on the old implementation
   * @param becomeImplementationData The encoded bytes data to be passed to _becomeImplementation
   */
  function _setImplementationSafe(
    address implementation_,
    bool allowResign,
    bytes calldata becomeImplementationData
  ) external override {
    // Check admin rights
    require(hasAdminRights(), "!admin");

    // Set implementation
    if (implementation != implementation_) {
      _setImplementationInternal(implementation_, allowResign, becomeImplementationData);
    }
  }

  /**
   * @notice Function called before all delegator functions
   * @dev Checks comptroller.autoImplementation and upgrades the implementation if necessary
   */
  function _prepare() external payable override {
    if (hasAdminRights() && ComptrollerV3Storage(address(comptroller)).autoImplementation()) {
      (address latestCErc20Delegate, bool allowResign, bytes memory becomeImplementationData) = IFuseFeeDistributor(
        fuseAdmin
      ).latestCErc20Delegate(implementation);
      if (implementation != latestCErc20Delegate) {
        _setImplementationInternal(latestCErc20Delegate, allowResign, becomeImplementationData);
      }
    }
  }
}
