const {
time,
loadFixture,
} = require("@nomicfoundation/hardhat-network-helpers");
// const { anyValue } = require("@nomicfoundation/hardhat-chai-matchers/withArgs");
const { expect } = require("chai");
const BigNumber = require("bignumber.js");
const { ethers, assert } = require("hardhat");

const PREMIUM = 0.1; // Fractional premium
const MAKER_FEE = 0.03;
const INIT_EPOCH = 2;
const INIT_MATURITY_DATE = Math.round(Date.now()/1000) + 86400;
const ENTITY_NAME = "UbeSwap";
const ENTITY_URL = "https://ubeswap.com";
const MAX_SELLER_COUNT = 10;
const MAX_BUYER_COUNT = 10;


console.log("help")
let acc0;
let acc1;
let acc2;
let acc3;
let acc4;
let acc5;
let acc6;
let acc7;
let acc8;
let acc9;
let acc10;
let acc11;
let acc12;
let acc13;
let acc14;
let acc15;

contract("CEXDefaultSwap", async () => {

    // const poolToken = await (await (await ethers.getContractFactory("ERC20Mock")).deploy()).deployed();

    let swapContract;
    let poolToken;
    let controller;
    let oracle;
    let voting;
    let snapshotId;
    let sample1;
    let sample2;
    let newSwapContract;
    let votingSigner;
    let [voterFeeRatio
        , voterFeeComplementaryRatio
        , recurringFeeRatio
        , recurringFeeComplementaryRatio
        , votersRequired
        , recurringPaymentInterval] = [1, 2, 1, 3, 7, 30*24*3600];

    before(async () => {

        [acc0, acc1, acc2, acc3, acc4, acc5, acc6, acc7, acc8, acc9, acc10, acc11, acc12, acc13, acc14, acc15] = await ethers.getSigners();
        controller = await (await (await ethers.getContractFactory("SwapController")).deploy(acc1.address
            , MAX_SELLER_COUNT.toString()
            , MAX_BUYER_COUNT.toString()
        )).deployed();
        oracle = await (await (await ethers.getContractFactory("RateOracle")).deploy(controller.address
            , acc1.address
            , voterFeeRatio
            , voterFeeComplementaryRatio
            , recurringFeeRatio
            , recurringFeeComplementaryRatio
            , votersRequired
            , recurringPaymentInterval)).deployed();

        voting = await (await (await ethers.getContractFactory("Voting")).deploy(acc1.address
            , controller.address
            , oracle.address)).deployed();
    })
    
    
    describe("Constructor", async () => {
        

        context("Happy path", () => {
            

            it("Should deploy and set global variables", async function() {
                [acc0, acc1, acc2, acc3, acc4, acc5] = await ethers.getSigners();
                poolToken = await (await (await ethers.getContractFactory("ERC20Mock")).deploy()).deployed();
                

                swapContract = await (await (await ethers.getContractFactory("CEXDefaultSwap")).deploy(
                    
                    ENTITY_NAME,
                    ENTITY_URL,
                    poolToken.address,
                    (PREMIUM * 10000).toString(),
                    (MAKER_FEE * 10000).toString(),
                    (INIT_MATURITY_DATE).toString(),
                    (INIT_EPOCH).toString(),
                    MAX_SELLER_COUNT.toString(),
                    MAX_BUYER_COUNT.toString(),
                    voting.address, // assumed voting Contract
                    oracle.address
                )).deployed();

                const entity = await swapContract.entityName();
                const token = (await swapContract.currency());
                const maturityDate = (await swapContract.maturityDate()).toString()
                const epochDays = (await swapContract.epochDays()).toString()
                const premium = (await swapContract.premium()).toString()
                const maxBuyerCount = (await swapContract.maxBuyerCount()).toString()
                const maxSellerCount = (await swapContract.maxSellerCount()).toString()
                console.log(maturityDate)

                assert(entity == ENTITY_NAME, "Entity Name Mismatch")
                assert(token == poolToken.address, "Pool Currency Mismatch")
                assert(maturityDate == INIT_MATURITY_DATE.toString(), "Maturity Date Mismatch")
                assert(epochDays == INIT_EPOCH.toString(), "Epoch Days Mismatch")
                assert(premium == (PREMIUM * 10000).toString(), "Premium Value Mismatch")
                assert(maxBuyerCount == MAX_BUYER_COUNT.toString(), "Buyer Count Mismatch")
                assert(maxSellerCount == MAX_SELLER_COUNT.toString(), "Seller Count Mismatch")

                expect(entity).to.equal(ENTITY_NAME);
            })
        })

        context("Edge cases", async () => {
            it("Should fail deployment if maturity date is below current timestamp", () => {
                currentTime = Math.round(Date.now()/1000)
                setTimeout(async () => {

                    const swapContractDeployer = (await ethers.getContractFactory("CEXDefaultSwap")).deploy(
                    
                        ENTITY_NAME,
                        ENTITY_URL,
                        poolToken.address,
                        (PREMIUM * 10000).toString(),
                        (MAKER_FEE * 10000).toString(),
                        currentTime.toString(),
                        (INIT_EPOCH).toString(),
                        MAX_SELLER_COUNT.toString(),
                        MAX_BUYER_COUNT.toString(),
                        voting.address, 
                        oracle.address
                    );
    
                    await expect(swapContractDeployer).to.be.revertedWith("Invalid Maturity Date set");
                }, 10000) 
                
                

            })

            it("Should fail deployment if premium value passed is 100% or above", async () => {
                maturityTime = Math.round(Date.now()/1000) + 86400
                testPremium = 1.5

                const swapContractDeployer = (await ethers.getContractFactory("CEXDefaultSwap")).deploy(
                    
                    ENTITY_NAME,
                    ENTITY_URL,
                    poolToken.address,
                    (testPremium * 10000).toString(),
                    (MAKER_FEE * 10000).toString(),
                    maturityTime.toString(),
                    (INIT_EPOCH).toString(),
                    MAX_SELLER_COUNT.toString(),
                    MAX_BUYER_COUNT.toString(),
                    voting.address, 
                    oracle.address
                );

                await expect(swapContractDeployer).to.be.revertedWith("Premium, and maker fee, can not be 100% or above");
            })

            it("Should fail deployment if maker fee value passed is 100% or above", async () => {
                maturityTime = Math.round(Date.now()/1000) + 86400
                testMakerFee = 1.5

                const swapContractDeployer = (await ethers.getContractFactory("CEXDefaultSwap")).deploy(
                    
                    ENTITY_NAME,
                    ENTITY_URL,
                    poolToken.address,
                    (PREMIUM * 10000).toString(),
                    (testMakerFee * 10000).toString(),
                    maturityTime.toString(),
                    (INIT_EPOCH).toString(),
                    MAX_SELLER_COUNT.toString(),
                    MAX_BUYER_COUNT.toString(),
                    voting.address, 
                    oracle.address
                );

                await expect(swapContractDeployer).to.be.revertedWith("Premium, and maker fee, can not be 100% or above");
            })

            it("Should fail deployment if a non-contract address is passed as voting or oracle contract", async () => {
                maturityTime = Math.round(Date.now()/1000) + 86400

                const swapContractDeployer1 = (await ethers.getContractFactory("CEXDefaultSwap")).deploy(
                    
                    ENTITY_NAME,
                    ENTITY_URL,
                    poolToken.address,
                    (PREMIUM * 10000).toString(),
                    (MAKER_FEE * 10000).toString(),
                    maturityTime.toString(),
                    (INIT_EPOCH).toString(),
                    MAX_SELLER_COUNT.toString(),
                    MAX_BUYER_COUNT.toString(),
                    acc4.address, 
                    oracle.address
                );

                const swapContractDeployer2 = (await ethers.getContractFactory("CEXDefaultSwap")).deploy(
                    
                    ENTITY_NAME,
                    ENTITY_URL,
                    poolToken.address,
                    (PREMIUM * 10000).toString(),
                    (MAKER_FEE * 10000).toString(),
                    maturityTime.toString(),
                    (INIT_EPOCH).toString(),
                    MAX_SELLER_COUNT.toString(),
                    MAX_BUYER_COUNT.toString(),
                    voting.address, 
                    acc5.address
                );

                await expect(swapContractDeployer1).to.be.revertedWith("Address supplied for Voting, or Oracle, contract is invalid");
                await expect(swapContractDeployer2).to.be.revertedWith("Address supplied for Voting, or Oracle, contract is invalid");
            })

        })

    })

    describe("Deposit", function() {
        let previousSellerData;
        let previousAvailableCollateral;
        let previousDepositedCollateral;
        let previousSellerTokenBalance;
        let previousContractTokenBalance;
        const depositAmount = 100;
        const amtInWei = ethers.utils.parseEther(depositAmount.toString())

        context("Happy path", function () {

            it("Should emit Deposit event", async() => {

                await poolToken.mint(acc0.address, amtInWei)
                await poolToken.approve(swapContract.address, amtInWei)
                previousSellerTokenBalance = await poolToken.balanceOf(acc0.address);
                previousContractTokenBalance = await poolToken.balanceOf(swapContract.address);
                previousSellerData = await swapContract.sellers(acc0.address);
                previousAvailableCollateral = await swapContract.availableCollateral_Total();
                previousDepositedCollateral = await swapContract.depositedCollateral_Total();

                const depositTx = swapContract.deposit(amtInWei);

                await expect(depositTx).to.emit(swapContract, "Deposit").withArgs(acc0.address, amtInWei, amtInWei);
                snapshotId = await network.provider.send('evm_snapshot');
            })

            it("Should update the seller mappings on deposit", async () => {

                const finalSellerData = await swapContract.sellers(acc0.address);
                

                expect(await swapContract.onSellerList(acc0.address)).to.be.true;
                
                expect(+finalSellerData.depositedCollateral.toString() - (+previousSellerData.depositedCollateral.toString())).to.equal(+amtInWei.toString())
                expect(+finalSellerData.availableCollateral.toString() - (+previousSellerData.availableCollateral.toString())).to.equal(+amtInWei.toString())

            })

            it("Should update the global total deposit collateral data", async () => {
                const finalAvailableCollateral = await swapContract.availableCollateral_Total();
                const finalDepositedCollateral = await swapContract.depositedCollateral_Total();

                expect(+finalAvailableCollateral.toString() - (+previousAvailableCollateral.toString())).to.equal(+amtInWei.toString())
                expect(+finalDepositedCollateral.toString() - (+previousDepositedCollateral.toString())).to.equal(+amtInWei.toString())

            })

            it("Should reduce token balance of seller by deposit amount and increase balance of contract by same amount", async () => {

                finalSellerTokenBalance = await poolToken.balanceOf(acc0.address);
                finalContractTokenBalance = await poolToken.balanceOf(swapContract.address);

                expect(+previousSellerTokenBalance.toString() - (+finalSellerTokenBalance.toString())).to.equal(+amtInWei.toString())
                expect(+finalContractTokenBalance.toString() - (+previousContractTokenBalance.toString())).to.equal(+amtInWei.toString())

            })
        })

        context("Edge cases", () => {

            it("Should not deposit if seller has insufficient balance", async () => {
                await poolToken.approve(swapContract.address, amtInWei)

                const depositTx = swapContract.deposit(amtInWei);

                await expect(depositTx).to.be.revertedWith("ERC20: transfer amount exceeds balance");

            })

            it("Should not deposit without sufficient allowance", async () => {

                await poolToken.mint(acc0.address, amtInWei)
                await poolToken.decreaseAllowance(swapContract.address, amtInWei)

                const depositTx = swapContract.deposit(amtInWei);

                await expect(depositTx).to.be.revertedWith("ERC20: insufficient allowance");

            })

            it("Should not deposit if seller count already exceeded Max Seller Count", async () => {

                const accs = [acc5, acc6, acc7, acc8, acc9, acc10, acc11, acc12, acc13, acc14, acc15];

                for (const acc of accs.slice(0, MAX_SELLER_COUNT - 1)) {
                    await poolToken.mint(acc.address, amtInWei)
                    await poolToken.connect(acc).approve(swapContract.address, amtInWei)

                    await (await swapContract.connect(acc).deposit(amtInWei)).wait();

                }

                // Try to deposit on the next address
                const nextAcc = accs[MAX_SELLER_COUNT - 1]
                await poolToken.mint(nextAcc.address, amtInWei);
                await poolToken.connect(nextAcc).approve(swapContract.address, amtInWei);

                const depositTx = swapContract.connect(nextAcc).deposit(amtInWei);

                await expect(depositTx).to.be.revertedWith("Already reached maximum allowable sellers");
                await network.provider.send('evm_revert', [snapshotId]);
                
            })
        })
    })


    describe("Withdraw", function () {
        let previousSellerData;
        let previousAvailableCollateral;
        let previousDepositedCollateral;
        let previousSellerTokenBalance;
        let previousContractTokenBalance;
        const withdrawAmount = 5;
        const amtInWei = ethers.utils.parseEther(withdrawAmount.toString())

        context("Happy path", function () {

            it("should emit withdraw event", async () => {
                previousSellerTokenBalance = await poolToken.balanceOf(acc0.address);
                previousContractTokenBalance = await poolToken.balanceOf(swapContract.address);
                previousSellerData = await swapContract.sellers(acc0.address);
                previousAvailableCollateral = await swapContract.availableCollateral_Total();
                previousDepositedCollateral = await swapContract.depositedCollateral_Total();

                const withdrawTx = swapContract.withdraw(amtInWei);

                await expect(withdrawTx).to.emit(swapContract, "Withdraw").withArgs(acc0.address, amtInWei, amtInWei);
            })

            it("Should update the seller mappings on withdraw", async () => {

                const finalSellerData = await swapContract.sellers(acc0.address);
                

                expect(await swapContract.onSellerList(acc0.address)).to.be.true;
                
                expect(+previousSellerData.depositedCollateral.toString() - (+finalSellerData.depositedCollateral.toString())).to.equal(+amtInWei.toString())
                expect(+previousSellerData.availableCollateral.toString() - (+finalSellerData.availableCollateral.toString())).to.equal(+amtInWei.toString())

            })

            it("Should update the global total deposit collateral data", async () => {
                const finalAvailableCollateral = await swapContract.availableCollateral_Total();
                const finalDepositedCollateral = await swapContract.depositedCollateral_Total();

                expect(+previousAvailableCollateral.toString() - (+finalAvailableCollateral.toString())).to.equal(+amtInWei.toString())
                expect(+previousDepositedCollateral.toString() - (+finalDepositedCollateral.toString())).to.equal(+amtInWei.toString())

            })

            it("Should increase token balance of seller by withdraw amount and decrease balance of contract by the same", async () => {

                finalSellerTokenBalance = await poolToken.balanceOf(acc0.address);
                finalContractTokenBalance = await poolToken.balanceOf(swapContract.address);

                expect(+finalSellerTokenBalance.toString() - (+previousSellerTokenBalance.toString())).to.equal(+amtInWei.toString())
                expect(+previousContractTokenBalance.toString() - (+finalContractTokenBalance.toString())).to.equal(+amtInWei.toString())

            })

        })

        context("Edge cases", () => {

            it("Should not withdraw if amount exceeds seller's available collateral", async () => {
                const finalSellerData = await swapContract.sellers(acc0.address);

                const availableCollateral = ethers.utils.formatEther(finalSellerData.availableCollateral)
                const withdrawAmtInWei = ethers.utils.parseEther((+availableCollateral + 10).toString())

                const depositTx = swapContract.withdraw(withdrawAmtInWei);

                await expect(depositTx).to.be.revertedWith("Not enough unlocked collateral");

            })
        })
    })

    describe("Purchase", function () {
        let makerFee;
        let previousAvailableCollateral;
        let previousLockedCollateral;
        let previousSellerTokenBalance;
        let previousContractTokenBalance;
        let previousBuyerData;
        let previousCollateralCovered;
        let previousUnclaimedPremium;
        let previousBuyerTokenBalance;
        const purchaseAmount = 50;
        const amtInWei = ethers.utils.parseEther(purchaseAmount.toString())

        before(async () => {
            await poolToken.mint(acc4.address, amtInWei)
            await poolToken.connect(acc4).approve(swapContract.address, amtInWei);

            previousBuyerTokenBalance = await poolToken.balanceOf(acc4.address);
            previousContractTokenBalance = await poolToken.balanceOf(swapContract.address);
            previousBuyerData = await swapContract.buyers(acc4.address);
            previousAvailableCollateral = await swapContract.availableCollateral_Total();
            previousLockedCollateral = await swapContract.lockedCollateral_Total();
            previousCollateralCovered = await swapContract.collateralCovered_Total();
            previousUnclaimedPremium = await swapContract.unclaimedPremium_Total();

            makerFee = await swapContract.makerFee();
        })

        context("Happy path", function () {

            it("should emit purchase event", async () => {

                expectedPremiumPayable = purchaseAmount * PREMIUM;
                expectedMakerFee = purchaseAmount * (+makerFee.toString())/10000;

                premiumInWei = ethers.utils.parseEther(expectedPremiumPayable.toString());
                makerFeeInWei = ethers.utils.parseEther(expectedMakerFee.toString());

                const purchaseTx = swapContract.connect(acc4).purchase(amtInWei);

                await expect(purchaseTx).to.emit(swapContract, "PurchaseCollateral").withArgs(acc4.address, amtInWei, amtInWei, premiumInWei, makerFeeInWei);
                snapshotId = await network.provider.send('evm_snapshot');
            })

            it("Should update the buyer mappings on purchase", async () => {

                const finalBuyerData = await swapContract.buyers(acc4.address);

                expect(await swapContract.onBuyerList(acc4.address)).to.be.true;

                expectedPremiumPayable = purchaseAmount * PREMIUM;

                premiumInWei = ethers.utils.parseEther(expectedPremiumPayable.toString());
                
                expect(+previousBuyerData.collateralCovered.toString() - (+finalBuyerData.collateralCovered.toString())).to.equal(-amtInWei.toString())
                expect(+previousBuyerData.premiumPaid.toString() - (+finalBuyerData.premiumPaid.toString())).to.equal(-premiumInWei.toString())

            })

            it("Should update the global total collateral and premium data", async () => {
                const finalAvailableCollateral = await swapContract.availableCollateral_Total();
                const finalLockedCollateral = await swapContract.lockedCollateral_Total();

                const finalCollateralCovered = await swapContract.collateralCovered_Total();
                const finalUnclaimedPremium = await swapContract.unclaimedPremium_Total();

                expect(+previousAvailableCollateral.toString() - (+finalAvailableCollateral.toString())).to.equal(+amtInWei.toString())
                expect(+previousLockedCollateral.toString() - (+finalLockedCollateral.toString())).to.equal(-amtInWei.toString())

                expectedPremiumPayable = purchaseAmount * PREMIUM;

                premiumInWei = ethers.utils.parseEther(expectedPremiumPayable.toString());

                expect(+previousCollateralCovered.toString() - (+finalCollateralCovered.toString())).to.equal(-amtInWei.toString())
                expect(+previousUnclaimedPremium.toString() - (+finalUnclaimedPremium.toString())).to.equal(-premiumInWei.toString())

            })

            it("Should decrease token balance of buyer by expected premium plus maker fee and increase contract balance by the makerFee less voterFee", async () => {
                
                expectedPremiumPayable = purchaseAmount * PREMIUM;
                expectedMakerFee = purchaseAmount * (+makerFee.toString())/10000;

                premiumInWei = ethers.utils.parseEther(expectedPremiumPayable.toString());
                makerFeeInWei = ethers.utils.parseEther(expectedMakerFee.toString());

                finalBuyerTokenBalance = await poolToken.balanceOf(acc4.address);
                finalContractTokenBalance = await poolToken.balanceOf(swapContract.address);

                const expectedDiff = -premiumInWei.toString() + (-makerFeeInWei.toString());

                const voterFee = await oracle.getDefaultFeeAmount(makerFeeInWei, swapContract.address);
                const expectedContractDiff = expectedDiff + (+voterFee.toString())

                expect(+finalBuyerTokenBalance.toString() - (+previousBuyerTokenBalance.toString())).to.equal(expectedDiff)
                expect(+previousContractTokenBalance.toString() - (+finalContractTokenBalance.toString())).to.equal(expectedContractDiff)

            })

        })

        context("Edge cases", () => {

            it("Should not purchase if buyer count already exceeded Max Buyer Count", async () => {
                const amtToBuy = (purchaseAmount/10)/MAX_BUYER_COUNT;
                const amtToBuyInWei = ethers.utils.parseEther(amtToBuy.toString())

                const accs = [acc5, acc6, acc7, acc8, acc9, acc10, acc11, acc12, acc13, acc14, acc15];

                for (const acc of accs.slice(0, MAX_BUYER_COUNT - 1)) {
                    await poolToken.mint(acc.address, amtToBuyInWei)
                    await poolToken.connect(acc).approve(swapContract.address, amtToBuyInWei)

                    await (await swapContract.connect(acc).purchase(amtToBuyInWei)).wait();

                }

                // Try to deposit on the next address
                const nextAcc = accs[MAX_BUYER_COUNT - 1]
                await poolToken.mint(nextAcc.address, amtToBuyInWei);
                await poolToken.connect(nextAcc).approve(swapContract.address, amtToBuyInWei);

                const purchaseTx = swapContract.connect(nextAcc).purchase(amtToBuyInWei);

                await expect(purchaseTx).to.be.revertedWith("Already reached maximum allowable buyers");
                await network.provider.send('evm_revert', [snapshotId]);
                
            })
        })
    })


    describe("claimPremium", function () {
        let previousSellerData;
        let previousUnclaimedPremium;
        let previousSellerTokenBalance;

        before(async () => {

            previousSellerTokenBalance = await poolToken.balanceOf(acc0.address);
            previousSellerData = await swapContract.sellers(acc0.address);
            previousUnclaimedPremium = await swapContract.unclaimedPremium_Total();

        })

        context("Happy path", function () {

            it("should emit ClaimPremium event", async () => {

                const claimTx = swapContract.connect(acc0).claimPremium();
                const premiumClaimed = previousSellerData.unclaimedPremium;
                await expect(claimTx).to.emit(swapContract, "ClaimPremium").withArgs(acc0.address
                    , premiumClaimed
                    , premiumClaimed);
            })

            it("Should update the seller mappings and universal unclaimed premium", async () => {

                const finalSellerData = await swapContract.sellers(acc0.address);

                const finalUnclaimedPremium = await swapContract.unclaimedPremium_Total();
                expect(finalSellerData.unclaimedPremium.toString()).to.equal('0');
                expect(+previousUnclaimedPremium.toString() - (+finalUnclaimedPremium.toString())).to.equal(+previousSellerData.unclaimedPremium.toString())

            })

            it("Should transfer the premium amount to the seller", async () => {

                const finalSellerTokenBalance = await poolToken.balanceOf(acc0.address);
                expect(+finalSellerTokenBalance.toString() - (+previousSellerTokenBalance.toString())).to.equal(+previousSellerData.unclaimedPremium.toString())

            })

        })

    })


    describe("setDefaulted", function () {
        let previousSellerData;
        let previousAvailableCollateral;
        let previousLockedCollateral;
        let previousBuyerData;
        let previousCollateralCovered;
        let previousClaimableCollateral;
        let previousPauseState;

        context("Happy path", function () {

            before(async () => {

                sample1 = await (await (await ethers.getContractFactory("Sample")).deploy()).deployed();
                sample2 = await (await (await ethers.getContractFactory("Sample")).deploy()).deployed();

                await (await sample1.deposit({value: ethers.utils.parseEther("1")})).wait();
                await (await sample2.deposit({value: ethers.utils.parseEther("1")})).wait();

                newSwapContract = await (await (await ethers.getContractFactory("CEXDefaultSwap")).deploy(
                    
                    ENTITY_NAME,
                    ENTITY_URL,
                    poolToken.address,
                    (PREMIUM * 10000).toString(),
                    (MAKER_FEE * 10000).toString(),
                    (INIT_MATURITY_DATE).toString(),
                    (INIT_EPOCH).toString(),
                    MAX_SELLER_COUNT.toString(),
                    MAX_BUYER_COUNT.toString(),
                    sample1.address, // assumed voting Contract
                    oracle.address
                )).deployed();
                const depositAmount = 100;
                const purchaseAmount = 50;
                await (await poolToken.mint(acc1.address
                    , ethers.utils.parseEther(depositAmount.toString())
                )).wait();

                await (await poolToken.mint(acc3.address
                    , ethers.utils.parseEther(purchaseAmount.toString())
                )).wait();

                await (await poolToken.connect(acc1).approve(newSwapContract.address
                    , ethers.utils.parseEther(depositAmount.toString())
                )).wait();

                await (await poolToken.connect(acc3).approve(newSwapContract.address
                    , ethers.utils.parseEther(purchaseAmount.toString())
                )).wait();

                await (await newSwapContract.connect(acc1).deposit(ethers.utils.parseEther(depositAmount.toString()))).wait();
                await (await newSwapContract.connect(acc3).purchase(ethers.utils.parseEther(purchaseAmount.toString()))).wait();

                await hre.network.provider.request({
                    method: "hardhat_impersonateAccount",
                    params: [sample1.address],
                });

                votingSigner = await ethers.getSigner(sample1.address);
                
                previousSellerData = await newSwapContract.sellers(acc1.address);
                previousBuyerData = await newSwapContract.buyers(acc3.address);
                previousLockedCollateral = await newSwapContract.lockedCollateral_Total();
                previousCollateralCovered = await newSwapContract.collateralCovered_Total();
                previousClaimableCollateral = await newSwapContract.claimableCollateral_Total();
                previousPauseState = await newSwapContract.isPaused();
            })

            it("should update the pool state to defaulted", async () => {

                const tx = await newSwapContract.connect(votingSigner).setDefaulted();

                await tx.wait();

                expect(await newSwapContract.defaulted()).to.be.true;
            })

            it("Should set the pool state to paused", async () => {

                const finalPauseState = await newSwapContract.isPaused();
                expect(finalPauseState && previousPauseState).to.be.false;
                expect(finalPauseState).to.be.true;
            })

            it("Should update all buyer and seller numbers", async () => {

                const finalSellerData = await newSwapContract.sellers(acc1.address);
                const finalBuyerData = await newSwapContract.buyers(acc3.address);
                const finalLockedCollateral = await newSwapContract.lockedCollateral_Total();
                const finalCollateralCovered = await newSwapContract.collateralCovered_Total();
                const finalClaimableCollateral = await newSwapContract.claimableCollateral_Total();
                
                expect(+previousSellerData.depositedCollateral.toString() - (+finalSellerData.depositedCollateral.toString())).to.equal(+previousSellerData.lockedCollateral.toString())
                expect(+finalSellerData.lockedCollateral.toString()).to.equal(0)
                expect(+previousBuyerData.claimableCollateral.toString() - (+finalBuyerData.claimableCollateral.toString())).to.equal(-previousBuyerData.collateralCovered.toString())
                expect(+finalBuyerData.collateralCovered.toString()).to.equal(0)
                expect(+finalLockedCollateral.toString()).to.equal(0)

                expect(+previousClaimableCollateral.toString() - (+finalClaimableCollateral.toString())).to.equal(-previousCollateralCovered.toString())
                expect(+finalCollateralCovered.toString()).to.equal(0)

            })

        })

        context("Fail cases", () => {

            it("should only be callable from votingContract", async () => {

                const defaultTx = newSwapContract.setDefaulted();

                await expect(defaultTx).to.be.revertedWith("Unauthorized");

                const defaultTx2 = newSwapContract.connect(acc0).setDefaulted();

                await expect(defaultTx2).to.be.revertedWith("Unauthorized");
            })
        })
    })


    describe("claimCollateral", function () {
        let previousBuyerData;
        let previousClaimableCollateral;
        let previousBuyerTokenBalance;

        before(async () => {

            previousBuyerTokenBalance = await poolToken.balanceOf(acc3.address);
            previousBuyerData = await newSwapContract.buyers(acc3.address);
            previousClaimableCollateral = await newSwapContract.claimableCollateral_Total();
            console.log({previousBuyerData})
        })

        context("Happy path", function () {

            it("should emit ClaimCollateral event", async () => {

                const claimTx = newSwapContract.connect(acc3).claimCollateral();
                const collateralClaimed = previousBuyerData.claimableCollateral;
                await expect(claimTx).to.emit(newSwapContract, "ClaimCollateral").withArgs(acc3.address, collateralClaimed, collateralClaimed);
            })

            it("Should update the seller mappings and universal unclaimed premium", async () => {

                const finalBuyerData = await newSwapContract.buyers(acc3.address);

                const finalClaimableCollateral = await newSwapContract.claimableCollateral_Total();
                expect(finalBuyerData.claimableCollateral.toString()).to.equal('0');
                expect(+previousClaimableCollateral.toString() - (+finalClaimableCollateral.toString())).to.equal(+previousBuyerData.claimableCollateral.toString())

            })

            it("Should transfer the premium amount to the seller", async () => {

                const finalBuyerTokenBalance = await poolToken.balanceOf(acc3.address);
                expect(+finalBuyerTokenBalance.toString() - (+previousBuyerTokenBalance.toString())).to.equal(+previousBuyerData.claimableCollateral.toString())

            })

        })

    })

    describe("resetAfterDefault", function () {

        context("Happy path", function () {

            it("should update pool defaulted state to false", async () => {
                const newMaturityDate = Math.round(Date.now()/1000) + (86400 * 3);
                const tx = await newSwapContract.connect(acc0).resetAfterDefault(newMaturityDate);

                await tx.wait();

                expect(await newSwapContract.defaulted()).to.be.false;
                expect((await newSwapContract.maturityDate()).toString()).to.equal(newMaturityDate.toString());
            })

        })

    })

    describe("rollEpoch", function () {

        let epochDays;
        let previousMaturityDate;

        context("Happy path", function () {
            before(async () => {

                epochDays = await newSwapContract.epochDays();
                previousMaturityDate = await newSwapContract.maturityDate();

                // await network.provider.send('evm_setNextBlockTimestamp', [+previousMaturityDate.toString() + 1000]);
                // await network.provider.send('evm_mine');
                
            })

            it("should move the pool maturity date backward by as many seconds as in the epoch days", async () => {
                const tx = await newSwapContract.connect(acc0).rollEpoch();

                await tx.wait();

                const finalMaturityDate = await newSwapContract.maturityDate();

                expect(+finalMaturityDate.toString()).to.equal(+previousMaturityDate.toString() + (epochDays * 86400));
            })

        })

        context("Fail cases", function () {

            it("should not be callable by an address that is not the controller contract", async () => {

                const rollTx = newSwapContract.connect(votingSigner).rollEpoch();
    
                await expect(rollTx).to.be.revertedWith("Unauthorized");
            })

        })
    })

    describe("pause", function () {
        let previousPauseState;

        context("Happy path", function () {
            before(async () => {
                previousPauseState = await newSwapContract.isPaused();
            })

            it("should set the pool state to paused", async () => {
                const tx = await newSwapContract.connect(acc0).pause();
                await tx.wait();

                const finalPauseState = await newSwapContract.isPaused();
                expect(finalPauseState && previousPauseState).to.be.false;
                expect(finalPauseState).to.be.true;
            })

        })

        context("Fail cases", function () {

            it("should not be callable by an address that is not the controller or voting contract", async () => {

                const pauseTx = newSwapContract.connect(acc3).pause();
    
                await expect(pauseTx).to.be.revertedWith("Unauthorized");
            })

        })
    })

    describe("unpause", function () {
        let previousPauseState;

        context("Happy path", function () {
            before(async () => {
                previousPauseState = await newSwapContract.isPaused();
            })

            it("should set the pool state to paused", async () => {
                const tx = await newSwapContract.connect(acc0).unpause();
                await tx.wait();

                const finalPauseState = await newSwapContract.isPaused();
                expect(finalPauseState && previousPauseState).to.be.false;
                expect(finalPauseState).to.be.false;
            })

        })

        context("Fail cases", function () {

            it("should not be callable by an address that is not the controller or voting contract", async () => {

                const pauseTx = newSwapContract.connect(acc3).unpause();
    
                await expect(pauseTx).to.be.revertedWith("Unauthorized");
            })

        })
    })

    describe("closePool", function () {
        let previousSellerData;
        let previousAvailableCollateral;
        let previousLockedCollateral;
        let previousBuyerData;
        let previousCollateralCovered;
        let previousCloseState;

        context("Happy path", function () {
            before(async () => {
                previousSellerData = await newSwapContract.sellers(acc1.address);
                previousBuyerData = await newSwapContract.buyers(acc3.address);
                previousAvailableCollateral = await newSwapContract.availableCollateral_Total();
                previousLockedCollateral = await newSwapContract.lockedCollateral_Total();
                previousCollateralCovered = await newSwapContract.collateralCovered_Total();
                previousCloseState = await newSwapContract.closed();
            })

            it("should set the pool state to closed", async () => {
                const tx = await newSwapContract.connect(acc0).unpause();
                await tx.wait();

                const finalCloseState = await newSwapContract.closed();
                expect(finalCloseState && previousCloseState).to.be.false;
                expect(finalCloseState).to.be.false;
            })

            it("should revert locked collaterals to available collaterals and update the states", async () => {
                finalSellerData = await newSwapContract.sellers(acc1.address);
                finalBuyerData = await newSwapContract.buyers(acc3.address);
                finalAvailableCollateral = await newSwapContract.availableCollateral_Total();
                finalLockedCollateral = await newSwapContract.lockedCollateral_Total();
                finalCollateralCovered = await newSwapContract.collateralCovered_Total();

                expect(+previousSellerData.availableCollateral.toString() - (+finalSellerData.availableCollateral.toString())).to.equal(-previousSellerData.lockedCollateral.toString())
                expect(+finalSellerData.lockedCollateral.toString()).to.equal(0)
                expect(+finalBuyerData.collateralCovered.toString()).to.equal(0)
                expect(+previousAvailableCollateral.toString() - (+finalAvailableCollateral.toString())).to.equal(-previousLockedCollateral.toString())
                expect(+finalLockedCollateral.toString()).to.equal(0);
                expect(+finalCollateralCovered.toString()).to.equal(0)
            })

        })

        context("Fail cases", function () {

            it("should not be callable by an address that is not the controller", async () => {

                const closeTx = newSwapContract.connect(votingSigner).closePool();
    
                await expect(closeTx).to.be.revertedWith("Unauthorized");
            })

        })
    })

})
