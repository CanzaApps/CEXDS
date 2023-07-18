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
const ENTITY_NAME = "UbeSwap";


describe("Voting", function() {

    let acc0, acc1, acc2, acc3, acc4, acc5, acc6, acc7, acc8, acc9, acc10;
    let poolAddress;
    let poolToken;
    let controller;
    let snapshotId;
    let contract;

    before(async function() {

        [acc0, acc1, acc2, acc3, acc4, acc5, acc6, acc7, acc8, acc9, acc10] = await ethers.getSigners();
        controller = await (await (await ethers.getContractFactory("SwapController")).deploy(acc1.address)).deployed();
        contract = await (await (await ethers.getContractFactory("Voting")).deploy(acc1.address, controller.address)).deployed();
        poolToken = await (await (await ethers.getContractFactory("ERC20Mock")).deploy()).deployed();

        let tx = await controller.setVotingContract(contract.address);
        await tx.wait();

        tx = await controller.createSwapContract(
            ENTITY_NAME
            , poolToken.address
            , (PREMIUM * 10000).toString()
            , INIT_MATURITY_DATE.toString()
            , INIT_EPOCH.toString()
        )

        await tx.wait();

        poolAddress = await controller.swapList(0);
        snapshotId = await network.provider.send('evm_snapshot');

    })

    describe("Whitelist Voters", function() {
        let voterAccs;

        beforeEach(function() {
            voterAccs = [acc2, acc3, acc4, acc5, acc6, acc7, acc9];
        })
        context("Happy path", function() {

            it("Should grant voter roles to all whitelisted voters and update voter list", async() => {

                const voterAddresses = voterAccs.map(acc => acc.address);

                const tx = await contract.whiteListVoters(voterAddresses);
                await tx.wait();

                const voterRole = await contract.VOTER_ROLE();

                expect((await contract.getVoterList()).length).to.equal(voterAddresses.length);
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

                const votersExpected = await contract.NUMBER_OF_VOTERS_EXPECTED();
                let voterCount = 0;

                
                voterCount = (await contract.getVoterList()).length;
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

            it("Should not add an account which is already an existing voter", async () => {

                const whitelistTx = contract.whiteListVoters([acc3.address]);

                expect(whitelistTx).to.be.revertedWith("Already a voter");
            })

            it("Should revert if number of voters are already up to expected number", async() => {

                const votersExpected = await contract.NUMBER_OF_VOTERS_EXPECTED();
                let voterCount = 0;

                
                voterCount = (await contract.getVoterList()).length;
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

    describe("vote", function() {
        let voterAccs;
        let poolContract;
        let voterTokenBalances = [];

        before(async () => {
            voterAccs = [acc2, acc3, acc4, acc5, acc6, acc7, acc8];

            await network.provider.send('evm_revert', [snapshotId]);

            await poolToken.mint(acc9.address, ethers.utils.parseEther('100'));
            await poolToken.mint(acc10.address, ethers.utils.parseEther('100'));

            await poolToken.connect(acc9).approve(poolAddress, ethers.utils.parseEther('50'));
            await poolToken.connect(acc10).approve(poolAddress, ethers.utils.parseEther('50'));

            poolContract = await ethers.getContractAt("CEXDefaultSwap", poolAddress);
            await poolContract.connect(acc9).deposit(ethers.utils.parseEther('50'));
            await poolContract.connect(acc10).purchase(ethers.utils.parseEther('20'));
        })
        context("Happy path", function() {

            it("Should allow user vote, update vote data and emit vote event", async () => {
                await network.provider.send('evm_revert', [snapshotId]);

                const tx = contract.connect(acc2).vote(poolAddress, true);
                voterTokenBalances.push((await poolToken.balanceOf(acc2.address)).toString());
                // await tx.wait();

                await expect(tx).to.emit(contract, "Vote").withArgs(poolAddress, acc2.address, true, 1);

                const vote = await contract.poolVotes(poolAddress, 0)
                expect(vote.voter).to.equal(acc2.address);
                expect(vote.choice).to.equal(true);
                expect(await contract.voterHasVoted(poolAddress, acc2.address)).to.equal(true);
                expect(await contract.trueVoteCount(poolAddress)).to.equal(1);
                expect(await contract.votingState(poolAddress)).to.equal(false);

            }) 

            it("Should set voting state to true and pause pool contract upon second vote", async () => {
                const poolContract = await ethers.getContractAt("CEXDefaultSwap", poolAddress)
                const poolPreviouslyPaused = await poolContract.isPaused();
                const tx = await contract.connect(acc3).vote(poolAddress, true);
                voterTokenBalances.push((await poolToken.balanceOf(acc3.address)).toString());

                await tx.wait();
                const vote = await contract.poolVotes(poolAddress, 1)
                
                expect(vote.voter).to.equal(acc3.address);
                expect(vote.choice).to.equal(true);
                expect(await contract.votingState(poolAddress)).to.equal(true);
                expect(await poolContract.isPaused()).to.be.true;
                expect((await poolContract.isPaused()) && poolPreviouslyPaused).to.be.false;
            })

            it("Should execute the final vote and pay all fees to the voters in rational majority and set defaulted if rational majority voted true", async () => {
                const voterFeePaid = await poolContract.totalVoterFeePaid();
                const votersExpected = await contract.NUMBER_OF_VOTERS_EXPECTED();
                const prevContractTokenBalance = (await poolToken.balanceOf(contract.address)).toString();

                let voterChoices = [true, true]; //previous 2 truth votes

                for (const acc of voterAccs.slice(2)) {
                    const k = (await poolToken.balanceOf(acc2.address)).toString();
                    voterTokenBalances.push(k);
                    
                    const choice = Math.round(Math.random());
                    voterChoices.push(choice ? true : false);
                    const tx = await contract.connect(acc).vote(poolAddress, choice ? true : false);

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

            it("Should have reset all mapping and state objects after 7th vote", async() => {
                voterAccs.forEach(async acc => {
                    expect(await contract.voterHasVoted(poolAddress, acc.address)).to.be.false;
                })
                expect(await contract.votingState(poolAddress)).to.be.false;
                await expect(contract.poolVotes(poolAddress, 0)).to.be.reverted;
                expect(await contract.trueVoteCount(poolAddress)).to.equal(0);
                
            })

            it("Should allow a voter vote again if a next cycle is initiated on the pool", async () => {
                let resetPoolTx = await controller.resetPoolAfterDefault(poolAddress, (Math.round(Date.now()/1000) + 86400).toString());

                await resetPoolTx.wait();

                await poolToken.connect(acc9).approve(poolAddress, ethers.utils.parseEther('50'));
                await poolToken.connect(acc10).approve(poolAddress, ethers.utils.parseEther('50'));

                await poolContract.connect(acc9).deposit(ethers.utils.parseEther('20'));
                await poolContract.connect(acc10).purchase(ethers.utils.parseEther('15'));

                //this is done to ensure pool must default, which is required before resetting.
                for (const acc of voterAccs) {

                    const tx = await contract.connect(acc).vote(poolAddress, true);
                    await tx.wait();
                }

                resetPoolTx = await controller.resetPoolAfterDefault(poolAddress, (Math.round(Date.now()/1000) + 86400).toString());

                await resetPoolTx.wait();

                await poolContract.connect(acc9).deposit(ethers.utils.parseEther('20'));
                await poolContract.connect(acc10).purchase(ethers.utils.parseEther('15'));

                const voteTx = contract.connect(acc3).vote(poolAddress, true);
                expect(voteTx).to.emit(contract, "Vote").withArgs(poolAddress, acc3.address, true, 1);
                await voteTx;

                const vote = await contract.poolVotes(poolAddress, 0)

                expect(vote.voter).to.equal(acc3.address);
                expect(vote.choice).to.equal(true);
                expect(await contract.voterHasVoted(poolAddress, acc3.address)).to.equal(true);
                expect(await contract.trueVoteCount(poolAddress)).to.equal(1);
                expect(await contract.votingState(poolAddress)).to.equal(false);

            })

        })
        
        context("Edge cases", function() {

            it("Should not allow voting twice in same cycle", async () => {
                // reset back to state after voter whitelist
                await network.provider.send('evm_revert', [snapshotId]);

                await poolToken.mint(acc9.address, ethers.utils.parseEther('100'));
                await poolToken.mint(acc10.address, ethers.utils.parseEther('100'));

                await poolToken.connect(acc9).approve(poolAddress, ethers.utils.parseEther('50'));
                await poolToken.connect(acc10).approve(poolAddress, ethers.utils.parseEther('50'));

                const poolContract = await ethers.getContractAt("CEXDefaultSwap", poolAddress);

                await poolContract.connect(acc9).deposit(ethers.utils.parseEther('20'));
                await poolContract.connect(acc10).purchase(ethers.utils.parseEther('15'));

                const firstVoteTx = contract.connect(acc5).vote(poolAddress, true);

                await firstVoteTx;

                const secondVoteTx = contract.connect(acc5).vote(poolAddress, true);

                expect(secondVoteTx).to.be.revertedWith("Already voted in the current cycle");

            })

            it("Should revert if called by account without voter role", async () => {
                const voterRole = await contract.VOTER_ROLE();
                const voteTx = contract.connect(acc0).vote(poolAddress, true);

                expect(voteTx).to.be.revertedWith("AccessControl: account " +
                acc0 +
                " is missing role " +
                voterRole)
            })
        })
        
    })
})