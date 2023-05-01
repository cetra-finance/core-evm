// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IAaveFacet {

    function getUsdcOraclePrice() external view returns (uint256);

    function getToken0OraclePrice() external view returns (uint256);

    function getToken1OraclePrice() external view returns (uint256);

    function getAUSDCTokenBalance() external view returns (uint256);

    function getVToken0Balance() external view returns (uint256);

    function getVToken1Balance() external view returns (uint256);
    
}