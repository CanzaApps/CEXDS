//SPDX-License-Identifier: Unlicensed
pragma solidity ^0.8.18;
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";

contract poolContract {

    uint256 public liquidationPercentage;
    address public currency;

    uint256 basisPoints = 10000;
    
    mapping (address=>uint256) public depositUser;
    mapping (address=>uint256) public claimeableUser;

    uint256 public claimableTotal;
    uint256 public depositTotal;
    
    address[] public users;
    mapping (address=>bool) public onUserList;
    
    address controllerAddress;


    constructor (uint256 _liquidationPercentage, address _currency){

        liquidationPercentage = _liquidationPercentage;
        currency = _currency;
        controllerAddress = msg.sender;

    }

    function deposit(uint256 _amount) public payable{

        _transferFrom(_amount);

        depositUser[msg.sender] += _amount;
        depositTotal += _amount;

        if(!onUserList[msg.sender]){

            users.push(msg.sender);
            onUserList[msg.sender] = true;

        }

    }

    function withdraw(uint256 _amount) public {

        require(_amount <= depositUser[msg.sender], "Not enough deposit");
        _transferTo(_amount, msg.sender);

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
    function claimDeposits(uint256 _amountToLiquidate) public{

        require(msg.sender == controllerAddress, "Not Controller");
        require(_amountToLiquidate <= depositTotal, "Trying to Over Liquidate");

        _amountToLiquidate = Math.min(_amountToLiquidate, depositTotal);
        
        _transferTo(_amountToLiquidate, msg.sender);
 

    }


    //@DEV-TODO: Needs only owner lock
    function sendCollateral(uint256 _amountToLiquidate) public payable {
    
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
        } 
        

    }

    function claimRewards() public {

        uint256 claimAmount = claimeableUser[msg.sender];
        _transferTo(claimAmount, msg.sender);
        
        claimableTotal -= claimAmount;
        claimeableUser[msg.sender] = 0;

    }

    function _transferFrom(uint256 _amount) internal {
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

    function _transferTo (uint256 _amount, address _user) internal {
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
        address[] poolAddress;
    }
    
    mapping (uint256=>auctionData) public openAuctions;

    function createAuction (uint256 _liquidationPercentageInterval, uint256 _intervals, address _currency) public {

        uint256 liquidationPercentage;
        openAuctions[auctionId].intervals = _intervals;

        for (uint256 i = 1; i < _intervals + 1 ; i++){

            liquidationPercentage = _liquidationPercentageInterval * i;

            auctionPool = new poolContract (liquidationPercentage, _currency);

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
            
            activeContract.claimDeposits(x);

            //This is where it would call liquidation function and send deposit

            address currency = activeContract.currency();
            _transferTo(payout, _address, currency);

            activeContract.sendCollateral(x);

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
