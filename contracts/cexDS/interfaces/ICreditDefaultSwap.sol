// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

interface ICreditDefaultSwap {
    function setDefaulted() external;

    function resetAfterDefault(uint256 _newMaturityDate) external;

    function pause() external;

    function unpause() external;

    function closePool() external;

    function rollEpoch() external;
}
