// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract USDT is ERC20 {
    constructor() ERC20("USDT", "USDT") {
        uint256 initialSupply = 1000000 * 10**decimals(); // 1 million tokens with decimals
        _mint(msg.sender, initialSupply);
    }
}