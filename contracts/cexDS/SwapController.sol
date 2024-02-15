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

    uint256 public maxNumberOfSellersPerPool;
    uint256 public maxNumberOfBuyersPerPool;

    event SetOracleContract(address _oracleContract);
    event SetVotingContract(address _votingContract);
    event SwapContractCreated(address indexed _poolAddress
    , address _poolToken
    , uint256 _premium
    , uint256 _initialMaturityTimestamp
    , uint256 _epochDays
    , bool _withVoterConsensus
    , bool isThirdParty
    , address poolOwner);
    event PoolPaused(address indexed _poolAddress, address _sender);
    event PoolUnpaused(address indexed _poolAddress, address _sender);
    event PoolReset(address indexed _poolAddress, address _sender, uint256 _newMaturityDate);
    event PoolClosed(address indexed _poolAddress);
    event RollPoolEpoch(address indexed _poolAddress, address _sender);

    constructor(
        address secondSuperAdmin
        , uint256 _maxNumberOfSellersPerPool
        , uint256 _maxNumberOfBuyersPerPool
    ) {
        if (secondSuperAdmin == address(0)) revert("Attempting to set zero address as admin");
        _setupRole(SUPER_ADMIN, msg.sender);
        _setupRole(SUPER_ADMIN, secondSuperAdmin);
        _setRoleAdmin(ADMIN_CONTROLLER, SUPER_ADMIN);
        maxNumberOfBuyersPerPool = _maxNumberOfBuyersPerPool;
        maxNumberOfSellersPerPool = _maxNumberOfSellersPerPool;
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
     * @notice Initializes a Swap Contract for a specific ERC20 token on a specified entity.
     * @param _entityName Human readable name for the entity
     * @param _entityUrl URL for the specific entity
     * @param _currency Token address, for which loan was taken in the specified entity. Token must implement the ERC-20 standard.
     * @param _premium Premium percentage desired for credit swap pool.
     * @param _initialMaturityDate Date for pool maturity.
     * @param _epochDays Number of days for increment of the maturity date after every cycle without a default
     */
    function createSwapContract(
        string memory _entityName,
        string memory _entityUrl,
        address _currency,
        uint256 _premium,
        uint256 _makerFee,
        uint256 _initialMaturityDate,
        uint256 _epochDays,
        bool withVoterConsensus

    ) public isAdmin {
        address poolAddress = _createSwapContract(_entityName, _entityUrl, _currency, _premium, _makerFee, _initialMaturityDate, _epochDays, withVoterConsensus);
        emit SwapContractCreated(poolAddress, _currency, _premium, _initialMaturityDate, _epochDays, withVoterConsensus, false, msg.sender);
    }

    /**
     * @notice Initializes a Swap Contract for a specific ERC20 token on a specified entity.
     * @param _entityName Human readable name for the entity
     * @param _entityUrl URL for the specific entity
     * @param _currency Token address, for which loan was taken in the specified entity. Token must implement the ERC-20 standard.
     * @param _premium Premium percentage desired for credit swap pool.
     * @param _initialMaturityDate Date for pool maturity.
     * @param _epochDays Number of days for increment of the maturity date after every cycle without a default
     * @param _owner the address of the owner of the 3rd party pool
     * @param _voters array of intended voter addresses
     */
    function createSwapContractAsThirdParty(
        string memory _entityName,
        string memory _entityUrl,
        address _currency,
        uint256 _premium,
        uint256 _makerFee,
        uint256 _initialMaturityDate,
        uint256 _epochDays,
        bool withVoterConsensus,
        address _owner,
        address[] memory _voters

    ) public isAdmin {
        address poolAddress = _createSwapContract(_entityName, _entityUrl, _currency, _premium, _makerFee, _initialMaturityDate, _epochDays, withVoterConsensus);
        bytes32 ownerRole = getPoolOwnerRole(poolAddress);
        _setRoleAdmin(ownerRole, SUPER_ADMIN);
        _grantRole(ownerRole, _owner);
        Voting(votingContract).setVotersForPool(_voters, poolAddress);
        emit SwapContractCreated(poolAddress, _currency, _premium, _initialMaturityDate, _epochDays, withVoterConsensus, false, msg.sender);
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
     * @notice sets a swap pool state to be unpaused. Unlike {setPoolPaused}, this is restricted to only the superAdmin
     * @param _add the swap pool address
     * @param _newMaturityDate the intended next maturity date of the pool in the next cycle
     */
    function resetPoolAfterDefault(address _add, uint256 _newMaturityDate) external isSuperAdminOrPoolOwner(_add) {
        ICreditDefaultSwap(_add).resetAfterDefault(_newMaturityDate);
        Voting(votingContract).clearVotingData(_add);
        emit PoolReset(_add, msg.sender, _newMaturityDate);
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

    function setVotingContract(address _address) external onlyRole(SUPER_ADMIN) {
        if (!_address.isContract()) revert("Attempting to set invalid address. Check that it is not zero address, and that it is for a contract");
        if (_address == votingContract) revert("Already set");

        votingContract = _address;
        emit SetVotingContract(_address);
    }

    function setOracleContract(address _address) external onlyRole(SUPER_ADMIN) {
        if (!_address.isContract()) revert("Attempting to set invalid address. Check that it is not zero address, and that it is for a contract");
        if (_address == oracleContract) revert("Already set");

        oracleContract = _address;
        emit SetOracleContract(_address);
    }

    function withdrawTokensFromPool(address _poolAddress, uint256 _amount, address _recipient) external onlyRole(SUPER_ADMIN) {
        ICreditDefaultSwap(_poolAddress).withdrawFromBalance(_amount, _recipient);
    }

    function _createSwapContract(
        string memory _entityName,
        string memory _entityUrl,
        address _currency,
        uint256 _premium,
        uint256 _makerFee,
        uint256 _initialMaturityDate,
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
            _initialMaturityDate,
            _epochDays,
            maxNumberOfSellersPerPool,
            maxNumberOfBuyersPerPool,
            votingContract,
            oracleContract,
            withVoterConsensus
        );

        contractAddress = address(swapContract);

        //Add to master list
        swapList.push(contractAddress);
    }

    function getSwapList() external view returns (address[] memory) {
        return swapList;
    }

    function isPoolOwner(address pool, address add) external view returns (bool) {
        return hasRole(getPoolOwnerRole(pool), add);
    }

    function getPoolOwnerRole(address _poolAddress) public pure returns (bytes32 ownerRole) {
        ownerRole = bytes32(abi.encodePacked(
            "Pool ",
            Strings.toHexString(uint160(_poolAddress), 20),
            " Owner Role"
        ));
    }

}