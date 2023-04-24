// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./libraries/DateTime.sol";

contract CreditDefaultSwap is DateTime {
    //Loan Data
    string public loanName;
    address public currency;
    uint256 public interestRate;
    string public status;
    bool public defaulted;
    string public loanID;
    string public loanURL;

    uint256 public maturity_day;
    uint256 public maturity_month;
    uint256 public maturity_year;

    //Seller Data
    struct SellerData {
        uint256 depositedCollateral;
        uint256 availableCollateral;
        uint256 lockedCollateral;
        //   uint256 expiredCollateral;
        uint256 unclaimedPremium;
    }

    //Mapping for Seller Data
    mapping(address => SellerData) public sellers;
    address[] public sellerList;
    mapping(address => bool) public onSellerList;

    //Buyer Data
    struct BuyerData {
        uint256 premiumPaid;
        uint256 collateralCovered;
        uint256 claimableCollateral;
    }

    //Mapping for Buyer Data
    mapping(address => BuyerData) public buyers;
    address[] public buyerList;
    mapping(address => bool) public onBuyerList;

    //Collateral Variables
    uint256 public depositedCollateral_Total;
    uint256 public availableCollateral_Total;
    uint256 public lockedCollateral_Total;
    //uint256 expiredCollateral_Total;
    uint256 public premiumPaid_Total;
    uint256 public unclaimedPremium_Total;
    uint256 public collateralCovered_Total;
    uint256 public claimableCollateral_Total;

    //Premium price
    uint256 public premium;

    //contract executed boolean to limit default conditions to single use
    bool executed;

    constructor(
        string memory _loanName,
        address _currency,
        uint256 _interestRate,
        uint256 _maturity_day,
        uint256 _maturity_month,
        uint256 _maturity_year,
        string memory _status,
        uint256 _premium,
        string memory _loanID,
        string memory _loanURL
    ) {
        loanName = _loanName;
        currency = _currency;
        interestRate = _interestRate;
        maturity_day = _maturity_day;
        maturity_month = _maturity_month;
        maturity_year = _maturity_year;
        status = _status;
        premium = _premium;
        loanID = _loanID;
        loanURL = _loanURL;
    }

    function deposit(uint256 _amount) public payable {
        require(!executed, "No longer can deposit");

        //@DEV-TODO Include transfer from logic when ready with below

        _transferFrom(_amount);

        sellers[msg.sender].depositedCollateral += _amount;
        sellers[msg.sender].availableCollateral += _amount;

        depositedCollateral_Total += _amount;
        availableCollateral_Total += _amount;

        if (!onSellerList[msg.sender]) {
            sellerList.push(msg.sender);
            onSellerList[msg.sender] = true;
        }
    }

    function withdraw(uint256 _amount) public payable {
        require(
            _amount <= sellers[msg.sender].availableCollateral,
            "Not enough unlocked collateral"
        );

        _transferTo(_amount, msg.sender);

        sellers[msg.sender].depositedCollateral -= _amount;
        sellers[msg.sender].availableCollateral -= _amount;

        depositedCollateral_Total -= _amount;
        availableCollateral_Total -= _amount;
    }

    function purchase(uint256 _amount) public payable {
        //N.B. _amount is the amount denominated in collateral being covered. i.e. assuming a premium of 5%, a 100 input in _amount will cover 100 units of collateral and cost the buyer 5 units.
        //This is done to simplify calculations and minimize divisions

        //Check available collateral is sufficient
        require(_amount <= availableCollateral_Total, "Not enough to sell");

        //Handle premium calculation & payment

        //@DEV-TODO does this need to be dyanmic for different dates?
        uint256 premiumPayable = (_amount * premium) / 10000;

        _transferFrom(premiumPayable);

        buyers[msg.sender].premiumPaid += premiumPayable;
        buyers[msg.sender].collateralCovered += _amount;

        //For each user reduce available amount pro-rata
        //Handle reductions per user first
        //User Available Amount  =- Purchase Amount Converted to Base * User Available Amount / Total Available Amount
        //User Locked Amount =+ Changes from above
        //Unclaimed Premium =+ Premium Paid * User Available Amount / Total Available Amount

        for (uint256 i = 0; i < sellerList.length; i++) {
            //Consider including min function to capture loop so it doesn't over subtract

            address _address = sellerList[i];

            //Calculate change in collateral
            uint256 w = (_amount *
                sellers[_address].availableCollateral *
                1000) / availableCollateral_Total;
            w = w / 1000;

            //Add premium to claimable amount
            uint256 z = (premiumPayable *
                sellers[_address].availableCollateral *
                1000) / availableCollateral_Total;
            z = z / 1000;

            sellers[_address].availableCollateral -= w;
            sellers[_address].lockedCollateral += w;
            sellers[_address].unclaimedPremium += z;
        }

        //Handle global amounts
        //Available Total =- Amount purchased converted to base
        //Locked amount =+ change from above

        availableCollateral_Total -= _amount;
        lockedCollateral_Total += _amount;

        premiumPaid_Total += premiumPayable;
        unclaimedPremium_Total += premiumPayable;
        collateralCovered_Total += _amount;

        if (!onBuyerList[msg.sender]) {
            buyerList.push(msg.sender);
            onBuyerList[msg.sender] = true;
        }
    }

    function claimPremium() public {
        uint256 payableAmount = sellers[msg.sender].unclaimedPremium;

        _transferTo(payableAmount, msg.sender);

        sellers[msg.sender].unclaimedPremium -= payableAmount;

        for (uint256 i = 0; i < sellerList.length; i++) {
            address _address = sellerList[i];

            //Calculate change in collateral
            uint256 w = (payableAmount *
                sellers[_address].depositedCollateral *
                1000) / depositedCollateral_Total;
            w = w / 1000;

            sellers[_address].depositedCollateral -= w;
        }

        depositedCollateral_Total -= payableAmount;
    }

    function claimCollateral() public {
        //@DEV TODO Call Oracle

        //Only trigger if defaulted boolean is true
        require(defaulted, "Has not defaulted");

        uint256 payableAmount = buyers[msg.sender].claimableCollateral;

        _transferTo(payableAmount, msg.sender);

        buyers[msg.sender].claimableCollateral = 0;

        depositedCollateral_Total -= payableAmount;
    }

    function execute(bool _default) public {
        //Execute contract and change variable for a default event

        if (!executed) {
            //@DEV TODO Replace with Call Oracle
            defaulted = _default;
            bool condition1;

            (uint _year, uint _month, uint _day) = timestampToDate(
                block.timestamp
            );
            if (
                maturity_day == _day &&
                maturity_month == _month &&
                maturity_year == _year
            ) {
                condition1 = true;
            } else {
                condition1 = false;
            }

            require(condition1 || defaulted, "Not at maturity or defaulted");

            if (defaulted) {
                //Handle buyer adjustments on liquidation
                for (uint256 i = 0; i < buyerList.length; i++) {
                    buyers[msg.sender].claimableCollateral = buyers[msg.sender]
                        .collateralCovered;
                    buyers[msg.sender].collateralCovered = 0;
                }

                claimableCollateral_Total += collateralCovered_Total;

                for (uint256 i = 0; i < sellerList.length; i++) {
                    sellers[msg.sender].availableCollateral = 0;
                    sellers[msg.sender].lockedCollateral = 0;
                }

                lockedCollateral_Total = 0;
            } else {
                for (uint256 i = 0; i < buyerList.length; i++) {
                    buyers[msg.sender].collateralCovered = 0;
                }

                for (uint256 i = 0; i < sellerList.length; i++) {
                    sellers[msg.sender].availableCollateral += sellers[
                        msg.sender
                    ].lockedCollateral;
                    sellers[msg.sender].lockedCollateral = 0;
                }

                availableCollateral_Total += lockedCollateral_Total;
                lockedCollateral_Total = 0;
            }
        }
    }

    function _transferFrom(uint256 _amount) internal {
        require(
            IERC20(currency).balanceOf(msg.sender) >= _amount,
            "Insufficient balance"
        );

        bool transferSuccess = IERC20(currency).transferFrom(
            msg.sender,
            address(this),
            _amount
        );

        if (!transferSuccess) revert();
    }

    function _transferTo(uint256 _amount, address _user) internal {
        bool transferSuccess = IERC20(currency).transfer(_user, _amount);

        if (!transferSuccess) revert();
    }
}
