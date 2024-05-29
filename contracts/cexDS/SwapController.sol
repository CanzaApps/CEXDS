// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import "./CXDefaultSwap.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "./interfaces/ICreditDefaultSwap.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "./Voting.sol";

contract SwapController is AccessControl {
    using Address for address;
    bytes32 public constant SUPER_ADMIN = 'SUPER_ADMIN';
    bytes32 public constant ADMIN_CONTROLLER = 'ADMIN_CONTROLLER';

    address[] public swapList;
    address public votingContract;
    address public oracleContract;

    event SetOracleContract(address _oracleContract);
    event SetVotingContract(address _votingContract);
    event SwapContractCreated(address indexed _poolAddress
    , address _poolToken
    , uint256 _premium
    , uint256 _epochDays
    , bool _withVoterConsensus
    , bool isThirdParty
    , address poolOwner);
    event PoolPaused(address indexed _poolAddress, address _sender);
    event PoolUnpaused(address indexed _poolAddress, address _sender);
    event PoolDefaulted(address indexed _poolAddress, uint256 _percentageDefaulted, address _sender);
    event PoolReset(address indexed _poolAddress, address _sender);
    event PoolClosed(address indexed _poolAddress);
    event RollPoolEpoch(address indexed _poolAddress, address _sender);
    event WithdrawPoolTokens(address indexed _poolAddress, uint256 _amount, address _recipient, address _sender);

    constructor(
        address secondSuperAdmin
    ) {
        if (secondSuperAdmin == address(0)) revert("Attempting to set zero address as admin");
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
     * @notice See {_createSwapContract}
     */
    function createSwapContract(
        string memory _entityName,
        string memory _entityUrl,
        address _currency,
        uint256 _premium,
        uint256 _makerFee,
        uint256 _epochDays,
        bool withVoterConsensus

    ) public isAdmin {
        address poolAddress = _createSwapContract(_entityName, _entityUrl, _currency, _premium, _makerFee, _epochDays, withVoterConsensus);
        emit SwapContractCreated(poolAddress, _currency, _premium, _epochDays, withVoterConsensus, false, msg.sender);
    }

    /**
     * @notice Initializes a Swap Contract for a specific ERC20 token on a specified entity.
     * @param _entityName Human readable name for the entity
     * @param _entityUrl URL for the specific entity
     * @param _currency Token address, for which loan was taken in the specified entity. Token must implement the ERC-20 standard.
     * @param _premium Premium percentage desired for credit swap pool.
     * @param _epochDays Number of days for increment of the maturity date after every cycle without a default
     * @param withVoterConsensus defines if a pool will be defaulted via voter consensus action
     * @param _owner the address of the owner of the 3rd party pool
     * @param _voters array of intended voter addresses
     */
    function createSwapContractAsThirdParty(
        string memory _entityName,
        string memory _entityUrl,
        address _currency,
        uint256 _premium,
        uint256 _makerFee,
        uint256 _epochDays,
        bool withVoterConsensus,
        address _owner,
        address[] memory _voters

    ) public isAdmin {
        address poolAddress = _createSwapContract(_entityName, _entityUrl, _currency, _premium, _makerFee, _epochDays, withVoterConsensus);
        bytes32 ownerRole = getPoolOwnerRole(poolAddress);
        _setRoleAdmin(ownerRole, SUPER_ADMIN);
        _grantRole(ownerRole, _owner);
        if (withVoterConsensus) Voting(votingContract).setVotersForPool(_voters, poolAddress);
        emit SwapContractCreated(poolAddress, _currency, _premium, _epochDays, withVoterConsensus, false, msg.sender);
    }

    /**
     * @notice sets a swap pool state to paused.
     * @param _add the swap pool address
     */
    function setPoolPaused(address _add) external isSuperAdminOrPoolOwner(_add) {
        ICreditDefaultSwap(_add).pause();
        emit PoolPaused(_add, msg.sender);
    }

    /**
     * @notice sets a swap pool state to be unpaused. Unlike {setPoolPaused}, this is restricted to only the superAdmin
     * @param _add the swap pool address
     */
    function setPoolUnpaused(address _add) external onlyRole(SUPER_ADMIN) {
        ICreditDefaultSwap(_add).unpause();
        emit PoolUnpaused(_add, msg.sender);
    }

    /**
     * @notice implements a default action on a Swap pool. 
     * Only exists for pools that do not require voter consensus for a default
     * Would revert if the pool requires voter consensus. See {CXDefaultSwap.setDefaulted}
     * @param _add the swap pool address
     */
    function setPoolDefaulted(address _add, uint256 _percentageDefaulted) external onlyRole(SUPER_ADMIN) {
        ICreditDefaultSwap(_add).setDefaulted(_percentageDefaulted);
        emit PoolDefaulted(_add, _percentageDefaulted, msg.sender);
    }
    
    /**
     * @notice sets a swap pool state to be unpaused. Unlike {setPoolPaused}, this is restricted to only the superAdmin
     * @param _add the swap pool address
     */
    function resetPoolAfterDefault(address _add) external isSuperAdminOrPoolOwner(_add) {
        ICreditDefaultSwap(_add).resetAfterDefault();
        Voting(votingContract).clearVotingData(_add);
        emit PoolReset(_add, msg.sender);
    }

    /**
     * @notice closes a swap pool in the event that the activity is no longer required within the pool
     * @param _add the swap pool address
     */
    function closePool(address _add) external isAdmin {
        ICreditDefaultSwap(_add).closePool();
        emit PoolClosed(_add);
    }

    /**
     * @notice provides a call to {CXDefaultSwap.rollEpoch} to update maturityTimestamp in a pool after it matures
     * @param _add the swap pool address
     */
    function rollPoolEpoch(address _add) external isSuperAdminOrPoolOwner(_add) {
        ICreditDefaultSwap(_add).rollEpoch();
        emit RollPoolEpoch(_add, msg.sender);
    }

    /**
     * @notice sets the address of the voting contract in the event that it is changed.
     * @param _address the new address for the oracle contract
     */
    function setVotingContract(address _address) external onlyRole(SUPER_ADMIN) {
        if (!_address.isContract()) revert("Attempting to set invalid address. Check that it is not zero address, and that it is for a contract");
        if (_address == votingContract) revert("Already set");

        votingContract = _address;
        emit SetVotingContract(_address);
    }

    /**
     * @notice sets the address of the oracle contract in the event that it is changed.
     * @param _address the new address for the oracle contract
     */
    function setOracleContract(address _address) external onlyRole(SUPER_ADMIN) {
        if (!_address.isContract()) revert("Attempting to set invalid address. Check that it is not zero address, and that it is for a contract");
        if (_address == oracleContract) revert("Already set");

        oracleContract = _address;
        emit SetOracleContract(_address);
    }

    /**
     * @notice withdraw trasury tokens on existing pools accumulated via maker fees paid at purchases.
     * @param _poolAddress address of pool from which to withdraw
     * @param _amount amount of tokens to withdraw
     * @param _recipient address of withdrawal recipient
     */
    function withdrawTokensFromPool(address _poolAddress, uint256 _amount, address _recipient) external onlyRole(SUPER_ADMIN) {
        ICreditDefaultSwap(_poolAddress).withdrawFromBalance(_amount, _recipient);
        emit WithdrawPoolTokens(_poolAddress, _amount, _recipient, msg.sender);
    }

    /**
     * @notice Initializes a Swap Contract for a specific ERC20 token on a specified entity.
     * @param _entityName Human readable name for the entity
     * @param _entityUrl URL for the specific entity
     * @param _currency Token address, for which loan was taken in the specified entity. Token must implement the ERC-20 standard.
     * @param _premium Premium percentage desired for credit swap pool.
     * @param _epochDays Number of days for increment of the maturity date after every cycle without a default
     * @param withVoterConsensus defines if a pool will be defaulted via voter consensus action
     */
    function _createSwapContract(
        string memory _entityName,
        string memory _entityUrl,
        address _currency,
        uint256 _premium,
        uint256 _makerFee,
        uint256 _epochDays,
        bool withVoterConsensus

    ) internal returns (address contractAddress) {
        require(votingContract != address(0x00), "Set Voting Contract first");
        require(oracleContract != address(0x00), "Set Oracle Contract first");

        CXDefaultSwap swapContract = new CXDefaultSwap(
            _entityName,
            _entityUrl,
            _currency,
            _premium,
            _makerFee,
            _epochDays,
            votingContract,
            oracleContract,
            withVoterConsensus
        );

        contractAddress = address(swapContract);

        //Add to master list
        swapList.push(contractAddress);
    }

    /**
     * @notice returns the list of all CXDefaultSwap pools already created
     */
    function getSwapList() external view returns (address[] memory) {
        return swapList;
    }

    /**
     * @notice checks if a specific address owns a third-party pool
     * @param pool address of the swap pool of interest
     * @param add address for which to check if is owner of pool
     */
    function isPoolOwner(address pool, address add) external view returns (bool) {
        return hasRole(getPoolOwnerRole(pool), add);
    }

    /**
     * @notice returns the bytes32 encoded role for the pool owner of a thirdparty pool
     * @param _poolAddress 3rd party pool address
     */
    function getPoolOwnerRole(address _poolAddress) public pure returns (bytes32 ownerRole) {
        ownerRole = bytes32(abi.encodePacked(
            "Pool ",
            Strings.toHexString(uint160(_poolAddress), 20),
            " Owner Role"
        ));
    }

}