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
const INIT_MATURITY_DATE = Math.round(Date.now()/1000) + (86400*2);
const ENTITY_NAME = "UbeSwap";
const ENTITY_URL = "https://ubeswap.com";
const MAX_SELLER_COUNT = 10;
const MAX_BUYER_COUNT = 10;


describe("SwapController", function() {
    let snapshotId;
    let [voterFeeRatio
        , voterFeeComplementaryRatio
        , recurringFeeRatio
        , recurringFeeComplementaryRatio
        , votersRequired
        , recurringPaymentInterval] = [1, 2, 1, 3, 7, 30*24*3600];
    let contract;
    let votingContract;
    let poolToken1, poolToken2;
    let acc0, acc1, acc2, acc3, acc4, acc5, acc6, acc7, acc8, acc9, acc10, acc11, acc12;

    before(async function() {

        [acc0, acc1, acc2, acc3, acc4, acc5, acc6, acc7, acc8, acc9, acc10, acc11, acc12] = await ethers.getSigners();
        contract = await (await (await ethers.getContractFactory("SwapController")).deploy(acc1.address
            , MAX_SELLER_COUNT.toString()
            , MAX_BUYER_COUNT.toString()
        )).deployed();
        oracle = await (await (await ethers.getContractFactory("RateOracle")).deploy(contract.address
            , acc1.address
            , voterFeeRatio
            , voterFeeComplementaryRatio
            , recurringFeeRatio
            , recurringFeeComplementaryRatio
            , votersRequired
            , recurringPaymentInterval)).deployed();
        votingContract = await (await (await ethers.getContractFactory("Voting")).deploy(acc1.address, contract.address, oracle.address)).deployed();
        poolToken1 = await (await (await ethers.getContractFactory("ERC20Mock")).deploy()).deployed();
        poolToken2 = await (await (await ethers.getContractFactory("ERC20Mock")).deploy()).deployed();

    })

    describe("Set Voting contract", function() {

        it("Should set the voting contract state to the assigned address", async () => {

            const tx = await contract.setVotingContract(votingContract.address);
            await tx.wait();

            expect(await contract.votingContract()).to.equal(votingContract.address);
        })
    })

    describe("Set Oracle contract", function() {

        it("Should set the oracle contract state to the assigned address", async () => {

            const tx = await contract.setOracleContract(oracle.address);
            await tx.wait();

            expect(await contract.oracleContract()).to.equal(oracle.address);
        })
    })

    describe("Create swap contract", function() {

        context("Happy path", function() {

            it("Should deploy instance of swap contract and set default state", async() => {

                const tx = await contract.createSwapContract(
                    ENTITY_NAME
                    , ENTITY_URL
                    , poolToken1.address
                    , (PREMIUM * 10000).toString()
                    , (MAKER_FEE * 10000).toString()
                    , INIT_MATURITY_DATE.toString()
                    , INIT_EPOCH.toString()
                )

                await tx.wait();

                const poolAddress = await contract.swapList(0);
                const poolContractDeployed = await ethers.getContractAt("CEXDefaultSwap", poolAddress);

                expect(await poolContractDeployed.entityName()).to.equal(ENTITY_NAME);
                expect(await poolContractDeployed.currency()).to.equal(poolToken1.address);
                expect(await poolContractDeployed.defaulted()).to.equal(false);

            })

        })

        context("Error cases", function() {

            it("Should fail if called by a non admin account", async () => {
                const superAdminRole = await contract.SUPER_ADMIN();
                const adminCtrlRole = await contract.ADMIN_CONTROLLER();
                const addrs = [acc0, acc1, acc2];
                let createSwapTx
                for (const acc of addrs) {
                    let isAdmin = await contract.hasRole(superAdminRole, acc.address) || await contract.hasRole(adminCtrlRole, acc.address);
                    if (!isAdmin) {

                        createSwapTx = contract.connect(acc).createSwapContract(
                            ENTITY_NAME
                            , ENTITY_URL
                            , poolToken1.address
                            , (PREMIUM * 10000).toString()
                            , (MAKER_FEE * 10000).toString()
                            , INIT_MATURITY_DATE.toString()
                            , INIT_EPOCH.toString()
                        )
                        break;

                    }

                }

                if(createSwapTx != undefined) expect(createSwapTx).to.be.revertedWith("Contract does not have any of the admin roles");
            })
        })
    })

    describe("createSwapContractAsThirdParty", function() {
        let voterAddresses;

        context("Happy path", function() {

            it("Should deploy instance of swap contract, set default state and grant pool owner role to owner", async() => {
                voterAddresses = [acc5, acc6, acc7, acc8, acc9, acc10, acc11].map(acc => acc.address);
                const tx = await contract.createSwapContractAsThirdParty(
                    ENTITY_NAME
                    , ENTITY_URL
                    , poolToken2.address
                    , (PREMIUM * 10000).toString()
                    , (MAKER_FEE * 10000).toString()
                    , INIT_MATURITY_DATE.toString()
                    , INIT_EPOCH.toString()
                    , acc3.address
                    , voterAddresses
                )

                await tx.wait();

                const poolAddress = await contract.swapList(1);
                const poolContractDeployed = await ethers.getContractAt("CEXDefaultSwap", poolAddress);

                expect(await poolContractDeployed.entityName()).to.equal(ENTITY_NAME);
                expect(await poolContractDeployed.currency()).to.equal(poolToken2.address);
                expect(await poolContractDeployed.defaulted()).to.equal(false);
                expect(await contract.hasRole(await contract.getPoolOwnerRole(poolAddress), acc3.address)).to.be.true;

                const votersOnPool = await votingContract.getVoterList(poolAddress)

                const votersMatch = () => voterAddresses.filter(voter => !votersOnPool.includes(voter)).length === 0 && votersOnPool.length === voterAddresses.length
                
                expect(votersMatch()).to.be.true;

            })

        })

        context("Error cases", function() {

            it("Should fail if called by a non admin account", async () => {
                const superAdminRole = await contract.SUPER_ADMIN();
                const adminCtrlRole = await contract.ADMIN_CONTROLLER();
                const addrs = [acc0, acc1, acc2];
                let createSwapTx
                for (const acc of addrs) {
                    let isAdmin = await contract.hasRole(superAdminRole, acc.address) || await contract.hasRole(adminCtrlRole, acc.address);
                    if (!isAdmin) {

                        createSwapTx = contract.connect(acc).createSwapContractAsThirdParty(
                            ENTITY_NAME
                            , ENTITY_URL
                            , poolToken2.address
                            , (PREMIUM * 10000).toString()
                            , (MAKER_FEE * 10000).toString()
                            , INIT_MATURITY_DATE.toString()
                            , INIT_EPOCH.toString()
                            , acc3.address
                            , voterAddresses
                        )
                        break;

                    }

                }

                if(createSwapTx != undefined) expect(createSwapTx).to.be.revertedWith("Contract does not have any of the admin roles");
            })
        })
    })

    describe("setPoolPaused", function() {
        let newSwap;
        before(async() => {
            const voterAddresses = [acc5, acc6, acc7, acc8, acc9, acc10, acc11].map(acc => acc.address);
            await (await contract.createSwapContractAsThirdParty(
                ENTITY_NAME
                , ENTITY_URL
                , poolToken2.address
                , (PREMIUM * 10000).toString()
                , (MAKER_FEE * 10000).toString()
                , INIT_MATURITY_DATE.toString()
                , INIT_EPOCH.toString()
                , acc3.address
                , voterAddresses
            )).wait();

            const updatedSwaps = await contract.getSwapList();
            newSwap = updatedSwaps[updatedSwaps.length - 1];
        })

        context("Happy path", function() {

            it("Should emit PoolPaused event", async () => {
                snapshotId = await network.provider.send('evm_snapshot');
                const pauseTx = contract.setPoolPaused(newSwap);

                await expect(pauseTx).to.emit("PoolPaused").withArgs(newSwap, acc0.address);
                
            })

            it("Should set a particular pool state to paused", async () => {
                const swapContract = await ethers.getContractAt("CEXDefaultSwap", newSwap);

                const isPaused = await swapContract.isPaused();
                expect(isPaused).to.be.true;
                await network.provider.send('evm_revert', [snapshotId]);
            })

            it("Should allow a call by the pool owner", async () => {
                const pauseTx = contract.connect(acc3).setPoolPaused(newSwap);
                await expect(pauseTx).to.emit("PoolPaused").withArgs(newSwap, acc3.address);

            })
        })

        context("Edge cases", async() => {

            it("Should not allow a call from a non-admin address that is not the pool owner", async() => {

                const pauseTx = contract.connect(acc4).setPoolPaused(newSwap);
                await expect(pauseTx).to.be.revertedWith("Unauthorized");
            })
        })
    })

    describe("setPoolUnpaused", function() {

        let newSwap;
        before(async() => {
            voterAddresses = [acc5, acc6, acc7, acc8, acc9, acc10, acc11].map(acc => acc.address);
            await (await contract.createSwapContractAsThirdParty(
                ENTITY_NAME
                , ENTITY_URL
                , poolToken2.address
                , (PREMIUM * 10000).toString()
                , (MAKER_FEE * 10000).toString()
                , INIT_MATURITY_DATE.toString()
                , INIT_EPOCH.toString()
                , acc3.address
                , voterAddresses
            )).wait();

            const updatedSwaps = await contract.getSwapList();
            newSwap = updatedSwaps[updatedSwaps.length - 1];

            await (await contract.setPoolPaused(newSwap)).wait();
        })

        context("Happy path", function() {

            it("Should emit PoolUnpaused event", async() => {

                snapshotId = await network.provider.send('evm_snapshot');
                const unpauseTx = contract.setPoolUnpaused(newSwap);

                await expect(unpauseTx).to.emit("PoolUnaused").withArgs(newSwap, acc0.address);
                
            })

            it("Should set a particular pool state to unpaused", async () => {
                const swapContract = await ethers.getContractAt("CEXDefaultSwap", newSwap);

                const isPaused = await swapContract.isPaused();
                expect(isPaused).to.be.false;
                await network.provider.send('evm_revert', [snapshotId]);
            })

            it("Should allow a call by the pool owner", async () => {
                const unpauseTx = contract.connect(acc3).setPoolUnpaused(newSwap);
                await expect(unpauseTx).to.emit("PoolUnpaused").withArgs(newSwap, acc3.address);

            })

        })

        context("Edge cases", async() => {

            it("Should not allow a call from a non-admin address that is not the pool owner", async() => {

                const unpauseTx = contract.connect(acc4).setPoolUnpaused(newSwap);
                await expect(unpauseTx).to.be.revertedWith("Unauthorized");
            })
        })
    })

})