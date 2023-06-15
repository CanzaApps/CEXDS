// SPDX-License-Identifier: MIT

/**
 * NOTE
 * Always do additions first
 * Check if the substracting value is greater than or less than the added values i.e check for a negative result
 */

pragma solidity ^0.8.18;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";

contract CurrencySwap {
    
    //Strike Price is the agreed price they buyer pays to the seller.
    uint256 public strikePrice; 
    
    //Actual Actual price at settlment date 
    uint256 public actualPrice;

    //Notional Balance * marginPercent = marginValue 
    uint256 public notionalBalance;
    uint256 public marginPercent;
    uint256 public marginValue;

    //Set Buyer & Seller
    //If the Actual Rate > Strike Price, the seller pays the buyer
    //If the Actual Rate < Strike Price, the buyer pays the seller 
    
    address public buyer;
    address public seller;
    address public deployerAddress;

    address public payee;

    //Margin Account Balances
    //mapping(address=>uint256) public marginAccountBalance;

    //Inputted Parameters for User
    struct UserInput{
        //Check that users have deposited
        bool deposited;

        //Track margin account balance
        uint256 marginAccountBalance;

        //Variables for Price agreement mechanism
        bool hasInputedPrice;
        uint256 inputPriceValue;
    }

    mapping (address=>UserInput) public user;

    //ERC-20 Address for settlment asset
    address public strikeAsset;
    
    //Expiry Date
    uint256 expiry;

    //Contract active boolean, for when both parties have deposited assets
    bool public contractActive;

    //Contract executed boolean
    bool public contractExecuted;

    //Boolean for when both parties have agreed on price and the contract can be executed
    bool public priceAgreed;

    event Deposit(
        address indexed _depositor,
        address indexed _strikeAsset,
        uint256 _amount
    );

    event Exectuted(
        address indexed _buyer,
        address indexed _seller,
        address indexed _strikeAsset,
        uint256 _payout,
        uint256 _buyerMarginBalance,
        uint256 _sellerMarginBalance
    );


    //Creates contract with contract parameters
    constructor ( 
                uint256 _notionalBalance,
                uint256 _marginPercent,
                address _buyer,
                address _seller,
                address _strikeAsset,
                uint256 _strikePrice,
                uint256 _daysToExpiry){
        
        //Set up notional amount and margin requirement
        notionalBalance = _notionalBalance;
        marginPercent = _marginPercent;
        marginValue = notionalBalance * marginPercent / 10e4;
        
        //Identify who is the buyer and who is the seller of the asset
        buyer = _buyer;
        seller = _seller;
        deployerAddress = msg.sender;

        //Identify the strike asset for the transactions
        strikeAsset = _strikeAsset;

        //Set Strike Price
        strikePrice = _strikePrice;

        expiry = block.timestamp + _daysToExpiry*60*24 ;

    }

    function deposit() public payable{

        
        require(!contractExecuted, "Contract has been executed");
        
        //Require depositor to be either buyer or seller
        require(msg.sender == buyer || msg.sender == seller);

        //Require that depositor has deposited
        require(!user[msg.sender].deposited, "You have already deposited");

        //Require that contract is not active
        require(!contractActive, "Contract is active");
        
        _transferFrom(marginValue);

        user[msg.sender].marginAccountBalance += marginValue;
        
        //Activates the contract if both buyer and seller has deposited
        user[msg.sender].deposited = true;
        contractActive = user[buyer].deposited && user[seller].deposited;

        emit Deposit(msg.sender, strikeAsset, marginValue);    
    }   

    function executeContract() public payable{

        require(!contractExecuted, "Contract has been executed");
        
        require(contractActive, "Contract is not Active");

        require(block.timestamp >= expiry, "Contract Has not expired");

        require(agreePrice(), "Price is not Agreed");

        uint256 payout;


        //Decide who gets paid buyer or seller

        //payout to/(from) buyer = (actualPrice - strikePrice)* Notional Balance / actualPrice

        //Buyer gets paid if rates increase
        //Seller gets paid if rates decrease

        if (actualPrice > strikePrice){

            payee = buyer;
    
            //Calculate the payout value
            payout  = actualPrice - strikePrice;
            payout = payout * notionalBalance * 10e5 / actualPrice;
            payout = payout/10e5;
            payout = Math.min(payout, marginValue);

            user[buyer].marginAccountBalance += payout;
            user[seller].marginAccountBalance -= payout;

        } else if ( actualPrice < strikePrice){
            payee = seller;

            //Calculate the payout value
            payout  = actualPrice - strikePrice;
            payout = payout * notionalBalance * 10e5 / actualPrice;
            payout = payout/10e5;
            payout = Math.min(payout, marginValue);

            user[buyer].marginAccountBalance -= payout;
            user[seller].marginAccountBalance += payout;

        }else{
            payout = 0;
        }

        //Payout both users
        _transferTo(user[buyer].marginAccountBalance, buyer);
        _transferTo(user[seller].marginAccountBalance, seller);

        emit Exectuted(buyer, seller, strikeAsset, payout, user[buyer].marginAccountBalance, user[seller].marginAccountBalance);

        //Halt & Catch Fire
        contractExecuted = true;

        //selfdestruct(payable(deployerAddress));

    } 
    

    function setActualPrice (uint256 _price) public {

        require(msg.sender == buyer || msg.sender == seller, "Sender is neither buyer or seller");
        require(!contractExecuted, "Contract has been executed");

        user[msg.sender].inputPriceValue = _price;
        user[msg.sender].hasInputedPrice = true;

    }

    function agreePrice () public returns (bool) {

        //If Both Parties Agree on price then True
        if (
            user[buyer].hasInputedPrice && 
            user[seller].hasInputedPrice &&
            user[buyer].inputPriceValue == user[seller].inputPriceValue 
        ){
            priceAgreed = true;
            actualPrice  = user[buyer].inputPriceValue;
        } 
        //If one party has entered a price and the other has entered one by expiry then True
        else if(
            block.timestamp > expiry &&
            (user[buyer].hasInputedPrice || user[seller].hasInputedPrice) &&
            (user[buyer].inputPriceValue == 0 || user[seller].inputPriceValue == 0)
        ){
            priceAgreed = true;
            actualPrice = Math.max(user[buyer].inputPriceValue, user[seller].inputPriceValue);

        }
        //Else False 
        return priceAgreed;

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

contract deployer {

    CurrencySwap public swapContract;

    struct Contract{
        uint256 notionalBalance;
        uint256 marginPercent;
        address buyer;
        address seller;
        address strikeAsset;
        uint256 strikePrice;
        uint256 daysToExpiry;
        bool contractExecuted;
    }
    mapping (address=>Contract) swapData ;

    address[] public swapList;
    uint256 public count;
    mapping (address=>address[]) public userSwaps;

    function createCurrencySwap (
        uint256 _notionalBalance,
        uint256 _marginPercent,
        address _buyer,
        address _seller,
        address _strikeAsset,
        uint256 _strikePrice,
        uint256 _daysToExpiry) 
    
    public {
        
        address  buyer = _buyer;
        address  seller = _seller;

        swapContract = new CurrencySwap (
        _notionalBalance,
        _marginPercent,
        _buyer,
        _seller,
        _strikeAsset,
        _strikePrice,
        _daysToExpiry);

        address contractAddress = address(swapContract);
        
        count ++;
        swapList.push(contractAddress);
        userSwaps[_buyer].push(contractAddress);
        userSwaps[_seller].push(contractAddress);

//        swapData[contractAddress].contractBuyer = buyer;
//        swapData[contractAddress].contractSeller = seller;


        //Load data into contract
        swapData[contractAddress].notionalBalance = _notionalBalance;
        swapData[contractAddress].marginPercent = _marginPercent;
        swapData[contractAddress].buyer= buyer;
        swapData[contractAddress].seller =seller;
        swapData[contractAddress].strikeAsset = _strikeAsset;
        swapData[contractAddress].strikePrice = _strikePrice;
        swapData[contractAddress].daysToExpiry = _daysToExpiry;

    }

    function getSwapList() external view returns (address[] memory) {
        return swapList;
    }

    function getUserSwaps(address _address) external view returns (address[] memory) {
        
        return userSwaps[_address];

    }

    //Need to refactor a dedicated function so that can send direct from user wallet through deployer
    function depositInContract(address _contract) public {
        
        //require(msg.sender == )


        CurrencySwap(_contract).deposit();

    }

    //Need to refactor to identify who is impacting the price
    function setPriceInContract(address _contract, uint256 _actualPrice) public {
    
        CurrencySwap(_contract).setActualPrice(_actualPrice);
    
    }

    //This can work with the existing logic because only buyer or  seller will be paid
    function executeSwapContract(address _contract) public {
    
        CurrencySwap(_contract).executeContract();
    
    }

}