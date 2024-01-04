// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

<<<<<<< HEAD
/// @notice Permission IDs for `JBPermissions`.
library JB721PermissionIds {
    // 1-20 - `JBPermissionIds`
    // 21 - `JBHandlePermissionIds`
    uint256 public constant ADJUST_TIERS = 22;
    uint256 public constant UPDATE_METADATA = 23;
    uint256 public constant MINT = 24;
=======
/// @title JBBitJB721Operationsmap
/// @notice Occupy namespace operations.
library JB721Operations {
    // 0...18 - JBOperations
    // 19 - JBOperations2 (ENS/Handle)
    // 20 - JBUriOperations (Set token URI)
    uint256 public constant ADJUST_TIERS = 21;
    uint256 public constant UPDATE_METADATA = 22;
    uint256 public constant MINT = 23;
>>>>>>> intermediate
}
