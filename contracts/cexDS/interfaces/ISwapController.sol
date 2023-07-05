// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

interface ISwapController {
    function payFees(uint256 _amountPaid) external;

    function swapList() external view returns (address[] memory);

    function PERCENTAGE_VOTERS_DEFAULT_FEE() external view returns (uint256);
}
