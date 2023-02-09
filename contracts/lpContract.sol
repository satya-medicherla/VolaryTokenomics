// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract lpToken is ERC721URIStorage {
     
    address owner;
    address vlryAddress;
    mapping (uint256 => uint256) private stakedAmount;
    uint256 id;

    
    constructor(address _vlryAddress)  ERC721("VOLARY LP POOL", "VLRYLP") {
        owner=msg.sender;
        vlryAddress = _vlryAddress;
        id=0;
    }

    function stakeVolary(uint256 amount) public {
       
       (bool success) = IERC20(vlryAddress).transferFrom(msg.sender, address(this), amount);
       require(success,"error on transferring volary tokens");
       _mint(msg.sender, id);
       stakedAmount[id] = amount;
       id++;    
    }

    function getLpStake(uint256 _id) public view returns(uint256){
        return stakedAmount[_id];
    }


}

