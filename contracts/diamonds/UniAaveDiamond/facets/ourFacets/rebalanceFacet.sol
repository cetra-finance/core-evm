// SPDX-License-Identifier: MIT License
pragma solidity >=0.8.0;
pragma abicoder v2;

import "@openzeppelin/contracts/proxy/utils/Initializable.sol";

import "../../libraries/TransferHelper.sol";
import "../../libraries/TickMath.sol";

import "../../libraries/AppStorage.sol";
import "../../libraries/BaseContract.sol";

import "hardhat/console.sol";

contract ChamberV1 is
    AppStorage,
    BaseContract,
    initializable
{

    // =================================
    // Constructor
    // =================================

    function init(
        address _uniswapSwapRouterAddress,
        address _uniswapPoolAddress,
        address _aaveV3poolAddress,
        address _aaveVTOKEN0Address,
        address _aaveVTOKEN1Address,
        address _aaveOracleAddress,
        address _aaveAUSDCAddress,
        int24 _ticksRange
    ) external initializer {
        getState().i_uniswapSwapRouter = ISwapRouter(_uniswapSwapRouterAddress);
        getState().i_uniswapPool = IUniswapV3Pool(_uniswapPoolAddress);
        getState().i_aaveV3Pool = IPool(_aaveV3poolAddress);
        getState().i_aaveOracle = IAaveOracle(_aaveOracleAddress);
        getState().i_aaveAUSDCToken = IAToken(_aaveAUSDCAddress);
        getState().i_aaveVToken0 = IVariableDebtToken(_aaveVTOKEN0Address);
        getState().i_aaveVToken1 = IVariableDebtToken(_aaveVTOKEN1Address);
        getState().i_usdcAddress = i_aaveAUSDCToken.UNDERLYING_ASSET_ADDRESS();
        getState().i_token0Address = i_aaveVToken0.UNDERLYING_ASSET_ADDRESS();
        getState().i_token1Address = i_aaveVToken1.UNDERLYING_ASSET_ADDRESS();
        getState().unlocked = true;
        getState().s_ticksRange = _ticksRange;
    }

    // =================================
    // Main funcitons
    // =================================

    function rebalance() external lock {
    }

    // =================================
    // View funcitons
    // =================================

    function getAdminBalance() public view returns (uint256, uint256) {
        return (s_cetraFeeWmatic, s_cetraFeeWeth);
    }

    function currentUSDBalance() public view returns (uint256) {
        (
            uint256 wmaticPoolBalance,
            uint256 wethPoolBalance
        ) = calculateCurrentPoolReserves();
        (
            uint256 wmaticFeePending,
            uint256 wethFeePending
        ) = calculateCurrentFees();
        uint256 pureUSDCAmount = getAUSDCTokenBalance() +
            TransferHelper.safeGetBalance(i_usdcAddress, address(this));
        uint256 poolTokensValue = ((wethPoolBalance +
            wethFeePending +
            TransferHelper.safeGetBalance(i_wethAddress, address(this)) -
            s_cetraFeeWeth) *
            getWethOraclePrice() +
            (wmaticPoolBalance +
                wmaticFeePending +
                TransferHelper.safeGetBalance(i_wmaticAddress, address(this)) -
                s_cetraFeeWmatic) *
            getWmaticOraclePrice()) /
            getUsdcOraclePrice() /
            1e12;
        uint256 debtTokensValue = (getVWETHTokenBalance() *
            getWethOraclePrice() +
            getVWMATICTokenBalance() *
            getWmaticOraclePrice()) /
            getUsdcOraclePrice() /
            1e12;
        return pureUSDCAmount + poolTokensValue - debtTokensValue;
    }

    function currentLTV() public view returns (uint256) {
        // return currentETHBorrowed * getWethOraclePrice() / currentUSDInCollateral/getUsdOraclePrice()
        (
            uint256 totalCollateralETH,
            uint256 totalBorrowedETH,
            ,
            ,
            ,

        ) = i_aaveV3Pool.getUserAccountData(address(this));
        uint256 ltv = totalCollateralETH == 0
            ? 0
            : (PRECISION * totalBorrowedETH) / totalCollateralETH;
        return ltv;
    }

    function sharesWorth(uint256 shares) public view returns (uint256) {
        return (currentUSDBalance() * shares) / s_totalShares;
    }

    function calculateCurrentPoolReserves()
        public
        view
        returns (uint256, uint256)
    {
        uint128 liquidity = getLiquidity();

        // compute current holdings from liquidity
        (uint256 amount0Current, uint256 amount1Current) = LiquidityAmounts
            .getAmountsForLiquidity(
                getSqrtRatioX96(),
                TickMath.getSqrtRatioAtTick(s_lowerTick),
                TickMath.getSqrtRatioAtTick(s_upperTick),
                liquidity
            );

        return (amount0Current, amount1Current);
    }

    // =================================
    // Admin functions
    // =================================

    function _redeemFees() public onlyOwner {
        TransferHelper.safeTransfer(i_wmaticAddress, owner(), s_cetraFeeWmatic);
        TransferHelper.safeTransfer(i_wethAddress, owner(), s_cetraFeeWeth);
        s_cetraFeeWmatic = 0;
        s_cetraFeeWeth = 0;
    }

    function giveApprove(address _token, address _to) public onlyOwner {
        TransferHelper.safeApprove(_token, _to, type(uint256).max);
    }

    function setLTV(
        uint256 _targetLTV,
        uint256 _minLTV,
        uint256 _maxLTV,
        uint256 _hedgeDev
    ) public onlyOwner {
        s_targetLTV = _targetLTV;
        s_minLTV = _minLTV;
        s_maxLTV = _maxLTV;
        s_hedgeDev = _hedgeDev;
    }
}