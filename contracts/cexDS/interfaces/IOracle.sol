// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

interface IOracle {
    function getRecurringFeeAmount(uint256 amountToPayFrom, address _pool) external view returns (uint256);

    function getDefaultFeeAmount(uint256 amountToPayFrom, address _pool) external view returns (uint256);

    function getNumberOfVotersRequired(address _pool) external view returns (uint8);

    function getRecurringPaymentInterval(address _pool) external view returns (uint256);

    function getPoolOwnerRole(address) external pure returns (bytes32);
}