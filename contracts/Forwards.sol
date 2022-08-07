    //SPDX-License-Identifier: MIT
    pragma solidity ^0.8.0;

    import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

    contract Forward{

        //Buyer and sellers addresses
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

        //Boolean to activate contract
        bool public contractActive;

        mapping(address=>bool) public deposited;
        
        
        struct Deposits {

            address assetAddress;
            uint assetBalance;
            uint depositTimestamp;

        }
        
        mapping(address=> Deposits) public userBalances ;

        //Timestamp for the Expiry
        uint public expiry;

        //For buyer or seller to deploy forward contract
        //consider swapping this into a constructor so that this deploys the contracts with the relevant parameters required
        constructor(address _strikeAsset,uint256 _strikePrice, address _underlyingAsset, uint256 _underlyingQuantity, address _buyerAddress, address _sellerAddress, uint256 _days) payable {
            
            //Require that contract is not active
            require(msg.sender == _buyerAddress || msg.sender == _sellerAddress, "Deployer needs to be either buyer or seller");        
            
            //Sets strike parameters
            strikeAsset = _strikeAsset;
            strikePrice = _strikePrice;

            //Sets underlying parameters
            underlyingAsset = _underlyingAsset;
            underlyingQuantity = _underlyingQuantity;

            //Sets buyer & seller 
            buyer = _buyerAddress;
            seller = _sellerAddress;

            //Sets deployer and counterparty
            if (msg.sender == buyer){
                deployer = buyer;
                counterParty = seller;

            }if (msg.sender == seller){
                deployer = seller;
                counterParty = buyer;

            }//Consider logic that can allow for third party deployments

        
            //Sets expiry
            expiry = block.timestamp + _days*60*24;

        }

        //Allows buyer or seller to deposit tokens
        function deposit() public payable{

            //Require only the seller identified by the buyer can deposit 
            require(!deposited[msg.sender], "You have already depsoited");


            //Require that contract is not active
            require(!contractActive, "Contract is active");

            //Checks whether the counterparty is the buyer and seller and adjusts variables accordingly

            address _asset;
            uint _quantity;

            if (msg.sender == buyer){
                _asset = strikeAsset;
                _quantity = strikePrice;
                deposited[buyer] = true;

            } if(msg.sender == seller){
                _asset = underlyingAsset;
                _quantity = underlyingQuantity;
                deposited[seller] = true;
                
            }

            //Checks that the buyer has enough balance to deploy
            require(_quantity <= IERC20(_asset).balanceOf(msg.sender),"Not Enough Balance");
            
            //Transfers tokens to the sender
            IERC20(_asset).transferFrom(msg.sender, address(this), _quantity);

            //Updates the userBalances mapping to have the required data available
            userBalances[msg.sender].assetAddress = _asset;
            userBalances[msg.sender].assetBalance = _quantity;
            userBalances[msg.sender].depositTimestamp = block.timestamp;

            //Activates the contract if both buyer and seller has deposited
            contractActive = deposited[buyer] && deposited[seller];
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
