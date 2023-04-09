// SPDX-License-Identifier: MIT License
pragma solidity >=0.8.0;
pragma abicoder v2;

import "../../libraries/uniLibraries/LiquidityAmounts.sol";

import "../../interfaces/UniInterfaces/ISwapRouter.sol";
import "../../interfaces/UniInterfaces/IUniswapV3Pool.sol";
import "../../interfaces/UniInterfaces/callback/IUniswapV3MintCallback.sol";

import "../../libraries/BaseContract.sol";
import "../../libraries/TransferHelper.sol";

contract uniFacet is 
    BaseContract,
    IUniswapV3MintCallback
{

    // =================================
    // Errors
    // =================================

    error ChamberV1__CallerIsNotUniPool();

    // =================================
    // Main funcitons
    // =================================

    function getSqrtRatioX96() private view returns (uint160) {
        (uint160 sqrtRatioX96, , , , , , ) = (getState().i_uniswapPool).slot0();
        return sqrtRatioX96;
    }

    function getTick() public view returns (int24) {
        (, int24 tick, , , , , ) = (getState().i_uniswapPool).slot0();
        return tick;
    }

    function _getPositionID() private view returns (bytes32 positionID) {
        return
            keccak256(
                abi.encodePacked(address(this), getState().s_lowerTick, getState().s_upperTick)
            );
    }

    function getLiquidity() private view returns (uint128) {
        (uint128 liquidity, , , , ) = (getState().i_uniswapPool).positions(_getPositionID());
        return liquidity;
    }

    function calculateCurrentFees()
        private
        view
        returns (uint256 fee0, uint256 fee1)
    {
        int24 tick = getTick();
        (
            uint128 liquidity,
            uint256 feeGrowthInside0Last,
            uint256 feeGrowthInside1Last,
            uint128 tokensOwed0,
            uint128 tokensOwed1
        ) = (getState().i_uniswapPool).positions(_getPositionID());
        fee0 =
            _computeFeesEarned(true, feeGrowthInside0Last, tick, liquidity) +
            uint256(tokensOwed0);

        fee1 =
            _computeFeesEarned(false, feeGrowthInside1Last, tick, liquidity) +
            uint256(tokensOwed1);
    }

    function _computeFeesEarned(
        bool isZero,
        uint256 feeGrowthInsideLast,
        int24 tick,
        uint128 liquidity
    ) private view returns (uint256 fee) {
        uint256 feeGrowthOutsideLower;
        uint256 feeGrowthOutsideUpper;
        uint256 feeGrowthGlobal;
        if (isZero) {
            feeGrowthGlobal = (getState().i_uniswapPool).feeGrowthGlobal0X128();
            (, , feeGrowthOutsideLower, , , , , ) = (getState().i_uniswapPool).ticks(
                getState().s_lowerTick
            );
            (, , feeGrowthOutsideUpper, , , , , ) = (getState().i_uniswapPool).ticks(
                getState().s_upperTick
            );
        } else {
            feeGrowthGlobal = (getState().i_uniswapPool).feeGrowthGlobal1X128();
            (, , , feeGrowthOutsideLower, , , , ) = (getState().i_uniswapPool).ticks(
                getState().s_lowerTick
            );
            (, , , feeGrowthOutsideUpper, , , , ) = (getState().i_uniswapPool).ticks(
                getState().s_upperTick
            );
        }

        unchecked {
            // calculate fee growth below
            uint256 feeGrowthBelow;
            if (tick >= getState().s_lowerTick) {
                feeGrowthBelow = feeGrowthOutsideLower;
            } else {
                feeGrowthBelow = feeGrowthGlobal - feeGrowthOutsideLower;
            }

            // calculate fee growth above
            uint256 feeGrowthAbove;
            if (tick < getState().s_upperTick) {
                feeGrowthAbove = feeGrowthOutsideUpper;
            } else {
                feeGrowthAbove = feeGrowthGlobal - feeGrowthOutsideUpper;
            }

            uint256 feeGrowthInside = feeGrowthGlobal -
                feeGrowthBelow -
                feeGrowthAbove;
            fee = FullMath.mulDiv(
                liquidity,
                feeGrowthInside - feeGrowthInsideLast,
                0x100000000000000000000000000000000
            );
        }
    }

    // =================================
    // Callbacks
    // =================================

    /// @notice Uniswap V3 callback fn, called back on pool.mint
    function uniswapV3MintCallback(
        uint256 amount0Owed,
        uint256 amount1Owed,
        bytes calldata /*_data*/
    ) external override {
        if (msg.sender != address(getState().i_uniswapPool)) {
            revert ChamberV1__CallerIsNotUniPool();
        }

        if (amount0Owed > 0) TransferHelper.safeTransfer(getState().i_token1Address, msg.sender, amount0Owed);
        if (amount1Owed > 0) TransferHelper.safeTransfer(getState().i_token0Address, msg.sender, amount1Owed);
    }

    receive() external payable {}

}