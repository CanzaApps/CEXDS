// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import "./interfaces/IOracle.sol";

contract RollContract {

    uint256 public depositedCollateralTotal;
    uint256 public availableCollateralTotal;
    uint256 public lockedCollateralTotal;
    uint256 public onActiveTransferredCollateralTotal;
    uint256 public premiumPaidTotal;
    uint256 public unclaimedPremiumTotal;
    uint256 public collateralCoveredTotal;
    uint256 public claimableCollateralTotal;
    uint256 public requestedWithdrawalTotal;
    address oracle;

    //Seller Data
    struct SellerData {
        uint256 depositedCollateral;
        uint256 availableCollateral;
        uint256 lockedCollateral;
        uint256 unclaimedPremium;
        uint256 requestedWithdrawal;
    }
    //Buyer Data
    struct BuyerData {
        uint256 premiumPaid;
        uint256 collateralCovered;
        uint256 claimableCollateral;
    }
    mapping (address=>SellerData) public sellers; 
    mapping (address=>BuyerData) public buyers;


    constructor (address oracleAddress, uint256 rollOverAvailableCollateral) {

        oracle = oracleAddress;
        availableCollateralTotal = rollOverAvailableCollateral;
    }

    function addDeposit(address depositor, uint256 amount) external {

        depositedCollateralTotal += amount;
        availableCollateralTotal += amount;

        sellers[depositor].depositedCollateral += amount;
        sellers[depositor].availableCollateral += amount;
    }

    function addWithdrawRequest(address depositor, uint256 amount, bool isActivePool) external {

        // Remove amount from available collateral since it will not be available for purchase when pool is active
        if (!isActivePool) {
            sellers[depositor].availableCollateral -= amount;
            availableCollateralTotal -= amount;
        }
        sellers[depositor].requestedWithdrawal += amount;
        requestedWithdrawalTotal += amount;
    }

    function withdraw(address depositor, uint256 amount) external {

        depositedCollateralTotal -= amount;
        requestedWithdrawalTotal -= amount;

        sellers[depositor].depositedCollateral -= amount;
        sellers[depositor].requestedWithdrawal -= amount;
    }

    function addPurchase(address buyer, uint256 amount, uint256 premiumAmount) external {

        availableCollateralTotal -= amount;
        // Adds the amount purchased from current active pool into new pool
        lockedCollateralTotal += amount;
        collateralCoveredTotal += amount;
        premiumPaidTotal += premiumAmount;

        buyers[buyer].collateralCovered += amount;
    }


    // function updateAfterPremiumClaim(uint256 amountClaimed, address seller) external {
    //     unclaimedPremiumTotal -= amountClaimed;
    //     sellers[seller].unclaimedPremium -= amountClaimed;
    // }

    // function updateAfterCollateralClaim(uint256 amountClaimed, address buyer) external {
    //     collateralCoveredTotal -= amountClaimed;
    //     buyers[buyer].collateralCovered -= amountClaimed;
    // }

    // stopping lockedCollateral from setting to zero at end of pool
    function updateOnExecute(bool isDefault, bool isMature) external {

        if (isDefault) {

            claimableCollateralTotal += collateralCoveredTotal;
            collateralCoveredTotal = 0;

            depositedCollateralTotal -= lockedCollateralTotal;
        } else if (isMature) {
            
            collateralCoveredTotal = 0;
            premiumPaidTotal = 0;

            availableCollateralTotal += lockedCollateralTotal;
        }
    }

    function setAsActive(
        uint256 previousDepositedCollateralTotal,
        uint256 previousRequestedWithdrawalTotal,
        uint256 previousClaimableCollateralTotal,
        uint256 previousUnclaimedPremiumTotal
    ) external returns (uint256 availableCollateralToTransfer) {
        availableCollateralToTransfer = availableCollateralTotal;
        depositedCollateralTotal += previousDepositedCollateralTotal - availableCollateralTotal;
        requestedWithdrawalTotal += previousRequestedWithdrawalTotal;

        claimableCollateralTotal += previousClaimableCollateralTotal;
        unclaimedPremiumTotal += previousUnclaimedPremiumTotal;

        onActiveTransferredCollateralTotal = availableCollateralToTransfer;
    }

}