// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";


interface  StakingToken {
    function createStake(uint256 _stakeAmount,uint256 _duration) external ;
    function updateStake(uint256 _stakeId,uint256 _addStake) external  returns(bool);
    function getStackerLevel(address _stakeholder) external  view returns(string memory);
    function removeStake(uint256 _stakeId,uint256 _stake) external  returns(bool);
    function stakeOf(address _stakeholder) external view returns(uint256);
    function totalStakes() external view returns(uint256);
    function rewardOf(address _stakeholder) external view returns(uint256);
    function getStartTimeOfStake(uint256 _stakeId) view external  returns(uint256);
    function getHolderByStakeId(uint256 _stakeId) external  view returns(address);
    function isDurationBound(uint256 _stakeId) external  view returns(bool);
    function getStakeAmount(uint256 _stakeId) external  view returns(uint256);
    function getDuration(uint256 _stakeId) external  view returns(uint256);
    function getTotalNumberOfStakes() external view returns(uint256);
    function getStakedPeriod(uint256 _stakeId) external view returns(uint256);
    function getAddedEpoch(uint256 _stakeId) external returns(uint256);
    function getstakesTillEpoch(uint256 epochNumber) external view returns(uint256);
    function getactiveStakesTillEpoch(uint256 epoch) external view returns(uint256);
}

