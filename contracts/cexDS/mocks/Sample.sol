// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

/// @title Sample Contract
/// @notice Sample Mock contract for testing function calls to contracts requiring the call to be from another contract
contract Sample {

    bool public initialized;
    uint256 deposits;

    constructor() {
        initialized = true;
    }

    function deposit() external payable {
        deposits += msg.value;
    }
}