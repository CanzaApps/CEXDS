// SPDX-License-Identifier: MIT

pragma solidity ~0.8.18;
import "@openzeppelin/contracts/access/Ownable.sol";
import "./interfaces/IRWAOracle.sol";

contract RWAOracle is Ownable, IRWAOracle {
    uint256 public bassisPoints = 10000;
    mapping(address => uint256) TVL;
    mapping(address => uint256) defaultedTVL;
    mapping(address => uint256) percentageDefaulted;


    function setPool(address _pool, uint256 _tvl) external onlyOwner {
        TVL[_pool] = _tvl;
        defaultedTVL[_pool] = 0;
        percentageDefaulted[_pool] = 0;
    }

    function updatePool(address _pool, uint256 _defaultedTVL, uint256 _percentageDefaulted) external onlyOwner {
        defaultedTVL[_pool] = _defaultedTVL;
        percentageDefaulted[_pool] = _percentageDefaulted;
    }

    function resetPool(address _pool) external onlyOwner {
        TVL[_pool] = 0;
        defaultedTVL[_pool] = 0;
        percentageDefaulted[_pool] = 0;
    }


    function getDefaultedTVL(address _pool) external view returns(uint256){
        return defaultedTVL[_pool];
       
    }

     function getPercentageDefaulted(address _pool) external view returns(uint256){
      return  percentageDefaulted[_pool]/bassisPoints;
    }


}