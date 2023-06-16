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


console.log("help")
let acc0;
let acc1;
let acc2;
let acc3;

contract("CEXDefaultSwap", async () => {

    // const poolToken = await (await (await ethers.getContractFactory("ERC20Mock")).deploy()).deployed();

    let swapContract;
    let poolToken;
    
    
    describe("Constructor", async () => {
        

        context("Happy path", () => {
            

            it("Should deploy and set global variables", async function() {
                [acc0, acc1, acc2, acc3] = await ethers.getSigners();
                poolToken = await (await (await ethers.getContractFactory("ERC20Mock")).deploy()).deployed();
                

                swapContract = await (await (await ethers.getContractFactory("CEXDefaultSwap")).deploy(
                    
                    ENTITY_NAME,
                    poolToken.address,
                    (PREMIUM * 10000).toString(),
                    (INIT_MATURITY_DATE).toString(),
                    (INIT_EPOCH).toString()
                )).deployed();

                const entity = await swapContract.entityName();
                const token = (await swapContract.currency());
                const maturityDate = (await swapContract.maturityDate()).toString()
                const epochDays = (await swapContract.epochDays()).toString()
                const premium = (await swapContract.premium()).toString()
                console.log(maturityDate)

                assert(entity == ENTITY_NAME, "Entity Name Mismatch")
                assert(token == poolToken.address, "Pool Currency Mismatch")
                assert(maturityDate == INIT_MATURITY_DATE.toString(), "Maturity Date Mismatch")
                assert(epochDays == INIT_EPOCH.toString(), "Epoch Days Mismatch")
                assert(premium == (PREMIUM * 10000).toString(), "Premium Value Mismatch")

                expect(entity).to.equal(ENTITY_NAME);
            })
        })

        context("Edge cases", async () => {
            it("Should fail deployment if maturity date is below current timestamp", () => {
                currentTime = Math.round(Date.now()/1000)
                setTimeout(async () => {

                    const swapContractDeployer = (await ethers.getContractFactory("CEXDefaultSwap")).deploy(
                    
                        ENTITY_NAME,
                        poolToken.address,
                        (PREMIUM * 10000).toString(),
                        currentTime.toString(),
                        (INIT_EPOCH).toString()
                    );
    
                    await expect(swapContractDeployer).to.be.revertedWith("Invalid Maturity Date set");
                }, 10000) 
                
                

            })

            it("Should fail deployment if premium value passed is 100% or above", async () => {
                maturityTime = Math.round(Date.now()/1000) + 86400
                testPremium = 1.5

                const swapContractDeployer = (await ethers.getContractFactory("CEXDefaultSwap")).deploy(
                    
                    ENTITY_NAME,
                    poolToken.address,
                    (testPremium * 10000).toString(),
                    maturityTime.toString(),
                    (INIT_EPOCH).toString()
                );

                await expect(swapContractDeployer).to.be.revertedWith("Premium can not be 100% or above");
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

                await expect(depositTx).to.emit(swapContract, "Deposit").withArgs(acc0.address, amtInWei);
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
        })
    })


    describe("Withdraw", function () {
        let previousSellerData;
        let previousAvailableCollateral;
        let previousDepositedCollateral;
        let previousSellerTokenBalance;
        let previousContractTokenBalance;
        const withdrawAmount = 50;
        const amtInWei = ethers.utils.parseEther(withdrawAmount.toString())

        context("Happy path", function () {

            it("should emit withdraw event", async () => {
                previousSellerTokenBalance = await poolToken.balanceOf(acc0.address);
                previousContractTokenBalance = await poolToken.balanceOf(swapContract.address);
                previousSellerData = await swapContract.sellers(acc0.address);
                previousAvailableCollateral = await swapContract.availableCollateral_Total();
                previousDepositedCollateral = await swapContract.depositedCollateral_Total();

                const withdrawTx = swapContract.withdraw(amtInWei);

                await expect(withdrawTx).to.emit(swapContract, "Withdraw").withArgs(acc0.address, amtInWei);
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

})

// describe("Constructor", async () => {
//     const PREMIUM = 0.1; // Fractional premium
//     const INIT_EPOCH = 2;
//     const INIT_MATURITY_DATE = (Date.now()/1000) + 86400;
//     const ENTITY_NAME = "UbeSwap";
    

//     const signers = await ethers.getSigners();
//     console.log("help")
//     let acc0 = signers[0];
//     let acc1 = signers[1];
//     let acc2 = signers[2];
//     let acc3 = signers[3];
    

//     // const poolToken = await (await (await ethers.getContractFactory("ERC20Mock")).deploy()).deployed();

//     let swapContract;
        

//     context("Happy path", () => {
        

//         it("Should deploy and set global variables", async function() {

//             swapContract = await (await (await ethers.getContractFactory("CEXDEfaultSwap")).deploy(
//                 ENTITY_NAME,
//                 poolToken.address,
//                 PREMIUM * 10000,
//                 INIT_MATURITY_DATE,
//                 INIT_EPOCH
//             )).deployed();

//             const entity = await swapContract.entityName();
//             const token = (await swapContract.currency()).address;
//             const maturityDate = BigNumber(await swapContract.maturityDate())
//             const epochDays = BigNumber(await swapContract.epochDays())
//             const premium = BigNumber(await swapContract.premium())

//             assert(entity == ENTITY_NAME, "Entity Name Mismatch")
//             assert(token == poolToken.address, "Pool Currency Mismatch")
//             assert(maturityDate == INIT_MATURITY_DATE, "Maturity Date Mismatch")
//             assert(epochDays == INIT_EPOCH, "Epoch Days Mismatch")
//             assert(premium == PREMIUM * 10000, "Premium Value Mismatch")

//             expect(entity.to.equal(ENTITY_NAME));
//         })
//     })


// })



