// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "./interfaces/ISwapController.sol";

contract RateOracle is AccessControl {

    bytes32 public constant SUPER_ADMIN = 'SUPER_ADMIN';
    uint256 public votersRecurringPaymentInterval;
    uint8 public votersDefaultFeeRatio;
    uint8 public votersDefaultFeeComplementaryRatio;
    uint8 public votersRecurringFeeRatio;
    uint8 public votersRecurringFeeComplementaryRatio;
    address private controllerAddress;
    // The max fractional feeRate that can be set, approx by 10^4. 
    // For instance, votersDefaultFeeRatio *10000/votersDefaultFeeComplementaryRatio <= maxFeeRate
    uint256 public constant maxFeeRate = 5000;

    uint8 public immutable numberOfVotersExpected;

    struct FeeRatioOverride {
        uint8 ratio;
        uint8 complementaryRatio;
    }

    mapping(address => uint256) public paymentIntervalOverride;
    mapping(address => FeeRatioOverride) public voterFeeRatioOverride;
    mapping(address => FeeRatioOverride) public recurringFeeRatioOverride;

    event SetNumberOfVoters(uint8 _value);
    event SetPaymentInterval(uint256 _value);
    event SetDefaultFeeRatio(uint8 _ratio, uint8 _complementaryRatio);
    event SetRecurringFeeRatio(uint8 _ratio, uint8 _complementaryRatio);
    event SetNumberOfVotersOverride(address _poolAddress, uint8 _value);
    event SetPaymentIntervalOverride(address _poolAddress, uint256 _value, address _sender);
    event SetDefaultFeeRatioOverride(address _poolAddress, uint8 _ratio, uint8 _complementaryRatio, address _sender);
    event SetRecurringFeeRatioOverride(address _poolAddress, uint8 _ratio, uint8 _complementaryRatio, address _sender);

    constructor(
        address controller
        , address secondSuperAdmin
        , uint8 _voterFeeRatio
        , uint8 _voterFeeComplementaryRatio
        , uint8 _recurringFeeRatio
        , uint8 _recurringFeeComplementaryRatio
        , uint8 votersRequired
        , uint256 recurringPaymentInterval
    ) {
        _setupRole(SUPER_ADMIN, msg.sender);
        _setupRole(SUPER_ADMIN, secondSuperAdmin);
        controllerAddress = controller;

        votersRecurringPaymentInterval = recurringPaymentInterval;
        votersDefaultFeeRatio = _voterFeeRatio;
        votersDefaultFeeComplementaryRatio = _voterFeeComplementaryRatio;
        votersRecurringFeeRatio = _recurringFeeRatio;
        votersRecurringFeeComplementaryRatio = _recurringFeeComplementaryRatio;
        numberOfVotersExpected = votersRequired;
    }

    modifier isSuperAdminOrPoolOwner(address _pool) {
        if(!ISwapController(controllerAddress).isPoolOwner(_pool, msg.sender) && !hasRole(SUPER_ADMIN, msg.sender)) revert("Unauthorized");
        _;
    }

    /**
     * @dev Sets the ratio to be used for computing the accumulated default rewards universally from purchase events on CXDS pools.
     * Value is passed via params representing the two sides of a ratio, which are also 2 sides of a fraction
     * 
     * So, amount * (_newVoterFeeRatio/_newVoterFeeComplementaryRatio) would give the fee amount from a specific amount.
     * @param _newVoterFeeRatio the numerator of the fractional fee
     * @param _newVoterFeeComplementaryRatio the denominator of the fractional fee
     */
    function setVoterFeeRatio(
        uint8 _newVoterFeeRatio
        , uint8 _newVoterFeeComplementaryRatio
    ) external onlyRole(SUPER_ADMIN) {
        require(uint256(_newVoterFeeRatio) *10000/(_newVoterFeeRatio + _newVoterFeeComplementaryRatio) <= maxFeeRate, "RateOracle: Fee rate specified too high");
        votersDefaultFeeRatio = _newVoterFeeRatio;
        votersDefaultFeeComplementaryRatio = _newVoterFeeComplementaryRatio;
        emit SetDefaultFeeRatio(_newVoterFeeRatio, _newVoterFeeComplementaryRatio);
    }

    /**
     * @dev override the universal fee ratio set in {RateOracle-setVoterFeeRatio} for a particular pool
     * @param _newVoterFeeRatio the numerator of the fractional fee
     * @param _newVoterFeeComplementaryRatio the denominator of the fractional fee
     * @param _poolAddress address of the pool on which the override should be set
     */
    function setVoterFeeRatioOverride(
        uint8 _newVoterFeeRatio
        , uint8 _newVoterFeeComplementaryRatio
        , address _poolAddress
    ) external isSuperAdminOrPoolOwner(_poolAddress) {
        require(uint256(_newVoterFeeRatio) *10000/(_newVoterFeeRatio + _newVoterFeeComplementaryRatio) <= maxFeeRate, "RateOracle: Fee rate specified too high");
        voterFeeRatioOverride[_poolAddress] = FeeRatioOverride(_newVoterFeeRatio, _newVoterFeeComplementaryRatio);
        emit SetDefaultFeeRatioOverride(_poolAddress, _newVoterFeeRatio, _newVoterFeeComplementaryRatio, msg.sender);
    }

    /**
     * @dev sets the recurring time interval after which voter rewards would be paid to voters universally.
     * @param _newInterval the new time interval in seconds
     */
    function setVotersPaymentInterval(
        uint256 _newInterval
    ) external onlyRole(SUPER_ADMIN) {
        votersRecurringPaymentInterval = _newInterval;
        emit SetPaymentInterval(_newInterval);
    }

    /**
     * @dev override the universal fee ratio set in {RateOracle-setVotersPaymentInterval} for a particular pool
     * @param _newInterval the new time interval in seconds
     * @param _poolAddress the address of the pool on which the override is set.
     */
    function setVotersPaymentIntervalOverride(
        uint256 _newInterval
        , address _poolAddress
    ) external isSuperAdminOrPoolOwner(_poolAddress) {
        paymentIntervalOverride[_poolAddress] = _newInterval;
        emit SetPaymentIntervalOverride(_poolAddress, _newInterval, msg.sender);
    }

    /**
     * @dev Sets the ratio to be used for computing the rewards paid at the recurring interval set in {RateOracle-setVotersPaymentInterval}.
     * Value is set just like in {RateOracle-setVoterFeeRatio} using the two params to represent a fraction
     * @param _newRecurringFeeRatio the numerator of the fractional fee
     * @param _newRecurringFeeComplementaryRatio the denominator of the fractional fee
     */
    function setRecurringFeeRatio(
        uint8 _newRecurringFeeRatio
        , uint8 _newRecurringFeeComplementaryRatio
    ) external onlyRole(SUPER_ADMIN) {
        require(uint256(_newRecurringFeeRatio) *10000/(_newRecurringFeeRatio + _newRecurringFeeComplementaryRatio) <= maxFeeRate, "RateOracle: Fee rate specified too high");
        votersRecurringFeeRatio = _newRecurringFeeRatio;
        votersRecurringFeeComplementaryRatio = _newRecurringFeeComplementaryRatio;
        emit SetRecurringFeeRatio(_newRecurringFeeRatio, _newRecurringFeeComplementaryRatio);
    }

    /**
     * @dev override the recurring fee ratio set in {RateOracle-setRecurringFeeRatio} for a specific pool.
     * @param _newRecurringFeeRatio the numerator of the fractional fee
     * @param _newRecurringFeeComplementaryRatio the denominator of the fractional fee
     * @param _poolAddress the address of the pool on which the override is set.
     */
    function setRecurringFeeRatioOverride(
        uint8 _newRecurringFeeRatio
        , uint8 _newRecurringFeeComplementaryRatio
        , address _poolAddress
    ) external isSuperAdminOrPoolOwner(_poolAddress) {
        require(uint256(_newRecurringFeeRatio) *10000/(_newRecurringFeeRatio + _newRecurringFeeComplementaryRatio) <= maxFeeRate, "RateOracle: Fee rate specified too high");
        recurringFeeRatioOverride[_poolAddress] = FeeRatioOverride(_newRecurringFeeRatio, _newRecurringFeeComplementaryRatio);
        emit SetRecurringFeeRatioOverride(_poolAddress, _newRecurringFeeRatio, _newRecurringFeeComplementaryRatio, msg.sender);
    }

    /**
     * @dev returns the expected recurring fee to be paid on {amountToPayFrom} using the recurringFeeRatio already set.
     * @param amountToPayFrom amount from which the recurring rewards is to be paid to the voters. This would usually be the total of the Voter reserve accumulated from CXDS purchases.
     * @param _pool the pool address, for which the rewards are to be paid. This is required to check if any overrides exist for the pool.
     * @return fee the fee amount to be paid.
     */
    function getRecurringFeeAmount(uint256 amountToPayFrom, address _pool) public view returns (uint256 fee) {
        FeeRatioOverride memory _override = recurringFeeRatioOverride[_pool];

        if (_override.ratio == 0) {
            fee = (amountToPayFrom * votersRecurringFeeRatio)/(votersRecurringFeeRatio + votersRecurringFeeComplementaryRatio);
        } else {
            fee = (amountToPayFrom * _override.ratio)/(_override.ratio + _override.complementaryRatio);
        }
    }

    /**
     * @dev returns the expected amount to be added to the voter reserve from the deposited makerFees paid by buyers during purchases.
     * @param amountToPayFrom amount from which the default rewards is to be paid to the voters. This would usually be the makerFee deposited by the buyer during a purchase event.
     * @param _pool the pool address, for which the rewards are to be paid. This is required to check if any overrides exist for the pool.
     * @return fee the fee amount to be paid.
     */
    function getDefaultFeeAmount(uint256 amountToPayFrom, address _pool) public view returns (uint256 fee) {
        FeeRatioOverride memory _override = voterFeeRatioOverride[_pool];

        if (_override.ratio == 0) {
            fee = (amountToPayFrom * votersDefaultFeeRatio)/(votersDefaultFeeRatio + votersDefaultFeeComplementaryRatio);
        } else {
            fee = (amountToPayFrom * _override.ratio)/(_override.ratio + _override.complementaryRatio);
        }
    }

    function getNumberOfVotersRequired(address) public view returns (uint8) {
        return numberOfVotersExpected;
    }

    function getRecurringPaymentInterval(address _pool) public view returns (uint256 count) {
        uint256 _override = paymentIntervalOverride[_pool];
        count = _override == 0 ? votersRecurringPaymentInterval : _override;
    }


}