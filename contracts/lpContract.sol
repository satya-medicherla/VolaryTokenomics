// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract lpToken is ERC20,Ownable {
     

    constructor() ERC20("testVolary", "tVLRY") {

    }
    
    function getLpTokens(address receiver,uint256 amount) 
    public
    onlyOwner
    returns(bool){
        _mint(receiver, amount);
        return true;
    }


}

