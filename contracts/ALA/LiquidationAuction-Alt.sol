// SPDX-License-Identifier: MIT

//SPDX-License-Identifier: Unlicensed
pragma solidity ^0.8.18;
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";

contract poolContract {

    uint256 public liquidationPercentage;
    address public currencyDeposit;
    address public currencyLiquidation;

    uint256 basisPoints = 10000;
    
    mapping (address=>uint256) public depositUser;
    mapping (address=>uint256) public claimeableUser;

    uint256 public claimableTotal;
    uint256 public depositTotal;
    uint256 public liqudationsTotal;

    address[] public users;
    mapping (address=>bool) public onUserList;

    address controllerAddress;

    constructor (uint256 _liquidationPercentage, address _currencyDeposit, address _currencyLiquidation){

        liquidationPercentage = _liquidationPercentage;
        
        currencyDeposit = _currencyDeposit;
        currencyLiquidation = _currencyLiquidation;
        controllerAddress = msg.sender;

    }

    function deposit(uint256 _amount) public payable{

        _transferFrom(_amount, currencyDeposit);

        depositUser[msg.sender] += _amount;
        depositTotal += _amount;

        if(!onUserList[msg.sender]){

            users.push(msg.sender);
            onUserList[msg.sender] = true;

        }

    }

    function withdraw(uint256 _amount) public {

        require(_amount <= depositUser[msg.sender], "Not enough deposit");
        _transferTo(_amount, msg.sender, currencyDeposit);

        depositUser[msg.sender] -= _amount;
        depositTotal -= _amount;

    }


    function calculatePayout(uint256 _amountToLiquidate) public view returns  (uint256){

        uint256 amountToLiquidate = Math.min(_amountToLiquidate, depositTotal);
        uint256 payout  = amountToLiquidate * liquidationPercentage / basisPoints;
        payout += amountToLiquidate;

        return payout;

    }
    
    
    //@DEV-TODO needs only owner lock
    function releaseDeposits(uint256 _amountToLiquidate) public{

        require(msg.sender == controllerAddress, "Not Controller");
        require(_amountToLiquidate <= depositTotal, "Trying to Over Liquidate");

        _amountToLiquidate = Math.min(_amountToLiquidate, depositTotal);
        
        _transferTo(_amountToLiquidate, msg.sender, currencyDeposit);
 
    }


    //@DEV-TODO: Needs only owner lock
    function payCollateral(uint256 _amountToLiquidate) public payable {
    
        require(msg.sender == controllerAddress, "Not Controller");
        if(depositTotal != 0){

            uint256 payout = calculatePayout(_amountToLiquidate);

            for (uint256 i = 0; i < users.length; i++){

                address userAddress = users[i];

                uint256 y = payout * depositUser[userAddress] * 1000 / depositTotal;
                y = y / 1000;
                claimeableUser[userAddress] += y;

                uint256 x = _amountToLiquidate * depositUser[userAddress] * 1000 / depositTotal;
                x = x / 1000;
                depositUser[userAddress] -= x;

            }

            depositTotal -= _amountToLiquidate;
            claimableTotal += payout;
            liqudationsTotal += payout;
        } 
        

    }

    function claimRewards() public {

        uint256 claimAmount = claimeableUser[msg.sender];
        _transferTo(claimAmount, msg.sender, currencyLiquidation);
        
        claimableTotal -= claimAmount;
        claimeableUser[msg.sender] = 0;

    }


    function _transferFrom(uint256 _amount, address _currency) internal {
        address currency = _currency;
        
        require(
            IERC20(currency).balanceOf(msg.sender) >=
            _amount,
            "Insufficient balance"
        );
        
            bool transferSuccess = IERC20(currency).transferFrom(
            msg.sender,
            address(this),
            _amount
        );

        if (!transferSuccess) revert();
    }

    function _transferTo (uint256 _amount, address _user, address _currency) internal {
        address currency = _currency;
        
        require(
            IERC20(currency).balanceOf(address(this)) >=
            _amount,
            "Insufficient Balance"
        );
        bool transferSuccess = IERC20(currency).transfer(
        _user,
        _amount
        );

        if (!transferSuccess) revert();

    }

}

