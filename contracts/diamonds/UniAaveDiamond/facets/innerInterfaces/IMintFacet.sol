// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IMintFacet {

    function mint(uint256 usdAmount) external;

    function mintInternal(uint256 _shares) external;

}