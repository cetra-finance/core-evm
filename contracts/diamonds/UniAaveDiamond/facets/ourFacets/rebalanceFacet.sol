// SPDX-License-Identifier: MIT License
pragma solidity >=0.8.0;
pragma abicoder v2;

import "../../libraries/TransferHelper.sol";
import "../../libraries/uniLibraries/TickMath.sol";
import "../../libraries/uniLibraries/LiquidityAmounts.sol";

import "../../libraries/BaseContract.sol";

import "../innerInterfaces/IUniFacet.sol";
import "../innerInterfaces/IAaveFacet.sol";
import "../innerInterfaces/IMintFacet.sol";
import "../innerInterfaces/IBurnFacet.sol";

contract RebalanceFacet is
    BaseContract
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
    ) external {
        require(!getState().unlocked, "Already initialized");

        getState().i_uniswapSwapRouter = ISwapRouter(_uniswapSwapRouterAddress);
        getState().i_uniswapPool = IUniswapV3Pool(_uniswapPoolAddress);
        getState().i_aaveV3Pool = IPool(_aaveV3poolAddress);
        getState().i_aaveOracle = IAaveOracle(_aaveOracleAddress);
        getState().i_aaveAUSDCToken = IAToken(_aaveAUSDCAddress);
        getState().i_aaveVToken0 = IVariableDebtToken(_aaveVTOKEN0Address);
        getState().i_aaveVToken1 = IVariableDebtToken(_aaveVTOKEN1Address);
        getState().i_usdcAddress = (getState().i_aaveAUSDCToken).UNDERLYING_ASSET_ADDRESS();
        getState().i_token0Address = (getState().i_aaveVToken0).UNDERLYING_ASSET_ADDRESS();
        getState().i_token1Address = (getState().i_aaveVToken1).UNDERLYING_ASSET_ADDRESS();
        getState().unlocked = true;
        getState().s_ticksRange = _ticksRange;
    }

    // =================================
    // Main funcitons
    // =================================

    function rebalance() external lock {
        getState().s_liquidityTokenId = false;
        IBurnFacet(address(this)).burnInternal(getState().s_totalShares);
        IMintFacet(address(this)).mintInternal(TransferHelper.safeGetBalance(getState().i_usdcAddress));
    }

    // =================================
    // View funcitons
    // =================================

    function getAdminBalance() public view returns (uint256, uint256) {
        return (getState().s_cetraFeeToken1, getState().s_cetraFeeToken0);
    }

    function currentUSDBalance() public view returns (uint256) {
        (
            uint256 token1PoolBalance,
            uint256 token0PoolBalance
        ) = calculateCurrentPoolReserves();
        (
            uint256 token1FeePending,
            uint256 token0FeePending
        ) = IUniFacet(address(this)).calculateCurrentFees();
        uint256 pureUSDCAmount = IAaveFacet(address(this)).getAUSDCTokenBalance() +
            TransferHelper.safeGetBalance(getState().i_usdcAddress);
        uint256 poolTokensValue = ((token0PoolBalance +
            token0FeePending +
            TransferHelper.safeGetBalance(getState().i_token0Address) -
            getState().s_cetraFeeToken0) *
            IAaveFacet(address(this)).getToken0OraclePrice() +
            (token1PoolBalance +
                token1FeePending +
                TransferHelper.safeGetBalance(getState().i_token1Address) -
                getState().s_cetraFeeToken1) *
            IAaveFacet(address(this)).getToken1OraclePrice()) /
            IAaveFacet(address(this)).getUsdcOraclePrice() /
            1e12;
        uint256 debtTokensValue = (IAaveFacet(address(this)).getVToken0Balance() *
            IAaveFacet(address(this)).getToken0OraclePrice() +
            IAaveFacet(address(this)).getVToken1Balance() *
            IAaveFacet(address(this)).getToken1OraclePrice()) /
            IAaveFacet(address(this)).getUsdcOraclePrice() /
            1e12;
        return pureUSDCAmount + poolTokensValue - debtTokensValue;
    }

    function calculateCurrentPoolReserves()
        public
        view
        returns (uint256, uint256)
    {
        uint128 liquidity = IUniFacet(address(this)).getLiquidity();

        // compute current holdings from liquidity
        (uint256 amount0Current, uint256 amount1Current) = LiquidityAmounts
            .getAmountsForLiquidity(
                IUniFacet(address(this)).getSqrtRatioX96(),
                TickMath.getSqrtRatioAtTick(getState().s_lowerTick),
                TickMath.getSqrtRatioAtTick(getState().s_upperTick),
                liquidity
            );

        return (amount0Current, amount1Current);
    }

    // =================================
    // Admin functions
    // =================================

    function _redeemFees() public onlyOwner {
        TransferHelper.safeTransfer(getState().i_token1Address, msg.sender, getState().s_cetraFeeToken1);
        TransferHelper.safeTransfer(getState().i_token0Address, msg.sender, getState().s_cetraFeeToken0);
        getState().s_cetraFeeToken1 = 0;
        getState().s_cetraFeeToken0 = 0;
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
        getState().s_targetLTV = _targetLTV;
        getState().s_minLTV = _minLTV;
        getState().s_maxLTV = _maxLTV;
        getState().s_hedgeDev = _hedgeDev;
    }
}