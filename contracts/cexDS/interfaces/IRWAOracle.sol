// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

interface IRWAOracle {
  
    function getDefaultedTVL(address _pool) external view returns(uint256);

     function getPercentageDefaulted(address _pool) external view returns(uint256);
}