// SPDX-License-Identifier: MIT License
pragma solidity >=0.8.0;
pragma abicoder v2;

import "../../libraries/AppStorage.sol";
import "../../libraries/BaseContract.sol";
import "../../libraries/TransferHelper.sol";

import "./Uniswap/utils/LiquidityAmounts.sol";

contract mintFacet is
    AppStorage,
    BaseContract
{

    // =================================
    // Main funcitons
    // =================================

    function mint(uint256 usdAmount) external lock {
        {
            uint256 currUsdBalance = currentUSDBalance();
            uint256 sharesToMint = (currUsdBalance > 10)
                ? ((usdAmount * s_totalShares) / (currUsdBalance))
                : usdAmount;
            s_totalShares += sharesToMint;
            s_userShares[msg.sender] += sharesToMint;
            if (sharesWorth(sharesToMint) >= usdAmount) {
                revert ChamberV1__sharesWorthMoreThenDep();
            }
            TransferHelper.safeTransferFrom(
                i_usdcAddress,
                msg.sender,
                address(this),
                usdAmount
            );
        }
        _mint(usdAmount);
    }

    // =================================
    // Intreral logic funcitons
    // =================================

    function _mint(uint256 usdAmount) private {
        uint256 amount0;
        uint256 amount1;
        uint256 usedLTV;

        int24 currentTick = getTick();

        if (!s_liquidityTokenId) {
            s_lowerTick = ((currentTick - 11000) / 10) * 10;
            s_upperTick = ((currentTick + 11000) / 10) * 10;
            usedLTV = s_targetLTV;
            s_liquidityTokenId = true;
        } else {
            usedLTV = currentLTV();
        }
        if (usedLTV < (10 * PRECISION) / 100) {
            usedLTV = s_targetLTV;
        }
        (amount0, amount1) = calculatePoolReserves(uint128(1e18));

        i_aaveV3Pool.supply(
            i_usdcAddress,
            TransferHelper.safeGetBalance(i_usdcAddress, address(this)),
            address(this),
            0
        );

        uint256 usdcOraclePrice = getUsdcOraclePrice();
        uint256 wmaticOraclePrice = getWmaticOraclePrice();
        uint256 wethOraclePrice = getWethOraclePrice();

        uint256 wethToBorrow = (usdAmount * usdcOraclePrice * usedLTV) /
            ((wmaticOraclePrice * amount0) /
                amount1 /
                1e12 +
                wethOraclePrice /
                1e12) /
            PRECISION;

        uint256 wmaticToBorrow = (usdAmount * usdcOraclePrice * usedLTV) /
            (wmaticOraclePrice /
                1e12 +
                (wethOraclePrice * amount1) /
                amount0 /
                1e12) /
            PRECISION;

        if (wmaticToBorrow > 0) {
            i_aaveV3Pool.borrow(
                i_wmaticAddress,
                wmaticToBorrow,
                2,
                0,
                address(this)
            );
        }

        if (wethToBorrow > 0) {
            i_aaveV3Pool.borrow(
                i_wethAddress,
                wethToBorrow,
                2,
                0,
                address(this)
            );
        }

        {
            uint256 wmaticRecieved = TransferHelper.safeGetBalance(
                i_wmaticAddress,
                address(this)
            ) - s_cetraFeeWmatic;
            uint256 wethRecieved = TransferHelper.safeGetBalance(
                i_wethAddress,
                address(this)
            ) - s_cetraFeeWeth;
            uint128 liquidityMinted = LiquidityAmounts.getLiquidityForAmounts(
                getSqrtRatioX96(),
                TickMath.getSqrtRatioAtTick(s_lowerTick),
                TickMath.getSqrtRatioAtTick(s_upperTick),
                wmaticRecieved,
                wethRecieved
            );

            i_uniswapPool.mint(
                address(this),
                s_lowerTick,
                s_upperTick,
                liquidityMinted,
                ""
            );
        }
    }

    // =================================
    // Private funcitons
    // =================================

    function calculatePoolReserves(
        uint128 liquidity
    ) private view returns (uint256, uint256) {
        uint256 amount0;
        uint256 amount1;
        (amount0, amount1) = LiquidityAmounts.getAmountsForLiquidity(
            getSqrtRatioX96(),
            TickMath.getSqrtRatioAtTick(s_lowerTick),
            TickMath.getSqrtRatioAtTick(s_upperTick),
            liquidity
        );
        return (amount0, amount1);
    }
    
}
