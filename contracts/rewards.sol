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
}

contract rewardPool is Ownable{
    uint256 public POOL_START_TIME;
    uint256 public DISTRIBUTION_CYCLE;
    uint256 constant EPOCH_TIME=604800; // 1 WEEK
   // uint256 constant EPOCH_TIME= 120;
    uint256 constant WEEK_TIME= 604800;
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
    mapping(uint256 => mapping(uint256 => uint256)) public REWARD_WEIGHT_TO_STAKE;
    mapping(uint256 => uint256) public  EPOCH_TO_START_TIME;
    mapping(uint256 => mapping(uint256 => uint256)) public STAKED_REWARDS_PER_EPOCH;
    mapping(uint256 => uint256) public EPOCH_START_BALANCE;
    mapping(uint256 => uint256) public  ACCUMALATED_REWARDS;
    mapping(uint256 => bool) isDistributed;
    mapping(uint256 => uint256) public CLAIMABLE_REWARDS;
    mapping(uint256 => uint256) DURATION_FACTOR;
    mapping(uint256 => uint256) public CLAIMED_REWARDS;
    address TREASURY;
    mapping(uint256 => uint256) rewardWeightCounter;
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
        require(rewardCounter[CURRENT_EPOCH]==StakingToken(STAKING_CONTRACT).getstakesTillEpoch(CURRENT_EPOCH),"ALL STAKE REWARDS ARE NOT CALCULATED");
        uint256 _allocatedRewards = calculateAllocatedRewards(CURRENT_EPOCH);
        CURRENT_EPOCH = CURRENT_EPOCH + 1;
        EPOCH_TO_START_TIME[CURRENT_EPOCH]=EPOCH_TO_START_TIME[CURRENT_EPOCH-1]+EPOCH_TIME;
        EPOCH_START_BALANCE[CURRENT_EPOCH] = EPOCH_START_BALANCE[CURRENT_EPOCH-1] - _allocatedRewards;
        if(CURRENT_EPOCH % 2 == 0 && CURRENT_EPOCH != 0)
        {
            DISTRIBUTION_CYCLE = DISTRIBUTION_CYCLE + 1;
            isDistributed[DISTRIBUTION_CYCLE] = true;
        }
        return true;

    }
    function calculateAllocatedRewards(uint256 _epoch)  onlyOwner view  internal returns(uint256 epochRewards){
          uint256 vlryBalance = EPOCH_START_BALANCE[_epoch];
          epochRewards= (vlryBalance * 7 * 3 ) / (10 ** 4);
          
    }

    function rewardOfStake(uint256 _stakeId) public  onlyOwner poolStarted returns(bool){
        require(rewardWeightCounter[CURRENT_EPOCH] == StakingToken(STAKING_CONTRACT).getstakesTillEpoch(CURRENT_EPOCH),"ALL THE REWARD WEIGHTS  ARE TO BE CALCULATED BEFORE REWARDING");
        require(!rewardCalculated[_stakeId][CURRENT_EPOCH],"reward already calculated");
        require(rewardCounter[CURRENT_EPOCH]<= StakingToken(STAKING_CONTRACT).getstakesTillEpoch(CURRENT_EPOCH),"ALL THE REWARDs ARE CALCULATED");
        uint256 _yield;
        uint256 _epochRewards=calculateAllocatedRewards(CURRENT_EPOCH);
        uint256 _stakeAmount = StakingToken(STAKING_CONTRACT).getStakeAmount(_stakeId);
        uint256 _rewardWeight = REWARD_WEIGHT_TO_STAKE[_stakeId][CURRENT_EPOCH];
        uint256 _totalRewardsWeight = totalRewardWeight[CURRENT_EPOCH];
        uint256 _rewards =  (_rewardWeight * _epochRewards)/_totalRewardsWeight;
        _yield = (_rewards * (10 ** 12)) / _stakeAmount;
        
        if(_yield > MAX_YIELD ) {
            _rewards = (_stakeAmount * MAX_YIELD) /  (10 ** 12) ;
        }
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

    function getRewardsToGive(uint256 _stakeId) internal view returns(uint256){
        uint256 _rewards = ACCUMALATED_REWARDS[_stakeId];
        uint256 stakedPeriod = StakingToken(STAKING_CONTRACT).getStakedPeriod(_stakeId);
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
    
    function calculateRewardWeight(uint256 _stakeId,
                            uint256 _mintingFactor,
                            uint256 _referalFactor,
                            uint256 _engagementFactor,
                            uint256 _durationFactor) public epochFinished onlyOwner returns(uint256)
    {
     require(StakingToken(STAKING_CONTRACT).getAddedEpoch(_stakeId) < CURRENT_EPOCH,"THIS STAKE SHOULD BE CONSIDERED FOR NEXT EPOCH");
     require(rewardWeightCounter[CURRENT_EPOCH] <= StakingToken(STAKING_CONTRACT).getstakesTillEpoch(CURRENT_EPOCH),"ALL THE REWARD WEIGTHS ARE CALCULATED");
     require(REWARD_WEIGHT_TO_STAKE[_stakeId][CURRENT_EPOCH] == 0,"WEIGHT OF THIS STAKE ALREADY CALCULATED");
     uint256 stakeAmount = StakingToken(STAKING_CONTRACT).getStakeAmount(_stakeId);
     if(CURRENT_EPOCH % 12 != 1 ) _engagementFactor = 10 ** 6;
     uint256 rewardWeight = (_mintingFactor * _referalFactor * _engagementFactor * _durationFactor * stakeAmount);
     REWARD_WEIGHT_TO_STAKE[_stakeId][CURRENT_EPOCH] = rewardWeight;
     DURATION_FACTOR[_stakeId] = _durationFactor;
     rewardWeightCounter[CURRENT_EPOCH]++;
     totalRewardWeight[CURRENT_EPOCH]+= REWARD_WEIGHT_TO_STAKE[_stakeId][CURRENT_EPOCH];
     return rewardWeight; 
    }
     
      function getCurrentEpoch() view  public returns(uint256){
          return CURRENT_EPOCH;
      }

    function getRewardPenalty(uint256 _rewards,uint256 stakedPeriod,uint256 _removedStake,uint256 _totalStake) public  view returns(uint256 penalty){
       if(stakedPeriod == 0) return 0;
       else if (stakedPeriod >= MIN_STACKING_PERIOD && stakedPeriod < 2*MIN_STACKING_PERIOD)
       {
           return (_rewards*60)/(100);
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
           (_rewards*10*_removedStake)/( _totalStake);
       }
       else if(stakedPeriod >= MAX_STACKING_PERIOD) penalty=0; 
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
    function getBlockStamp() view public returns(uint256){
          return block.timestamp;
    }
}
