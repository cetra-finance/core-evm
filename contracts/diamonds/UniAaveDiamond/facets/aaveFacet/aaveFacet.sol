// SPDX-License-Identifier: MIT License
pragma solidity >=0.8.0;
pragma abicoder v2;

import "../../libraries/BaseContract.sol";
import "../../libraries/TransferHelper.sol";

contract aaveFacet is 
    BaseContract
{
    function getUsdcOraclePrice() public view returns (uint256) {
        return ((getState().i_aaveOracle).getAssetPrice(getState().i_usdcAddress) * 1e10);
    }

    function getToken0OraclePrice() public view returns (uint256) {
        return ((getState().i_aaveOracle).getAssetPrice(getState().i_token0Address) * 1e10);
    }

    function getToken1OraclePrice() public view returns (uint256) {
        return ((getState().i_aaveOracle).getAssetPrice(getState().i_token1Address) * 1e10);
    }

    function getAUSDCTokenBalance() public view returns (uint256) {
        return (getState().i_aaveAUSDCToken).balanceOf(address(this));
    }

    function getVToken0Balance() public view returns (uint256) {
        return
            ((getState().i_aaveVToken0).scaledBalanceOf(address(this)) *
                (getState().i_aaveV3Pool).getReserveNormalizedVariableDebt(getState().i_token0Address)) /
            1e27;
    }

    function getVToken1Balance() public view returns (uint256) {
        return
            ((getState().i_aaveVToken1).scaledBalanceOf(address(this)) *
                (getState().i_aaveV3Pool).getReserveNormalizedVariableDebt(
                    getState().i_token1Address
                )) / 1e27;
    }

}