contract Controller{

    poolContract public auctionPool;
    uint256 public auctionId;
    address[] public deployments;

    struct auctionData{
        uint256 intervals;
        uint256 percentageInterval;
        address currencyDeposit;
        address currencyLiquidation;
        address[] poolAddress;
    }
    
    mapping (uint256=>auctionData) public openAuctions;

    function createAuction (uint256 _liquidationPercentageInterval, uint256 _intervals, address _currencyDeposit, address _currencyLiquidation) public {

        uint256 liquidationPercentage;
        openAuctions[auctionId].intervals = _intervals;
        openAuctions[auctionId].percentageInterval = _liquidationPercentageInterval;
        openAuctions[auctionId].currencyDeposit = _currencyDeposit;
        openAuctions[auctionId].currencyLiquidation = _currencyLiquidation;

        for (uint256 i = 1; i < _intervals + 1 ; i++){

            liquidationPercentage = _liquidationPercentageInterval * i;

            auctionPool = new poolContract (liquidationPercentage, _currencyDeposit, _currencyLiquidation);

            address contractAddress = address(auctionPool);
            openAuctions[auctionId].poolAddress.push(contractAddress);

            deployments.push(address(auctionPool));

        }

        auctionId++;
    
    }

    //Needs a liquidation function to trigger liquidation
    //Needs to check totals in each pool, ensure that there is enough to liquidate
    //Needs to get required payout from each pool
    //Subtract from running balance (remaining to liquidate)
    //Loop until done

    function liquidate(uint256 _amountToLiquidate, uint256 _auctionId) public {

        poolContract activeContract;


        uint256 runningBalance  = _amountToLiquidate;
        uint256 auctionIntervals = openAuctions[_auctionId].intervals;
        uint256 i;

        do{
                
            address _address = openAuctions[_auctionId].poolAddress[i];
            activeContract = poolContract(_address);

            uint256 depositTotal = activeContract.depositTotal();

            uint256 x = Math.min(depositTotal, runningBalance);

            uint256 payout = activeContract.calculatePayout(x); 
            
            activeContract.releaseDeposits(x);

            //This is where it would call liquidation function and send deposit

            address currency = activeContract.currencyLiquidation();
            _transferTo(payout, _address, currency);

            activeContract.payCollateral(x);

            runningBalance -= x;

            i++;

        }while(runningBalance > 0 && i < auctionIntervals);  
    
    } 

    function getPoolAddress(uint256 _loanId) public view returns (address[] memory){

        return openAuctions[_loanId].poolAddress;

    }

      function getdeploymentList() public view returns (address[] memory){

        return deployments;

    }

    function getAuctionDetails(uint256 _auctionId) public view returns (auctionData memory){

        return openAuctions[_auctionId];
        
    }

    function calculatePotentialPayout(uint256 _amountToLiquidate, uint256 _auctionId) public view returns (uint256 payout){

        poolContract activeContract;
        uint256 runningBalance  = _amountToLiquidate;
        uint256 auctionIntervals = openAuctions[_auctionId].intervals;
        uint256 i;
        uint256 potentialPayout;

        do{
                
            address _address = openAuctions[_auctionId].poolAddress[i];
            activeContract = poolContract(_address);

            uint256 depositTotal = activeContract.depositTotal();

            uint256 x = Math.min(depositTotal, runningBalance);

            potentialPayout += activeContract.calculatePayout(x); 

        }while(runningBalance > 0 && i < auctionIntervals);

        return potentialPayout;
    
    
    
    }

        function _transferFrom(uint256 _amount, address _currency) internal {
        require(
            IERC20(_currency).balanceOf(msg.sender) >=
            _amount,
            "Insufficient balance"
        );
        
            bool transferSuccess = IERC20(_currency).transferFrom(
            msg.sender,
            address(this),
            _amount
        );

        if (!transferSuccess) revert();
    }

    function _transferTo (uint256 _amount, address _user, address _currency) internal {
        require(
            IERC20(_currency).balanceOf(address(this)) >=
            _amount,
            "Insufficient Balance"
        );
        
        bool transferSuccess = IERC20(_currency).transfer(
        _user,
        _amount
        );

        if (!transferSuccess) revert();

    }

}
