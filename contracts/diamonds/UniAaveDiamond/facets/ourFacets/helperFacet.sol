// SPDX-License-Identifier: MIT License
pragma solidity >=0.8.0;
pragma abicoder v2;

import "../../libraries/BaseContract.sol";
import "../../libraries/TransferHelper.sol";

import "../../libraries/Constants.sol";

contract HelperFacet is
    BaseContract
{
    
    function currentLTV() public view returns (uint256) {
        // return currentETHBorrowed * getToken0OraclePrice() / currentUSDInCollateral/getUsdOraclePrice()
        (
            uint256 totalCollateralETH,
            uint256 totalBorrowedETH,
            ,
            ,
            ,

        ) = (getState().i_aaveV3Pool).getUserAccountData(address(this));
        uint256 ltv = totalCollateralETH == 0
            ? 0
            : (Constants.PRECISION * totalBorrowedETH) / totalCollateralETH;
        return ltv;
    }

    // =================================
    // View funcitons
    // =================================

    function getUserShares(address user) public view returns (uint256) {
        return getState().s_userShares[user];
    }

    function getTotalShares() public view returns (uint256) {
        return getState().s_totalShares;
    }

}