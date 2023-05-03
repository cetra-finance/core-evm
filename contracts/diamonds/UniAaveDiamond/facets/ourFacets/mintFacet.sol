// SPDX-License-Identifier: MIT License
pragma solidity >=0.8.0;
pragma abicoder v2;

import "../../libraries/BaseContract.sol";
import "../../libraries/TransferHelper.sol";

import "../../libraries/uniLibraries/LiquidityAmounts.sol";
import "../../libraries/uniLibraries/TickMath.sol";

import "../innerInterfaces/IRebalanceFacet.sol";
import "../innerInterfaces/IUniFacet.sol";
import "../innerInterfaces/IHelperFacet.sol";
import "../innerInterfaces/IAaveFacet.sol";

import "../../libraries/Constants.sol";

contract MintFacet is
    BaseContract
{

    // =================================
    // Errors
    // =================================

    error ChamberV1__sharesWorthMoreThenDep();

    // =================================
    // Main funcitons
    // =================================

    function mint(uint256 usdAmount) external lock {
        {   
            uint256 currUsdBalance = IRebalanceFacet(address(this)).currentUSDBalance();
            uint256 sharesToMint = (currUsdBalance > 10)
                ? ((usdAmount * getState().s_totalShares) / (currUsdBalance))
                : usdAmount;
            getState().s_totalShares += sharesToMint;
            getState().s_userShares[msg.sender] += sharesToMint;
            if (sharesWorth(sharesToMint) >= usdAmount) {
                revert ChamberV1__sharesWorthMoreThenDep();
            }
            TransferHelper.safeTransferFrom(
                getState().i_usdcAddress,
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

    function mintInternal(uint256 usdAmount) external lock {
        require(msg.sender == address(this), "ChamberV1__OnlyContract");
        _mint(usdAmount);
    }

    function _mint(uint256 usdAmount) private {
        uint256 amount0;
        uint256 amount1;
        uint256 usedLTV;

        int24 currentTick = IUniFacet(address(this)).getTick();

        if (!getState().s_liquidityTokenId) {
            getState().s_lowerTick = ((currentTick - getState().s_ticksRange) / getState().i_uniswapPool.tickSpacing()) * getState().i_uniswapPool.tickSpacing();
            getState().s_upperTick = ((currentTick + getState().s_ticksRange) / getState().i_uniswapPool.tickSpacing()) * getState().i_uniswapPool.tickSpacing();
            usedLTV = getState().s_targetLTV;
            getState().s_liquidityTokenId = true;
        } else {
            usedLTV = IHelperFacet(address(this)).currentLTV();
        }
        if (usedLTV < (10 * Constants.PRECISION) / 100) {
            usedLTV = getState().s_targetLTV;
        }
        (amount0, amount1) = calculatePoolReserves(uint128(1e18));

        (getState().i_aaveV3Pool).supply(
            getState().i_usdcAddress,
            TransferHelper.safeGetBalance(getState().i_usdcAddress),
            address(this),
            0
        );

        uint256 usdcOraclePrice = IAaveFacet(address(this)).getUsdcOraclePrice();
        uint256 token1OraclePrice = IAaveFacet(address(this)).getToken1OraclePrice();
        uint256 token0OraclePrice = IAaveFacet(address(this)).getToken0OraclePrice();

        uint256 token0ToBorrow = (usdAmount * usdcOraclePrice * usedLTV) /
            ((token1OraclePrice * amount0) /
                amount1 /
                1e12 +
                token0OraclePrice /
                1e12) /
            Constants.PRECISION;

        uint256 token1ToBorrow = (usdAmount * usdcOraclePrice * usedLTV) /
            (token1OraclePrice /
                1e12 +
                (token0OraclePrice * amount1) /
                amount0 /
                1e12) /
            Constants.PRECISION;

        if (token1ToBorrow > 0) {
            (getState().i_aaveV3Pool).borrow(
                getState().i_token1Address,
                token1ToBorrow,
                2,
                0,
                address(this)
            );
        }

        if (token0ToBorrow > 0) {
            (getState().i_aaveV3Pool).borrow(
                getState().i_token0Address,
                token0ToBorrow,
                2,
                0,
                address(this)
            );
        }

        {
            uint256 token1Recieved = TransferHelper.safeGetBalance(
                getState().i_token1Address
            ) - getState().s_cetraFeeToken1;
            uint256 token0Recieved = TransferHelper.safeGetBalance(
                getState().i_token0Address
            ) - getState().s_cetraFeeToken0;

            uint128 liquidityMinted = LiquidityAmounts.getLiquidityForAmounts(
                IUniFacet(address(this)).getSqrtRatioX96(),
                TickMath.getSqrtRatioAtTick(getState().s_lowerTick),
                TickMath.getSqrtRatioAtTick(getState().s_upperTick),
                token1Recieved,
                token0Recieved
            );

            (getState().i_uniswapPool).mint(
                address(this),
                getState().s_lowerTick,
                getState().s_upperTick,
                liquidityMinted,
                ""
            );
        }
    }

    // =================================
    // Private funcitons
    // =================================

    function sharesWorth(uint256 shares) public view returns (uint256) {
        return (IRebalanceFacet(address(this)).currentUSDBalance() * shares) / getState().s_totalShares;
    }

    function calculatePoolReserves(
        uint128 liquidity
    ) private view returns (uint256, uint256) {
        uint256 amount0;
        uint256 amount1;
        (amount0, amount1) = LiquidityAmounts.getAmountsForLiquidity(
            IUniFacet(address(this)).getSqrtRatioX96(),
            TickMath.getSqrtRatioAtTick(getState().s_lowerTick),
            TickMath.getSqrtRatioAtTick(getState().s_upperTick),
            liquidity
        );
        return (amount0, amount1);
    }

}
