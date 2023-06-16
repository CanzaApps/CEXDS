// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "./CEXDefaultSwap.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "./ICreditDefaultSwap.sol";

contract Deployer is AccessControl {
    CEXDefaultSwap public swapContract;

    bytes32 public constant SUPER_ADMIN = 'SUPER_ADMIN';
    bytes32 public constant ADMIN_CONTROLLER = 'ADMIN_CONTROLLER';
    address[] public swapList;
    mapping(address => address[]) public userSwaps;

    mapping(string => bool) public deployedLoanIDs;
    mapping(string => address) public loans;

    constructor() {
        _setupRole(SUPER_ADMIN, msg.sender);
        _setRoleAdmin(ADMIN_CONTROLLER, SUPER_ADMIN);
    }

    modifier isAdmin() {
        if(!hasRole(ADMIN_CONTROLLER, msg.sender) && !hasRole(SUPER_ADMIN, msg.sender)) revert("Caller does not have any of the admin roles");
        _;
    }

    function createSwapContract(
        string memory _entityName,
        address _currency,
        uint256 _premium,
        uint256 _initialMaturityDate,
        uint256 _epochDays

    ) public isAdmin {
        

        swapContract = new CEXDefaultSwap(
            _entityName,
            _currency,
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

    function setPoolDefaulted(address _add, bool _val) external isAdmin {
        ICreditDefaultSwap(_add).setDefaulted(_val);
    }

    function setPoolPaused(address _add) external isAdmin {
        ICreditDefaultSwap(_add).pause();
    }

    function setPoolUnpaused(address _add) external isAdmin {
        ICreditDefaultSwap(_add).unpause();
    }

    function resetPoolAfterDefault(address _add, uint256 _newMaturityDate) external isAdmin {
        ICreditDefaultSwap(_add).resetAfterDefault(_newMaturityDate);
    }
}
