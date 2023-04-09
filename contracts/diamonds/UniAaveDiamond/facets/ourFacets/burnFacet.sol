// SPDX-License-Identifier: MIT License
pragma solidity >=0.8.0;
pragma abicoder v2;

import "../../libraries/BaseContract.sol";
import "../../libraries/TransferHelper.sol";

import "../innerInterfaces/UniFacet.sol";
import "../innerInterfaces/AaveFacet.sol";
import "../innerInterfaces/HelperFacet.sol";

import "../../libraries/Constants.sol";

contract burnFacet is
    BaseContract
{

    // =================================
    // Errors
    // =================================

    error ChamberV1__SwappedUsdcForToken0StillCantRepay();
    error ChamberV1__UserRepaidMoreEthThanOwned();
    error ChamberV1__UserRepaidMoreMaticThanOwned();
    error ChamberV1__SwappedToken0ForToken1StillCantRepay();

    // =================================
    // Main funcitons
    // =================================

    function burn(uint256 _shares) external lock {
        uint256 usdcBalanceBefore = TransferHelper.safeGetBalance(
            getState().i_usdcAddress
        );
        _burn(_shares);

        getState().s_totalShares -= _shares;
        getState().s_userShares[msg.sender] -= _shares;

        TransferHelper.safeTransfer(
            getState().i_usdcAddress,
            msg.sender,
            TransferHelper.safeGetBalance(getState().i_usdcAddress) -
                usdcBalanceBefore
        );
    }

    // =================================
    // Intreral logic funcitons
    // =================================

    function _burn(uint256 _shares) private {
        (
            uint256 burnToken1,
            uint256 burnToken0,
            uint256 feeToken1,
            uint256 feeToken0
        ) = _withdraw(uint128((IUniFacet(address(this)).getLiquidity() * _shares) / getState().s_totalShares));
        _applyFees(feeToken1, feeToken0);

        uint256 amountToken1 = burnToken1 +
            ((TransferHelper.safeGetBalance(getState().i_token1Address) -
                burnToken1 -
                getState().s_cetraFeeToken1) * _shares) /
            getState().s_totalShares;
        uint256 amountToken0 = burnToken0 +
            ((TransferHelper.safeGetBalance(getState().i_token0Address) -
                burnToken0 -
                getState().s_cetraFeeToken0) * _shares) /
            getState().s_totalShares;

        {
            (
                uint256 token1Remainder,
                uint256 token0Remainder
            ) = _repayAndWithdraw(_shares, amountToken1, amountToken0);
            if (token1Remainder > 0) {
                swapExactAssetToStable(getState().i_token1Address, token1Remainder);
            }
            if (token0Remainder > 0) {
                swapExactAssetToStable(getState().i_token0Address, token0Remainder);
            }
        }
    }

    // =================================
    // Private funcitons
    // =================================

    function _repayAndWithdraw(
        uint256 _shares,
        uint256 token1OwnedByUser,
        uint256 token0OwnedByUser
    ) private returns (uint256, uint256) {
        uint256 token1DebtToCover = (IAaveFacet(address(this)).getVToken1Balance() * _shares) /
            getState().s_totalShares;
        uint256 token0DebtToCover = (IAaveFacet(address(this)).getVToken0Balance() * _shares) /
            getState().s_totalShares;
        uint256 token1BalanceBefore = TransferHelper.safeGetBalance(
            getState().i_token1Address
        );
        uint256 token0BalanceBefore = TransferHelper.safeGetBalance(
            getState().i_token0Address
        );
        uint256 token1Remainder;
        uint256 token0Remainder;

        uint256 token0Swapped = 0;
        uint256 usdcSwapped = 0;

        uint256 _currentLTV = IHelperFacet(address(this)).currentLTV();
        if (token1OwnedByUser < token1DebtToCover) {
            token0Swapped += swapAssetToExactAsset(
                getState().i_token0Address,
                getState().i_token1Address,
                token1DebtToCover - token1OwnedByUser
            );
            if (
                token1OwnedByUser +
                    TransferHelper.safeGetBalance(
                        getState().i_token1Address
                    ) -
                    token1BalanceBefore <
                token1DebtToCover
            ) {
                revert ChamberV1__SwappedToken0ForToken1StillCantRepay();
            }
        }
        (getState().i_aaveV3Pool).repay(
            getState().i_token1Address,
            token1DebtToCover,
            2,
            address(this)
        );
        if (
            TransferHelper.safeGetBalance(getState().i_token1Address) >=
            token1BalanceBefore - token1OwnedByUser
        ) {
            token1Remainder =
                TransferHelper.safeGetBalance(getState().i_token1Address) +
                token1OwnedByUser -
                token1BalanceBefore;
        } else {
            revert ChamberV1__UserRepaidMoreMaticThanOwned();
        }

        (getState().i_aaveV3Pool).withdraw(
            getState().i_usdcAddress,
            (((1e6 * token1DebtToCover * IAaveFacet(address(this)).getToken1OraclePrice()) /
                IAaveFacet(address(this)).getUsdcOraclePrice()) / _currentLTV),
            address(this)
        );

        if (token0OwnedByUser < token0DebtToCover + token0Swapped) {
            usdcSwapped += swapStableToExactAsset(
                getState().i_token0Address,
                token0DebtToCover + token0Swapped - token0OwnedByUser
            );
            if (
                (token0OwnedByUser +
                    TransferHelper.safeGetBalance(
                        getState().i_token0Address
                    )) -
                    token0BalanceBefore <
                token0DebtToCover
            ) {
                revert ChamberV1__SwappedUsdcForToken0StillCantRepay();
            }
        }
        (getState().i_aaveV3Pool).repay(getState().i_token0Address, token0DebtToCover, 2, address(this));

        if (
            TransferHelper.safeGetBalance(getState().i_token0Address) >=
            token0BalanceBefore - token0OwnedByUser
        ) {
            token0Remainder =
                TransferHelper.safeGetBalance(getState().i_token0Address) +
                token0OwnedByUser -
                token0BalanceBefore;
        } else {
            revert ChamberV1__UserRepaidMoreEthThanOwned();
        }

        (getState().i_aaveV3Pool).withdraw(
            getState().i_usdcAddress,
            (((1e6 * token0DebtToCover * IAaveFacet(address(this)).getToken0OraclePrice()) /
                IAaveFacet(address(this)).getUsdcOraclePrice()) / _currentLTV),
            address(this)
        );

        return (token1Remainder, token0Remainder);
    }

    function swapExactAssetToStable(
        address assetIn,
        uint256 amountIn
    ) private returns (uint256) {
        uint256 amountOut = (getState().i_uniswapSwapRouter).exactInput(
            ISwapRouter.ExactInputParams({
                path: abi.encodePacked(assetIn, uint24(500), getState().i_usdcAddress),
                recipient: address(this),
                deadline: block.timestamp,
                amountIn: amountIn,
                amountOutMinimum: 0
            })
        );
        return (amountOut);
    }

    function swapStableToExactAsset(
        address assetOut,
        uint256 amountOut
    ) private returns (uint256) {
        uint256 amountIn = (getState().i_uniswapSwapRouter).exactOutput(
            ISwapRouter.ExactOutputParams({
                path: abi.encodePacked(assetOut, uint24(500), getState().i_usdcAddress),
                recipient: address(this),
                deadline: block.timestamp,
                amountOut: amountOut,
                amountInMaximum: 1e50
            })
        );
        return (amountIn);
    }

    function swapAssetToExactAsset(
        address assetIn,
        address assetOut,
        uint256 amountOut
    ) private returns (uint256) {
        uint256 amountIn = (getState().i_uniswapSwapRouter).exactOutput(
            ISwapRouter.ExactOutputParams({
                path: abi.encodePacked(
                    assetOut,
                    uint24(500),
                    getState().i_usdcAddress,
                    uint24(500),
                    assetIn
                ),
                recipient: address(this),
                deadline: block.timestamp,
                amountOut: amountOut,
                amountInMaximum: type(uint256).max
            })
        );

        return (amountIn);
    }
    
    function _withdraw(
        uint128 liquidityToBurn
    ) private returns (uint256, uint256, uint256, uint256) {
        uint256 preBalanceToken1 = TransferHelper.safeGetBalance(
            getState().i_token1Address
        );
        uint256 preBalanceToken0 = TransferHelper.safeGetBalance(
            getState().i_token0Address
        );
        (uint256 burnToken1, uint256 burnToken0) = (getState().i_uniswapPool).burn(
            getState().s_lowerTick,
            getState().s_upperTick,
            liquidityToBurn
        );
        (getState().i_uniswapPool).collect(
            address(this),
            getState().s_lowerTick,
            getState().s_upperTick,
            type(uint128).max,
            type(uint128).max
        );
        uint256 feeToken1 = TransferHelper.safeGetBalance(
            getState().i_token1Address
        ) -
            preBalanceToken1 -
            burnToken1;
        uint256 feeToken0 = TransferHelper.safeGetBalance(
            getState().i_token0Address
        ) -
            preBalanceToken0 -
            burnToken0;
        return (burnToken1, burnToken0, feeToken1, feeToken0);
    }

    function _applyFees(uint256 _feeToken1, uint256 _feeToken0) private {
        getState().s_cetraFeeToken0 += (_feeToken0 * Constants.CETRA_FEE) / Constants.PRECISION;
        getState().s_cetraFeeToken1 += (_feeToken1 * Constants.CETRA_FEE) / Constants.PRECISION;
    }

}
