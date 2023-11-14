const {
    time,
    loadFixture,
} = require("@nomicfoundation/hardhat-network-helpers");
// const { anyValue } = require("@nomicfoundation/hardhat-chai-matchers/withArgs");
const { expect } = require("chai");
const BigNumber = require("bignumber.js");
const { ethers, assert } = require("hardhat");

const PREMIUM = 0.1; // Fractional premium
const INIT_EPOCH = 2;
const INIT_MATURITY_DATE = Math.round(Date.now()/1000) + 86400;
const ENTITY_NAME = "UbeSwap";



describe("SwapController", function() {

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
        contract = await (await (await ethers.getContractFactory("SwapController")).deploy(acc1.address)).deployed();
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
                    , poolToken1.address
                    , (PREMIUM * 10000).toString()
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
                            , poolToken1.address
                            , (PREMIUM * 10000).toString()
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
                    , poolToken2.address
                    , (PREMIUM * 10000).toString()
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
                            , poolToken2.address
                            , (PREMIUM * 10000).toString()
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

})