// SPDX-License-Identifier: MIT

/**
 * NOTE
 * Always do additions first
 * Check if the substracting value is greater than or less than the added values i.e check for a negative result
 */

pragma solidity ^0.8.17;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./libraries/WadRayMath.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";


contract cashSwaps {
    
    //False == Fixed Rate; True == Floating
    bool public buyerFloating;
    bool public sellerFloating;

    //Active Rate for each leg
    // For variable leg, we will need to trigger oracle. For fixed leg we will use the value from the initialization
    uint256 public buyerRate;
    uint256 public sellerRate;

    //Notional Balance for transaction (only supports single side)
    //TO-DO: Build logic for multiple notional balances 
    uint256 public notionalBalance;

    //Set Required margin amount
    uint256 public buffer;
    uint256 public margin;

    //Set Buyer & Seller
    address public buyer;
    address public seller;
    address public deployer;

    //ERC-20 Address for settlment asset
    address public strikeAsset;

    //Check that users have deposited
    mapping(address=>bool) public deposited;

    //Contract active boolean, for when both parties have deposited assets
    bool public contractActive;

    event Deposit(
        address indexed _depositor,
        address indexed _strikeAsset,
        uint256 _amount
    );

    event Exectuted(
        address indexed _buyer,
        address indexed _seller,
        address indexed _strikeAsset,
        uint256 _buyerPayout,
        uint256 _sellerPayout,
        uint256 _buyerExcessReturned,
        uint256 _sellerExcessReturned
    );

    constructor (bool _buyerFloating, 
                bool _sellerFloating, 
                uint256 _buyerFixedRate,  
                uint256 _sellerFixedRate, 
                uint256 _notionalBalance,
                uint256 _buffer,
                address _buyer,
                address _seller,
                address _strikeAsset){
        
        //Set up fixed or floating rates for buyer leg
        buyerFloating = _buyerFloating;
        if (!buyerFloating){
            buyerRate = _buyerFixedRate;
        }else{
            //TO-DO Call Oracle
            buyerRate = setBuyerRate(10000);
        }

        //Set up fixedor floating rates for seller leg
        sellerFloating = _sellerFloating;
        if(!sellerFloating){
            sellerRate = _sellerFixedRate;
        }else{
            //TO-DO Call Oracle
            sellerRate = setSellerRate(5000);
        }

        //Set up notional amount and margin requirement
        notionalBalance = _notionalBalance;
        buffer = _buffer;
        margin = notionalBalance * buffer / 10e5;
        
        //Identify who is the buyer and who is the seller of the asset
        buyer = _buyer;
        seller = _seller;
        deployer = msg.sender;

        //Identify the strike asset for the transactions
        strikeAsset = _strikeAsset;

    }

    function deposit() public payable{

        //Require depositor to be either buyer or seller
        require(msg.sender == buyer || msg.sender == seller, "Sender is neither buyer or seller");

        //Require that depositor has deposited        
        require(!deposited[msg.sender], "You have already depsoited");

        //Require that contract is not active
        require(!contractActive, "Contract is active");
        
        _transferFrom(margin);

        //Activates the contract if both buyer and seller has deposited
        deposited[msg.sender] = true;
        contractActive = deposited[buyer] && deposited[seller];

        emit Deposit(msg.sender, strikeAsset, margin);    
    }   

    function executeContract() public payable{

        require(contractActive, "Contract is not Active");

        //Calculate the payout value
        uint256 buyerPayout = calculatePayout(true);
        uint256 sellerPayout = calculatePayout(false);

        //Calculate the transfer value to buyer including the remaining margin
        uint256 buyerRemainingMargin = margin - sellerPayout;
        uint256 buyerTransfer = buyerRemainingMargin + buyerPayout;
        _transferTo(buyerTransfer, buyer);

        //Calculate the transfer value to seller including the remaining margin
        uint256 sellerRemainingMargin = margin - buyerPayout;
        uint256 sellerTransfer = sellerRemainingMargin + sellerPayout;
        _transferTo(sellerTransfer, seller);

        emit Exectuted(buyer, seller, strikeAsset, buyerPayout, sellerPayout, buyerRemainingMargin, sellerRemainingMargin);

        //Halt & Catch Fire
        selfdestruct(payable(deployer));

    } 
    
    function calculatePayout(bool _buyer) public view returns (uint256) {

        uint256 _buyerRate = getBuyerRate();
        uint256 _sellerRate = getSellerRate();
        uint256 _payout;

        if(_buyer){
            if(sellerRate > buyerRate){
                //Subtract buyer rate from seller rate
                _payout =  _sellerRate - _buyerRate;

                //Mutliply by notional balance to get payout value
                _payout = _payout * notionalBalance / 10e5;

                //Cap payout to the margin
                return Math.min(_payout, margin);

            }else{
                //No payout if seller rate greater than buyer rate
                return _payout = 0;
            }

        }else{
            if(buyerRate > sellerRate){
                //Subtract seller rate from buyer rate
                _payout = _buyerRate - _sellerRate;

                //Mutliply by notional balance to get payout value
                _payout = _payout * notionalBalance / 10e5;

                //Cap payout to margin
                return Math.min(_payout, margin);
            }else{
                //No payout if seller rate greater than buyer rate
                return _payout = 0;
            }
        }

    }
    
    function getBuyerRate () public view returns (uint256) {
        if(!buyerFloating){
            return buyerRate;
        }else{
            //TO-DO swap for oracle call
            return buyerRate;
        }
    }

    function getSellerRate () public view returns (uint256) {
        if(!sellerFloating){
            return sellerRate;
        }else{
            //TO-DO swap for oracle call
            return sellerRate;
        }
    }

    function setBuyerRate (uint256 _rate) public returns (uint256){
        require(buyerFloating, "Buyer Rate is Fixed");
        return buyerRate = _rate;
    }
    
    function setSellerRate (uint256 _rate) public returns (uint256){
        require(sellerFloating, "Seller Rate is Fixed");
        return sellerRate = _rate;
    }

    function _transferFrom(uint256 _amount) internal {
        require(
            IERC20(strikeAsset).balanceOf(msg.sender) >=
            _amount,
            "Insufficient balance"
        );
        
            bool transferSuccess = IERC20(strikeAsset).transferFrom(
            msg.sender,
            address(this),
            _amount
        );

        if (!transferSuccess) revert();
    }

    function _transferTo (uint256 _amount, address _user) internal {
        bool transferSuccess = IERC20(strikeAsset).transfer(
        _user,
        _amount
        );

        if (!transferSuccess) revert();

    }
}