// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract Forward{

    //Buyer and sellers addresses
    address public buyer;
    address public seller;
    
    //Set up Counterparty function to allow the deployer to be flexible
    address public counterParty;
    
    //Strike (purchasing) asset and Quantity
    address public strikeAsset;
    uint256 public strikePrice;

    //Underlying (sold) asset and quantity
    address public underlyingAsset;
    uint256 public underlyingQuantity;

    //Boolean to activate contract
    bool public contractActive;

    //Timestamp for the Expiry
    uint public expiry;

    //For buyer or seller to deploy forward contract
    //consider swapping this into a constructor so that this deploys the contracts with the relevant parameters required
    function deploy(address _strikeAsset,uint256 _strikePrice, address _underlyingAsset, uint256 _underlyingQuantity, address _buyerAddress, address _sellerAddress, uint256 _days) public payable {
        
        //Require that contract is not active
        require(!contractActive, "Contract is active");        
        
        //Sets strike parameters
        strikeAsset = _strikeAsset;
        strikePrice = _strikePrice;

        //Sets underlying parameters
        underlyingAsset = _underlyingAsset;
        underlyingQuantity = _underlyingQuantity;

        //Sets buyer & seller 
        buyer = _buyerAddress;
        seller = _sellerAddress;

        //Sets expiry
        expiry = block.timestamp + _days*60*24;


        //Checks whether the counterparty is the buyer and seller and adjusts requirement accordingly
        address _asset;
        uint _quantity;

        if (msg.sender == buyer){
            _asset = strikeAsset;
            _quantity = strikePrice;
            counterParty = seller;

        } if(msg.sender == seller){
            _asset = underlyingAsset;
            _quantity = underlyingQuantity;
            counterParty = buyer;
        }

        //Checks that the buyer has enough balance to deploy
        require(_quantity <= IERC20(_asset).balanceOf(msg.sender),"Not Enough Balance");
        
        //Transfers tokens to the sender
        IERC20(_asset).transferFrom(msg.sender, address(this), _quantity);

    }

    //Allows seller to deposit tokens
    function depositCounterparty() public payable{

        //Require only the seller identified by the buyer can deposit 
        require(msg.sender == counterParty, "You are not the counterParty");


        //Require that contract is not active
        require(!contractActive, "Contract is active");

        //Checks whether the counterparty is the buyer and seller and adjusts requirement accordingly
        address _asset;
        uint _quantity;

        if (counterParty == buyer){
            _asset = strikeAsset;
            _quantity = strikePrice;
            counterParty = seller;

        } if(counterParty == seller){
            _asset = underlyingAsset;
            _quantity = underlyingQuantity;
            counterParty = buyer;
        }
        //Require that the seller have the sufficient balance as identified in the contract
        require(underlyingQuantity <= IERC20(underlyingAsset).balanceOf(msg.sender),"Not Enough Balance");

        //Transfer tokens to the contract
        IERC20(_asset).transferFrom(msg.sender, address(this), _quantity);

        contractActive = true;
    }

    //Allows function to execute
    function executeForward() public{
        
        //Checks that contract is active (i.e. the seller has deposited his amount)
        require(contractActive, "Contract is not active");

        //Require that the contract expiry is passed before contract and be executed
        require(block.timestamp >= expiry, "Contract has not matured");

        //Send underlying assets to buyer
        //IERC20(underlyingAsset).transferFrom(address(this), buyer , underlyingQuantity);
        IERC20(underlyingAsset).transfer(buyer , underlyingQuantity);
        
        //Send strike assets to seller
        //IERC20(strikeAsset).transferFrom(address(this), seller, strikePrice);
        IERC20(strikeAsset).transfer(seller, strikePrice);

        //Self destruct contract once it has been executed
        selfdestruct(payable(buyer));
    }


    //Test Functions
    function getBalance(address _assetAddress) public view returns (uint256) {
        
        return IERC20(_assetAddress).balanceOf(msg.sender);


    }

      function getBalance2(address _token) public view returns(uint256){
        return IERC20(_token).balanceOf(msg.sender);
    }

    function transfer(uint256 _amount, address payable _asset) public{

        //IERC20(_asset).approve(address(this), _amount);
        //IERC20(_asset).allowance(msg.sender, address(this));

        IERC20(_asset).transferFrom(msg.sender, address(this), _amount);

    }


    function setTime() public{

        expiry = block.timestamp;
    }


}
