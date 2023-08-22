// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "./interfaces/ISwapController.sol";

contract RateOracle is AccessControl {

    bytes32 public constant SUPER_ADMIN = 'SUPER_ADMIN';
    uint256 public VOTER_RECURRING_PAYMENT_INTERVAL;
    uint8 public VOTERS_DEFAULT_FEE_RATIO;
    uint8 public VOTERS_DEFAULT_FEE_COMPLEMENTARY_RATIO;
    uint8 public VOTERS_RECURRING_FEE_RATIO;
    uint8 public VOTERS_RECURRING_FEE_COMPLEMENTARY_RATIO;
    uint8 public NUMBER_OF_VOTERS_EXPECTED;
    address private controllerAddress;

    struct FeeRatioOverride {
        uint8 ratio;
        uint8 complementaryRatio;
    }

    mapping(address => uint8) numberOfVotersOverride;
    mapping(address => uint256) paymentIntervalOverride;
    mapping(address => FeeRatioOverride) public voterFeeRatioOverride;
    mapping(address => FeeRatioOverride) recurringFeeRatioOverride;

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

        VOTER_RECURRING_PAYMENT_INTERVAL = recurringPaymentInterval;
        VOTERS_DEFAULT_FEE_RATIO = _voterFeeRatio;
        VOTERS_DEFAULT_FEE_COMPLEMENTARY_RATIO = _voterFeeComplementaryRatio;
        VOTERS_RECURRING_FEE_RATIO = _recurringFeeRatio;
        VOTERS_RECURRING_FEE_COMPLEMENTARY_RATIO = _recurringFeeComplementaryRatio;
        NUMBER_OF_VOTERS_EXPECTED = votersRequired;
    }

    modifier isSuperAdminOrPoolOwner(address _pool) {
        if(!hasRole(ISwapController(controllerAddress).getPoolOwnerRole(_pool), msg.sender) && !hasRole(SUPER_ADMIN, msg.sender)) revert("Unauthorized");
        _;
    }

    function grantPoolOwnerRole(address _poolAddress, address _owner) external {

        require(msg.sender == controllerAddress, "Not authorised");
        bytes32 ownerRole = ISwapController(controllerAddress).getPoolOwnerRole(_poolAddress);

        _setRoleAdmin(ownerRole, SUPER_ADMIN);
        grantRole(ownerRole, _owner);

    }

    function setVoterFeeRatio(
        uint8 _newVoterFeeRatio
        , uint8 _newVoterFeeComplementaryRatio
    ) external onlyRole(SUPER_ADMIN) {
        VOTERS_DEFAULT_FEE_RATIO = _newVoterFeeRatio;
        VOTERS_DEFAULT_FEE_COMPLEMENTARY_RATIO = _newVoterFeeComplementaryRatio;
    }

    function setVoterFeeRatioOverride(
        uint8 _newVoterFeeRatio
        , uint8 _newVoterFeeComplementaryRatio
        , address _poolAddress
    ) external isSuperAdminOrPoolOwner(_poolAddress) {
        voterFeeRatioOverride[_poolAddress] = FeeRatioOverride(_newVoterFeeRatio, _newVoterFeeComplementaryRatio);
    }

    function setNumberOfVoters(
        uint8 _newValue
    ) external onlyRole(SUPER_ADMIN) {
        NUMBER_OF_VOTERS_EXPECTED = _newValue;
    }

    function setNumberOfVotersOverride(
        uint8 _newValue
        , address _poolAddress
    ) external isSuperAdminOrPoolOwner(_poolAddress) {
        numberOfVotersOverride[_poolAddress] = _newValue;
    }

    function setVotersPaymentInterval(
        uint256 _newInterval
    ) external onlyRole(SUPER_ADMIN) {
        VOTER_RECURRING_PAYMENT_INTERVAL = _newInterval;
    }

    function setVotersPaymentIntervalOverride(
        uint256 _newInterval
        , address _poolAddress
    ) external isSuperAdminOrPoolOwner(_poolAddress) {
        paymentIntervalOverride[_poolAddress] = _newInterval;
    }

    function setRecurringFeeRatio(
        uint8 _newRecurringFeeRatio
        , uint8 _newRecurringFeeComplementaryRatio
    ) external onlyRole(SUPER_ADMIN) {
        VOTERS_RECURRING_FEE_RATIO = _newRecurringFeeRatio;
        VOTERS_RECURRING_FEE_COMPLEMENTARY_RATIO = _newRecurringFeeComplementaryRatio;
    }

    function setRecurringFeeRatioOverride(
        uint8 _newRecurringFeeRatio
        , uint8 _newRecurringFeeComplementaryRatio
        , address _poolAddress
    ) external isSuperAdminOrPoolOwner(_poolAddress) {
        recurringFeeRatioOverride[_poolAddress] = FeeRatioOverride(_newRecurringFeeRatio, _newRecurringFeeComplementaryRatio);
    }


    function getRecurringFeeAmount(uint256 amountToPayFrom, address _pool) public view returns (uint256 fee) {
        FeeRatioOverride memory _override = recurringFeeRatioOverride[_pool];

        if (_override.ratio == 0) {
            fee = (amountToPayFrom * VOTERS_RECURRING_FEE_RATIO)/(VOTERS_RECURRING_FEE_RATIO + VOTERS_RECURRING_FEE_COMPLEMENTARY_RATIO);
        } else {
            fee = (amountToPayFrom * _override.ratio)/(_override.ratio + _override.complementaryRatio);
        }
    }

    function getDefaultFeeAmount(uint256 amountToPayFrom, address _pool) public view returns (uint256 fee) {
        FeeRatioOverride memory _override = voterFeeRatioOverride[_pool];

        if (_override.ratio == 0) {
            fee = (amountToPayFrom * VOTERS_DEFAULT_FEE_RATIO)/(VOTERS_DEFAULT_FEE_RATIO + VOTERS_DEFAULT_FEE_COMPLEMENTARY_RATIO);
        } else {
            fee = (amountToPayFrom * _override.ratio)/(_override.ratio + _override.complementaryRatio);
        }
    }

    function getNumberOfVotersRequired(address _pool) public view returns (uint8 count) {
        uint8 _override = numberOfVotersOverride[_pool];
        count = _override == 0 ? NUMBER_OF_VOTERS_EXPECTED : _override;
    }

    function getRecurringPaymentInterval(address _pool) public view returns (uint256 count) {
        uint256 _override = paymentIntervalOverride[_pool];
        count = _override == 0 ? VOTER_RECURRING_PAYMENT_INTERVAL : _override;
    }


    function getPoolOwnerRole(address _poolAddress) public pure returns (bytes32 ownerRole) {
        ownerRole = bytes32(abi.encodePacked(
            "Pool ",
            Strings.toHexString(uint160(_poolAddress), 20),
            " Owner Role"
        ));
    }


}