contract rewardPool is Ownable{
    uint256 public POOL_START_TIME;
    uint256 public DISTRIBUTION_CYCLE;
    uint256 constant EPOCH_TIME=604800; // 1 WEEK
   // uint256 constant EPOCH_TIME= 120;
    uint256 constant WEEK_TIME= 604800;
    uint256 constant ONE_DAY =  86400;
    //uint256 constant WEEK_TIME= 120;
    uint256 constant DISTRIBUTION_TIME = 604800*2;
   uint256 MIN_STACKING_PERIOD = 2419200; // 4 weeks time
   //uint256 MIN_STACKING_PERIOD = 240;
    uint256 MAX_STACKING_PERIOD = 13305600;
    address TOKEN_ADDRESS;
    address STAKING_CONTRACT;
    uint256 public CURRENT_EPOCH;
    address EXCHANGE_ADDRESS;
    address USDT_ADDRESS;
    mapping(uint256 => uint256) public  EPOCH_TO_START_TIME;
    mapping(uint256 => uint256) public EPOCH_START_BALANCE;
    mapping(uint256 => uint256) public  ACCUMALATED_REWARDS;
    mapping(uint256 => bool) isDistributed;
    mapping(uint256 => uint256) public CLAIMABLE_REWARDS;
    mapping(uint256 => uint256) DURATION_FACTOR;
    mapping(uint256 => uint256) public CLAIMED_REWARDS;
    address TREASURY;
    mapping(uint256 => uint256) rewardCounter;
    mapping(uint256 => uint256) totalRewardWeight;
    mapping(uint256 => mapping(uint256 => bool)) rewardCalculated;


    uint256 MAX_YIELD = 9079502202;
    


    constructor(address _token,address _stackingAddress,address _exchange,address _usdt,address _treasury)
    {
        TOKEN_ADDRESS=_token;
        CURRENT_EPOCH=0;
        DISTRIBUTION_CYCLE=0;
        STAKING_CONTRACT= _stackingAddress;
        EXCHANGE_ADDRESS = _exchange;
        USDT_ADDRESS = _usdt;
        TREASURY = _treasury;
    }
    modifier epochFinished{
        require(block.timestamp >= EPOCH_TO_START_TIME[CURRENT_EPOCH]+EPOCH_TIME," epoch not completed");
        _;
    }
    modifier poolStarted{
        require(CURRENT_EPOCH != 0 && DISTRIBUTION_CYCLE != 0,
                "POOL NOT STARTED");
        _;
    }

    modifier userAccess
    {
        uint256 epochEndTime = EPOCH_TO_START_TIME[CURRENT_EPOCH]+EPOCH_TIME;
        require( block.timestamp >= epochEndTime 
                && block.timestamp <= epochEndTime+ONE_DAY,"ACCESS RESTRICTED FOR USERS NOW");
        _;
    }

    modifier adminAccess
    {
        uint256 userAccessEndTime = EPOCH_TO_START_TIME[CURRENT_EPOCH]+EPOCH_TIME + ONE_DAY;
        require( block.timestamp > userAccessEndTime 
                && block.timestamp <= userAccessEndTime+ONE_DAY,"ACCESS RESTRICTED FOR ADMIN NOW");
        _;
    }
    function startPool() onlyOwner public returns(bool)
    {
       require(CURRENT_EPOCH == 0 && DISTRIBUTION_CYCLE== 0 ,
                "POOL ALREADY STARTED");
       CURRENT_EPOCH = 1;
       DISTRIBUTION_CYCLE = 1;
       POOL_START_TIME=block.timestamp;
       EPOCH_TO_START_TIME[CURRENT_EPOCH]=POOL_START_TIME;
       EPOCH_START_BALANCE[CURRENT_EPOCH] = IERC20(TOKEN_ADDRESS).balanceOf(address(this));
       isDistributed[DISTRIBUTION_CYCLE] = true;
      return true;
    }
    
    function finishEpoch() onlyOwner epochFinished public returns(bool){
        require(rewardCounter[CURRENT_EPOCH]==StakingToken(STAKING_CONTRACT).getactiveStakesTillEpoch(CURRENT_EPOCH),"ALL STAKE REWARDS ARE NOT CALCULATED");
        CURRENT_EPOCH = CURRENT_EPOCH + 1;
        EPOCH_TO_START_TIME[CURRENT_EPOCH]=EPOCH_TO_START_TIME[CURRENT_EPOCH-1]+EPOCH_TIME;
        if(CURRENT_EPOCH % 2 == 0 && CURRENT_EPOCH != 0)
        {
            DISTRIBUTION_CYCLE = DISTRIBUTION_CYCLE + 1;
            isDistributed[DISTRIBUTION_CYCLE] = true;
        }
        return true;

    }

    function rewardOfStake(uint256 _stakeId,string memory message,bytes memory signature) public   poolStarted userAccess returns(bool){
        require( msg.sender == StakingToken(STAKING_CONTRACT).getHolderByStakeId(_stakeId),"not stake holder");
        require( ! rewardCalculated[_stakeId][CURRENT_EPOCH] , "REWARD FOR THIS EPOCH IS SET");
        require( StakingToken(STAKING_CONTRACT).getStakeAmount(_stakeId) > 0 ,"STAKE DOESNT EXISTS");
        address signer =verifyString(message, signature);
        require(signer == owner(),"signature mismatch");
        (uint256 _rewards,bool err) = stringToUint(message);
        require(!err , "rewards type mismatch");
        ACCUMALATED_REWARDS[_stakeId] = ACCUMALATED_REWARDS[_stakeId]+_rewards;
        rewardCalculated[_stakeId][CURRENT_EPOCH]=true;
        if(CURRENT_EPOCH % 2 == 0 && CURRENT_EPOCH != 0){
              uint256 _rewardsGiven = getRewardsToGive(_stakeId);
              CLAIMABLE_REWARDS[_stakeId] = _rewardsGiven;
              CLAIMABLE_REWARDS[_stakeId] -= CLAIMED_REWARDS[_stakeId];
        }
        rewardCounter[CURRENT_EPOCH]++;
        return true;
    }

    function rewardOfStakeByAdmin(uint256 _stakeId,uint256 _rewards, uint256 _gasFeePenalty) public onlyOwner poolStarted adminAccess returns(bool){
        require( ! rewardCalculated[_stakeId][CURRENT_EPOCH] , "REWARD FOR THIS EPOCH IS SET");
        require( StakingToken(STAKING_CONTRACT).getStakeAmount(_stakeId) > 0 ,"STAKE DOESNT EXISTS");
        _rewards = _rewards - _gasFeePenalty;
        IERC20(TOKEN_ADDRESS).transfer(owner(),_gasFeePenalty);
        ACCUMALATED_REWARDS[_stakeId] = ACCUMALATED_REWARDS[_stakeId]+_rewards;
        rewardCalculated[_stakeId][CURRENT_EPOCH]=true;
        if(CURRENT_EPOCH % 2 == 0 && CURRENT_EPOCH != 0){
              uint256 _rewardsGiven = getRewardsToGive(_stakeId);
              CLAIMABLE_REWARDS[_stakeId] = _rewardsGiven;
              CLAIMABLE_REWARDS[_stakeId] -= CLAIMED_REWARDS[_stakeId];
        }
        rewardCounter[CURRENT_EPOCH]++;
        return true;
        
    } 

    function getRewardsToGive(uint256 _stakeId) internal view returns(uint256){
        uint256 _rewards = ACCUMALATED_REWARDS[_stakeId];
        uint256 stakedPeriod = block.timestamp - StakingToken(STAKING_CONTRACT).getStartTimeOfStake(_stakeId);
        if(stakedPeriod < MIN_STACKING_PERIOD ) return (_rewards*50)/(100);    
       else if (stakedPeriod >= MIN_STACKING_PERIOD && stakedPeriod < 2*MIN_STACKING_PERIOD)
       {
           return (_rewards*60)/(100);
       }
       else if (stakedPeriod >= 2*MIN_STACKING_PERIOD && stakedPeriod < 3*MIN_STACKING_PERIOD)
       {
           return (_rewards*70)/(100); 
       }
       else if (stakedPeriod >= 3*MIN_STACKING_PERIOD && stakedPeriod < 4*MIN_STACKING_PERIOD)
       {
           return (_rewards*80)/(100);
       }
       else if (stakedPeriod >= 4*MIN_STACKING_PERIOD && stakedPeriod < MAX_STACKING_PERIOD)
       {
           return (_rewards*90)/(100);
       }
       else return _rewards;

    }    

    function claimRewards(uint256 _stakeId,uint256 _rewardToClaim) public returns(bool){
        require(msg.sender == StakingToken(STAKING_CONTRACT).getHolderByStakeId(_stakeId),"ONLY HOLDER CLAIM REWARDS");
        require(_rewardToClaim <= CLAIMABLE_REWARDS[_stakeId],"cant withdraw more than claimble rewards");
        CLAIMED_REWARDS[_stakeId] += _rewardToClaim;
        CLAIMABLE_REWARDS[_stakeId] -= _rewardToClaim;
        IERC20(TOKEN_ADDRESS).transfer(msg.sender,_rewardToClaim);
        return true;

    }

    function getDuration(uint256 _stakeId) view public returns(uint256){
       return DURATION_FACTOR[_stakeId];
    }

     
      function getCurrentEpoch() view  public returns(uint256){
          return CURRENT_EPOCH;
      }

    function getRewardPenalty(uint256 _rewards,uint256 stakedPeriod,uint256 _removedStake,uint256 _totalStake) public  view returns(uint256 penalty){
       if (stakedPeriod >= MIN_STACKING_PERIOD && stakedPeriod < 2*MIN_STACKING_PERIOD)
       {
           penalty = (_rewards*60* _removedStake )/(_totalStake);
       }
       else if (stakedPeriod >= 2*MIN_STACKING_PERIOD && stakedPeriod < 3*MIN_STACKING_PERIOD)
       {
           penalty= (_rewards*30*_removedStake)/( _totalStake); 
       }
       else if (stakedPeriod >= 3*MIN_STACKING_PERIOD && stakedPeriod < 4*MIN_STACKING_PERIOD)
       {
           penalty= (_rewards*20*_removedStake)/( _totalStake);
       }
       else if (stakedPeriod >= 4*MIN_STACKING_PERIOD && stakedPeriod < MAX_STACKING_PERIOD)
       {
           penalty = (_rewards*10*_removedStake)/( _totalStake);
       }
        
    }
    function imposeRewardPenalty(uint256 _stakeId,uint256 stakedPeriod,uint256 _removedStake,uint256 _totalStake) external returns(bool){
        require(msg.sender == STAKING_CONTRACT,"Only stacking contract can impose penalty");
        uint256 _rewards = ACCUMALATED_REWARDS[_stakeId];
        uint256 _penalty = getRewardPenalty(_rewards, stakedPeriod, _removedStake, _totalStake)/100;
        uint256 rewardsToBeTransferedNow = ( ACCUMALATED_REWARDS[_stakeId] * _removedStake)/(_totalStake);
        rewardsToBeTransferedNow -= _penalty ;
        IERC20(TOKEN_ADDRESS).transfer(TREASURY,_penalty);
        ACCUMALATED_REWARDS[_stakeId] -= rewardsToBeTransferedNow;
        ACCUMALATED_REWARDS[_stakeId] -= _penalty;
        address holder = StakingToken(STAKING_CONTRACT).getHolderByStakeId(_stakeId);
        IERC20(TOKEN_ADDRESS).transfer(holder,rewardsToBeTransferedNow);
        return true;
    }

    function totalStakeRemoved(uint256 _stakeId) external returns(bool) {
        require(msg.sender == STAKING_CONTRACT,"not stacking contract");
        CLAIMABLE_REWARDS[_stakeId] += ACCUMALATED_REWARDS[_stakeId];
        return true; 
    }

   


    //verifying functions 

       function verifyString(string memory message,bytes memory signature) public pure returns (address signer) {

        string memory header = "\x19Ethereum Signed Message:\n000000";
        (bytes32 r, bytes32 s, uint8 v) = splitSignature(signature);
        uint256 lengthOffset;
        uint256 length;
        assembly {
           
            length := mload(message)
            // The beginning of the base-10 message length in the prefix
            lengthOffset := add(header, 57)
        }

        // Maximum length we support
        require(length <= 999999);

        // The length of the message's length in base-10
        uint256 lengthLength = 0;

        // The divisor to get the next left-most message length digit
        uint256 divisor = 100000;

        // Move one digit of the message length to the right at a time
        while (divisor != 0) {

            // The place value at the divisor
            uint256 digit = length / divisor;
            if (digit == 0) {
                // Skip leading zeros
                if (lengthLength == 0) {
                    divisor /= 10;
                    continue;
                }
            }

            // Found a non-zero digit or non-leading zero digit
            lengthLength++;

            // Remove this digit from the message length's current value
            length -= digit * divisor;

            // Shift our base-10 divisor over
            divisor /= 10;

            // Convert the digit to its ASCII representation (man ascii)
            digit += 0x30;
            // Move to the next character and write the digit
            lengthOffset++;

            assembly {
                mstore8(lengthOffset, digit)
            }
        }

        // The null string requires exactly 1 zero (unskip 1 leading 0)
        if (lengthLength == 0) {
            lengthLength = 1 + 0x19 + 1;
        } else {
            lengthLength += 1 + 0x19;
        }

        // Truncate the tailing zeros from the header
        assembly {
            mstore(header, lengthLength)
        }

        // Perform the elliptic curve recover operation
        bytes32 check = keccak256(abi.encodePacked(header, message));

        return ecrecover(check, v, r, s);
    }

    function splitSignature(
        bytes memory sig
    ) public pure returns (bytes32 r, bytes32 s, uint8 v) {
        require(sig.length == 65, "invalid signature length");

        assembly {
           
            r := mload(add(sig, 32))
            s := mload(add(sig, 64))
            v := byte(0, mload(add(sig, 96)))
        }
    }

    function stringToUint(string memory s) public pure returns (uint, bool) {
    bool hasError = false;
    bytes memory b = bytes(s);
    uint result = 0;
    uint oldResult = 0;
    for (uint i = 0; i < b.length; i++) { // c = b[i] was not needed
        if ( uint8(b[i]) >= 48 && uint8(b[i]) <= 57) {
            // store old value so we can check for overflows
            oldResult = result;
            result = result * 10 + (uint8(b[i]) - 48); // bytes and int are not compatible with the operator -.
            // prevent overflows
            if(oldResult > result ) {
                // we can only get here if the result overflowed and is smaller than last stored value
                hasError = true;
            }
        } else {
            hasError = true;
        }
    }
    return (result, hasError); 
}
}
