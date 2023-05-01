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
  });

  it("should have six facets -- call to facetAddresses function", async () => {
      for (const address of await diamondLoupeFacet.facetAddresses()) {
          addresses.push(address);
      }
      assert.equal(addresses.length, 8);
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
  });

  it("should add test1 functions", async () => {
      const Test1Facet = await ethers.getContractFactory("Test1Facet");
      const test1Facet = await Test1Facet.deploy();
      await test1Facet.deployed();
      addresses.push(test1Facet.address);
      const selectors = removeSelectors(getSelectors(test1Facet), [
          " supportsInterface(bytes4)",
      ]);
      let tx = await diamondCutFacet.diamondCut(
          [
              {
                  facetAddress: test1Facet.address,
                  action: FacetCutAction.Add,
                  functionSelectors: selectors,
              },
          ],
          ethers.constants.AddressZero,
          "0x",
          { gasLimit: 800000 }
      );
      let receipt = await tx.wait();
      if (!receipt.status) {
          throw Error(`Diamond upgrade failed: ${tx.hash}`);
      }
      let result = await diamondLoupeFacet.facetFunctionSelectors(
          test1Facet.address
      );
      assert.sameMembers(result, selectors);
  });

  it("should test function call", async () => {
      const test1Facet = await ethers.getContractAt(
          "Test1Facet",
          diamondAddress
      );
      await test1Facet.test1Func10();
  });

  it("should replace supportsInterface function", async () => {
      const t1facet = await ethers.getContractFactory("Test1Facet");
      const test1Facet = await ethers.getContractFactory("Test1Facet");
      const selectors = getSelectors(t1facet).get([
          "supportsInterface(bytes4)",
      ]);
      const testFacetAddress = addresses[8];
      let tx = await diamondCutFacet.diamondCut(
          [
              {
                  facetAddress: testFacetAddress,
                  action: FacetCutAction.Replace,
                  functionSelectors: selectors,
              },
          ],
          ethers.constants.AddressZero,
          "0x",
          { gasLimit: 800000 }
      );
      let receipt = await tx.wait();
      if (!receipt.status) {
          throw Error(`Diamond upgrade failed: ${tx.hash}`);
      }
      let result = await diamondLoupeFacet.facetFunctionSelectors(
          testFacetAddress
      );
      assert.sameMembers(result, getSelectors(test1Facet));
  });

  it("should add test2 functions", async () => {
      const Test2Facet = await ethers.getContractFactory("Test2Facet");
      const test2Facet = await Test2Facet.deploy();
      await test2Facet.deployed();
      addresses.push(test2Facet.address);
      const selectors = getSelectors(test2Facet);
      let tx = await diamondCutFacet.diamondCut(
          [
              {
                  facetAddress: test2Facet.address,
                  action: FacetCutAction.Add,
                  functionSelectors: selectors,
              },
          ],
          ethers.constants.AddressZero,
          "0x",
          { gasLimit: 800000 }
      );
      let receipt = await tx.wait();
      if (!receipt.status) {
          throw Error(`Diamond upgrade failed: ${tx.hash}`);
      }
      let result = await diamondLoupeFacet.facetFunctionSelectors(
          test2Facet.address
      );
      assert.sameMembers(result, selectors);
  });

  it("should remove some test2 functions", async () => {
      const test2Facet = await ethers.getContractAt(
          "Test2Facet",
          diamondAddress
      );
      const functionsToKeep = [
          "test2Func1()",
          "test2Func5()",
          "test2Func6()",
          "test2Func19()",
          "test2Func20()",
      ];
      const selectors = removeSelectors(
          getSelectors(test2Facet),
          functionsToKeep
      );
      let tx = await diamondCutFacet.diamondCut(
          [
              {
                  facetAddress: ethers.constants.AddressZero,
                  action: FacetCutAction.Remove,
                  functionSelectors: selectors,
              },
          ],
          ethers.constants.AddressZero,
          "0x",
          { gasLimit: 800000 }
      );
      let receipt = await tx.wait();
      if (!receipt.status) {
          throw Error(`Diamond upgrade failed: ${tx.hash}`);
      }
      let result = await diamondLoupeFacet.facetFunctionSelectors(
          addresses[7]
      );
      assert.sameMembers(
          result,
          getSelectors(test2Facet).get(functionsToKeep)
      );
  });

  it("should remove some test1 functions", async () => {
      const test1Facet = await ethers.getContractAt(
          "Test1Facet",
          diamondAddress
      );
      const functionsToKeep = [
          "test1Func2()",
          "test1Func11()",
          "test1Func12()",
      ];
      const selectors = removeSelectors(
          getSelectors(test1Facet),
          functionsToKeep
      );
      let tx = await diamondCutFacet.diamondCut(
          [
              {
                  facetAddress: ethers.constants.AddressZero,
                  action: FacetCutAction.Remove,
                  functionSelectors: selectors,
              },
          ],
          ethers.constants.AddressZero,
          "0x",
          { gasLimit: 800000 }
      );
      let receipt = await tx.wait();
      if (!receipt.status) {
          throw Error(`Diamond upgrade failed: ${tx.hash}`);
      }
      let result = await diamondLoupeFacet.facetFunctionSelectors(
          addresses[8]
      );
      assert.sameMembers(
          result,
          getSelectors(test1Facet).get(functionsToKeep)
      );
  });

  it("remove all functions and facets except 'diamondCut' and 'facets'", async () => {
      let selectors = [];
      let facets = await diamondLoupeFacet.facets();
      for (let i = 0; i < facets.length; i++) {
          selectors.push(...facets[i].functionSelectors);
      }
      selectors = removeSelectors(selectors, [
          "facets()",
          "diamondCut(tuple(address,uint8,bytes4[])[],address,bytes)",
      ]);
      let tx = await diamondCutFacet.diamondCut(
          [
              {
                  facetAddress: ethers.constants.AddressZero,
                  action: FacetCutAction.Remove,
                  functionSelectors: selectors,
              },
          ],
          ethers.constants.AddressZero,
          "0x",
          { gasLimit: 800000 }
      );
      let receipt = await tx.wait();
      if (!receipt.status) {
          throw Error(`Diamond upgrade failed: ${tx.hash}`);
      }
      facets = await diamondLoupeFacet.facets();
      assert.equal(facets.length, 2);
      assert.equal(facets[0][0], addresses[0]);
      assert.sameMembers(facets[0][1], ["0x1f931c1c"]);
      assert.equal(facets[1][0], addresses[1]);
      assert.sameMembers(facets[1][1], ["0x7a0ed627"]);
  });
});
