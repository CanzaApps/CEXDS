// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

interface ICreditDefaultSwap {
    function setDefaulted(uint256 _percentageDefaulted) external;

    function resetAfterDefault() external;

    function withdrawFromBalance(uint256 _amount, address _recipient) external;

    function pause() external;

    function unpause() external;

    function closePool() external;

    function rollEpoch() external;

    function totalVoterFeeRemaining() external view returns (uint256);
}
