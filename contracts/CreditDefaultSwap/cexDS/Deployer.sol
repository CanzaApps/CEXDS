// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "./CEXDefaultSwap.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./ICreditDefaultSwap.sol";

import "./ICreditDefaultSwap.sol";

contract deployer is Ownable {
    CEXDefaultSwap public swapContract;

    address[] public swapList;
    mapping(address => address[]) public userSwaps;

    mapping(string => bool) public deployedLoanIDs;
    mapping(string => address) public loans;

    function createSwapContract(
        string memory _entityName,
        address _currency,
        string memory _currency_name,
        uint256 _premium,
        uint256 _initialMaturityDate,
        uint256 _epochDays

    ) public onlyOwner {

        swapContract = new CEXDefaultSwap(
            _entityName,
            _currency,
            _currency_name,
            _premium,
            _initialMaturityDate,
            _epochDays
        );

        address contractAddress = address(swapContract);

        //Add to master list
        swapList.push(contractAddress);
    }

    function getSwapList() external view returns (address[] memory) {
        return swapList;
    }

    function setPoolDefaulted(address _add, bool _val) external onlyOwner {
        ICreditDefaultSwap(_add).setDefaulted(_val);
    }

    function setPoolPaused(address _add) external onlyOwner{
        ICreditDefaultSwap(_add).pause();
    }

    function setPoolUnpaused(address _add) external onlyOwner{
        ICreditDefaultSwap(_add).unpause();
    }

    function resetPoolAfterDefault(address _add, uint256 _newMaturityDate) external onlyOwner{
        ICreditDefaultSwap(_add).resetAfterDefault(_newMaturityDate);
    }
}
