// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./Voting.sol";
import "./interfaces/IOracle.sol";

contract CXDefaultSwap {

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

    uint256 public depositedCollateralTotal;
    uint256 public availableCollateralTotal;
    uint256 public premiumPaidTotal;
    uint256 public unclaimedPremiumTotal;
    uint256 public collateralCoveredTotal;
    uint256 public claimableCollateralTotal;

    uint256 public globalShareDeposit;
    //Premium price in bps
    uint256 public immutable premium;
    uint256 public immutable makerFee;
    uint256 public immutable maxSellerCount;
    uint256 public immutable maxBuyerCount;
    uint256 public constant basisPoints = 10000;

    //Pause boolean (for after default event)
    bool private paused;
    bool public closed;
    bool public defaulted;
    bool public isVoterDefaulting;
        
    mapping (uint256=>uint256) public globalShareLock;

    //Seller Data
    struct SellerData {

        uint256 userShareDeposit;
        mapping (uint256=>uint256) userShareLock;
        mapping (uint256=>bool) interactedThisEpoch;

    }

    //Buyer Data
    struct BuyerData {
        uint historicalPremiumPaid;
        mapping (uint256=> uint256) premiumPaid;
        mapping (uint256=> uint256) collateralCovered;
        mapping (uint256=> uint256) claimableCollateral;
    }

    mapping (address=>SellerData) public sellers;
    mapping (address=>BuyerData) public buyers;

    // _actualDepositedAmount would be less than _amount in event that the ERC20 token deposited implements fee on transfer
    event Deposit(address indexed _seller, uint256 _amount, uint256 _actualdepositedAmount);
    event Withdraw(address indexed _seller, uint256 _amount, uint256 _actualwithdrawAmount);
    event PurchaseCollateral(address indexed _buyer, uint256 _amount, uint256 _actualPurchasedAmount, uint256 premiumPaid, uint256 _makerFeePaid);
    event ClaimPremium(address indexed _seller, uint256 _amount, uint256 _actualTransferAmount);
    event ClaimCollateral(address indexed _buyer, uint256 _amount, uint256 _actualPurchasedAmount);
    event WithdrawFromBalance(address _recipient, uint256 _amount, uint256 _actualAmountReceived);
    event RollEpoch(address caller, uint256 newMaturityDate, uint256 newEpoch);
    event SetDefaulted(address caller, uint256 percentageDefaulted);
    event ResetAfterDefault(address caller);
    event PausePool(address caller);
    event UnPausePool(address caller);

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
    /// @param _isVoterDefaulting determines if the pool can be defaulted via a voter consensus or by the admin
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
        bool _isVoterDefaulting
    ) {
        require(_votingContract.isContract() && _oracle.isContract() && _currency.isContract(), 
        "Address supplied for Voting, Currency, or Oracle, contract is invalid");
        require(_initialMaturityDate > block.timestamp, "Invalid Maturity Date set");
        require(_premium < basisPoints && _makerFee < basisPoints, "Premium, and maker fee, can not be 100% or above");
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
        controller = msg.sender;
        isVoterDefaulting = _isVoterDefaulting;
    }

    modifier validCaller {
        if(msg.sender != controller && msg.sender != votingContract) revert("Unauthorized");
        _;
    }
    
    /// @notice Allows intending seller to sell specified amount of collateral. Sellers can always add to previous sold amount.
    /// @dev the actualTransferAmount implementation is considering the event where the ERC20 token for the pool implements fee on transfer
    /// @param _amount intended collateral amount to sell
    /// NOTE: The eventual deposited collateral may not match the value of _amount, if the token implements fee on transfer
    function deposit(uint256 _amount) public {

        require(!paused,"Contract Paused");
        require(!closed,"Pool closed");
        
        uint256 actualTransferAmount = _transferFrom(_amount);

        //Check if previous interaction to roll deposit share into lock share
        bool notInteracted = !sellers[msg.sender].interactedThisEpoch[epoch];
        bool notZeroDeposit =  sellers[msg.sender].userShareDeposit != 0;

        if(notInteracted && notZeroDeposit){

            //If the seller is interacting for the first time in this epoch add his collateral share balance to his ShareLock
            sellers[msg.sender].userShareLock[epoch] = sellers[msg.sender].userShareDeposit;
        
        }
        
        //Handle the Deposit share changes
        uint256 userShareDepositChange;

        if (globalShareDeposit == 0 || depositedCollateralTotal == 0){

            userShareDepositChange = actualTransferAmount;

        }else{

            userShareDepositChange = globalShareDeposit * actualTransferAmount / depositedCollateralTotal;

        }

        //Increase userShareDeposit Ratio variables
        sellers[msg.sender].userShareDeposit += userShareDepositChange;
        globalShareDeposit += userShareDepositChange;

        //Handle the Lock Share changes
        uint256 userShareLockChange;
        
        if (globalShareLock[epoch]==0 || depositedCollateralTotal == 0){

            userShareLockChange = actualTransferAmount;

        }else{

            userShareLockChange = globalShareLock[epoch] * actualTransferAmount / availableCollateralTotal;

        }

        //Increase userShareLock Ratio variables
        sellers[msg.sender].userShareLock[epoch] += userShareLockChange;        
        globalShareLock[epoch] += userShareLockChange;

        //Set boolean to true for deposited this epoch
        sellers[msg.sender].interactedThisEpoch[epoch] = true;


        //Increase Deposited collateral and Available Collateral totals post the calculations
        depositedCollateralTotal += actualTransferAmount;
        availableCollateralTotal += actualTransferAmount;

        emit Deposit(msg.sender, _amount, actualTransferAmount);
    }

    /// @notice Allows intending buyer to purchase a specified amount of collateral, paying a premium and protocol fee, and locking the purchased amount from the sellers.
    /// @dev Call to execute must be done to validate actual balances before proceeding with purchase
    /// @param _amount intended amount of collateral to purchase
    function purchase(uint256 _amount) public {

        require(_amount <= availableCollateralTotal, "Not enough to sell");

        //Don't allow deposits during Pause after default event
        require(!paused,"Contract Paused");
        require(!closed,"Pool closed");
        
        uint256 makerFeePayable = (_amount * makerFee) / basisPoints;
        
        uint256 premiumPayable = (_amount * premium) / basisPoints;

        uint256 totalPayable = makerFeePayable + premiumPayable;

        uint256 actualTransferAmount = _transferFrom(totalPayable);

        //backpropagate the actualTransferAmount in the event that there was a fee on transfer, and get actual makerFeePaid & premium & collateral
        uint256 makerFeePaid = (makerFeePayable * actualTransferAmount)/totalPayable;
        uint256 premiumPaid = actualTransferAmount - makerFeePaid;

        uint256 actualCollateralToPurchase = premiumPaid * basisPoints/premium;

        if (isVoterDefaulting) {
            uint256 voterFee = IOracle(oracleContract).getDefaultFeeAmount(makerFeePaid, address(this));
            uint256 actualVotingFeeSent = _transferTo(voterFee, votingContract);
            totalVoterFeePaid += actualVotingFeeSent;
            totalVoterFeeRemaining += actualVotingFeeSent;
        }
        
        depositedCollateralTotal += premiumPaid;
        premiumPaidTotal += premiumPaid;

        collateralCoveredTotal += actualCollateralToPurchase;

        availableCollateralTotal -= (actualCollateralToPurchase - premiumPaid);

        buyers[msg.sender].premiumPaid[epoch] += premiumPaid;
        buyers[msg.sender].collateralCovered[epoch] += actualCollateralToPurchase;
        emit PurchaseCollateral(msg.sender, _amount, actualCollateralToPurchase, premiumPaid, makerFeePaid);
    }

    /// @notice Allows existing seller to withdraw collateral available to them. Locked collateral can not be withdrawn.
    /// @dev Call to execute must be done to validate actual balances before proceeding with withdraw
    /// @param _amount intended amount of collateral to withdraw
    function withdraw(uint256 _amount) public {

        uint256 depositedCollateral = calculateDespositedCollateralUser(msg.sender);
        uint256 availableCollateral = calculateAvailableCollateralUser(msg.sender);  

        require(_amount<= availableCollateral, "Not enough available");
        require(availableCollateral>0, "Nothing Deposited");

        //Check if previous interaction to roll deposit share into lock share
        bool notInteracted = !sellers[msg.sender].interactedThisEpoch[epoch];
        bool notZeroDeposit =  sellers[msg.sender].userShareDeposit != 0;

        
        if(notInteracted && notZeroDeposit){

            //If the seller is interacting for the first time in this epoch add his collateral share balance to his ShareLock
            sellers[msg.sender].userShareLock[epoch] = sellers[msg.sender].userShareDeposit ;
        
        }

        //Calculate reduction in userShareDeposit
        uint256 userShareDepositChange =  sellers[msg.sender].userShareDeposit * _amount / depositedCollateral;

        sellers[msg.sender].userShareDeposit -= userShareDepositChange;
        globalShareDeposit -= userShareDepositChange;

        //Calculate reduction in userShareLock
        uint256 userShareLockChange = sellers[msg.sender].userShareLock[epoch] * _amount / availableCollateral;

        sellers[msg.sender].userShareLock[epoch] -= userShareLockChange;
        globalShareLock[epoch] -= userShareLockChange;


        //Set boolean to true for deposited this epoch
        sellers[msg.sender].interactedThisEpoch[epoch] = true;


        //Increase Deposited collateral and Available Collateral totals post the calculations
        depositedCollateralTotal -= _amount;
        availableCollateralTotal -= _amount;

        uint256 actualTransferAmount = _transferTo(_amount, msg.sender);
        emit Withdraw(msg.sender, _amount, actualTransferAmount);

    }

    /// @notice Allows existing buyer to claim collateral locked in the event of a default
    function claimcollateral() public {
        uint256 payableAmount = buyers[msg.sender].collateralCovered[epoch];
        claimableCollateralTotal -= payableAmount;
        buyers[msg.sender].collateralCovered[epoch] = 0;

        uint256 actualTransfer = _transferTo(payableAmount, msg.sender);
        emit ClaimCollateral(msg.sender, payableAmount, actualTransfer);

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

    //Go next period
    function rollEpoch() public {
        require(msg.sender == controller, "Unauthorized");
        require(block.timestamp >= maturityDate, "Maturity Date not yet reached");

        _rollEpoch(false);
        emit RollEpoch(msg.sender, maturityDate, epoch);
    }

    function setDefaulted(uint256 percentageDefaulted) external validCaller {
        
        claimableCollateralTotal = collateralCoveredTotal * percentageDefaulted/basisPoints;
        depositedCollateralTotal -= claimableCollateralTotal;
        collateralCoveredTotal -= claimableCollateralTotal;

        if (percentageDefaulted == basisPoints) {
            defaulted = true;
            paused = true;
        }
        emit SetDefaulted(msg.sender, percentageDefaulted);
    }

    function pause() external validCaller {
        paused = true;
        emit PausePool(msg.sender);
    }

    function unpause() external validCaller {
        require(!defaulted, "Contract has defaulted, use default reset");

        paused = false;
        emit UnPausePool(msg.sender);
    }
    
    
    function resetAfterDefault() external {
        require(msg.sender == controller, "Unauthorized");
        require(defaulted, "Not defaulted");

        defaulted = false;
        paused = false;
        _rollEpoch(true);
        emit ResetAfterDefault(msg.sender);
    }

    function _rollEpoch(bool afterDefault) internal {
        
        maturityDate = afterDefault ? block.timestamp : maturityDate + (epochDays * 86400);
        epoch ++;
        collateralCoveredTotal = 0;
        availableCollateralTotal = depositedCollateralTotal;
        globalShareLock[epoch] = globalShareDeposit;
        defaulted = false;

        if(isVoterDefaulting) Voting(votingContract).payRecurringVoterFee();
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

 
    //Functions to calculate all relevant variables without loops
    function calculateDespositedCollateralUser(address _address) public view returns (uint256 userCollateral){
        userCollateral = depositedCollateralTotal * sellers[_address].userShareDeposit / globalShareDeposit;
    }

    function calculateAvailableCollateralUser(address _address) public view returns (uint256 availableCollateralUser){
        if(sellers[_address].interactedThisEpoch[epoch]){
            //Calculate on Share Lock Ratio for this user
            availableCollateralUser = availableCollateralTotal * sellers[_address].userShareLock[epoch] / globalShareLock[epoch];

        }else{
            //Calculate on Deposit share ratio
            availableCollateralUser = availableCollateralTotal * sellers[_address].userShareDeposit / globalShareLock[epoch];
        }
    }

    function calculateLockedCollateralUser(address _address) public view returns (uint256 lockedCollateralUser){
        lockedCollateralUser = calculateDespositedCollateralUser(_address) - calculateAvailableCollateralUser(_address) ;
    }

    function getInteractedThisEpoch(address _address) public view returns (bool interacted){
        interacted = sellers[_address].interactedThisEpoch[epoch];
    }

}