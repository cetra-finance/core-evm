// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.10;

interface IToken0Gateway {
  function depositETH(
    address pool,
    address onBehalfOf,
    uint16 referralCode
  ) external payable;

  function withdrawToken0(
    address pool,
    uint256 amount,
    address onBehalfOf
  ) external;

  function repayETH(
    address pool,
    uint256 amount,
    uint256 rateMode,
    address onBehalfOf
  ) external payable;

  function borrowToken0(
    address pool,
    uint256 amount,
    uint256 interesRateMode,
    uint16 referralCode
  ) external;

  function withdrawWithPermit(
    address pool,
    uint256 amount,
    address to,
    uint256 deadline,
    uint8 permitV,
    bytes32 permitR,
    bytes32 permitS
  ) external;
}