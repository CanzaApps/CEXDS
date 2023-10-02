// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./Voting.sol";
import "./interfaces/IOracle.sol";

contract CEXDefaultSwap {

    //Loan Data
    string public entityName;
    // Ensures a valid ERC20 compliant address is passed in constructor
    IERC20 public currency;
    bool public defaulted;
    address public votingContract;
    address public oracleContract;
    address public controller;
    uint256 public totalVoterFeePaid;

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

    //Pause boolean (for after default event)
    bool paused;

    event Deposit(address indexed _seller, uint256 _amount);
    event Withdraw(address indexed _seller, uint256 _amount);
    event PurchaseCollateral(address indexed _buyer, uint256 _amount, uint256 premiumPaid, uint256 _makerFeePaid);
    event ClaimPremium(address indexed _seller, uint256 _amount);
    event ClaimCollateral(address indexed _buyer, uint256 _amount);

    constructor(
        string memory _entityName,
        address _currency,
        uint256 _premium,
        uint256 _initialMaturityDate,
        uint256 _epochDays,
        address _votingContract,
        address _oracle
    ) {
        require(_initialMaturityDate > block.timestamp, "Invalid Maturity Date set");
        require(_premium < 10000, "Premium can not be 100% or above");
        currency = IERC20(_currency);
        entityName = _entityName;
        premium = _premium;
        maturityDate = _initialMaturityDate;
        epochDays = _epochDays;
        votingContract = _votingContract;
        oracleContract = _oracle;
        controller = msg.sender;
    }

    modifier validCaller {
        if(msg.sender != controller && msg.sender != votingContract) revert("Unauthorized");
        _;
    }

    function deposit(uint256 _amount) external {

        execute();
        
        //Don't allow deposits during Pause after default event
        require(!paused,"Contract Paused");

        //@DEV-TODO Include transfer from logic when ready with below

        sellers[msg.sender].depositedCollateral += _amount;
        sellers[msg.sender].availableCollateral += _amount;

        depositedCollateral_Total += _amount;
        availableCollateral_Total += _amount;

        if (!onSellerList[msg.sender]) {
            sellerList.push(msg.sender);
            onSellerList[msg.sender] = true;
        }
        _transferFrom(_amount);

        emit Deposit(msg.sender, _amount);
    }

    function withdraw(uint256 _amount) external {
        
        //Ensures execute happens before withdraw happens if pause event not active
        if(!paused){
            execute();
        }
        
        require(
            _amount <= sellers[msg.sender].availableCollateral,
            "Not enough unlocked collateral"
        );

        sellers[msg.sender].depositedCollateral -= _amount;
        sellers[msg.sender].availableCollateral -= _amount;

        depositedCollateral_Total -= _amount;
        availableCollateral_Total -= _amount;

        _transferTo(_amount, msg.sender);
        emit Withdraw(msg.sender, _amount);
    }

    function purchase(uint256 _amount) external {
        
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
        uint256 voterFee = IOracle(oracleContract).getDefaultFeeAmount(makerFeePayable, address(this));
        _transferTo(voterFee, votingContract);
        _transferTo(makerFeePayable - voterFee, controller);
        totalVoterFeePaid += voterFee;

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
                1e18) / availableCollateral_Total;

            //Add premium to claimable amount
            uint256 z = (premiumPayable *
                sellers[_address].availableCollateral *
                1e18) / availableCollateral_Total;

            sellers[_address].availableCollateral = (sellers[_address].availableCollateral*1e18 - w)/1e18;
            sellers[_address].lockedCollateral = (sellers[_address].lockedCollateral*1e18 + w)/1e18;
            sellers[_address].unclaimedPremium = (sellers[_address].unclaimedPremium*1e18 + z)/1e18;
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

        emit PurchaseCollateral(msg.sender, _amount, premiumPayable, makerFeePayable);
    }

    function claimPremium() external {
        //Ensures execute happens before claim happens if pause event not active
        if(!paused){
            execute();
        }

        uint256 payableAmount = sellers[msg.sender].unclaimedPremium;

        sellers[msg.sender].unclaimedPremium -= payableAmount;

        unclaimedPremium_Total -= payableAmount;

        _transferTo(payableAmount, msg.sender);
        emit ClaimPremium(msg.sender, payableAmount);
    }

    function claimCollateral() external {
        //@DEV TODO Call Oracle

        uint256 payableAmount = buyers[msg.sender].claimableCollateral;

        buyers[msg.sender].claimableCollateral = 0;

        claimableCollateral_Total -= payableAmount;
        _transferTo(payableAmount, msg.sender);
        emit ClaimCollateral(msg.sender, payableAmount);

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

    function deductFromVoterFee(uint256 _amount) external validCaller {
        if (_amount > totalVoterFeePaid) revert("Not sufficient deductible");
        totalVoterFeePaid -= _amount;
    }

    function setDefaulted() external validCaller {
        require(!defaulted, "Contract already defaulted");
        defaulted = true;
        paused = false;
        execute();
    }

    //@TODO-Only to be handled by multisig 
    function pause() external validCaller {
        paused = true;
    }

    function unpause() external validCaller {
        require(!defaulted, "Contract has defaulted, use default reset");

        paused = false;
        execute();
    }
    
    //@TODO-Only to be handled by multisig 
    function resetAfterDefault(uint256 _newMaturityDate) external {
        require(msg.sender == controller, "Unauthorized");
        require(defaulted, "Not defaulted");

        defaulted = false;
        paused = false;
        rollEpoch(_newMaturityDate);

    }
    
    //Epoch Vairable Handlers
    function rollEpoch(uint256 _newMaturityDate) internal {

        maturityDate = _newMaturityDate;
        epoch ++;

    }
    

    function _transferFrom(uint256 _amount) internal {

        bool transferSuccess = currency.transferFrom(
            msg.sender,
            address(this),
            _amount
        );

        if (!transferSuccess) revert();
    }

    function _transferTo(uint256 _amount, address _user) internal {
        bool transferSuccess = currency.transfer(_user, _amount);

        if (!transferSuccess) revert();
    }

    function isPaused() public view returns (bool) {
        return paused;
    }

}
