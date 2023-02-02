// SPDX-License-Identifier: MIT

/**
 * NOTE
 * Always do additions first
 * Check if the substracting value is greater than or less than the added values i.e check for a negative result
 */

import "./Forwards.sol";


pragma solidity ^0.8.17;

contract Deployer{
    
    Forward public forwardContract;
    address[] public forwardsList;
    uint256 public count;
    mapping (address=>address[]) public userForwards;

    function createForward (
        address _strikeAsset,
        uint256 _strikePrice, 
        address _underlyingAsset, 
        uint256 _underlyingQuantity, 
        address _buyerAddress, 
        address _sellerAddress, 
        uint256 _days) 
    
    public {

        forwardContract = new Forward (
            _strikeAsset,
            _strikePrice, 
            _underlyingAsset, 
            _underlyingQuantity, 
            _buyerAddress, 
            _sellerAddress, 
            _days);

        count ++;
        forwardsList.push(address(forwardContract));
        userForwards[msg.sender].push(address(forwardContract));
    }

    function getForwardsList() external view returns (address[] memory) {
        return forwardsList;
    }

    function getUserForwards(address _address) external view returns (address[] memory) {
        //address[] memory allUserForwards ;
        //address[] memory activeForwards;
        //Forward a;

        //for(uint256 i = 0; i < userForwards[_address].length; i++) {
        //    allUserForwards = userForwards[_address];
        //    a = Forward(address(allUserForwards[i]));
        //    if(a.contractActive() == true || a.awaitingDeposit() == true){
        //        activeForwards[i] = address(a);
        //    }
        //}

        //return activeForwards;

        return userForwards[_address];
    }
}
