const {
    time,
    loadFixture,
} = require("@nomicfoundation/hardhat-network-helpers");
// const { anyValue } = require("@nomicfoundation/hardhat-chai-matchers/withArgs");
const { expect } = require("chai");
const { ethers, assert, network } = require("hardhat");

const VOTER_FEE_RATIO = 1;
const VOTER_FEE_COMPLEMENTARY_RATIO = 2;
const RECURRING_FEE_RATIO = 1;
const RECURRING_FEE_COMPLEMENTARY_RATIO = 3;
const VOTERS_REQUIRED = 7;
const RECURRING_PAYMENT_INTERVAL = (7 * 24 * 3600);
const MAX_SELLER_COUNT = 10;
const MAX_BUYER_COUNT = 10;

const PREMIUM = 0.1; // Fractional premium
const MAKER_FEE = 0.03;
const INIT_EPOCH = 2;
const INIT_MATURITY_DATE = Math.round(Date.now()/1000) + (86400 * 2);
const ENTITY_NAME = "UbeSwap";
const ENTITY_URL = "https://ubeswap.com";
const ZERO_ADDRESS = "0x0000000000000000000000000000000000000000"

describe("RateOracle", function () {
    let controller;
    let acc0, acc1, acc2, acc3, acc4, acc5;
    let oracleContract;
    let swapContract;
    let thirdPartySwapContract;


    before(async () => {
        [acc0, acc1, acc2, acc3, acc4, acc5, acc6, acc7, acc8, acc9, acc10] = await ethers.getSigners();
        controller = await (await (await ethers.getContractFactory("SwapController")).deploy(acc1.address
        )).deployed();

    })

    describe("Constructor", function () {

        it("Should deploy the contract and set the state variables", async () => {

            oracleContract = await (await (await ethers.getContractFactory("RateOracle")).deploy(controller.address
                , acc1.address
                , VOTER_FEE_RATIO
                , VOTER_FEE_COMPLEMENTARY_RATIO
                , RECURRING_FEE_RATIO
                , RECURRING_FEE_COMPLEMENTARY_RATIO
                , VOTERS_REQUIRED
                , RECURRING_PAYMENT_INTERVAL
            )).deployed();


            expect(await oracleContract.votersDefaultFeeRatio()).to.equal(VOTER_FEE_RATIO);
            expect(await oracleContract.votersDefaultFeeComplementaryRatio()).to.equal(VOTER_FEE_COMPLEMENTARY_RATIO);
            expect(await oracleContract.votersRecurringFeeRatio()).to.equal(RECURRING_FEE_RATIO);
            expect(await oracleContract.votersRecurringFeeComplementaryRatio()).to.equal(RECURRING_FEE_COMPLEMENTARY_RATIO);
            expect(await oracleContract.numberOfVotersExpected()).to.equal(VOTERS_REQUIRED);
            expect(await oracleContract.votersRecurringPaymentInterval()).to.equal(RECURRING_PAYMENT_INTERVAL);
        })
    })

    describe("setVoterFeeRatio", function() {

        before(async() => {
            const votingContract = await (await (await ethers.getContractFactory("Voting")).deploy(acc1.address, controller.address, oracleContract.address)).deployed();
            const poolToken1 = await (await (await ethers.getContractFactory("ERC20Mock")).deploy()).deployed();
            await (await controller.setOracleContract(
                oracleContract.address
            )).wait();

            await (await controller.setVotingContract(
                votingContract.address
            )).wait();

            await (await controller.createSwapContract(
                ENTITY_NAME
                , ENTITY_URL
                , poolToken1.address
                , (PREMIUM * 10000).toString()
                , (MAKER_FEE * 10000).toString()
                , INIT_MATURITY_DATE.toString()
                , INIT_EPOCH.toString()
            )).wait();

            await (await controller.createSwapContractAsThirdParty(
                ENTITY_NAME
                , ENTITY_URL
                , poolToken1.address
                , (PREMIUM * 10000).toString()
                , (MAKER_FEE * 10000).toString()
                , INIT_MATURITY_DATE.toString()
                , INIT_EPOCH.toString()
                , acc3.address
                , [acc4.address, acc5.address, acc6.address, acc7.address, acc8.address, acc9.address, acc10.address]
            )).wait();

            [swapContract, thirdPartySwapContract] = await controller.getSwapList();
        })

        context("Happy path", function() {
            const ratio = 1;
            const complementaryRatio = 2;
            it("Should emit SetDefaultFeeRatio event", async () => {
                const setTx = oracleContract.setVoterFeeRatio(ratio, complementaryRatio);

                await expect(setTx).to.emit(oracleContract, "SetDefaultFeeRatio").withArgs(ratio, complementaryRatio);
            })

            it("Should update contract state and use set values for default fee", async () => {

                expect(await oracleContract.votersDefaultFeeRatio()).to.equal(ratio);
                expect(await oracleContract.votersDefaultFeeComplementaryRatio()).to.equal(complementaryRatio);

                const amountToCalculateFrom = 1500;
                const expectedFee = ratio * amountToCalculateFrom/(ratio + complementaryRatio);

                expect((await oracleContract.getDefaultFeeAmount(ethers.utils.parseEther(amountToCalculateFrom.toString()), ZERO_ADDRESS)).toString())
                .to.equal(ethers.utils.parseEther(expectedFee.toString()).toString())
            })
        })

        context("Fail cases", function() {
            const ratio = 1;
            const complementaryRatio = 2;
            it("Should revert if called with address without admin role", async ()=> {
                const adminRole = await oracleContract.SUPER_ADMIN();
                const setTx = oracleContract.connect(acc2).setVoterFeeRatio(ratio, complementaryRatio);

                await expect(setTx).to.be.revertedWith(`AccessControl: account ${acc2.address.toLowerCase()} is missing role ${adminRole}`)
            })

            it("Should fail if ratio set produces a fraction above max fee rate", async () => {

                const maxFeeRate = (await oracleContract.maxFeeRate()).toString();
                let testRatio;
                let testComplementaryRatio
                do {
                    testRatio = Math.floor(Math.random() * 10);
                    testComplementaryRatio = Math.floor(Math.random() * 10);

                } while (testRatio * 10000/(testRatio + testComplementaryRatio) <= +maxFeeRate || testRatio === 0 || testComplementaryRatio === 0)
                const setTx = oracleContract.setVoterFeeRatio(testRatio, testComplementaryRatio);

                await expect(setTx).to.be.revertedWith("RateOracle: Fee rate specified too high");
            })
        })
    })

    describe("setVoterFeeRatioOverride", function() {

        context("Happy path", function() {
            const ratio = 1;
            const complementaryRatio = 5;
            it("Should emit SetDefaultFeeRatioOverride event", async () => {
                const setTx = oracleContract.setVoterFeeRatioOverride(ratio, complementaryRatio, thirdPartySwapContract);

                await expect(setTx).to.emit(oracleContract, "SetDefaultFeeRatioOverride").withArgs(thirdPartySwapContract
                    , ratio
                    , complementaryRatio
                    , acc0.address
                );
            })

            it("Should allow update by the pool owner", async () => {
                const setTx = oracleContract.connect(acc3).setVoterFeeRatioOverride(ratio, complementaryRatio, thirdPartySwapContract);

                await expect(setTx).to.not.be.reverted;
            })

            it("Should update contract state and use set values for default fee", async () => {

                const amountToCalculateFrom = 1500;
                const universalRatio = await oracleContract.votersDefaultFeeRatio();
                const universalComplementaryRatio = await oracleContract.votersDefaultFeeComplementaryRatio();
                const expectedFee = ratio * amountToCalculateFrom/(ratio + complementaryRatio);
                const expectedFalseFeeWithoutOverride = universalRatio * amountToCalculateFrom/(universalRatio + universalComplementaryRatio);

                expect((await oracleContract.getDefaultFeeAmount(ethers.utils.parseEther(amountToCalculateFrom.toString()), thirdPartySwapContract)).toString())
                .to.equal(ethers.utils.parseEther(expectedFee.toString()).toString());
                expect((await oracleContract.getDefaultFeeAmount(ethers.utils.parseEther(amountToCalculateFrom.toString()), thirdPartySwapContract)).toString())
                .to.not.equal(ethers.utils.parseEther(expectedFalseFeeWithoutOverride.toString()).toString())
            })
        })

        context("Fail cases", function() {
            const ratio = 1;
            const complementaryRatio = 2;
            it("Should revert if called with address without admin role or not pool owner", async ()=> {
                const adminRole = await oracleContract.SUPER_ADMIN();
                const setTx = oracleContract.connect(acc2).setVoterFeeRatioOverride(ratio, complementaryRatio, thirdPartySwapContract);

                await expect(setTx).to.be.revertedWith(`Unauthorized`)
            })

            it("Should fail if ratio set produces a fraction above max fee rate", async () => {

                const maxFeeRate = (await oracleContract.maxFeeRate()).toString();
                let testRatio;
                let testComplementaryRatio
                do {
                    testRatio = Math.floor(Math.random() * 10);
                    testComplementaryRatio = Math.floor(Math.random() * 10);

                } while (testRatio * 10000/(testRatio + testComplementaryRatio) <= +maxFeeRate || testRatio === 0 || testComplementaryRatio === 0)
                const setTx = oracleContract.setVoterFeeRatioOverride(testRatio, testComplementaryRatio, thirdPartySwapContract);

                await expect(setTx).to.be.revertedWith("RateOracle: Fee rate specified too high");
            })
        })
    })

    describe("setRecurringFeeRatio", function() {

        context("Happy path", function() {
            const ratio = 1;
            const complementaryRatio = 3;
            it("Should emit SetRecurringFeeRatio event", async () => {
                const setTx = oracleContract.setRecurringFeeRatio(ratio, complementaryRatio);

                await expect(setTx).to.emit(oracleContract, "SetRecurringFeeRatio").withArgs(ratio, complementaryRatio);
            })

            it("Should update contract state and use set values for default fee", async () => {

                expect(await oracleContract.votersRecurringFeeRatio()).to.equal(ratio);
                expect(await oracleContract.votersRecurringFeeComplementaryRatio()).to.equal(complementaryRatio);

                const amountToCalculateFrom = 1500;
                const expectedFee = ratio * amountToCalculateFrom/(ratio + complementaryRatio);

                expect((await oracleContract.getRecurringFeeAmount(ethers.utils.parseEther(amountToCalculateFrom.toString()), ZERO_ADDRESS)).toString())
                .to.equal(ethers.utils.parseEther(expectedFee.toString()).toString())
            })
        })

        context("Fail cases", function() {
            const ratio = 1;
            const complementaryRatio = 2;
            it("Should revert if called with address without admin role", async ()=> {
                const adminRole = await oracleContract.SUPER_ADMIN();
                const setTx = oracleContract.connect(acc3).setRecurringFeeRatio(ratio, complementaryRatio);

                await expect(setTx).to.be.revertedWith(`AccessControl: account ${acc3.address.toLowerCase()} is missing role ${adminRole}`)
            })

            it("Should fail if ratio set produces a fraction above max fee rate", async () => {

                const maxFeeRate = (await oracleContract.maxFeeRate()).toString();
                let testRatio;
                let testComplementaryRatio
                do {
                    testRatio = Math.floor(Math.random() * 10);
                    testComplementaryRatio = Math.floor(Math.random() * 10);

                } while (testRatio * 10000/(testRatio + testComplementaryRatio) <= +maxFeeRate || testRatio === 0 || testComplementaryRatio === 0)
                const setTx = oracleContract.setRecurringFeeRatio(testRatio, testComplementaryRatio);

                await expect(setTx).to.be.revertedWith("RateOracle: Fee rate specified too high");
            })
        })
    })

    describe("setRecurringFeeRatioOverride", function() {

        context("Happy path", function() {
            const ratio = 1;
            const complementaryRatio = 4;
            it("Should emit SetRecurringFeeRatioOverride event", async () => {
                const setTx = oracleContract.setRecurringFeeRatioOverride(ratio, complementaryRatio, thirdPartySwapContract);

                await expect(setTx).to.emit(oracleContract, "SetRecurringFeeRatioOverride").withArgs(thirdPartySwapContract
                    , ratio
                    , complementaryRatio
                    , acc0.address
                );
            })

            it("Should allow update by the pool owner", async () => {
                const setTx = oracleContract.connect(acc3).setRecurringFeeRatioOverride(ratio, complementaryRatio, thirdPartySwapContract);

                await expect(setTx).to.not.be.reverted;
            })

            it("Should update contract state and use set values for recurring fee", async () => {

                const amountToCalculateFrom = 1500;
                const universalRatio = await oracleContract.votersRecurringFeeRatio();
                const universalComplementaryRatio = await oracleContract.votersRecurringFeeComplementaryRatio();
                const expectedFee = ratio * amountToCalculateFrom/(ratio + complementaryRatio);
                const expectedFalseFeeWithoutOverride = universalRatio * amountToCalculateFrom/(universalRatio + universalComplementaryRatio);

                expect((await oracleContract.getRecurringFeeAmount(ethers.utils.parseEther(amountToCalculateFrom.toString()), thirdPartySwapContract)).toString())
                .to.equal(ethers.utils.parseEther(expectedFee.toString()).toString());
                expect((await oracleContract.getRecurringFeeAmount(ethers.utils.parseEther(amountToCalculateFrom.toString()), thirdPartySwapContract)).toString())
                .to.not.equal(ethers.utils.parseEther(expectedFalseFeeWithoutOverride.toString()).toString())
            })
        })

        context("Fail cases", function() {
            const ratio = 1;
            const complementaryRatio = 2;
            it("Should revert if called with address without admin role or not pool owner", async ()=> {
                const adminRole = await oracleContract.SUPER_ADMIN();
                const setTx = oracleContract.connect(acc2).setRecurringFeeRatioOverride(ratio, complementaryRatio, thirdPartySwapContract);

                await expect(setTx).to.be.revertedWith(`Unauthorized`)
            })

            it("Should fail if ratio set produces a fraction above max fee rate", async () => {

                const maxFeeRate = (await oracleContract.maxFeeRate()).toString();
                let testRatio;
                let testComplementaryRatio
                do {
                    testRatio = Math.floor(Math.random() * 10);
                    testComplementaryRatio = Math.floor(Math.random() * 10);

                } while (testRatio * 10000/(testRatio + testComplementaryRatio) <= +maxFeeRate || testRatio === 0 || testComplementaryRatio === 0)
                const setTx = oracleContract.setRecurringFeeRatioOverride(testRatio, testComplementaryRatio, thirdPartySwapContract);

                await expect(setTx).to.be.revertedWith("RateOracle: Fee rate specified too high");
            })
        })
    })

    describe("setVotersPaymentInterval", function() {

        
        context("Happy path", function() {
            const interval = (5 * 24 * 3600); //5 days

            it("Should emit SetPaymentInterval event", async () => {
                const setTx = oracleContract.setVotersPaymentInterval(interval.toString());

                await expect(setTx).to.emit(oracleContract, "SetPaymentInterval").withArgs(interval.toString());
            })

            it("Should update contract state and use set values for payment interval", async () => {

                expect((await oracleContract.votersRecurringPaymentInterval()).toString()).to.equal(interval.toString());

                expect((await oracleContract.getRecurringPaymentInterval(ZERO_ADDRESS)).toString())
                .to.equal(interval.toString())
            })
        })

        context("Fail cases", function() {
            const interval = (5 * 24 * 3600);
            it("Should revert if called with address without admin role", async ()=> {
                const adminRole = await oracleContract.SUPER_ADMIN();
                const setTx = oracleContract.connect(acc2).setVotersPaymentInterval(interval.toString());

                await expect(setTx).to.be.revertedWith(`AccessControl: account ${acc2.address.toLowerCase()} is missing role ${adminRole}`)
            })
        })
    })

    describe("setVotersPaymentIntervalOverride", function() {

        context("Happy path", function() {
            const interval = (6 * 24 * 3600);
            it("Should emit SetPaymentIntervalOverride event", async () => {
                const setTx = oracleContract.setVotersPaymentIntervalOverride(interval.toString(), thirdPartySwapContract);

                await expect(setTx).to.emit(oracleContract, "SetPaymentIntervalOverride").withArgs(thirdPartySwapContract
                    , interval.toString()
                    , acc0.address
                );
            })

            it("Should allow update by the pool owner", async () => {
                const setTx = oracleContract.connect(acc3).setVotersPaymentIntervalOverride(interval.toString(), thirdPartySwapContract);

                await expect(setTx).to.not.be.reverted;
            })

            it("Should update contract state and use set values for default fee", async () => {

                expect((await oracleContract.paymentIntervalOverride(thirdPartySwapContract)).toString()).to.equal(interval.toString());

                const intervalWithoutOverride = await oracleContract.votersRecurringPaymentInterval();

                expect((await oracleContract.getRecurringPaymentInterval(thirdPartySwapContract)).toString())
                .to.not.equal(intervalWithoutOverride.toString());
                expect((await oracleContract.getRecurringPaymentInterval(thirdPartySwapContract)).toString())
                .to.equal(interval.toString());

            })
        })

        context("Fail cases", function() {
            const interval = (6 * 24 * 3600);
            it("Should revert if called with address without admin role or not pool owner", async ()=> {
                const setTx = oracleContract.connect(acc2).setVotersPaymentIntervalOverride(interval.toString(), thirdPartySwapContract);

                await expect(setTx).to.be.revertedWith(`Unauthorized`)
            })

        })
    })
})