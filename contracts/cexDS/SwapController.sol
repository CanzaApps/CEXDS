// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "./CEXDefaultSwap.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "./interfaces/ICreditDefaultSwap.sol";
import "./Voting.sol";

contract SwapController is AccessControl {

    bytes32 public constant SUPER_ADMIN = 'SUPER_ADMIN';
    bytes32 public constant ADMIN_CONTROLLER = 'ADMIN_CONTROLLER';

    address[] public swapList;
    address public votingContract;

    constructor(
        address secondSuperAdmin
    ) {
        _setupRole(SUPER_ADMIN, msg.sender);
        _setupRole(SUPER_ADMIN, secondSuperAdmin);
        _setRoleAdmin(ADMIN_CONTROLLER, SUPER_ADMIN);
    }

    modifier isAdmin() {
        if(!hasRole(ADMIN_CONTROLLER, msg.sender) && !hasRole(SUPER_ADMIN, msg.sender)) revert("Caller does not have any of the admin roles");
        _;
    }

    /**
     * @notice Initializes a Swap Contract for a specified entity.
     * @param _entityName Human readable name for the entity
     * @param _currency Token address, for which loan was taken in the specified entity. Token must implement the ERC-20 standard.
     * @param _premium Premium percentage desired for credit swap pool.
     * @param _initialMaturityDate Date for pool maturity.
     */
    function createSwapContract(
        string memory _entityName,
        address _currency,
        uint256 _premium,
        uint256 _initialMaturityDate,
        uint256 _epochDays

    ) public isAdmin {
        require(votingContract != address(0x00), "Set Voting Contract first");

        CEXDefaultSwap swapContract = new CEXDefaultSwap(
            _entityName,
            _currency,
            _premium,
            _initialMaturityDate,
            _epochDays,
            votingContract
        );

        address contractAddress = address(swapContract);

        //Add to master list
        swapList.push(contractAddress);

    }

    function setPoolPaused(address _add) external onlyRole(SUPER_ADMIN) {
        ICreditDefaultSwap(_add).pause();
    }

    function setPoolUnpaused(address _add) external onlyRole(SUPER_ADMIN) {
        ICreditDefaultSwap(_add).unpause();
    }
    
    function resetPoolAfterDefault(address _add, uint256 _newMaturityDate) external onlyRole(SUPER_ADMIN) {
        ICreditDefaultSwap(_add).resetAfterDefault(_newMaturityDate);
        Voting(votingContract).clearVotingData(_add);
    }

    function setVotingContract(address _address) external onlyRole(SUPER_ADMIN) {
        if (_address == votingContract) revert("Already set");

        votingContract = _address;
    }

    function getSwapList() external view returns (address[] memory) {
        return swapList;
    }

}