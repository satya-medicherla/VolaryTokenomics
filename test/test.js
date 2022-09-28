const stackingContract = artifacts.require("contracts/stacking.sol:StakingToken");
const rewardsContract = artifacts.require("contracts/rewards.sol:rewardPool");
const tokenContract = artifacts.require("Volary")
const { assert } = require('chai');
const truffleAssert = require('truffle-assertions');
const { ethers } = require("hardhat");

