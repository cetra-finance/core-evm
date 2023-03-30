// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { LibDiamond } from "../libraries/LibDiamond.sol";

contract OwnershipFacet {
    
    function flipOwnershipStatus(address _newOwner) external {
        LibDiamond.enforceIsContractOwner();
        LibDiamond.flipContractOwnerStatus(_newOwner);
    }

    function isOwner(address addr) external view returns (bool result_) {
        result_ = LibDiamond.contractOwner(addr);
    }
}
