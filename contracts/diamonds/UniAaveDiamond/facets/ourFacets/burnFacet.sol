// SPDX-License-Identifier: MIT License
pragma solidity >=0.8.0;
pragma abicoder v2;

import "../../libraries/AppStorage.sol";
import "../../libraries/BaseContract.sol";
import "../../libraries/TransferHelper.sol";

contract burnFacet is
    AppStorage,
    BaseContract
{

    // =================================
    // Main funcitons
    // =================================

    function burn(uint256 _shares) external lock {
        uint256 usdcBalanceBefore = TransferHelper.safeGetBalance(
            i_usdcAddress,
            address(this)
        );
        _burn(_shares);

        s_totalShares -= _shares;
        s_userShares[msg.sender] -= _shares;

        TransferHelper.safeTransfer(
            i_usdcAddress,
            msg.sender,
            TransferHelper.safeGetBalance(i_usdcAddress, address(this)) -
                usdcBalanceBefore
        );
    }

    // =================================
    // Intreral logic funcitons
    // =================================

    function _burn(uint256 _shares) private {
        (
            uint256 burnWMATIC,
            uint256 burnWETH,
            uint256 feeWmatic,
            uint256 feeWeth
        ) = _withdraw(uint128((getLiquidity() * _shares) / s_totalShares));
        _applyFees(feeWmatic, feeWeth);

        uint256 amountWmatic = burnWMATIC +
            ((TransferHelper.safeGetBalance(i_wmaticAddress, address(this)) -
                burnWMATIC -
                s_cetraFeeWmatic) * _shares) /
            s_totalShares;
        uint256 amountWeth = burnWETH +
            ((TransferHelper.safeGetBalance(i_wethAddress, address(this)) -
                burnWETH -
                s_cetraFeeWeth) * _shares) /
            s_totalShares;

        {
            (
                uint256 wmaticRemainder,
                uint256 wethRemainder
            ) = _repayAndWithdraw(_shares, amountWmatic, amountWeth);
            if (wmaticRemainder > 0) {
                swapExactAssetToStable(i_wmaticAddress, wmaticRemainder);
            }
            if (wethRemainder > 0) {
                swapExactAssetToStable(i_wethAddress, wethRemainder);
            }
        }
    }

    // =================================
    // Private funcitons
    // =================================

    function _repayAndWithdraw(
        uint256 _shares,
        uint256 wmaticOwnedByUser,
        uint256 wethOwnedByUser
    ) private returns (uint256, uint256) {
        uint256 wmaticDebtToCover = (getVWMATICTokenBalance() * _shares) /
            s_totalShares;
        uint256 wethDebtToCover = (getVWETHTokenBalance() * _shares) /
            s_totalShares;
        uint256 wmaticBalanceBefore = TransferHelper.safeGetBalance(
            i_wmaticAddress,
            address(this)
        );
        uint256 wethBalanceBefore = TransferHelper.safeGetBalance(
            i_wethAddress,
            address(this)
        );
        uint256 wmaticRemainder;
        uint256 wethRemainder;

        uint256 wethSwapped = 0;
        uint256 usdcSwapped = 0;

        uint256 _currentLTV = currentLTV();
        if (wmaticOwnedByUser < wmaticDebtToCover) {
            wethSwapped += swapAssetToExactAsset(
                i_wethAddress,
                i_wmaticAddress,
                wmaticDebtToCover - wmaticOwnedByUser
            );
            if (
                wmaticOwnedByUser +
                    TransferHelper.safeGetBalance(
                        i_wmaticAddress,
                        address(this)
                    ) -
                    wmaticBalanceBefore <
                wmaticDebtToCover
            ) {
                revert ChamberV1__SwappedWethForWmaticStillCantRepay();
            }
        }
        i_aaveV3Pool.repay(
            i_wmaticAddress,
            wmaticDebtToCover,
            2,
            address(this)
        );
        if (
            TransferHelper.safeGetBalance(i_wmaticAddress, address(this)) >=
            wmaticBalanceBefore - wmaticOwnedByUser
        ) {
            wmaticRemainder =
                TransferHelper.safeGetBalance(i_wmaticAddress, address(this)) +
                wmaticOwnedByUser -
                wmaticBalanceBefore;
        } else {
            revert ChamberV1__UserRepaidMoreMaticThanOwned();
        }

        i_aaveV3Pool.withdraw(
            i_usdcAddress,
            (((1e6 * wmaticDebtToCover * getWmaticOraclePrice()) /
                getUsdcOraclePrice()) / _currentLTV),
            address(this)
        );

        if (wethOwnedByUser < wethDebtToCover + wethSwapped) {
            usdcSwapped += swapStableToExactAsset(
                i_wethAddress,
                wethDebtToCover + wethSwapped - wethOwnedByUser
            );
            if (
                (wethOwnedByUser +
                    TransferHelper.safeGetBalance(
                        i_wethAddress,
                        address(this)
                    )) -
                    wethBalanceBefore <
                wethDebtToCover
            ) {
                revert ChamberV1__SwappedUsdcForWethStillCantRepay();
            }
        }
        i_aaveV3Pool.repay(i_wethAddress, wethDebtToCover, 2, address(this));

        if (
            TransferHelper.safeGetBalance(i_wethAddress, address(this)) >=
            wethBalanceBefore - wethOwnedByUser
        ) {
            wethRemainder =
                TransferHelper.safeGetBalance(i_wethAddress, address(this)) +
                wethOwnedByUser -
                wethBalanceBefore;
        } else {
            revert ChamberV1__UserRepaidMoreEthThanOwned();
        }

        i_aaveV3Pool.withdraw(
            i_usdcAddress,
            (((1e6 * wethDebtToCover * getWethOraclePrice()) /
                getUsdcOraclePrice()) / _currentLTV),
            address(this)
        );

        return (wmaticRemainder, wethRemainder);
    }

    function swapExactAssetToStable(
        address assetIn,
        uint256 amountIn
    ) private returns (uint256) {
        uint256 amountOut = i_uniswapSwapRouter.exactInput(
            ISwapRouter.ExactInputParams({
                path: abi.encodePacked(assetIn, uint24(500), i_usdcAddress),
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
        uint256 amountIn = i_uniswapSwapRouter.exactOutput(
            ISwapRouter.ExactOutputParams({
                path: abi.encodePacked(assetOut, uint24(500), i_usdcAddress),
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
        uint256 amountIn = i_uniswapSwapRouter.exactOutput(
            ISwapRouter.ExactOutputParams({
                path: abi.encodePacked(
                    assetOut,
                    uint24(500),
                    i_usdcAddress,
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
        uint256 preBalanceWmatic = TransferHelper.safeGetBalance(
            i_wmaticAddress,
            address(this)
        );
        uint256 preBalanceWeth = TransferHelper.safeGetBalance(
            i_wethAddress,
            address(this)
        );
        (uint256 burnWmatic, uint256 burnWeth) = i_uniswapPool.burn(
            s_lowerTick,
            s_upperTick,
            liquidityToBurn
        );
        i_uniswapPool.collect(
            address(this),
            s_lowerTick,
            s_upperTick,
            type(uint128).max,
            type(uint128).max
        );
        uint256 feeWmatic = TransferHelper.safeGetBalance(
            i_wmaticAddress,
            address(this)
        ) -
            preBalanceWmatic -
            burnWmatic;
        uint256 feeWeth = TransferHelper.safeGetBalance(
            i_wethAddress,
            address(this)
        ) -
            preBalanceWeth -
            burnWeth;
        return (burnWmatic, burnWeth, feeWmatic, feeWeth);
    }

    function _applyFees(uint256 _feeWmatic, uint256 _feeWeth) private {
        s_cetraFeeWeth += (_feeWeth * CETRA_FEE) / PRECISION;
        s_cetraFeeWmatic += (_feeWmatic * CETRA_FEE) / PRECISION;
    }

}
