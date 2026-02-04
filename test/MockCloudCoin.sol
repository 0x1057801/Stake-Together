// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

import {ERC20} from "openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";


// using my own Mock token based on what I learned doing the NFT auction project

contract MockCloudCoin is ERC20 {
    
    constructor() ERC20("CloudCoin", "CLOUD") {
        // mint 10 milion tokens for testing
        _mint(msg.sender, 10_000_000 * 10**18); 
    }
    
    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}