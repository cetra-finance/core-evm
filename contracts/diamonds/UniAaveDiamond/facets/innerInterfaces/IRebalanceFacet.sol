// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IRebalanceFacet {

    function currentUSDBalance() external view returns (uint256);

}