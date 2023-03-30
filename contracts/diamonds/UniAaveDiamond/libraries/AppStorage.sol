// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

library AppStorage {
	struct State {

		uint256 s_totalShares;

    	mapping(address => uint256) s_userShares;
		
	}

	bytes32 constant APP_STORAGE_POSITION = keccak256("diamond.standard.the.cetra.storage");

	function getState() internal pure returns (State storage s) {
		bytes32 position = APP_STORAGE_POSITION;
        assembly {
            s.slot := position
        }
    }
}
