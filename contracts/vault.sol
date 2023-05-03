// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.19;

contract vault {
    // ===================
    // Storage
    // ===================

    struct Strategy{
        address daimondOfStrategy;
        uint256 share;
    }

    Strategy[] public strategies;
    
}