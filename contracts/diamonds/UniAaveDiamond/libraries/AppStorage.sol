// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "../interfaces/UniInterfaces/ISwapRouter.sol";
import "../interfaces/UniInterfaces/IUniswapV3Pool.sol";
import "../interfaces/UniInterfaces/callback/IUniswapV3MintCallback.sol";

import "../interfaces/AaveInterfaces/IPool.sol";
import "../interfaces/AaveInterfaces/IAaveOracle.sol";
import "../interfaces/AaveInterfaces/IAToken.sol";
import "../interfaces/AaveInterfaces/IVariableDebtToken.sol";

library AppStorage {
	struct State {

		// =================================
		// Storage for users and their deposits
		// =================================

		uint256 s_totalShares;
		mapping(address => uint256) s_userShares;

		// =================================
		// Storage for pool
		// =================================

		int24 s_lowerTick;
		int24 s_upperTick;
		bool s_liquidityTokenId;

		// =================================
		// Storage for logic
		// =================================

		bool unlocked;

		uint256 s_targetLTV;
		uint256 s_minLTV;
		uint256 s_maxLTV;
		uint256 s_hedgeDev;

		uint256 s_cetraFeeToken0;
		uint256 s_cetraFeeToken1;

		int24 s_ticksRange;

		// =================================
		// Immutable
		// =================================

		address i_usdcAddress;
		address i_token0Address;
		address i_token1Address;

		IAToken i_aaveAUSDCToken;
		IVariableDebtToken i_aaveVToken0;
		IVariableDebtToken i_aaveVToken1;

		IAaveOracle i_aaveOracle;
		IPool i_aaveV3Pool;

		ISwapRouter i_uniswapSwapRouter;
		IUniswapV3Pool i_uniswapPool;
			
	}

	bytes32 constant APP_STORAGE_POSITION = keccak256("diamond.standard.the.cetra.storage");

	function getState() internal pure returns (State storage s) {
		bytes32 position = APP_STORAGE_POSITION;
        assembly {
            s.slot := position
        }
    }
}
