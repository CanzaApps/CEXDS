pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract Forward{

    //Buyer and sellers addresses
    address public buyer;
    address public seller;
    
    //Strike (purchasing) asset and Quantity
    address public strikeAsset;
    uint256 public strikePrice;

    //Underlying (sold) asset and quantity
    address public underlyingAsset;
    uint256 public underlyingQuantity;

    //Boolean to activate contract
    bool public contractActive;

    uint public timestamp;

    //For buyer to deploy forward contract
    function deployBuyer(address _strikeAsset,uint256 _strikePrice, address _underlyingAsset, uint256 _underlyingQuantity, address _sellerAddress, uint256 _days) public payable {
        require(_strikePrice <= IERC20(_strikeAsset).balanceOf(msg.sender),"Not Enough Balance");
        
        
        //Sets strike parameters
        strikeAsset = _strikeAsset;
        strikePrice = _strikePrice;

        //Sets underlying parameters
        underlyingAsset = _underlyingAsset;
        underlyingQuantity = _underlyingQuantity;

        //Sets seller 
        seller = _sellerAddress;

        //Sets timelock
        timestamp = block.timestamp + _days;

        IERC20(strikeAsset).transfer(address(msg.sender), strikePrice);

    }

    //Allows seller to deposit tokens
    function depositSeller() public payable{
        require(msg.sender == seller, "You are not the seller");
        require(underlyingQuantity <= IERC20(underlyingAsset).balanceOf(msg.sender),"Not Enough Balance");
        require(!contractActive, "Contract is Active");
        IERC20(underlyingAsset).transfer(address(this), underlyingQuantity);
        contractActive = true;
    }

    //Allows function to execute
    function executeBuyerForward() public{
        
        //Checks that contract is active
        require(contractActive, "Contract is Not Active");
        require(block.timestamp >= timestamp, "Contract Has not Matured");
        IERC20(underlyingAsset).transferFrom(address(this), buyer , underlyingQuantity);
        IERC20(strikeAsset).transferFrom(address(this), seller, strikePrice);

        selfdestruct(payable(buyer));
    }



    //Test Functions
    function getBalance(address _assetAddress) public view returns (uint256) {
        
        return IERC20(_assetAddress).balanceOf(msg.sender);


    }

    function trasnfer(uint256 _amount, address payable _asset) public{

        IERC20(_asset).transfer(address(this), _amount);

    }


    function setTime() public{

        timestamp = block.timestamp;
    }


}
