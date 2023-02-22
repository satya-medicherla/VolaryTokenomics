// SPDX-License-Identifier: MIT
// this contract is sample demonstation of pricefeed oracle to feed vlry price

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";

contract priceFeed is Ownable{

    uint256 priceInUsd;
    constructor(){

    }

    function feedPrice(uint256 price) public  onlyOwner returns(bool){
         priceInUsd = price;
         return true;
    }

    function getPrice() public view returns(uint256){
        return priceInUsd;
    }
    
    
}