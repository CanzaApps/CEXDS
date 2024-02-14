// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

interface ISwapController {
    function payFees(uint256 _amountPaid) external;

    function getSwapList() external view returns (address[] memory);

    function PERCENTAGE_VOTERS_DEFAULT_FEE() external view returns (uint256);

    function getPoolOwnerRole(address _poolAddress) external pure returns (bytes32 ownerRole);

    function isPoolOwner(address _poolAddress, address _user) external view returns (bool);
}
