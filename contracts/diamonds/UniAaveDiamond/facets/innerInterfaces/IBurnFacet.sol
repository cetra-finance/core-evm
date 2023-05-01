// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IBurnFacet {

    function burn(uint256 _shares) external;

    function burnInternal(uint256 _shares) external;

}