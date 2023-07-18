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

    let contract;
    let poolToken1, poolToken2;
    let acc0, acc1, acc2;

    before(async function() {

        [acc0, acc1, acc2] = await ethers.getSigners();
        contract = await (await (await ethers.getContractFactory("SwapController")).deploy(acc1.address)).deployed();
        poolToken1 = await (await (await ethers.getContractFactory("ERC20Mock")).deploy()).deployed();

    })

    describe("Set Voting contract", function() {

        it("Should set the voting contract state to the assigned address", async () => {

            let votingContract = await (await (await ethers.getContractFactory("Voting")).deploy(acc1.address, contract.address)).deployed();
            const tx = await contract.setVotingContract(votingContract.address);
            await tx.wait();

            expect(await contract.votingContract()).to.equal(votingContract.address);
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

})