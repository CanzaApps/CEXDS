// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./DateTime.sol";
import "./ICreditDefaultSwap.sol";

contract CEXDefaultSwap is DateTime, Ownable, ICreditDefaultSwap {
    //Loan Data
    string public entityName;
    address public currency;
    string public currencyName;
    string public status;
    bool public defaulted;
    string public entityURL;

    //Epoch variables
    uint256 public epoch;
    uint256 public maturityDate;
    uint256 public epochDays;

    //Seller Data
    struct SellerData {
        uint256 depositedCollateral;
        uint256 availableCollateral;
        uint256 lockedCollateral;
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
    uint256 public premiumPaid_Total;
    uint256 public unclaimedPremium_Total;
    uint256 public collateralCovered_Total;
    uint256 public claimableCollateral_Total;

    //Premium price in bps
    uint256 public premium;
    uint256 public makerFee = 30;

    //Treasury Address
    //@TODO CHANGE TO DEPLOYER CONTRACT
    address treasuryAddress = 0xAb8483F64d9C6d1EcF9b849Ae677dD3315835cb2;

    //Pause boolean (for after default event)
    bool paused;

    constructor(
        string memory _entityName,
        address _currency,
        string memory _currency_name,
        string memory _status,
        uint256 _premium,
        uint256 _initialMaturityDate,
        uint256 _epochDays
    ) {
        entityName = _entityName;
        currency = _currency;
        currencyName = _currency_name;
        status = _status;
        premium = _premium;
        maturityDate = _initialMaturityDate;
        epochDays = _epochDays;

    }

    function deposit(uint256 _amount) external payable {

        execute();
        
        //Don't allow deposits during Pause after default event
        require(!paused,"Contract Paused");

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

    function withdraw(uint256 _amount) external payable {
        
        //Ensures execute happens before withdraw happens if pause event not active
        if(!paused){
            execute();
        }
        
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

    function purchase(uint256 _amount) external payable {
        
        execute();

        //N.B. _amount is the amount denominated in collateral being covered. i.e. assuming a premium of 5%, a 100 input in _amount will cover 100 units of collateral and cost the buyer 5 units.
        //This is done to simplify calculations and minimize divisions

        //Check available collateral is sufficient
        require(_amount <= availableCollateral_Total, "Not enough to sell");

        //Don't allow deposits during Pause after default event
        require(!paused,"Contract Paused");

        //@DEV-TODO does this need to be dyanmic for different dates?
        
        uint256 makerFeePayable = (_amount * makerFee) / 10000;
        
        uint256 premiumPayable = (_amount * premium) / 10000;

        uint256 totalPayable = makerFeePayable + premiumPayable;

        _transferFrom(totalPayable);
        _transferTo(makerFeePayable, treasuryAddress);

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

    function claimPremium() external {
        //Ensures execute happens before claim happens if pause event not active
        if(!paused){
            execute();
        }

        uint256 payableAmount = sellers[msg.sender].unclaimedPremium;

        _transferTo(payableAmount, msg.sender);

        sellers[msg.sender].unclaimedPremium -= payableAmount;

        unclaimedPremium_Total -= payableAmount;
    }

    function claimCollateral() external {
        //@DEV TODO Call Oracle

        //Only trigger if defaulted boolean is true
        require(defaulted, "Has not defaulted");

        uint256 payableAmount = buyers[msg.sender].claimableCollateral;

        _transferTo(payableAmount, msg.sender);

        buyers[msg.sender].claimableCollateral = 0;

    }

    function execute() internal {
        //Execute contract and change variable for a default event

        require(!paused, "Contract is paused");

        bool matured = block.timestamp >= maturityDate;

        //Triggers in default event only
        if (defaulted) {
            //Handle buyer adjustments for default
            //buyers can now claim their covered collateral
            //Collateral Covered set to 0 


            for (uint256 i = 0; i < buyerList.length; i++) {
                address _address = buyerList[i];
            
                buyers[_address].claimableCollateral = buyers[_address]
                    .collateralCovered;
                buyers[_address].collateralCovered = 0;
            }

            claimableCollateral_Total += collateralCovered_Total;
            collateralCovered_Total = 0;

            //Handle seller adjustments for default
            //Seller locked collateral set to 0
            //Deposited collateral reduced for locked collateral
            //Available collateral is rolled forward for next epoch
            //user can still withdraw even when paused.
            for (uint256 i = 0; i < sellerList.length; i++) {
                address _address = sellerList[i];
                sellers[_address].depositedCollateral -= sellers[_address].lockedCollateral; 
                sellers[_address].lockedCollateral = 0;
            }

            depositedCollateral_Total -= lockedCollateral_Total;
            lockedCollateral_Total = 0;
            
            //Pauses contract until reset
            paused = true;
            status = "Defaulted";

        } else if (matured) {

            //Handle buyer adjustments for maturity
            //Covered collateral reset to 0
            //Premium paid reset to 0 
            for (uint256 i = 0; i < buyerList.length; i++) {
                address _address = buyerList[i];
                buyers[_address].collateralCovered = 0;
                buyers[_address].premiumPaid = 0;
            }

            collateralCovered_Total = 0;
            premiumPaid_Total = 0;

            //Handle seller adjustments for maturity
            //All collateral made available to depositors
            //Automatically rolled over
            for (uint256 i = 0; i < sellerList.length; i++) {
                address _address = sellerList[i];
                sellers[_address].availableCollateral += 
                   sellers[_address].lockedCollateral;
                sellers[_address].lockedCollateral = 0;
            }

            availableCollateral_Total += lockedCollateral_Total;
            lockedCollateral_Total = 0;

            uint256 x = epochDays * 86400;

            maturityDate += x; 

            rollEpoch(maturityDate);
        }

    }

    function setDefaulted(bool _value) external onlyOwner {
        defaulted = _value;
        execute();
    }

    //@TODO-Only to be handled by multisig 
    function pause() external onlyOwner {
        paused = true;
        status = "Paused";
    }

    function unpause() external onlyOwner{
        require(!defaulted, "Contract has defaulted, use default reset");

        paused = false;
        status = "Active";
        execute();
    }
    
    //@TODO-Only to be handled by multisig 
    function resetAfterDefault(uint256 _newMaturityDate) external onlyOwner {
        
        require(defaulted, "Not defaulted");

        defaulted = false;
        paused = false;
        status = "Active";
        rollEpoch(_newMaturityDate);

    }
    
    //Epoch Vairable Handlers
    function rollEpoch(uint256 _newMaturityDate) internal {

        maturityDate = _newMaturityDate;
        epoch ++;

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
