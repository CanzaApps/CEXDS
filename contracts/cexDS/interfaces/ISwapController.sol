// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

interface ISwapController {
    function payFees(uint256 _amountPaid) external;
}
