// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

interface ICreditDefaultSwap {
    function setDefaulted(bool _value) external;

    function resetAfterDefault(uint256 _newMaturityDate) external;

    function pause() external;

    function unpause() external;
}
