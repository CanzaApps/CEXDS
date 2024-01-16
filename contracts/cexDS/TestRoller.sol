// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import "./RollContract.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract RollTest {
    using SafeERC20 for IERC20;
    IERC20 public immutable currency;

    address expiredPool;
    address activePool;
    address nextPool;
    address oracleAddress;

    bool paused;
    bool closed;
    bool defaulted;
    uint256 maturityDate;
    uint8 epochDays;
    uint256 epoch;
        
   //Seller Data
    struct SellerData {
        uint256 depositedCollateral;
        uint256 availableCollateral;
        uint256 lockedCollateral;
        uint256 unclaimedPremium;
    }
    //Buyer Data
    struct BuyerData {
        uint256 premiumPaid;
        uint256 collateralCovered;
        uint256 claimableCollateral;
    }
    mapping (address=>SellerData) seller; 
    mapping (address=>BuyerData) buyer;

    constructor (address _currency) {

        currency = IERC20(_currency);
    }
    
    //Deposit collateral as buyer
    function deposit(uint256 _amt) public {
        RollContract(nextPool).addDeposit(msg.sender, _amt);
    }
    //Initiate withdrawl request, removing collateral from being sold in following period
    function requestWithdraw(uint256 _amt) public {

        (,uint256 activePoolSellerAvailableCollateral,,,) = RollContract(activePool).sellers(msg.sender);

        uint256 amountToNextPool;
        if (_amt > activePoolSellerAvailableCollateral) {
            amountToNextPool = _amt - activePoolSellerAvailableCollateral;
            _amt = activePoolSellerAvailableCollateral;
        }
        (,uint256 nextPoolSellerAvailableCollateral,,,) = RollContract(nextPool).sellers(msg.sender);
        require(amountToNextPool <= nextPoolSellerAvailableCollateral, "Can not withdraw more than available");

        RollContract(activePool).addWithdrawRequest(msg.sender, _amt, true);

        RollContract(nextPool).addWithdrawRequest(msg.sender, amountToNextPool, false);
    }

    //Complete requested withdrawl process
    function confirmWithdraw(uint256 _amt) public{

        (,,,,uint256 activePoolSellerRequestedWithdrawal) = RollContract(activePool).sellers(msg.sender);
        require(_amt <= activePoolSellerRequestedWithdrawal, "Can not withdraw more than requested");

        RollContract(activePool).withdraw(msg.sender, _amt);
    }
    //Withdraw any available excess
    function instantWithdra(uint256 _amt) public {
    }
    //Purchase collateral
    function purchase(uint256 _amt) external {

        uint256 activePoolAvailableCollateral = RollContract(activePool).availableCollateralTotal();

        uint256 amountToNextPool;
        if (_amt > activePoolAvailableCollateral) {
            amountToNextPool = _amt - activePoolAvailableCollateral;
            _amt = activePoolAvailableCollateral;
        }

        RollContract(nextPool).addPurchase(msg.sender, amountToNextPool, _amt);

    }
    //Go next period
    function rollEpoch() public {

    }
    function claimPremium() external {

        (,uint256 expiredPoolSellerAvailableCollateral,,,)= RollContract(expiredPool).sellers(msg.sender);

        uint256 expiredPoolAvailableCollateralTotal = RollContract(expiredPool).availableCollateralTotal();
        uint256 expiredPoolUnclaimedPremiumTotal = RollContract(expiredPool).availableCollateralTotal();

        uint256 sellerUnclaimedPremium = (expiredPoolSellerAvailableCollateral * expiredPoolUnclaimedPremiumTotal)/expiredPoolAvailableCollateralTotal;

        _transferTo(sellerUnclaimedPremium, msg.sender);
    }

    function claimCollateral() public {
        
        (,uint256 expiredPoolBuyerCollateralCovered,)= RollContract(expiredPool).buyers(msg.sender);

        uint256 expiredPoolCollateralCoveredTotal = RollContract(expiredPool).collateralCoveredTotal();
        uint256 expiredPoolClaimableCollateralTotal = RollContract(expiredPool).claimableCollateralTotal();

        uint256 buyerClaimableCollateral = (expiredPoolBuyerCollateralCovered * expiredPoolClaimableCollateralTotal)/expiredPoolCollateralCoveredTotal;

        _transferTo(buyerClaimableCollateral, msg.sender);
    }

    function execute(bool closeCall) internal {
        //Execute contract and change variable for a default event

        require(!paused, "Contract is paused");

        bool matured = block.timestamp >= maturityDate;

        // triggered on a close pool action
        RollContract(activePool).updateOnExecute(defaulted, matured);
        if (matured) {

            uint256 x = epochDays * 86400;

            maturityDate += x; 

            _rollEpoch(maturityDate);
            _executeRoll();
        }

    }

    function _executeRoll() internal {

        uint256 activePoolDepositedCollateralTotal = RollContract(activePool).depositedCollateralTotal();
        uint256 activePoolAvailableCollateralTotal = RollContract(activePool).availableCollateralTotal();
        uint256 activePoolrequestedWithdrawalTotal = RollContract(activePool).depositedCollateralTotal();

        uint256 activePoolUnclaimedPremiumTotal = RollContract(activePool).unclaimedPremiumTotal();
        uint256 activePoolClaimableCollateralTotal = RollContract(activePool).claimableCollateralTotal();

        RollContract(nextPool).setAsActive(
            activePoolDepositedCollateralTotal
            , activePoolAvailableCollateralTotal
            , activePoolrequestedWithdrawalTotal
            , activePoolUnclaimedPremiumTotal
            , activePoolClaimableCollateralTotal
        );

        expiredPool = activePool;
        activePool = nextPool;
        RollContract nextPoolContract = new RollContract(oracleAddress);
        nextPool = address(nextPoolContract);

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

    //Epoch Vairable Handlers
    function _rollEpoch(uint256 _newMaturityDate) internal {

        maturityDate = _newMaturityDate;
        epoch ++;
    }


}