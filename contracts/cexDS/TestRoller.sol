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

    //Premium price in bps
    uint256 public premium;
    uint256 public makerFee;

    enum PoolEndState {
        Matured,
        Defaulted,
        Closed
    }
        
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
    mapping (address=>SellerData) sellers; 
    mapping (address=>BuyerData) buyers;

    struct SellerPoolData {
        address poolAddress;
        uint256 depositedCollateral;
        uint256 availableCollateral;
    }

    // tracks the activePool as of when seller or buyer initiated their last activity, so to reduce the loop interval when calculating collaterals
    // See {getSellerCollaterals} and {getBuyerCollaterals}
    mapping (address => address) sellerToLastActivityPool;
    mapping (address => address) buyerToLastActivityPool;
    mapping (address => uint256) poolToIndex;
    // Tracks what state the pool ended in after it was active. Either defaulted, matured or closed
    mapping (address => PoolEndState) poolToEndState;
    address[] public pools;


    constructor (address _currency) {

        currency = IERC20(_currency);
        RollContract nextPoolContract = new RollContract(oracleAddress, 0);
        nextPool = address(nextPoolContract);
    }
    
    //Deposit collateral as buyer
    function deposit(uint256 _amt) public {
        (
            uint256 depositedCollateral
            , uint256 availableCollateral
            , uint256 lockedCollateral
            , uint256 unclaimedPremium
            , uint256 requestedWithdrawal
        ) = getSellerCollaterals(msg.sender);

        SellerData memory newSellerInfo = SellerData(
            depositedCollateral + _amt,
            availableCollateral + _amt,
            lockedCollateral,
            unclaimedPremium,
            requestedWithdrawal
        );

        sellers[msg.sender] = newSellerInfo;
        
        RollContract(nextPool).addDeposit(msg.sender, _amt);
    }
    //Initiate withdrawl request, removing collateral from being sold in following period
    function requestWithdraw(uint256 _amt) public {

        (
            uint256 depositedCollateral
            , uint256 availableCollateral
            , uint256 lockedCollateral
            , uint256 unclaimedPremium
            , uint256 requestedWithdrawal
        ) = getSellerCollaterals(msg.sender);

        uint256 activePoolLockedCollateral = RollContract(activePool).availableCollateralTotal();

        if (_amt > lockedCollateral) revert("Unable to request above locked amount");
        uint256 amountToNextPool;
        if (_amt > activePoolLockedCollateral) {
            amountToNextPool = _amt - activePoolLockedCollateral;
            _amt = activePoolLockedCollateral;
        }

        RollContract(activePool).addWithdrawRequest(msg.sender, _amt, true);

        RollContract(nextPool).addWithdrawRequest(msg.sender, amountToNextPool, false);

        SellerData memory newSellerInfo = SellerData(
            depositedCollateral,
            availableCollateral,
            lockedCollateral,
            unclaimedPremium,
            requestedWithdrawal + _amt
        );

        sellers[msg.sender] = newSellerInfo;
        sellerToLastActivityPool[msg.sender] = activePool;
    }

    //Complete requested withdrawl process
    function confirmWithdraw(uint256 _amt) public{

        (
            uint256 depositedCollateral
            , uint256 availableCollateral
            , uint256 lockedCollateral
            , uint256 unclaimedPremium
            , uint256 requestedWithdrawal
        ) = getSellerCollaterals(msg.sender);

        // TODO: check that this is not buggy to withdraw from request on activePool and nextPool
        require(_amt <= requestedWithdrawal, "Can not confirm withdraw of value more than requested");

        RollContract(nextPool).withdraw(msg.sender, _amt);

        SellerData memory newSellerInfo = SellerData(
            depositedCollateral - _amt,
            availableCollateral - _amt,
            lockedCollateral,
            unclaimedPremium,
            requestedWithdrawal - _amt
        );

        sellers[msg.sender] = newSellerInfo;
        sellerToLastActivityPool[msg.sender] = activePool;
    }

    //Withdraw any available excess
    function instantWithdraw(uint256 _amt) public {

        (
            uint256 depositedCollateral
            , uint256 availableCollateral
            , uint256 lockedCollateral
            , uint256 unclaimedPremium
            , uint256 requestedWithdrawal
        ) = getSellerCollaterals(msg.sender);

        uint256 nextPoolAvailableCollateral = RollContract(nextPool).availableCollateralTotal();
        uint256 nextPoolRequestedWithdrawalTotal = RollContract(nextPool).requestedWithdrawalTotal();

        require(_amt <= availableCollateral || _amt > nextPoolAvailableCollateral - nextPoolRequestedWithdrawalTotal, "Withdraw amount exceeds available");

        RollContract(nextPool).withdraw(msg.sender, _amt);

        SellerData memory newSellerInfo = SellerData(
            depositedCollateral - _amt,
            availableCollateral - _amt,
            lockedCollateral,
            unclaimedPremium,
            requestedWithdrawal
        );

        sellers[msg.sender] = newSellerInfo;
        sellerToLastActivityPool[msg.sender] = activePool;
    }
    //Purchase collateral
    function purchase(uint256 _amt) external {

        (
            uint256 premiumPaid
            , uint256 collateralCovered
            , uint256 claimableCollateral
        ) = getBuyerCollaterals(msg.sender);

        uint256 nextPoolAvailableCollateral = RollContract(nextPool).availableCollateralTotal();
        uint256 nextPoolRequestedWithdrawalTotal = RollContract(nextPool).requestedWithdrawalTotal();

        if(_amt > nextPoolAvailableCollateral - nextPoolRequestedWithdrawalTotal) revert("Collateral not available for purchase");

        uint256 makerFeePayable = (_amt * makerFee) / 10000;
        
        uint256 premiumPayable = (_amt * premium) / 10000;

        uint256 totalPayable = makerFeePayable + premiumPayable;

        uint256 actualTransferAmount = _transferFrom(totalPayable);

        RollContract(nextPool).addPurchase(msg.sender, _amt, premiumPayable);
        buyerToLastActivityPool[msg.sender] = activePool;

        BuyerData memory newBuyerInfo = BuyerData(
            premiumPaid + premiumPayable,
            collateralCovered + _amt,
            claimableCollateral
        );

        buyers[msg.sender] = newBuyerInfo;

    }
    //Go next period
    function rollEpoch() public {

    }
    function claimPremium() external {

        (
            uint256 depositedCollateral
            , uint256 availableCollateral
            , uint256 lockedCollateral
            , uint256 unclaimedPremium
            , uint256 requestedWithdrawal
        ) = getSellerCollaterals(msg.sender);

        _transferTo(unclaimedPremium, msg.sender);

        SellerData memory newSellerInfo = SellerData(
            depositedCollateral,
            availableCollateral,
            lockedCollateral,
            0,
            requestedWithdrawal
        );

        sellers[msg.sender] = newSellerInfo;
        sellerToLastActivityPool[msg.sender] = activePool;
    }

    function claimCollateral() public {

        (
            uint256 premiumPaid
            , uint256 collateralCovered
            , uint256 claimableCollateral
        ) = getBuyerCollaterals(msg.sender);

        _transferTo(claimableCollateral, msg.sender);

        BuyerData memory newBuyerInfo = BuyerData(
            premiumPaid,
            collateralCovered,
            0
        );

        buyers[msg.sender] = newBuyerInfo;

        _transferTo(claimableCollateral, msg.sender);
    }

    function execute(bool closeCall) internal {
        //Execute contract and change variable for a default event

        require(!paused, "Contract is paused");

        bool matured = block.timestamp >= maturityDate;

        // triggered on a close pool action
        if (activePool != address(0)) RollContract(activePool).updateOnExecute(defaulted, matured);
        
        if (matured) {

            uint256 x = epochDays * 86400;

            maturityDate += x; 

            _rollEpoch(maturityDate);
            _executeRoll();
        }

    }

    function setDefaulted() external {
        defaulted = true;
        poolToEndState[activePool] = PoolEndState.Defaulted;

        execute(false);
    }

    function _executeRoll() internal {
        
        uint256 nextPoolExistingAvailableCollateral;
        if (activePool != address(0)) {

            uint256 activePoolDepositedCollateralTotal = RollContract(activePool).depositedCollateralTotal();
            uint256 activePoolAvailableCollateralTotal = RollContract(activePool).availableCollateralTotal();
            uint256 activePoolrequestedWithdrawalTotal = RollContract(activePool).depositedCollateralTotal();

            uint256 activePoolUnclaimedPremiumTotal = RollContract(activePool).unclaimedPremiumTotal();
            uint256 activePoolClaimableCollateralTotal = RollContract(activePool).claimableCollateralTotal();

            nextPoolExistingAvailableCollateral = RollContract(nextPool).setAsActive(
                activePoolDepositedCollateralTotal
                , activePoolrequestedWithdrawalTotal
                , activePoolUnclaimedPremiumTotal
                , activePoolClaimableCollateralTotal
            );

            // add current active pool available collateral with
            nextPoolExistingAvailableCollateral += activePoolAvailableCollateralTotal;
        } else {
            nextPoolExistingAvailableCollateral = RollContract(nextPool).setAsActive(
                0
                , 0
                , 0
                , 0
            );
        }

        expiredPool = activePool;
        activePool = nextPool;
 
        RollContract nextPoolContract = new RollContract(oracleAddress, nextPoolExistingAvailableCollateral);
        nextPool = address(nextPoolContract);
        pools.push(activePool);
        poolToIndex[activePool] = pools.length - 1;

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


    function getSellerCollaterals(address _seller) public view returns (
        uint256 depositedCollateral
        , uint256 availableCollateral
        , uint256 lockedCollateral
        , uint256 unclaimedPremium
        , uint256 requestedWithdrawal
    ) {

        uint256 activePoolLockedCollateralTotal = RollContract(activePool).lockedCollateralTotal();
        uint256 activePoolOnActiveTransferredCollateralTotal = RollContract(activePool).onActiveTransferredCollateralTotal();
        (,,,,uint256 activePoolSellerRequestedWithdrawal) = RollContract(activePool).sellers(msg.sender);

        address sellerLastParticipationPool = sellerToLastActivityPool[_seller];
        uint256 poolIndex = poolToIndex[sellerLastParticipationPool];
        SellerData memory sellerInfo = sellers[_seller];

        uint256 depositDeductions;
        for (uint256 i = poolIndex; i < pools.length; i++) {

            address pool = pools[i];
            uint256 poolPremium = RollContract(pool).premiumPaidTotal();
            uint256 poolLockedCollateral = RollContract(pool).lockedCollateralTotal();
            uint256 poolTransferredCollateral = RollContract(pool).onActiveTransferredCollateralTotal();

            // pro-rata premium calculation as ratio of seller's available collateral against total that was available before pool became active
            unclaimedPremium += (sellerInfo.availableCollateral * poolPremium)/(poolLockedCollateral + poolTransferredCollateral);
            if (poolToEndState[pool] == PoolEndState.Defaulted) 
            depositDeductions += (sellerInfo.availableCollateral * poolLockedCollateral)/(poolLockedCollateral + poolTransferredCollateral);
        }

        requestedWithdrawal = sellerInfo.requestedWithdrawal + activePoolSellerRequestedWithdrawal;
        lockedCollateral = (sellerInfo.availableCollateral * activePoolLockedCollateralTotal)
        /(activePoolLockedCollateralTotal + activePoolOnActiveTransferredCollateralTotal);
        
        depositedCollateral = sellerInfo.depositedCollateral - depositDeductions;
        availableCollateral = sellerInfo.availableCollateral - depositDeductions;
    }


    function getBuyerCollaterals(address _buyer) public view returns (
        uint256 premiumPaid
        , uint256 collateralCovered
        , uint256 claimableCollateral
    ) {

        (uint256 activePoolBuyerPremiumPaid,uint256 activePoolBuyerCollateralCovered,) = RollContract(activePool).buyers(msg.sender);
        (uint256 nextPoolBuyerPremiumPaid,uint256 nextPoolBuyerCollateralCovered,) = RollContract(nextPool).buyers(msg.sender);

        address buyerLastParticipationPool = buyerToLastActivityPool[_buyer];
        uint256 poolIndex = poolToIndex[buyerLastParticipationPool];
        BuyerData memory buyerInfo = buyers[_buyer];

        uint256 totalClaimable;
        for (uint256 i = poolIndex; i < pools.length; i++) {

            address pool = pools[i];
            (,uint256 poolBuyerCollateralCovered,) = RollContract(pool).buyers(msg.sender);
            uint256 poolClaimableCollateral = RollContract(pool).claimableCollateralTotal();
            uint256 poolCollateralCovered = RollContract(pool).collateralCoveredTotal();

            if (poolToEndState[pool] == PoolEndState.Defaulted) 
            totalClaimable += (poolBuyerCollateralCovered * poolClaimableCollateral)/(poolCollateralCovered);
        }

        claimableCollateral = buyerInfo.claimableCollateral + totalClaimable;
        premiumPaid = activePoolBuyerPremiumPaid + nextPoolBuyerPremiumPaid;
        collateralCovered = activePoolBuyerCollateralCovered + nextPoolBuyerCollateralCovered;
    }


}