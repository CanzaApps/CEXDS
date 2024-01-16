// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import "./interfaces/IOracle.sol";

contract RollContract {

    uint256 public depositedCollateralTotal;
    uint256 public availableCollateralTotal;
    uint256 public lockedCollateralTotal;
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


    constructor (address oracleAddress) {

        oracle = oracleAddress;
    }

    function addDeposit(address depositor, uint256 amount) external {

        depositedCollateralTotal += amount;
        availableCollateralTotal += amount;

        sellers[depositor].depositedCollateral += amount;
        sellers[depositor].availableCollateral += amount;
    }

    function withdraw(address depositor, uint256 amount) external {
        require(amount <= sellers[depositor].requestedWithdrawal, "Can not withdraw what was not requested");

        depositedCollateralTotal -= amount;
        requestedWithdrawalTotal -= amount;

        sellers[depositor].depositedCollateral -= amount;
        sellers[depositor].requestedWithdrawal -= amount;
    }

    function addPurchase(address buyer, uint256 amount, uint256 amountFromPreviousPool) external {

        availableCollateralTotal -= amount;
        // Adds the amount purchased from current active pool into new pool
        lockedCollateralTotal += amount + amountFromPreviousPool;
        collateralCoveredTotal += amount + amountFromPreviousPool;

        buyers[buyer].collateralCovered += amount + amountFromPreviousPool;
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

    function updateAfterPremiumClaim(uint256 amountClaimed, address seller) external {
        unclaimedPremiumTotal -= amountClaimed;
        sellers[seller].unclaimedPremium -= amountClaimed;
    }

    function updateAfterCollateralClaim(uint256 amountClaimed, address buyer) external {
        collateralCoveredTotal -= amountClaimed;
        buyers[buyer].collateralCovered -= amountClaimed;
    }

    function updateOnExecute(bool isDefault, bool isMature) external {

        if (isDefault) {

            claimableCollateralTotal += collateralCoveredTotal;
            collateralCoveredTotal = 0;

            depositedCollateralTotal -= lockedCollateralTotal;
            lockedCollateralTotal = 0;
        } else if (isMature) {
            
            collateralCoveredTotal = 0;
            premiumPaidTotal = 0;

            availableCollateralTotal += lockedCollateralTotal;
            lockedCollateralTotal = 0;
        }
    }

    function setAsActive(
        uint256 previousDepositedCollateralTotal,
        uint256 previousAvailableCollateralTotal,
        uint256 previousRequestedWithdrawalTotal,
        uint256 previousClaimableCollateralTotal,
        uint256 previousUnclaimedPremiumTotal
    ) external {

        depositedCollateralTotal += previousDepositedCollateralTotal;
        availableCollateralTotal += previousAvailableCollateralTotal;
        requestedWithdrawalTotal += previousRequestedWithdrawalTotal;

        claimableCollateralTotal += previousClaimableCollateralTotal;
        unclaimedPremiumTotal += previousUnclaimedPremiumTotal;
    }

}