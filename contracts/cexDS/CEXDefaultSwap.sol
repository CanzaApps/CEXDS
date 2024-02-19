// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./Voting.sol";
import "./interfaces/IOracle.sol";

/// @title Centralized Exchange Default Swap
/// @notice This contract implements all the functionalities for user interaction with a Credit Default Swap pool
/// @dev Pool is deployed as a single instance representing a specific ERC20 token on a singular entity
contract CEXDefaultSwap {
    using SafeERC20 for IERC20;
    using Address for address;
    //Loan Data
    string public entityName;
    string public entityUrl;
    IERC20 public immutable currency;
    address public immutable votingContract;
    address public immutable oracleContract;
    address public immutable controller;
    uint256 public totalVoterFeePaid;
    uint256 public totalVoterFeeRemaining;

    //Epoch variables
    uint256 public epoch;
    uint256 public maturityDate;
    uint256 public immutable epochDays;

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

    struct UserPoolData {
        bool isSeller;
        bool isBuyer;
        SellerData sellerData;
        BuyerData buyerData;
    }

    //Pool Data
    struct PoolData {
        string entityName;
        address poolAddress;
        string status;
        address poolToken;
        uint256 premium;
        uint256 makerFee;
        uint256 maturityDate;
        uint256 epochCount;
        uint256 epochDays;
        uint256 totalVoterFeePaid;
        uint256 totalVoterFeeRemaining;
        uint256 depositedCollateralTotal;
        uint256 availableCollateralTotal;
        uint256 lockedCollateralTotal;
        uint256 premiumPaidTotal;
        uint256 unclaimedPremiumTotal;
        uint256 collateralCoveredTotal;
        uint256 claimableCollateralTotal;
        UserPoolData userPoolData;
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
    uint256 public immutable premium;
    uint256 public immutable makerFee;
    uint256 public immutable maxSellerCount;
    uint256 public immutable maxBuyerCount;

    //Pause boolean (for after default event)
    bool private paused;
    bool public closed;
    bool public defaulted;

    //Stores all token Values sent to the contract
    mapping(address => uint256) public fallBackEntries;

    // _actualDepositedAmount would be less than _amount in event that the ERC20 token deposited implements fee on transfer
    event Deposit(address indexed _seller, uint256 _amount, uint256 _actualdepositedAmount);
    event Withdraw(address indexed _seller, uint256 _amount, uint256 _actualwithdrawAmount);
    event PurchaseCollateral(address indexed _buyer, uint256 _amount, uint256 _actualPurchasedAmount, uint256 premiumPaid, uint256 _makerFeePaid);
    event ClaimPremium(address indexed _seller, uint256 _amount, uint256 _actualTransferAmount);
    event ClaimCollateral(address indexed _buyer, uint256 _amount, uint256 _actualPurchasedAmount);
    event WithdrawFromBalance(address _recipient, uint256 _amount, uint256 _actualAmountReceived);

    /// @dev Deploys contract and initializes state variables
    /// @param _entityName the name of the specific entity which the Swap pool represents
    /// @param _entityUrl url representing the entity which the Swap pool represents. Could be a website URL or some other URI
    /// @param _currency the ERC20 standard token on which the pool is dependent
    /// @param _premium the premium percentage to be paid on every collateral purchase marked up by 10**4
    /// @param _makerFee the percentage to be paid on every purchase to amount to the treasury and voter reserve, marked up by 10**4
    /// @param _initialMaturityDate Initial timestamp set for the swap pool to mature, in the event of no default
    /// @param _epochDays number of days with which to update the maturity timestamp after a maturation cycle has elapsed
    /// @param _maxSellerCount Maximum number of sellers allowed
    /// @param _maxBuyerCount Maximum number of collateral buyers allowed
    /// @param _votingContract address at where the contract implementing Voting consensus is deployed
    /// @param _oracle address at where the contract providing oracle data is deployed
    constructor(
        string memory _entityName,
        string memory _entityUrl,
        address _currency,
        uint256 _premium,
        uint256 _makerFee,
        uint256 _initialMaturityDate,
        uint256 _epochDays,
        uint256 _maxSellerCount,
        uint256 _maxBuyerCount,
        address _votingContract,
        address _oracle,
        address _controller
    ) {
        require(_votingContract.isContract() && _oracle.isContract(), "Address supplied for Voting, or Oracle, contract is invalid");
        require(_initialMaturityDate > block.timestamp, "Invalid Maturity Date set");
        require(_premium < 10000 && _makerFee < 10000, "Premium, and maker fee, can not be 100% or above");
        currency = IERC20(_currency);
        entityName = _entityName;
        entityUrl = _entityUrl;
        premium = _premium;
        makerFee = _makerFee;
        maturityDate = _initialMaturityDate;
        epochDays = _epochDays;
        maxSellerCount = _maxSellerCount;
        maxBuyerCount = _maxBuyerCount;
        votingContract = _votingContract;
        oracleContract = _oracle;
        controller = _controller;
    }

    modifier validCaller {
        if(msg.sender != controller && msg.sender != votingContract) revert("Unauthorized");
        _;
    }

    /// @notice Allows intending seller to sell specified amount of collateral. Sellers can always add to previous sold amount.
    /// @dev the actualTransferAmount implementation is considering the event where the ERC20 token for the pool implements fee on transfer
    /// @param _amount intended collateral amount to sell
    /// NOTE: The eventual deposited collateral may not match the value of _amount, if the token implements fee on transfer
    function deposit(uint256 _amount) external {
        bool isPreviousSeller = onSellerList[msg.sender];
        if (!isPreviousSeller && sellerList.length == maxSellerCount) revert("Already reached maximum allowable sellers");
        execute(false);
        
        //Don't allow deposits during Pause after default event
        require(!paused,"Contract Paused");
        require(!closed,"Pool closed");
        
        uint256 actualTransferAmount = _transferFrom(_amount);
        sellers[msg.sender].depositedCollateral += actualTransferAmount;
        sellers[msg.sender].availableCollateral += actualTransferAmount;

        depositedCollateral_Total += actualTransferAmount;
        availableCollateral_Total += actualTransferAmount;

        if (!isPreviousSeller) {
            sellerList.push(msg.sender);
            onSellerList[msg.sender] = true;
        }
        

        emit Deposit(msg.sender, _amount, actualTransferAmount);
    }

    /// @notice Allows existing seller to withdraw collateral available to them. Locked collateral can not be withdrawn.
    /// @dev Call to execute must be done to validate actual balances before proceeding with withdraw
    /// @param _amount intended amount of collateral to withdraw
    function withdraw(uint256 _amount) external {
        
        //Ensures execute happens before withdraw happens if pause event not active
        if(!paused){
            execute(false);
        }
        
        require(
            _amount <= sellers[msg.sender].availableCollateral,
            "Not enough unlocked collateral"
        );

        sellers[msg.sender].depositedCollateral -= _amount;
        sellers[msg.sender].availableCollateral -= _amount;

        depositedCollateral_Total -= _amount;
        availableCollateral_Total -= _amount;

        uint256 actualTransferAmount = _transferTo(_amount, msg.sender);
        emit Withdraw(msg.sender, _amount, actualTransferAmount);
    }

    /// @notice Allows intending buyer to purchase a specified amount of collateral, paying a premium and protocol fee, and locking the purchased amount from the sellers.
    /// @dev Call to execute must be done to validate actual balances before proceeding with purchase
    /// @param _amount intended amount of collateral to purchase
    function purchase(uint256 _amount) external {
        bool isPreviousBuyer = onBuyerList[msg.sender];
        if (!isPreviousBuyer && buyerList.length == maxBuyerCount) revert("Already reached maximum allowable buyers");
        
        execute(false);

        //N.B. _amount is the amount denominated in collateral being covered. i.e. assuming a premium of 5%, a 100 input in _amount will cover 100 units of collateral and cost the buyer 5 units.
        //This is done to simplify calculations and minimize divisions

        //Check available collateral is sufficient
        require(_amount <= availableCollateral_Total, "Not enough to sell");

        //Don't allow deposits during Pause after default event
        require(!paused,"Contract Paused");
        require(!closed,"Pool closed");
        
        uint256 makerFeePayable = (_amount * makerFee) / 10000;
        
        uint256 premiumPayable = (_amount * premium) / 10000;

        uint256 totalPayable = makerFeePayable + premiumPayable;

        uint256 actualTransferAmount = _transferFrom(totalPayable);

        //backpropagate the actualTransferAmount in the event that there was a fee on transfer, and get actual makerFeePaid & premium & collateral
        uint256 makerFeePaid = (makerFeePayable * actualTransferAmount)/totalPayable;
        uint256 premiumPaid = actualTransferAmount - makerFeePaid;

        uint256 actualCollateralToPurchase = premiumPaid * 10000/premium;

        uint256 voterFee = IOracle(oracleContract).getDefaultFeeAmount(makerFeePaid, address(this));
        uint256 actualVotingFeeSent = _transferTo(voterFee, votingContract);
        totalVoterFeePaid += actualVotingFeeSent;
        totalVoterFeeRemaining += actualVotingFeeSent;

        buyers[msg.sender].premiumPaid += premiumPaid;
        buyers[msg.sender].collateralCovered += actualCollateralToPurchase;

        //For each user reduce available amount pro-rata
        //Handle reductions per user first
        //User Available Amount  =- Purchase Amount Converted to Base * User Available Amount / Total Available Amount
        //User Locked Amount =+ Changes from above
        //Unclaimed Premium =+ Premium Paid * User Available Amount / Total Available Amount
        uint256 sellerCount = sellerList.length;
        for (uint256 i = 0; i < sellerCount; i++) {
            //Consider including min function to capture loop so it doesn't over subtract

            address _address = sellerList[i];
            SellerData memory sellerInfo = sellers[_address];

            if (sellerInfo.availableCollateral == 0) continue;

            //Calculate change in collateral
            uint256 w = (actualCollateralToPurchase *
                sellerInfo.availableCollateral *
                1e18) / availableCollateral_Total;

            //Add premium to claimable amount
            uint256 z = (premiumPaid *
                sellerInfo.availableCollateral *
                1e18) / availableCollateral_Total;

            sellerInfo.availableCollateral = (sellerInfo.availableCollateral*1e18 - w)/1e18;
            sellerInfo.lockedCollateral = (sellerInfo.lockedCollateral*1e18 + w)/1e18;
            sellerInfo.unclaimedPremium = (sellerInfo.unclaimedPremium*1e18 + z)/1e18;

            sellers[_address] = sellerInfo;
        }

        //Handle global amounts
        //Available Total =- Amount purchased converted to base
        //Locked amount =+ change from above

        availableCollateral_Total -= actualCollateralToPurchase;
        lockedCollateral_Total += actualCollateralToPurchase;

        premiumPaid_Total += premiumPaid;
        unclaimedPremium_Total += premiumPaid;
        collateralCovered_Total += actualCollateralToPurchase;

        if (!isPreviousBuyer) {
            buyerList.push(msg.sender);
            onBuyerList[msg.sender] = true;
        }

        emit PurchaseCollateral(msg.sender, _amount, actualCollateralToPurchase, premiumPaid, makerFeePaid);
    }

    /// @notice Allows existing seller to claim premium previously paid by buyers on purchase
    function claimPremium() external {
        //Ensures execute happens before claim happens if pause event not active
        if(!paused){
            execute(false);
        }

        uint256 payableAmount = sellers[msg.sender].unclaimedPremium;

        sellers[msg.sender].unclaimedPremium -= payableAmount;

        unclaimedPremium_Total -= payableAmount;

        uint256 actualTransfer = _transferTo(payableAmount, msg.sender);
        emit ClaimPremium(msg.sender, payableAmount, actualTransfer);
    }

    /// @notice Allows existing buyer to claim collateral locked in the event of a default
    function claimCollateral() external {
        uint256 payableAmount = buyers[msg.sender].claimableCollateral;

        buyers[msg.sender].claimableCollateral = 0;

        claimableCollateral_Total -= payableAmount;
        uint256 actualTransfer = _transferTo(payableAmount, msg.sender);
        emit ClaimCollateral(msg.sender, payableAmount, actualTransfer);

    }

    function execute(bool closeCall) internal {
        //Execute contract and change variable for a default event

        require(!paused, "Contract is paused");

        bool matured = block.timestamp >= maturityDate;
        uint256 buyerCount = buyerList.length;
        uint256 sellerCount = sellerList.length;

        // triggered on a close pool action
        if (closeCall) {
            //Handle buyer adjustments for close pool
            //Collateral Covered set to 0 
            for (uint256 i = 0; i < buyerCount; i++) {
                address _address = buyerList[i];
                buyers[_address].collateralCovered = 0;
            }

            collateralCovered_Total = 0;

            //Handle seller adjustments for maturity
            //All collateral made available to depositors
            //Automatically rolled over
            for (uint256 i = 0; i < sellerCount; i++) {
                address _address = sellerList[i];
                sellers[_address].availableCollateral += 
                   sellers[_address].lockedCollateral;
                sellers[_address].lockedCollateral = 0;
            }

            availableCollateral_Total += lockedCollateral_Total;
            lockedCollateral_Total = 0;

            paused = true;
            closed = true;

        //Triggers in default event only
        } else if (defaulted) {
            //Handle buyer adjustments for default
            //buyers can now claim their covered collateral
            //Collateral Covered set to 0 


            for (uint256 i = 0; i < buyerCount; i++) {
                address _address = buyerList[i];
                buyers[_address].claimableCollateral +=  buyers[_address].collateralCovered;
                buyers[_address].collateralCovered -= 0;
            }

            claimableCollateral_Total += collateralCovered_Total;
            collateralCovered_Total = 0;

            //Handle seller adjustments for default
            //Seller locked collateral set to 0
            //Deposited collateral reduced for locked collateral
            //Available collateral is rolled forward for next epoch
            //user can still withdraw even when paused.
            for (uint256 i = 0; i < sellerCount; i++) {
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
            for (uint256 i = 0; i < buyerCount; i++) {
                address _address = buyerList[i];
                buyers[_address].collateralCovered = 0;
                buyers[_address].premiumPaid = 0;
            }

            collateralCovered_Total = 0;
            premiumPaid_Total = 0;

            //Handle seller adjustments for maturity
            //All collateral made available to depositors
            //Automatically rolled over
            for (uint256 i = 0; i < sellerCount; i++) {
                address _address = sellerList[i];
                sellers[_address].availableCollateral += 
                   sellers[_address].lockedCollateral;
                sellers[_address].lockedCollateral = 0;
            }

            availableCollateral_Total += lockedCollateral_Total;
            lockedCollateral_Total = 0;

            uint256 x = epochDays * 86400;

            maturityDate += x; 

            _rollEpoch(maturityDate);
        }

    }


    function exercuteRWA(uint256 percentage) internal {
         require(!paused, "Contract is paused");

        bool matured = block.timestamp >= maturityDate;
        uint256 buyerCount = buyerList.length;
        uint256 sellerCount = sellerList.length;

         //Handle buyer adjustments for default
            //buyers can now claim their covered collateral
            //Collateral Covered set to 0 


            for (uint256 i = 0; i < buyerCount; i++) {
                address _address = buyerList[i];
                 uint amount = buyers[_address].collateralCovered * percentage;
                buyers[_address].claimableCollateral += amount;
                buyers[_address].collateralCovered -= amount;
            }

            claimableCollateral_Total += collateralCovered_Total;
            collateralCovered_Total = 0;

            //Handle seller adjustments for default
            //Seller locked collateral set to 0
            //Deposited collateral reduced for locked collateral
            //Available collateral is rolled forward for next epoch
            //user can still withdraw even when paused.
            for (uint256 i = 0; i < sellerCount; i++) {
                address _address = sellerList[i];
                sellers[_address].depositedCollateral -= sellers[_address].lockedCollateral; 
                sellers[_address].lockedCollateral = 0;
            }

            depositedCollateral_Total -= lockedCollateral_Total;
            lockedCollateral_Total = 0;
            
            //Pauses contract until reset
            paused = false;
    }

    /// @notice Provides a means to maintain running voter reserve balance when paying voter fees on the voting contract
    /// @dev Should ensure every call from {Voting} reverts if it tries to pay out more than the reserve amount left.
    /// @param _amount intended amount to deduct from the reserve
    function deductFromVoterReserve(uint256 _amount) external {
        if(msg.sender != votingContract) revert("Unauthorized");
        if (_amount > totalVoterFeeRemaining) revert("Not sufficient deductible");
        totalVoterFeeRemaining -= _amount;
    }

    /// @notice Withdraw from the treasury rewards reserve paid at purchases
    /// @param _amount intended amount to deduct from the reserve
    /// @param _recipient address to which the withdrawn amount should be sent
    function withdrawFromBalance(uint256 _amount, address _recipient) external {
        if(msg.sender != controller) revert("Unauthorized");

        uint256 actualAmountSent = _transferTo(_amount, _recipient);
        emit WithdrawFromBalance(_recipient, _amount, actualAmountSent);
    }

    function setDefaulted(bool _defaulted, uint256 percentage) external {
        // if(msg.sender != votingContract) revert("Unauthorized");
        require(!defaulted, "Contract already defaulted");
        defaulted = _defaulted;
        paused = false;
        execute(false);
    }


    function pause() external validCaller {
        paused = true;
    }

    function unpause() external validCaller {
        require(!defaulted, "Contract has defaulted, use default reset");
        paused = false;
        execute(false);
    }
    
    
    function resetAfterDefault(uint256 _newMaturityDate) external {
        require(msg.sender == controller, "Unauthorized");
        require(defaulted, "Not defaulted");

        defaulted = false;
        paused = false;
        _rollEpoch(_newMaturityDate);

    }

    /// @notice Close a pool to not be used anymore, refunding all locked collaterals to the sellers to be withdrawn
    function closePool() external {
        require(msg.sender == controller, "Unauthorized");

        execute(true);
    }

    function rollEpoch() external {
        require(msg.sender == controller, "Unauthorized");
        require(block.timestamp >= maturityDate, "Maturity Date not yet reached");
        execute(false);
    }
    
    //Epoch Vairable Handlers
    function _rollEpoch(uint256 _newMaturityDate) internal {

        maturityDate = _newMaturityDate;
        epoch ++;

    }
    

    function _transferFrom(uint256 _amount) internal returns (uint256 actualTransferAmount) {
        uint256 previousBalanceOfContract = currency.balanceOf(address(this));

        currency.safeTransferFrom(
            msg.sender,
            address(this),
            _amount
        );

        uint256 finalBalanceOfContract = currency.balanceOf(address(this));
        actualTransferAmount = finalBalanceOfContract - previousBalanceOfContract;
    }

    function _transferTo(uint256 _amount, address _user) internal returns (uint256 actualTransferAmount) {
        uint256 previousBalanceOfReceiver = currency.balanceOf(_user);
        currency.safeTransfer(_user, _amount);

        uint256 finalBalanceOfReceiver = currency.balanceOf(_user);
        actualTransferAmount = finalBalanceOfReceiver - previousBalanceOfReceiver;
    }

    function isPaused() public view returns (bool) {
        return paused;
    }

    function getPoolData(address _user) public view returns (PoolData memory poolData) {

        SellerData memory sellerData = sellers[_user];
        BuyerData memory buyerData = buyers[_user];

        bool isSeller = onSellerList[_user];
        bool isBuyer = onBuyerList[_user];

        UserPoolData memory userData = UserPoolData(
            isSeller
            , isBuyer
            , sellerData
            , buyerData
        );

        poolData = PoolData(
            entityName
            , address(this)
            , closed ? "Closed" : defaulted ? "Defaulted" : paused ? "Paused" : "Current"
            , address(currency)
            , premium
            , makerFee
            , maturityDate
            , epoch
            , epochDays
            , totalVoterFeePaid
            , totalVoterFeeRemaining
            , depositedCollateral_Total
            , availableCollateral_Total
            , lockedCollateral_Total
            , premiumPaid_Total
            , unclaimedPremium_Total
            , collateralCovered_Total
            , claimableCollateral_Total
            , userData
        );
    }

}
