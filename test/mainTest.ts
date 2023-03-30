/* global describe it before ethers */

const {
  getSelectors,
  FacetCutAction,
  removeSelectors,
  findAddressPositionInFacets
} = require('../scripts/libraries/diamond.js')

const { deployDiamond } = require('../scripts/deploy.js')

const { assert, expect } = require('chai')
const { ethers } = require('hardhat')
const { mine } = require("@nomicfoundation/hardhat-network-helpers");

describe('DiamondTest', async function () {
  let diamondAddress
  let diamondCutFacet
  let diamondLoupeFacet
  let diamondInit
  let ownershipFacet, pausableFacet, tokenFacet
  let tx
  let receipt
  let result
  const addresses = []
  let finalContract

  let signer, owner, _, user1, user2, user3, user4, user5, user6, user7;

  const mintSign = async (user) => {
    let nonce = await tokenFacet.getMintNonce(user.address)

    let encodePacked = ethers.utils.arrayify(
      ethers.utils.keccak256(
        ethers.utils.solidityPack(["address", "uint256"], [user.address.toLowerCase(), nonce])
      )
    )
    const signatureInfo = ethers.utils.splitSignature(await signer.signMessage(encodePacked))
    return {
      v: signatureInfo.v,
      r: signatureInfo.r,
      s: signatureInfo.s
    }
  }

  const giveFreeDaysSign = async (tokenId, daysNum) => {
    let nonce = await tokenFacet.getNonce(tokenId)

    let encodePacked = ethers.utils.arrayify(
      ethers.utils.keccak256(
        ethers.utils.solidityPack(["uint256", "uint256", "uint256"], [tokenId, daysNum, nonce])
      )
    )

    const signatureInfo = ethers.utils.splitSignature(await signer.signMessage(encodePacked))

    return {
      v: signatureInfo.v,
      r: signatureInfo.r,
      s: signatureInfo.s
    }

  }

  const mintFunc = async (user, days, pay) => {
    const balanceBefore = +(await tokenFacet.balanceOf(user.address))
    const currentIndexBefore = +(await tokenFacet.getCurrentIndex())

    let vrs = await mintSign(user);
    await tokenFacet.connect(user).mint(vrs.v, vrs.r, vrs.s, {value: ethers.utils.parseEther(pay)})

    expect(await tokenFacet.balanceOf(user.address)).to.be.equal(balanceBefore+1)
    expect(await tokenFacet.getCurrentIndex()).to.be.equal(currentIndexBefore+1)
    expect((await tokenFacet.getSubscriptionDeadline(currentIndexBefore)) > (Math.floor(Date.now() / 1000) + (days * 24 * 60 * 60))).to.be.true
    expect((await tokenFacet.getSubscriptionDeadline(currentIndexBefore)) < (Math.floor(Date.now() / 1000) + (days * 24 * 60 * 60) + 100)).to.be.true
  }
  

  before(async function () {
    [owner, signer, _, user1, user2, user3, user4, user5, user6, user7] = await ethers.getSigners()

    diamondAddress = await deployDiamond()

    diamondCutFacet = await ethers.getContractAt('DiamondCutFacet', diamondAddress)
    diamondLoupeFacet = await ethers.getContractAt('DiamondLoupeFacet', diamondAddress)

    ownershipFacet = await ethers.getContractAt('OwnershipFacet', diamondAddress)
    tokenFacet = await ethers.getContractAt('TokenFacet', diamondAddress)

  })

  it('should have three facets -- call to facetAddresses function', async () => {
    for (const address of await diamondLoupeFacet.facetAddresses()) {
      addresses.push(address)
    }

    assert.equal(addresses.length, 4)
  })

  it('facets should have the right function selectors -- call to facetFunctionSelectors function', async () => {
    let selectors = getSelectors(diamondCutFacet)
    result = await diamondLoupeFacet.facetFunctionSelectors(addresses[0])
    assert.sameMembers(result, selectors)
    selectors = getSelectors(diamondLoupeFacet)
    result = await diamondLoupeFacet.facetFunctionSelectors(addresses[1])
    assert.sameMembers(result, selectors)
    selectors = getSelectors(ownershipFacet)
    result = await diamondLoupeFacet.facetFunctionSelectors(addresses[2])
    assert.sameMembers(result, selectors)
    selectors = getSelectors(tokenFacet)
    result = await diamondLoupeFacet.facetFunctionSelectors(addresses[3])
    assert.sameMembers(result, selectors)
  })

  it('should add test1 functions', async () => {
    const Test1Facet = await ethers.getContractFactory('Test1Facet')
    const test1Facet = await Test1Facet.deploy()
    await test1Facet.deployed()
    addresses.push(test1Facet.address)
    const selectors = getSelectors(test1Facet).remove(['supportsInterface(bytes4)'])
    tx = await diamondCutFacet.diamondCut(
      [{
        facetAddress: test1Facet.address,
        action: FacetCutAction.Add,
        functionSelectors: selectors
      }],
      ethers.constants.AddressZero, '0x', { gasLimit: 800000 })
    receipt = await tx.wait()
    if (!receipt.status) {
      throw Error(`Diamond upgrade failed: ${tx.hash}`)
    }
    result = await diamondLoupeFacet.facetFunctionSelectors(test1Facet.address)
    assert.sameMembers(result, selectors)
  })

  it('should test function call', async () => {
    const test1Facet = await ethers.getContractAt('Test1Facet', diamondAddress)
    await test1Facet.test1Func10()
  })

  it('should replace supportsInterface function', async () => {
    const Test1Facet = await ethers.getContractFactory('Test1Facet')
    const selectors = getSelectors(Test1Facet).get(['supportsInterface(bytes4)'])
    const testFacetAddress = addresses[4]
    tx = await diamondCutFacet.diamondCut(
      [{
        facetAddress: testFacetAddress,
        action: FacetCutAction.Replace,
        functionSelectors: selectors
      }],
      ethers.constants.AddressZero, '0x', { gasLimit: 800000 })
    receipt = await tx.wait()
    if (!receipt.status) {
      throw Error(`Diamond upgrade failed: ${tx.hash}`)
    }
    result = await diamondLoupeFacet.facetFunctionSelectors(testFacetAddress)
    assert.sameMembers(result, getSelectors(Test1Facet))
  })

  it('should remove some test1 functions', async () => {
    const test1Facet = await ethers.getContractAt('Test1Facet', diamondAddress)
    const functionsToKeep = ['test1Func2()', 'test1Func11()', 'test1Func12()']
    const selectors = getSelectors(test1Facet).remove(functionsToKeep)
    tx = await diamondCutFacet.diamondCut(
      [{
        facetAddress: ethers.constants.AddressZero,
        action: FacetCutAction.Remove,
        functionSelectors: selectors
      }],
      ethers.constants.AddressZero, '0x', { gasLimit: 800000 })
    receipt = await tx.wait()
    if (!receipt.status) {
      throw Error(`Diamond upgrade failed: ${tx.hash}`)
    }
    result = await diamondLoupeFacet.facetFunctionSelectors(addresses[4])
    assert.sameMembers(result, getSelectors(test1Facet).get(functionsToKeep))
  })

  it("Should revert uri check", async () => {
    await expect(tokenFacet.tokenURI(2)).to.be.reverted
  })

  it("should not set signer", async () => {
    await expect(tokenFacet.connect(user1).setPublicKey(signer.address)).to.be.reverted
  })

  it("should not set RenewSubscriptionPrice", async () => {
    await expect(tokenFacet.connect(user1).setRenewSubscriptionPrice(ethers.utils.parseEther("0.1"))).to.be.reverted
  })

  it("should not set AfterMintSubscription", async () => {
    await expect(tokenFacet.connect(user1).setAfterMintSubscription(10)).to.be.reverted
  })

  it("should not set base uri", async () => {
    await expect(tokenFacet.connect(user1).setBaseURI("666")).to.be.reverted
  })

  it("should now set max supply", async () => {
    await expect(tokenFacet.connect(user1).setMaxSupply(100)).to.be.reverted
  })


  it("Sets signer", async () => {
    await tokenFacet.connect(owner).setPublicKey(signer.address)
    expect(await tokenFacet.getPublicKey()).to.be.equal(signer.address)
  })
  
  it("sets RenewSubscriptionPrice", async () => {
    await tokenFacet.connect(owner).setRenewSubscriptionPrice(ethers.utils.parseEther("0.1"))
    expect(await tokenFacet.getRenewSubscriptionPrice()).to.be.equal(ethers.utils.parseEther("0.1"))
  })

  it("sets AfterMintSubscription", async () => {
    await tokenFacet.connect(owner).setAfterMintSubscription(10)
    expect(await tokenFacet.getAfterMintSubscription()).to.be.equal(10)
  })
  
  it("set max supply", async () => {
    await tokenFacet.connect(owner).setMaxSupply(30)
    expect(await tokenFacet.getMaxSupply()).to.be.equal(30)
  })

  it("Mints 4 tokens for user1; 2 tokens for user2; 1 token for other, expect user7", async () => {
    await mintFunc(user1, 10, "0")
    await mintFunc(user1, 10, "0")
    await mintFunc(user1, 10, "0")
    await mintFunc(user1, 10, "0")

    await mintFunc(user2, 10, "0")
    await mintFunc(user2, 10, "0")

    await mintFunc(user3, 10, "0")
    await mintFunc(user4, 10, "0")
    await mintFunc(user5, 10, "0")
    await mintFunc(user6, 10, "0")
  })

  it("renew nft for 2 nft of user1; 1 nft of user2; nfts of user3, user4, user5", async () => {
    let subscriptionDeadlineBefore = await tokenFacet.getSubscriptionDeadline(1)
    await tokenFacet.connect(user1).renewSubscription(1, { value: ethers.utils.parseEther("0.1") })
    expect(await tokenFacet.getSubscriptionDeadline(1)).to.be.equal(subscriptionDeadlineBefore.add(30 * 24 * 60 * 60))

    subscriptionDeadlineBefore = await tokenFacet.getSubscriptionDeadline(3)
    await tokenFacet.connect(user1).renewSubscriptionForSeveralMonth(3, 3, { value: ethers.utils.parseEther("0.3") })
    expect(await tokenFacet.getSubscriptionDeadline(3)).to.be.equal(subscriptionDeadlineBefore.add(3 * 30 * 24 * 60 * 60))

    subscriptionDeadlineBefore = await tokenFacet.getSubscriptionDeadline(5)
    let vrs = await giveFreeDaysSign(5, 15)
    await tokenFacet.connect(user2).freeRenewSubscription(5, 15, vrs.v, vrs.r, vrs.s)
    expect(await tokenFacet.getSubscriptionDeadline(5)).to.be.equal(subscriptionDeadlineBefore.add(15 * 24 * 60 * 60))

    subscriptionDeadlineBefore = await tokenFacet.getSubscriptionDeadline(7)
    await tokenFacet.connect(owner).airDropSubscriptionForToken(7, 17)
    expect(await tokenFacet.getSubscriptionDeadline(7)).to.be.equal(subscriptionDeadlineBefore.add(17 * 24 * 60 * 60))

    subscriptionDeadlineBefore = await tokenFacet.getSubscriptionDeadline(8)
    await tokenFacet.connect(user4).renewSubscription(8, { value: ethers.utils.parseEther("0.1") })
    expect(await tokenFacet.getSubscriptionDeadline(8)).to.be.equal(subscriptionDeadlineBefore.add(30 * 24 * 60 * 60))

    subscriptionDeadlineBefore = await tokenFacet.getSubscriptionDeadline(9)
    await tokenFacet.connect(user5).renewSubscription(9, { value: ethers.utils.parseEther("0.1") })
    expect(await tokenFacet.getSubscriptionDeadline(9)).to.be.equal(subscriptionDeadlineBefore.add(30 * 24 * 60 * 60))
  })

  it("should withdraw all funds", async () => {
    let balanceBefore = await ethers.provider.getBalance(owner.address)

    let tx = await tokenFacet.connect(owner).withdrawEth()
    let receipt = await tx.wait()

    expect(await ethers.provider.getBalance(owner.address)).to.be.equal(balanceBefore.add(ethers.utils.parseEther("0.6")).sub(receipt.gasUsed.mul(tx.gasPrice)))
  })

  it("should airfrop free subscription all active users", async () => {
    await tokenFacet.connect(owner).setAfterMintSubscription(0)
    expect(await tokenFacet.getAfterMintSubscription()).to.be.equal(0)

    await mintFunc(user6, 0, "0")

    let subscriptionDeadlineBefore = []
    let totalSupply = await tokenFacet.getCurrentIndex()
    for (let i = 0; i < totalSupply; i++) {
      subscriptionDeadlineBefore.push(await tokenFacet.getSubscriptionDeadline(i))
    }
    await tokenFacet.connect(owner).airDropSubscriptionForActiveTokens(5)
    for (let i = 0; i < totalSupply - 1; i++) {
      expect(await tokenFacet.getSubscriptionDeadline(i)).to.be.equal(subscriptionDeadlineBefore[i].add(5 * 24 * 60 * 60))
    }
    expect(await tokenFacet.getSubscriptionDeadline(10)).to.be.equal(subscriptionDeadlineBefore[10].add(0 * 24 * 60 * 60))

    await tokenFacet.connect(owner).setAfterMintSubscription(10)
    expect(await tokenFacet.getAfterMintSubscription()).to.be.equal(10)
  })

  it("should airfrop free subscription to all users", async () => {
    let subscriptionDeadlineBefore = []
    let totalSupply = await tokenFacet.getCurrentIndex()
    for (let i = 0; i < totalSupply; i++) {
      subscriptionDeadlineBefore.push(await tokenFacet.getSubscriptionDeadline(i))
    }

    await tokenFacet.connect(owner).airDropSubscriptionForAllTokens(8)

    for (let i = 0; i < totalSupply; i++) {
      expect((await tokenFacet.getSubscriptionDeadline(i)) >= (subscriptionDeadlineBefore[i].add(8 * 24 * 60 * 60))).to.be.true
      expect((await tokenFacet.getSubscriptionDeadline(i)) < (subscriptionDeadlineBefore[i].add(8 * 24 * 60 * 60).add(5))).to.be.true
    }
  })

  it("should test flipPauseAllTransfers", async () => {
    expect(await tokenFacet.isTransfersPaused()).to.be.false
    await tokenFacet.connect(owner).flipPauseAllTransfers()
    expect(await tokenFacet.isTransfersPaused()).to.be.true

    await expect(tokenFacet.connect(user1).transferFrom(user1.address, user2.address, 1)).to.be.reverted

    await tokenFacet.connect(owner).flipPauseAllTransfers()
    expect(await tokenFacet.isTransfersPaused()).to.be.false

    await expect(tokenFacet.connect(user1).transferFrom(user1.address, user2.address, 1)).to.not.be.reverted
  })

  it("should test flipPauseOneToken", async () => {
    expect(await tokenFacet.isTokenPaused(1)).to.be.false
    await tokenFacet.connect(owner).flipPauseOneToken(1)
    expect(await tokenFacet.isTokenPaused(1)).to.be.true

    await expect(tokenFacet.connect(user2).transferFrom(user2.address, user1.address, 1)).to.be.reverted

    await tokenFacet.connect(owner).flipPauseOneToken(1)
    expect(await tokenFacet.isTokenPaused(1)).to.be.false

    await expect(tokenFacet.connect(user2).transferFrom(user2.address, user1.address, 1)).to.not.be.reverted
  })

  it("Should mint after change of mintPrice", async () => {
    expect(await tokenFacet.getMintPrice()).to.be.equal(0)
    await tokenFacet.connect(owner).setMintPrice(ethers.utils.parseEther("0.1"))
    expect(await tokenFacet.getMintPrice()).to.be.equal(ethers.utils.parseEther("0.1"))

    await mintFunc(user7, 10, "0.1")

    await tokenFacet.connect(owner).setMintPrice(ethers.utils.parseEther("0"))
    expect(await tokenFacet.getMintPrice()).to.be.equal(0)
  })

  it("Should kick user", async () => {
    let currentIndexBefore = await tokenFacet.getCurrentIndex()
    let balanceOfUser1Before = await tokenFacet.balanceOf(user1.address)

    await tokenFacet.connect(owner).kickMember(3)

    expect(await tokenFacet.getCurrentIndex()).to.be.equal(currentIndexBefore)
    expect(await tokenFacet.balanceOf(user1.address)).to.be.equal(balanceOfUser1Before.sub(1))
    await expect(tokenFacet.tokenURI(3)).to.be.reverted
  })

  it("Should not mint more then Max Supply", async () => {
    let user4BalanceBefore = await tokenFacet.balanceOf(user4.address)

    for(let i = 0; i < 19; i++) {
      await mintFunc(user4, 10, "0")
    }

    expect(await tokenFacet.balanceOf(user4.address)).to.be.equal(user4BalanceBefore.add(19))
    expect(await tokenFacet.getCurrentIndex()).to.be.equal(31)
  })

  it("should change Max Supply", async () => {
    for (let i = 0; i < 5; i++) {
      await tokenFacet.connect(owner).kickMember(21+i)
    }

    expect(await tokenFacet.getCurrentIndex()).to.be.equal(31)
    expect(await tokenFacet.totalSupply()).to.be.equal(25)

    await tokenFacet.connect(owner).setMaxSupply(28)
    expect(await tokenFacet.getMaxSupply()).to.be.equal(28)

    for(let i = 0; i < 3; i++) {
      await mintFunc(user4, 10, "0")
    }

    expect(await tokenFacet.getCurrentIndex()).to.be.equal(34)
    expect(await tokenFacet.totalSupply()).to.be.equal(28)

    await tokenFacet.connect(owner).setMaxSupply(35)
    expect(await tokenFacet.getMaxSupply()).to.be.equal(35)

    for (let i = 0; i < 7; i++) {
      await mintFunc(user4, 10, "0")
    }

    expect(await tokenFacet.getCurrentIndex()).to.be.equal(41)
    expect(await tokenFacet.totalSupply()).to.be.equal(35)
  })

  it("Should not mint more then Max Supply again", async () => {
    expect(mintFunc(user6, 10, "0")).to.be.reverted
  })

  it("final withdraw", async () => {
    let balanceBefore = await ethers.provider.getBalance(owner.address)

    let tx = await tokenFacet.connect(owner).withdrawEth()
    let receipt = await tx.wait()

    console.log(await tokenFacet.tokenURI(0))
    console.log(await tokenFacet.tokenURI(2))
    await mine(2, { interval: 60*60*24*12 })
    console.log(await tokenFacet.tokenURI(20))

    expect(await ethers.provider.getBalance(owner.address)).to.be.equal(balanceBefore.add(ethers.utils.parseEther("0.1")).sub(receipt.gasUsed.mul(tx.gasPrice)))
  })

  it('remove all functions and facets except \'diamondCut\' and \'facets\'', async () => {
    let selectors = []
    let facets = await diamondLoupeFacet.facets()
    for (let i = 0; i < facets.length; i++) {
      selectors.push(...facets[i].functionSelectors)
    }
    selectors = removeSelectors(selectors, ['facets()', 'diamondCut(tuple(address,uint8,bytes4[])[],address,bytes)'])
    tx = await diamondCutFacet.diamondCut(
      [{
        facetAddress: ethers.constants.AddressZero,
        action: FacetCutAction.Remove,
        functionSelectors: selectors
      }],
      ethers.constants.AddressZero, '0x', { gasLimit: 800000 })
    receipt = await tx.wait()
    if (!receipt.status) {
      throw Error(`Diamond upgrade failed: ${tx.hash}`)
    }
    facets = await diamondLoupeFacet.facets()
    assert.equal(facets.length, 2)
    assert.equal(facets[0][0], addresses[0])
    assert.sameMembers(facets[0][1], ['0x1f931c1c'])
    assert.equal(facets[1][0], addresses[1])
    assert.sameMembers(facets[1][1], ['0x7a0ed627'])
  })

})

