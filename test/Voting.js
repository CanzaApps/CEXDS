const {
    time,
    loadFixture,
} = require("@nomicfoundation/hardhat-network-helpers");
// const { anyValue } = require("@nomicfoundation/hardhat-chai-matchers/withArgs");
const { expect } = require("chai");
const BigNumber = require("bignumber.js");
const { ethers, assert, network } = require("hardhat");
const fs = require('fs');

const PREMIUM = 0.1; // Fractional premium
const INIT_EPOCH = 2;
const INIT_MATURITY_DATE = Math.round(Date.now()/1000) + 86400;
const ownedEntityName = "UbeSwap";
const thirdPartyEntityName = "SwapUber"

const ZERO_ADDRESS = "0x0000000000000000000000000000000000000000"

describe("Voting", function() {

    let [voterFeeRatio
    , voterFeeComplementaryRatio
    , recurringFeeRatio
    , recurringFeeComplementaryRatio
    , votersRequired
    , recurringPaymentInterval] = [1, 2, 1, 3, 7, 30*24*3600];
    let acc0, acc1, acc2, acc3, acc4, acc5, acc6, acc7, acc8, acc9, acc10, acc11, acc12, acc13, acc14, acc15, acc16, acc17, acc18;
    let ownedPoolAddress;
    let thirdPartyPoolAddress;
    let poolToken;
    let controller;
    let snapshotId;
    let contract;
    let oracle;

    before(async function() {

        [acc0, acc1, acc2, acc3, acc4, acc5, acc6, acc7, acc8, acc9, acc10, acc11, acc12, acc13, acc14, acc15, acc16, acc17, acc18] = await ethers.getSigners();
        controller = await (await (await ethers.getContractFactory("SwapController")).deploy(acc1.address)).deployed();
        oracle = await (await (await ethers.getContractFactory("RateOracle")).deploy(controller.address
            , acc1.address
            , voterFeeRatio
            , voterFeeComplementaryRatio
            , recurringFeeRatio
            , recurringFeeComplementaryRatio
            , votersRequired
            , recurringPaymentInterval)).deployed();
        contract = await (await (await ethers.getContractFactory("Voting")).deploy(acc1.address, controller.address, oracle.address)).deployed();
        poolToken = await (await (await ethers.getContractFactory("ERC20Mock")).deploy()).deployed();

        let tx = await controller.setVotingContract(contract.address);
        await tx.wait();

        tx = await controller.setOracleContract(oracle.address);
        await tx.wait();

        tx = await controller.createSwapContract(
            ownedEntityName
            , poolToken.address
            , (PREMIUM * 10000).toString()
            , INIT_MATURITY_DATE.toString()
            , INIT_EPOCH.toString()
        )

        await tx.wait();

        ownedPoolAddress = await controller.swapList(0);

        snapshotId = await network.provider.send('evm_snapshot');

    })

    describe("Whitelist Voters", function() {
        let voterAccs;

        beforeEach(function() {
            voterAccs = [acc2, acc3, acc4, acc5, acc6, acc7, acc9];
        })
        context("Happy path", function() {

            it("Should grant voter roles to all universal whitelisted voters and update voter list", async() => {

                const voterAddresses = voterAccs.map(acc => acc.address);

                const tx = await contract.whiteListVoters(voterAddresses);
                await tx.wait();

                const voterRole = await contract.VOTER_ROLE();

                expect((await contract.getVoterList(ownedPoolAddress)).length).to.equal(voterAddresses.length);
                voterAddresses.forEach(async add => {
                    expect(await contract.hasRole(voterRole, add)).to.equal(true);
                })
                snapshotId = await network.provider.send('evm_snapshot');
            })
        })

        context("Fail cases", function() {

            it("Should revert if called by non-admin", async () => {
                const adminRole = await contract.SUPER_ADMIN();

                let whitelistTx;
                let caller;
                
                for (const addr of voterAccs) {
                    if (!(await contract.hasRole(adminRole, addr.address))) {
                        whitelistTx = contract.connect(addr).whiteListVoters([acc4.address])
                        caller = addr;
                        break;
                    }
                }

                expect(whitelistTx).to.be.revertedWith("AccessControl: account " +
                caller.address +
                " is missing role " +
                adminRole)
            })

            it("Should not add an account which is already an existing voter", async () => {

                const whitelistTx = contract.whiteListVoters([acc3.address]);

                expect(whitelistTx).to.be.revertedWith("Already a voter");
            })

            it("Should revert if number of voters are already up to expected number", async() => {

                const votersExpected = await oracle.getNumberOfVotersRequired(ownedPoolAddress);
                let voterCount = 0;

                
                voterCount = (await contract.getVoterList(ownedPoolAddress)).length;
                // First ensure voter list is full
                if (voterCount < votersExpected)  {
                    const accsToAdd = voterAccs.slice(2 + voterCount, votersExpected + 2).map(acc => acc.address);

                    const tx = await contract.whiteListVoters(accsToAdd);
                    await tx.wait();
                }

                const expectedToFailTx = contract.whiteListVoters([acc10.address]);

                expect(expectedToFailTx).to.be.revertedWith("Voters added exceed allowable number of voters");
            })
        })
    })

    describe("Set Pool Voters", function() {
        let voterAccs;
        let expectedThirdPartyVoters;

        beforeEach(function() {
            voterAccs = [acc2, acc3, acc4, acc5, acc6, acc7, acc9];
            expectedThirdPartyVoters = [acc12, acc13, acc14, acc15, acc16, acc17, acc18].map(acc => acc.address);
        })
        context("Happy path", function() {

            it("Should retain voters specified on 3rd party pools, without voter role, and not use the universal whitelisted", async() => {
                
                const tx = await controller.createSwapContractAsThirdParty(
                    thirdPartyEntityName
                    , poolToken.address
                    , (PREMIUM * 10000).toString()
                    , INIT_MATURITY_DATE.toString()
                    , INIT_EPOCH.toString()
                    , acc11.address
                    , expectedThirdPartyVoters.slice(0, -1)
                )
        
                await tx.wait();

                const swaps = await controller.getSwapList();

                thirdPartyPoolAddress = swaps[swaps.length - 1];

                const voterRole = await contract.VOTER_ROLE();

                const votersOnThirdPartyPool = await contract.getVoterList(thirdPartyPoolAddress);

                expect(votersOnThirdPartyPool.length).to.equal(expectedThirdPartyVoters.slice(0, -1).length);
                votersOnThirdPartyPool.forEach(async add => {
                    expect(await contract.hasRole(voterRole, add)).to.equal(false);
                    expect(expectedThirdPartyVoters.includes(add)).to.be.true;
                })
                snapshotId = await network.provider.send('evm_snapshot');
            })
        })

        context("Fail cases", function() {

            it("Should not add an account which is already an existing voter", async () => {
                const [add] = expectedThirdPartyVoters.slice(0, 1)
                const whitelistTx = contract.connect(acc11).setVotersForPool([add], thirdPartyPoolAddress);

                expect(whitelistTx).to.be.revertedWith(`Address ${add} already has voting privileges for pool ${thirdPartyPoolAddress}`);
            })

            it("Should revert if number of voters are already up to expected number", async() => {

                const votersExpected = await oracle.getNumberOfVotersRequired(thirdPartyPoolAddress);
                let voterCount = 0;

                
                voterCount = (await contract.getVoterList(thirdPartyPoolAddress)).length;
                // First ensure voter list is full
                if (voterCount < votersExpected)  {
                    const accsToAdd = expectedThirdPartyVoters.slice(voterCount);

                    const tx = await contract.setVotersForPool(accsToAdd, thirdPartyPoolAddress);
                    await tx.wait();
                }

                const expectedToFailTx = contract.connect(acc11).setVotersForPool(expectedThirdPartyVoters.slice(-1), thirdPartyPoolAddress);

                expect(expectedToFailTx).to.be.revertedWith("Voters added exceed allowable number of voters");
            })
        })
    })


    describe("Replace voter", function() {
        let voterAccs;

        beforeEach(function() {
            voterAccs = [acc2, acc3, acc4, acc5, acc6, acc7, acc9];
        })

        context("Happy path", function() {

            it("Should revoke old voter role and grant role to replacement", async() => {

                const voterRole = await contract.VOTER_ROLE();
                const previousAcc9Role = await contract.hasRole(voterRole, acc9.address);
                const previousAcc8Role = await contract.hasRole(voterRole, acc8.address);
                const voterList = await contract.getVoterList(ownedPoolAddress);
                console.log({previousAcc9Role, previousAcc8Role, voterList, acc9: acc9.address})
                //acc9 already a voter. Replace with acc8
                const tx = await contract.replaceVoter(acc9.address, acc8.address);
                await tx.wait();


                const finalAcc9Role = await contract.hasRole(voterRole, acc9.address);
                const finalAcc8Role = await contract.hasRole(voterRole, acc8.address);

                expect(finalAcc8Role).to.be.true;
                expect(finalAcc9Role).to.be.false;
                expect(finalAcc8Role && previousAcc8Role).to.be.false;
                expect(finalAcc9Role && previousAcc9Role).to.be.false;
                snapshotId = await network.provider.send('evm_snapshot');
            })

            it("Should replace old voter on third party pool and add new one without granting voter role", async () => {

                const voterRole = await contract.VOTER_ROLE();

                const previousIsAcc10Voter = await contract.isPoolVoter(thirdPartyPoolAddress, acc10.address);
                const previousIsAcc18Voter = await contract.isPoolVoter(thirdPartyPoolAddress, acc18.address);

                const tx = await contract.replaceVoterOnPool(acc18.address, acc10.address, thirdPartyPoolAddress);
                await tx.wait();

                const finalIsAcc10Voter = await contract.isPoolVoter(thirdPartyPoolAddress, acc10.address);
                const finalIsAcc18Voter = await contract.isPoolVoter(thirdPartyPoolAddress, acc18.address);

                expect(finalIsAcc10Voter).to.be.true;
                expect(finalIsAcc18Voter).to.be.false;
                expect(finalIsAcc10Voter && previousIsAcc10Voter).to.be.false;
                expect(finalIsAcc18Voter && previousIsAcc18Voter).to.be.false;
                expect(await contract.hasRole(voterRole, acc10.address)).to.be.false;

                await network.provider.send('evm_revert', [snapshotId]);
            })

            it("Should emit RemoveVoter and AddVoter events", async () => {

                const replaceTx = contract.replaceVoter(acc8.address, acc9.address);

                await expect(replaceTx).to.emit(contract, "RemoveVoter").withArgs(acc8.address);
                await expect(replaceTx).to.emit(contract, "AddVoter").withArgs(acc9.address);
            })
        })

        context("Fail cases", function() {

            it("Should revert if called by non-admin", async () => {
                const adminRole = await contract.SUPER_ADMIN();

                let whitelistTx;
                let caller;
                
                for (const addr of voterAccs) {
                    if (!(await contract.hasRole(adminRole, addr.address))) {
                        whitelistTx = contract.connect(addr).whiteListVoters([acc4.address])
                        caller = addr;
                        break;
                    }
                }

                expect(whitelistTx).to.be.revertedWith("AccessControl: account ",
                caller.address,
                " is missing role ",
                adminRole)
            })

            it("Should revert if trying to replace a voter that did not was not one previously", async () => {

                const thirdPartyReplaceTx = contract.replaceVoterOnPool(acc3.address, acc10.address, thirdPartyPoolAddress);

                const ownedReplaceTx = contract.replaceVoter(acc18.address, acc10.address);

                expect(thirdPartyReplaceTx).to.be.revertedWith("Address being removed is not a voter");
                expect(ownedReplaceTx).to.be.revertedWith("Address being removed is not a voter");
            })
        })
    })

    describe("vote", function() {
        let voterAccs;
        let poolContract;
        let voterTokenBalances = [];

        before(async () => {
            voterAccs = [acc2, acc3, acc4, acc5, acc6, acc7, acc9];

            await network.provider.send('evm_revert', [snapshotId]);

            await poolToken.mint(acc9.address, ethers.utils.parseEther('100'));
            await poolToken.mint(acc10.address, ethers.utils.parseEther('100'));

            await poolToken.connect(acc9).approve(ownedPoolAddress, ethers.utils.parseEther('50'));
            await poolToken.connect(acc10).approve(ownedPoolAddress, ethers.utils.parseEther('50'));

            poolContract = await ethers.getContractAt("CEXDefaultSwap", ownedPoolAddress);
            await poolContract.connect(acc9).deposit(ethers.utils.parseEther('50'));
            await poolContract.connect(acc10).purchase(ethers.utils.parseEther('20'));
        })
        context("Happy path", function() {

            it("Should allow user vote, update vote data and emit vote event", async () => {
                await network.provider.send('evm_revert', [snapshotId]);

                const tx = contract.connect(acc2).vote(ownedPoolAddress, true);
                voterTokenBalances.push((await poolToken.balanceOf(acc2.address)).toString());
                // await tx.wait();

                await expect(tx).to.emit(contract, "Vote").withArgs(ownedPoolAddress, acc2.address, true, 1);

                const vote = await contract.poolVotes(ownedPoolAddress, 0)
                expect(vote.voter).to.equal(acc2.address);
                expect(vote.choice).to.equal(true);
                expect(await contract.voterHasVoted(ownedPoolAddress, acc2.address)).to.equal(true);
                expect(await contract.trueVoteCount(ownedPoolAddress)).to.equal(1);
                expect(await contract.votingState(ownedPoolAddress)).to.equal(false);

            }) 

            it("Should set voting state to true and pause pool contract upon second vote", async () => {
                const poolContract = await ethers.getContractAt("CEXDefaultSwap", ownedPoolAddress)
                const poolPreviouslyPaused = await poolContract.isPaused();
                const tx = await contract.connect(acc3).vote(ownedPoolAddress, true);
                voterTokenBalances.push((await poolToken.balanceOf(acc3.address)).toString());

                await tx.wait();
                const vote = await contract.poolVotes(ownedPoolAddress, 1)
                
                expect(vote.voter).to.equal(acc3.address);
                expect(vote.choice).to.equal(true);
                expect(await contract.votingState(ownedPoolAddress)).to.equal(true);
                expect(await poolContract.isPaused()).to.be.true;
                expect((await poolContract.isPaused()) && poolPreviouslyPaused).to.be.false;
            })

            it("Should execute the final vote and pay all fees to the voters in rational majority and set defaulted if rational majority voted true", async () => {
                const voterFeePaid = await poolContract.totalVoterFeePaid();
                const votersExpected = await oracle.getNumberOfVotersRequired(ownedPoolAddress);
                const prevContractTokenBalance = (await poolToken.balanceOf(contract.address)).toString();

                let voterChoices = [true, true]; //previous 2 truth votes

                const voterList = await contract.getVoterList(ownedPoolAddress);
                console.log({voterList})

                for (const acc of voterAccs.slice(2)) {
                    const k = (await poolToken.balanceOf(acc.address)).toString();
                    voterTokenBalances.push(k);
                    
                    const choice = Math.round(Math.random());
                    voterChoices.push(choice ? true : false);
                    console.log({acc: acc.address})
                    const tx = await contract.connect(acc).vote(ownedPoolAddress, choice ? true : false);
                    
                    await tx.wait();
                }

                const trueCounts = voterChoices.reduce((acc, curr) => acc + curr, 0);
                const expectedFeeForEachVoter = +voterFeePaid.toString()/Math.max(trueCounts, votersExpected - trueCounts);

                
                for (const acc of voterAccs) {

                    accIndex = voterAccs.indexOf(acc);
                    tokenBalance = (await poolToken.balanceOf(acc.address)).toString();

                    const checker = (trueCounts > votersExpected - trueCounts) === voterChoices[accIndex];

                    if (checker) {
                        expect((+tokenBalance) - (+voterTokenBalances[accIndex])).to.equal(expectedFeeForEachVoter);
                    } else {
                        expect(+tokenBalance - (+voterTokenBalances[accIndex])).to.equal(0);
                    }

                }
                // Confirm contract token balance
                if (trueCounts > votersExpected/2) expect(await poolContract.defaulted()).to.be.true;
                else expect(await poolContract.defaulted()).to.be.false;
                expect(+prevContractTokenBalance - (+(await poolToken.balanceOf(contract.address)).toString())).to.equal(+voterFeePaid.toString())
                
            })

            it("Should have reset all mapping and state objects after 7th vote if pool did not default", async() => {
                const poolDefaulted = await poolContract.defaulted();
                if (!poolDefaulted) {
                    voterAccs.forEach(async acc => {
                        expect(await contract.voterHasVoted(ownedPoolAddress, acc.address)).to.be.false;
                    })
                    expect(await contract.votingState(ownedPoolAddress)).to.be.false;
                    await expect(contract.poolVotes(ownedPoolAddress, 0)).to.be.reverted;
                    expect(await contract.trueVoteCount(ownedPoolAddress)).to.equal(0);
                }
                
                
            })

            it("Should allow a voter vote again if a next cycle is initiated on the pool", async () => {
                const poolDefaulted = await poolContract.defaulted();
                if (poolDefaulted) {
                    let resetPoolTx = await controller.resetPoolAfterDefault(ownedPoolAddress, (Math.round(Date.now()/1000) + 86400).toString());

                    await resetPoolTx.wait();

                    await poolToken.connect(acc9).approve(ownedPoolAddress, ethers.utils.parseEther('50'));
                    await poolToken.connect(acc10).approve(ownedPoolAddress, ethers.utils.parseEther('50'));

                    await poolContract.connect(acc9).deposit(ethers.utils.parseEther('20'));
                    await poolContract.connect(acc10).purchase(ethers.utils.parseEther('15'));

                    //this is done to ensure pool must default, which is required before resetting.
                    for (const acc of voterAccs) {

                        const tx = await contract.connect(acc).vote(ownedPoolAddress, true);
                        await tx.wait();
                    }

                    resetPoolTx = await controller.resetPoolAfterDefault(ownedPoolAddress, (Math.round(Date.now()/1000) + 86400).toString());

                    await resetPoolTx.wait();

                    await poolContract.connect(acc9).deposit(ethers.utils.parseEther('20'));
                    await poolContract.connect(acc10).purchase(ethers.utils.parseEther('15'));

                    const voteTx = contract.connect(acc3).vote(ownedPoolAddress, true);
                    expect(voteTx).to.emit(contract, "Vote").withArgs(ownedPoolAddress, acc3.address, true, 1);
                    await voteTx;

                    const vote = await contract.poolVotes(ownedPoolAddress, 0)

                    expect(vote.voter).to.equal(acc3.address);
                    expect(vote.choice).to.equal(true);
                    expect(await contract.voterHasVoted(ownedPoolAddress, acc3.address)).to.equal(true);
                    expect(await contract.trueVoteCount(ownedPoolAddress)).to.equal(1);
                    expect(await contract.votingState(ownedPoolAddress)).to.equal(false);
                }
                

            })

        })
        
        context("Edge cases", function() {

            it("Should not allow voting twice in same cycle", async () => {
                // reset back to state after voter whitelist
                await network.provider.send('evm_revert', [snapshotId]);

                await poolToken.mint(acc9.address, ethers.utils.parseEther('100'));
                await poolToken.mint(acc10.address, ethers.utils.parseEther('100'));

                await poolToken.connect(acc9).approve(ownedPoolAddress, ethers.utils.parseEther('50'));
                await poolToken.connect(acc10).approve(ownedPoolAddress, ethers.utils.parseEther('50'));

                const poolContract = await ethers.getContractAt("CEXDefaultSwap", ownedPoolAddress);

                await poolContract.connect(acc9).deposit(ethers.utils.parseEther('20'));
                await poolContract.connect(acc10).purchase(ethers.utils.parseEther('15'));

                const firstVoteTx = contract.connect(acc5).vote(ownedPoolAddress, true);

                await firstVoteTx;

                const secondVoteTx = contract.connect(acc5).vote(ownedPoolAddress, true);

                expect(secondVoteTx).to.be.revertedWith("Already voted in the current cycle");

            })

            it("Should revert if called by account without voter role", async () => {
                const voterRole = await contract.VOTER_ROLE();
                const voteTx = contract.connect(acc0).vote(ownedPoolAddress, true);

                expect(voteTx).to.be.revertedWith("AccessControl: account " +
                acc0 +
                " is missing role " +
                voterRole)
            })
        })
        
    })
})