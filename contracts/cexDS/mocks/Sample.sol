// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

/// @title Sample Contract
/// @notice Sample Mock contract for testing function calls to contracts requiring the call to be from another contract
contract Sample {

    bool public initialized;
    uint256 deposits;
    uint8 public constant epochDays = 7;
    uint256 public totalVoterFeeRemaining;

    constructor() {
        initialized = true;
        totalVoterFeeRemaining += 10000 * 1e18;
    }

    function deposit() external payable {
        deposits += msg.value;
    }

    function deductFromVoterReserve(uint256 _amount) external {
        totalVoterFeeRemaining -= _amount;
    }
}