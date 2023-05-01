// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IUniFacet {

    function getSqrtRatioX96() external view returns (uint160);

    function getTick() external view returns (int24);

    function _getPositionID() external view returns (bytes32);

    function getLiquidity() external view returns (uint128);

    function calculateCurrentFees() external view returns (uint256 fee0, uint256 fee1);

}