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
    address public oracleContract;

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

    modifier isSuperAdminOrPoolOwner(address _pool) {
        if(!hasRole(getPoolOwnerRole(_pool), msg.sender) && !hasRole(SUPER_ADMIN, msg.sender)) revert("Unauthorized");
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

    ) public isAdmin returns (address contractAddress) {
        require(votingContract != address(0x00), "Set Voting Contract first");
        require(oracleContract != address(0x00), "Set Oracle Contract first");

        CEXDefaultSwap swapContract = new CEXDefaultSwap(
            _entityName,
            _currency,
            _premium,
            _initialMaturityDate,
            _epochDays,
            votingContract,
            oracleContract
        );

        contractAddress = address(swapContract);

        //Add to master list
        swapList.push(contractAddress);

    }

    function createSwapContract(
        string memory _entityName,
        address _currency,
        uint256 _premium,
        uint256 _initialMaturityDate,
        uint256 _epochDays,
        address _owner

    ) public isAdmin {
        address poolAddress = createSwapContract(_entityName, _currency, _premium, _initialMaturityDate, _epochDays);
        bytes32 ownerRole = getPoolOwnerRole(poolAddress);
        _setRoleAdmin(ownerRole, SUPER_ADMIN);
        grantRole(ownerRole, _owner);

    }

    function setPoolPaused(address _add) external isSuperAdminOrPoolOwner(_add) {
        ICreditDefaultSwap(_add).pause();
    }

    function setPoolUnpaused(address _add) external isSuperAdminOrPoolOwner(_add) {
        ICreditDefaultSwap(_add).unpause();
    }
    
    function resetPoolAfterDefault(address _add, uint256 _newMaturityDate) external isSuperAdminOrPoolOwner(_add) {
        ICreditDefaultSwap(_add).resetAfterDefault(_newMaturityDate);
        Voting(votingContract).clearVotingData(_add);
    }

    function setVotingContract(address _address) external onlyRole(SUPER_ADMIN) {
        if (_address == votingContract) revert("Already set");

        votingContract = _address;
    }

    function setOracleContract(address _address) external onlyRole(SUPER_ADMIN) {
        if (_address == oracleContract) revert("Already set");

        oracleContract = _address;
    }

    function getSwapList() external view returns (address[] memory) {
        return swapList;
    }

    function getPoolOwnerRole(address _poolAddress) public pure returns (bytes32 ownerRole) {
        ownerRole = bytes32(abi.encodePacked(
            "Pool ",
            Strings.toHexString(uint160(_poolAddress), 20),
            " Owner Role"
        ));
    }

}