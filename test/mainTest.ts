/* global describe it before ethers */

import {
    getSelectors,
    FacetCutAction,
    removeSelectors,
    findAddressPositionInFacets,
} from "../scripts/libraries/diamond";

import { deployDiamond } from "../scripts/deploy";

import { assert, expect } from "chai";
import { mine } from "@nomicfoundation/hardhat-network-helpers";
import helpers from "@nomicfoundation/hardhat-network-helpers";
import { impersonateAccount } from "@nomicfoundation/hardhat-network-helpers";
import { ethers, network } from "hardhat";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { Contract } from "ethers";

import { networkConfig } from "../helper-hardhat-config";

describe("DiamondTest", async function () {
    const addresses: string[] = [];

    let owner: SignerWithAddress;
    let user: SignerWithAddress;

    let diamondAddress: string;

    let diamondCutFacet: Contract;
    let diamondLoupeFacet: Contract;
    let ownershipFacet: Contract;
    let burnFacet: Contract;
    let rebalanceFacet: Contract;
    let mintFacet: Contract;
    let uniFacet: Contract;
    let aaveFacet: Contract;
    let helperFacet: Contract;

    const currNetworkConfig = networkConfig[network.config.chainId];

    this.beforeAll(async () => {
        [owner, user] = await ethers.getSigners();

        diamondAddress = await deployDiamond();

        diamondCutFacet = await ethers.getContractAt(
            "DiamondCutFacet",
            diamondAddress
        );
        diamondLoupeFacet = await ethers.getContractAt(
            "DiamondLoupeFacet",
            diamondAddress
        );

        ownershipFacet = await ethers.getContractAt(
            "OwnershipFacet",
            diamondAddress
        );
        burnFacet = await ethers.getContractAt("BurnFacet", diamondAddress);
        rebalanceFacet = await ethers.getContractAt(
            "RebalanceFacet",
            diamondAddress
        );
        mintFacet = await ethers.getContractAt("MintFacet", diamondAddress);
        uniFacet = await ethers.getContractAt("UniFacet", diamondAddress);
        aaveFacet = await ethers.getContractAt("AaveFacet", diamondAddress);
        helperFacet = await ethers.getContractAt("HelperFacet", diamondAddress);
    });

    it("should have six facets -- call to facetAddresses function", async () => {
        for (const address of await diamondLoupeFacet.facetAddresses()) {
            addresses.push(address);
        }
        assert.equal(addresses.length, 9);
    });

    it("facets should have the right function selectors -- call to facetFunctionSelectors function", async () => {
        let selectors = getSelectors(diamondCutFacet);
        let result = await diamondLoupeFacet.facetFunctionSelectors(
            addresses[0]
        );
        assert.sameMembers(result, selectors);

        selectors = getSelectors(diamondLoupeFacet);
        result = await diamondLoupeFacet.facetFunctionSelectors(addresses[1]);
        assert.sameMembers(result, selectors);

        selectors = getSelectors(ownershipFacet);
        result = await diamondLoupeFacet.facetFunctionSelectors(addresses[2]);
        assert.sameMembers(result, selectors);

        selectors = getSelectors(burnFacet);
        result = await diamondLoupeFacet.facetFunctionSelectors(addresses[3]);
        assert.sameMembers(result, selectors);

        selectors = getSelectors(mintFacet);
        result = await diamondLoupeFacet.facetFunctionSelectors(addresses[4]);
        assert.sameMembers(result, selectors);

        selectors = getSelectors(rebalanceFacet);
        result = await diamondLoupeFacet.facetFunctionSelectors(addresses[5]);
        assert.sameMembers(result, selectors);

        selectors = getSelectors(uniFacet);
        result = await diamondLoupeFacet.facetFunctionSelectors(addresses[6]);
        assert.sameMembers(result, selectors);

        selectors = getSelectors(aaveFacet);
        result = await diamondLoupeFacet.facetFunctionSelectors(addresses[7]);
        assert.sameMembers(result, selectors);

        selectors = getSelectors(helperFacet);
        result = await diamondLoupeFacet.facetFunctionSelectors(addresses[8]);
        assert.sameMembers(result, selectors);
    });

    it("Init our logic", async () => {
        await rebalanceFacet.init(
            currNetworkConfig.uniswapRouterAddress,
            currNetworkConfig.uniswapPoolAddress,
            currNetworkConfig.aaveV3PoolAddress,
            currNetworkConfig.aaveVWETHAddress,
            currNetworkConfig.aaveVWMATICAddress,
            currNetworkConfig.aaveOracleAddress,
            currNetworkConfig.aaveAUSDCAddress,
            3000
        );
        await rebalanceFacet.setLTV(
            currNetworkConfig.targetLTV,
            currNetworkConfig.minLTV,
            currNetworkConfig.maxLTV,
            currNetworkConfig.hedgeDev
        );

        await impersonateAccount(currNetworkConfig.donorWalletAddress);
        let donorWallet = await ethers.getSigner(
            currNetworkConfig.donorWalletAddress
        );

        let usd = await ethers.getContractAt(
            "IERC20",
            currNetworkConfig.usdcAddress
        );
        let weth = await ethers.getContractAt(
            "IERC20",
            currNetworkConfig.wethAddress
        );
        let wmatic = await ethers.getContractAt(
            "WMATIC",
            currNetworkConfig.wmaticAddress
        );

        await usd
            .connect(donorWallet)
            .transfer(user.address, 2000 * 1000 * 1000 * 1000);

        await usd
            .connect(user)
            .approve(rebalanceFacet.address, 1000 * 1000 * 1000 * 1000 * 1000);

        await rebalanceFacet.giveApprove(
            usd.address,
            currNetworkConfig.aaveV3PoolAddress
        );
        await rebalanceFacet.giveApprove(
            usd.address,
            currNetworkConfig.uniswapRouterAddress
        );
        await rebalanceFacet.giveApprove(
            usd.address,
            currNetworkConfig.uniswapPoolAddress
        );
        await rebalanceFacet.giveApprove(
            usd.address,
            currNetworkConfig.aaveVWETHAddress
        );

        await rebalanceFacet.giveApprove(
            weth.address,
            currNetworkConfig.aaveV3PoolAddress
        );
        await rebalanceFacet.giveApprove(
            weth.address,
            currNetworkConfig.uniswapRouterAddress
        );
        await rebalanceFacet.giveApprove(
            weth.address,
            currNetworkConfig.uniswapPoolAddress
        );
        await rebalanceFacet.giveApprove(
            weth.address,
            currNetworkConfig.aaveVWETHAddress
        );

        await rebalanceFacet.giveApprove(
            wmatic.address,
            currNetworkConfig.aaveV3PoolAddress
        );
        await rebalanceFacet.giveApprove(
            wmatic.address,
            currNetworkConfig.uniswapRouterAddress
        );
    });

    it("Makes deposit", async () => {
        await mintFacet.connect(user).mint(1000 * 1e6);
    });

    it("Makes rebalance", async () => {
        // await mintFacet.connect(user).mint(1000 * 1e6);
    });

    it("Makes burn", async () => {
        let shares = await helperFacet.getUserShares(user.address);
        await burnFacet.connect(user).burn(shares);
    });
});
