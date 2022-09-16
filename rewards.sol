// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
import "./uniswapFeeRouter.sol";
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
}

contract rewardPool is Ownable{
    uint256 POOL_START_TIME;
    uint256 DISTRIBUTION_CYCLE;
    //uint256 EPOCH_TIME=604800; // 1 WEEK
    uint256 EPOCH_TIME= 120;
    uint256 constant WEEK_TIME= 604800;
    uint256 constant DISTRIBUTION_TIME = 604800*2;
    uint256 MIN_STACKING_PERIOD = 2419200; // 4 weeks time
    uint256 MAX_STACKING_PERIOD = 13305600;
    address TOKEN_ADDRESS;
    address STAKING_CONTRACT;
    uint256 CURRENT_EPOCH;
    address EXCHANGE_ADDRESS;
    address USDT_ADDRESS;
    mapping(uint256 => uint256) REWARD_WEIGHT_TO_STAKE;
    mapping(uint256 => uint256) EPOCH_TO_START_TIME;
    mapping(uint256 => mapping(uint256 => uint256)) STAKED_REWARDS_PER_EPOCH;
    mapping(uint256 => uint256) EPOCH_START_BALANCE;
    mapping(uint256 => mapping(uint256 => uint256)) public  ACCUMALATED_REWARDS_IN_DISTRIBUTION_CYCLE;
    mapping(uint256 => mapping(uint256 => uint256)) public  ACCUMALATED_REWARDS_IN_EPOCH;
    mapping(uint256 => mapping(uint256 => uint256)) public  ACCUMALATED_PENALTY_IN_DISTRIBUTION_CYCLE;
    mapping(uint256 => bool) isDistributed;
    


    uint256 MAX_YIELD = 9079502202;
    


    constructor(address _token,address _stackingAddress,address _exchange,address _usdt){
        TOKEN_ADDRESS=_token;
        CURRENT_EPOCH=0;
        DISTRIBUTION_CYCLE=0;
        STAKING_CONTRACT= _stackingAddress;
        EXCHANGE_ADDRESS = _exchange;
        USDT_ADDRESS = _usdt;
    }
    modifier epochFinished{
        require(block.timestamp >= EPOCH_TO_START_TIME[CURRENT_EPOCH]," epoch not completed");
        _;
    }
    modifier isDistributionReady{
        require(CURRENT_EPOCH % 2 == 1 && !isDistributed[DISTRIBUTION_CYCLE],"Rewards can be distributed only after 4 epochs");
        _;
    }
    modifier poolStarted{
        require(CURRENT_EPOCH != 0 && DISTRIBUTION_CYCLE!=1,
                "POOL NOT STARTED");
        _;
    }
    function startPool() onlyOwner public returns(bool)
    {
       require(CURRENT_EPOCH == 0 && DISTRIBUTION_CYCLE==1,
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
        uint256 len = StakingToken(STAKING_CONTRACT).getTotalNumberOfStakes();
        uint256 _allocatedRewards = calculateAllocatedRewards(CURRENT_EPOCH);
        for(uint256 i=0;i < len;i++){
              if(StakingToken(STAKING_CONTRACT).getAddedEpoch(i) >= CURRENT_EPOCH) break;
              rewardOfStake(i, _allocatedRewards);
            }
        CURRENT_EPOCH = CURRENT_EPOCH + 1;
        EPOCH_TO_START_TIME[CURRENT_EPOCH]=EPOCH_TO_START_TIME[CURRENT_EPOCH-1]+EPOCH_TIME;
        EPOCH_START_BALANCE[CURRENT_EPOCH] = EPOCH_START_BALANCE[CURRENT_EPOCH-1] - _allocatedRewards;

        return true;

    }
    function calculateAllocatedRewards(uint256 _epoch)  onlyOwner view  internal returns(uint256 epochRewards){
          uint256 vlryBalance = EPOCH_START_BALANCE[_epoch];
          epochRewards= (vlryBalance * 7 * 3 ) / (10 ** 4);
          
    }

    function rewardOfStake(uint256 _stakeId,uint256 _epochRewards) public  onlyOwner poolStarted returns(bool){
        uint256 _yield;
        uint256 _stakeAmount = StakingToken(STAKING_CONTRACT).getStakeAmount(_stakeId);
        uint256 _rewardWeight = REWARD_WEIGHT_TO_STAKE[_stakeId];
        uint256 _totalRewardsWeight = totalRewardWeight();
        uint256 _rewards =  (_rewardWeight * _epochRewards)/_totalRewardsWeight;
        _yield = (_rewards * (10 ** 12)) / _stakeAmount;
        
        if(_yield > MAX_YIELD ) {
            _rewards = (_stakeAmount * MAX_YIELD) /  (10 ** 12) ;
        }

        ACCUMALATED_REWARDS_IN_DISTRIBUTION_CYCLE[DISTRIBUTION_CYCLE][_stakeId] = ACCUMALATED_REWARDS_IN_DISTRIBUTION_CYCLE[DISTRIBUTION_CYCLE][_stakeId]+_rewards;
        ACCUMALATED_REWARDS_IN_EPOCH[CURRENT_EPOCH][_stakeId]=_rewards;

        return true;
    }

    function distributeRewards() public onlyOwner isDistributionReady poolStarted returns(uint256){
        uint256 distributedRewards = 0;
        uint256 len = StakingToken(STAKING_CONTRACT).getTotalNumberOfStakes();
        for(uint256 i=0;i < len;i++){
              if(StakingToken(STAKING_CONTRACT).getAddedEpoch(i) >= CURRENT_EPOCH) break;
              uint256 _rewards = ACCUMALATED_REWARDS_IN_DISTRIBUTION_CYCLE[DISTRIBUTION_CYCLE][i];
              if(_rewards >= 50 * (10**18))
              {
              address holder = StakingToken(STAKING_CONTRACT).getHolderByStakeId(i);
              bool result = IERC20(TOKEN_ADDRESS).transfer(holder,_rewards);
              require(result,"ERROR : transferring rewards");
              distributedRewards= distributedRewards + _rewards;
              ACCUMALATED_REWARDS_IN_DISTRIBUTION_CYCLE[DISTRIBUTION_CYCLE+1][i]=0;
              }
              else{
                   ACCUMALATED_REWARDS_IN_DISTRIBUTION_CYCLE[DISTRIBUTION_CYCLE+1][i]= ACCUMALATED_REWARDS_IN_DISTRIBUTION_CYCLE[DISTRIBUTION_CYCLE][i];
              }
              
        }
        isDistributed[DISTRIBUTION_CYCLE] = true;
        DISTRIBUTION_CYCLE = DISTRIBUTION_CYCLE + 1;
        return distributedRewards;
            
    }

    function getRewardsToGive(uint256 _stakePeriod) internal  returns(uint256){
        
    }
    
    function calculateRewardWeight(uint256 _stakeId,
                            uint256 _mintingFactor,
                            uint256 _referalFactor,
                            uint256 _engagementFactor,
                            uint256 _durationFactor) public epochFinished returns(uint256)
    {
     require(StakingToken(STAKING_CONTRACT).getAddedEpoch(_stakeId) < CURRENT_EPOCH,"THIS STAKE SHOULD BE CONSIDERED FOR NEXT EPOCH");
     uint256 stakeAmount = StakingToken(STAKING_CONTRACT).getStakeAmount(_stakeId);
     if(CURRENT_EPOCH % 12 != 1 ) _engagementFactor = 10 ** 6;
     uint256 rewardWeight = (_mintingFactor * _referalFactor * _engagementFactor * _durationFactor * stakeAmount) / (10 ** 24);
     REWARD_WEIGHT_TO_STAKE[_stakeId] = rewardWeight;
     return rewardWeight; 
    }

    function totalRewardWeight() public view  returns(uint256)
    {
        uint256 len = StakingToken(STAKING_CONTRACT).getTotalNumberOfStakes();
        uint256 _totalRewardWeight=0;
        for(uint256 i=0;i<len;i++){
            _totalRewardWeight= _totalRewardWeight + REWARD_WEIGHT_TO_STAKE[i] ;       
         }
        return  _totalRewardWeight;
    }
     
      function getCurrentEpoch() view  public returns(uint256){
          return CURRENT_EPOCH;
      }

    function getRewardPenalty(uint256 _rewards,uint256 stakedPeriod,uint256 _removedStake,uint256 _totalStake) public  view returns(uint256 penalty){
       if(stakedPeriod == 0) return 0;
       if(stakedPeriod < MIN_STACKING_PERIOD ) penalty = (_rewards*50*_removedStake)/( _totalStake);
       else if (stakedPeriod >= MIN_STACKING_PERIOD && stakedPeriod < 2*MIN_STACKING_PERIOD)
       {
           penalty= (_rewards*40*_removedStake)/( _totalStake);
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
       else if(stakedPeriod > MAX_STACKING_PERIOD) penalty=0; 
    }
    function imposeRewardPenalty(uint256 _stakeId,uint256 stakedPeriod,uint256 _removedStake,uint256 _totalStake) external returns(bool){
        require(msg.sender == STAKING_CONTRACT,"Only stacking contract can impose penalty");
        uint256 _rewards=ACCUMALATED_REWARDS_IN_DISTRIBUTION_CYCLE[DISTRIBUTION_CYCLE][_stakeId];
        ACCUMALATED_PENALTY_IN_DISTRIBUTION_CYCLE[DISTRIBUTION_CYCLE][_stakeId] =getRewardPenalty(_rewards, stakedPeriod,_removedStake,_totalStake);
        return true;
    }
    function sqrt(uint256 x) internal pure  returns (uint256 y)  {
    uint256 z = (x + 1) / 2;
    y = x;
    while (z < y) {
        y = z;
        z = (x / z + z) / 2;
    }

}



}
