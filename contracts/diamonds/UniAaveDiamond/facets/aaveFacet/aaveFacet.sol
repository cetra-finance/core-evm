// SPDX-License-Identifier: MIT License
pragma solidity >=0.8.0;
pragma abicoder v2;

import "../../libraries/AppStorage.sol";
import "../../libraries/BaseContract.sol";
import "../../libraries/TransferHelper.sol";

contract aaveFacet is 
    AppStorage,
    BaseContract
{
    function getUsdcOraclePrice() public view returns (uint256) {
        return (i_aaveOracle.getAssetPrice(i_usdcAddress) * 1e10);
    }

    function getWethOraclePrice() public view returns (uint256) {
        return (i_aaveOracle.getAssetPrice(i_wethAddress) * 1e10);
    }

    function getWmaticOraclePrice() public view returns (uint256) {
        return (i_aaveOracle.getAssetPrice(i_wmaticAddress) * 1e10);
    }

    function getAUSDCTokenBalance() public view returns (uint256) {
        return i_aaveAUSDCToken.balanceOf(address(this));
    }

    function getVWETHTokenBalance() public view returns (uint256) {
        return
            (i_aaveVWETHToken.scaledBalanceOf(address(this)) *
                i_aaveV3Pool.getReserveNormalizedVariableDebt(i_wethAddress)) /
            1e27;
    }

    function getVWMATICTokenBalance() public view returns (uint256) {
        return
            (i_aaveVWMATICToken.scaledBalanceOf(address(this)) *
                i_aaveV3Pool.getReserveNormalizedVariableDebt(
                    i_wmaticAddress
                )) / 1e27;
    }
    
}