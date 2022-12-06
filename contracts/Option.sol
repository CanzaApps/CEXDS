    //SPDX-License-Identifier: MIT
    pragma solidity ^0.8.0;

    import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

    contract Option{

        //Set Addresses
        address public buyer;
        address public seller;

        //Set up Counterparty function to allow the deployer to be flexible
        address public deployer;
        address public counterParty;
        
        //Strike (purchasing) asset and Quantity
        address public strikeAsset;
        uint256 public strikePrice;

        //Underlying (sold) asset and quantity
        address public underlyingAsset;
        uint256 public underlyingQuantity;

        //Premium Asset and quantity
        address public premiumAsset;
        uint256 public premiumQuantity;

        //Boolean to determine if contract is active
        bool public contractActive;

        //Contract Expiry
        uint public expiry;

        //American or European
        bool public put;

        //Transaction Fees
        uint256 public txFee = 3;
        address public treasuryAddress = 0x4B20993Bc481177ec7E8f571ceCaE8A9e22C02db;


        //Deposit Struct
        mapping(address=>bool) public deposited;
        
        struct Deposits {

            address assetAddress;
            uint assetBalance;
            uint depositTimestamp;

        }
        
        mapping(address=> Deposits) public userBalances ;

        //Set up contract paratmeters
        constructor(address _strikeAsset,uint256 _strikePrice, address _underlyingAsset, uint256 _underlyingQuantity, address _premiumAsset, uint256 _premiumQuantity, address _buyerAddress, address _sellerAddress, uint256 _days, bool _put) payable {

            //Sets strike parameters
            strikeAsset = _strikeAsset;
            strikePrice = _strikePrice;

            //Sets underlying parameters
            underlyingAsset = _underlyingAsset;
            underlyingQuantity = _underlyingQuantity;

            //Sets underlying parameters
            premiumAsset = _premiumAsset;
            premiumQuantity = _premiumQuantity;

            //Sets buyer & seller 
            buyer = _buyerAddress;
            seller = _sellerAddress;

            if (msg.sender == buyer){
                deployer = buyer;
                counterParty = seller;

            }if (msg.sender == seller){
                deployer = seller;
                counterParty = buyer;

            }//Consider logic that can allow for third party deployments

            //Sets expiry
            expiry = block.timestamp + _days*60*24;

            //Sets Put of Call
            put = _put;

        }

        function deposit () public payable {

            require(!deposited[msg.sender], "Deposited");
            require(!contractActive, "Contract Active");
            require(msg.sender == seller, "Seller must deposit");

            address _asset;
            uint _quantity;

            if (!put){
                _asset = underlyingAsset;
                _quantity = underlyingQuantity;
            } else{
                _asset = strikeAsset;
                _quantity = strikePrice;
            }

            require(_quantity <= IERC20(_asset).balanceOf(msg.sender),"Not Enough Balance");
            
            //Transfers tokens to the contract
            IERC20(_asset).transferFrom(msg.sender, address(this), _quantity);

            //Set deposited Boolean to true
            deposited[msg.sender] = true;

            //Updates the userBalances mapping to have the required data available
            userBalances[msg.sender].assetAddress = _asset;
            userBalances[msg.sender].assetBalance += _quantity;
            userBalances[msg.sender].depositTimestamp = block.timestamp;

        }

        function payPremium () public payable {
            require(msg.sender == buyer, "Not contract buyer");
            require(deposited[seller], "Seller Has Not Deposited Assets");
            require(!contractActive, "Contract is Active");

            address _asset = premiumAsset;
            uint256 _quantity = premiumQuantity;
            uint256 premiumFee;

            premiumFee = txFee*premiumQuantity/1000;

            require(_quantity <= IERC20(_asset).balanceOf(msg.sender),"Not Enough Balance");
            
            //Transfers tokens to the sender
            IERC20(_asset).transferFrom(msg.sender, seller, _quantity-premiumFee);

            //Transfer tokens to treasury
            IERC20(_asset).transferFrom(msg.sender, treasuryAddress, premiumFee);

            //Activate Contract
            contractActive = true;
        }

        function excercise () public payable {

            require(msg.sender == buyer, "Not Contract buyer");
            require(contractActive, "Contract not Active" );
            require(expiry > block.timestamp, "Contract Expired");

            address _assetPaid;
            uint256 _quantityPaid;
            address _assetReceived;
            uint256 _quantityReceived;

            uint256 paidFee;
            uint256 receivedFee;


            if (!put){
                //Call options pay the strike and receive the underlying
                _assetPaid = strikeAsset;
                _quantityPaid = strikePrice;
                _assetReceived = underlyingAsset;
                _quantityReceived = underlyingQuantity;
            } else{
                //Put options pay the underlying and receive the strike
                _assetPaid = underlyingAsset;
                _quantityPaid = underlyingQuantity;
                _assetReceived = strikeAsset;
                _quantityReceived = strikePrice;
            } 


            //Calculate Transaction Fee
            paidFee = txFee * _quantityPaid / 1000;
            receivedFee = txFee * _quantityReceived / 1000;
             

            require(_quantityPaid <= IERC20(_assetPaid).balanceOf(msg.sender),"Not Enough Balance");
            
            //Transfers tokens to the sender
            IERC20(_assetPaid).transferFrom(msg.sender, seller, _quantityPaid-paidFee);
            IERC20(_assetReceived).transfer(buyer, _quantityReceived-receivedFee);

            //Transfers to treasury
            IERC20(_assetPaid).transferFrom(msg.sender, treasuryAddress, paidFee);
            IERC20(_assetReceived).transfer(treasuryAddress, receivedFee);

        }

        function undwind () public {
            //Allows user to unwind a position if the option has expired

            require(expiry <= block.timestamp, "Contract has not expired yet");
            
            //Returns underlying assets to seller if option has expired
            
            address _asset;
            uint256 _quantity;
            
            if (!put){
                _asset = underlyingAsset;
                _quantity = underlyingQuantity;
            } else{
                _asset = strikeAsset;
                _quantity = strikePrice;
            }

            IERC20(_asset).transfer(buyer, _quantity);


        }


    }
