// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import '@openzeppelin/contracts/utils/introspection/IERC165.sol';
import '@jbx-protocol/juice-contracts-v3/contracts/structs/JBTokenAmount.sol';
import './../structs/JB721Tier.sol';

interface IJB721PricingResolver is IERC165 {
  function priceFor(
    JB721Tier calldata _tier,
    address _beneficiary,
    uint256 _currency
  ) external view returns (uint256);
}