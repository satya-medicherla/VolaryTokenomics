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
}

contract rewardPool is Ownable{
    uint256 POOL_START_TIME;
    uint256 EPOCH_TIME=604800; // 1 WEEK
    uint256 constant WEEK_TIME= 604800;
    uint256 MIN_STACKING_PERIOD = 2419200; // 4 weeks time
    uint256 MAX_STACKING_PERIOD = 13305600;
    address TOKEN_ADDRESS;
    address STAKING_CONTRACT;
    uint256 CURRENT_EPOCH;
    address EXCHANGE_ADDRESS;
    address USDT_ADDRESS;
    mapping(uint256 => uint256) REWARD_WEIGHT_TO_STAKE;
    mapping(uint256 => uint256) EPOCH_TO_START_TIME;
    


    constructor(address _token,address _stackingAddress,address _exchange,address _usdt){
        TOKEN_ADDRESS=_token;
        POOL_START_TIME=block.timestamp;
        CURRENT_EPOCH=1;
        EPOCH_TO_START_TIME[CURRENT_EPOCH]=POOL_START_TIME;
        STAKING_CONTRACT= _stackingAddress;
        EXCHANGE_ADDRESS = _exchange;
        USDT_ADDRESS = _usdt;
    }
    modifier epochFinished{
        uint256 timeElasped = block.timestamp - POOL_START_TIME - CURRENT_EPOCH*EPOCH_TIME;
        require(timeElasped > EPOCH_TIME," epoch not completed");
        _;
    }
    function calculateEpochRewards()  onlyOwner internal returns(uint256 epochRewards){
          uint256 vlryBalance = IERC20(TOKEN_ADDRESS).balanceOf(address(this));
          epochRewards= (vlryBalance * 7 * 3 ) / 100 ;
          CURRENT_EPOCH = CURRENT_EPOCH + 1;
          EPOCH_TO_START_TIME[CURRENT_EPOCH]=EPOCH_TO_START_TIME[CURRENT_EPOCH-1]+EPOCH_TIME;
    }

    function rewardOfStake(uint256 _stakeId,uint256 _epochRewards) public view returns(uint256){
        uint256 _stakeAmount = StakingToken(STAKING_CONTRACT).getStakeAmount(_stakeId);
        uint256 _rewardWeight = REWARD_WEIGHT_TO_STAKE[_stakeId];
        uint256 _totalRewardsWeight = totalRewardWeight();
        uint256 _rewards =  (_rewardWeight * _epochRewards)/_totalRewardsWeight;
        _rewards = _rewards - getRewardPenalty(_stakeId, _rewards);
        uint256 _yield = (_rewards*10) / _stakeAmount;
        if(_yield > 6) {
            _rewards = (_stakeAmount * 6) / 10 ;
        }
        return _rewards;
    }

    function distributeEpochRewards() public onlyOwner epochFinished returns(uint256){
        uint256 epochRewards = calculateEpochRewards();
        uint256 distributedRewards = 0;
        uint256 len = StakingToken(STAKING_CONTRACT).getTotalNumberOfStakes();
        for(uint256 i=0;i < len;i++){
              uint256 _rewards = rewardOfStake(i,epochRewards);
              address holder = StakingToken(STAKING_CONTRACT).getHolderByStakeId(i);
              bool result = IERC20(TOKEN_ADDRESS).transfer(holder,_rewards);
              require(result,"ERROR : transferring rewards");
              distributedRewards= distributedRewards + _rewards;
        }
        if(distributedRewards < epochRewards) {
            uint256 buybackRewards= epochRewards - distributedRewards;
            IUniswapV2Pair(EXCHANGE_ADDRESS).swap(buybackRewards*2,buybackRewards,STAKING_CONTRACT,"0x");
        }

        return distributedRewards;
            
    }
    
    function calculateRewardWeight(uint256 _stakeId,
                            uint256 _mintingFactor,
                            uint256 _referalFactor,
                            uint256 _engagementFactor) public  returns(uint256)
    {
     uint256 stakeAmount = StakingToken(STAKING_CONTRACT).getStakeAmount(_stakeId);
     uint256 _duration = StakingToken(STAKING_CONTRACT).getDuration(_stakeId);
     uint256 durationInWeek = _duration / (WEEK_TIME);
     if(CURRENT_EPOCH % 12 != 1 ) _engagementFactor = 1;
     uint256 _durationFactor = 1 + ( ( 3 * sqrt(durationInWeek) / 10 ) ); 

     uint256 rewardWeight = _mintingFactor * _referalFactor * _engagementFactor * _durationFactor * stakeAmount ;
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


    function getRewardPenalty(uint256 _stakeId,uint256 _rewards) public  view returns(uint256 penalty){

        uint256 stakedPeriod = StakingToken(STAKING_CONTRACT).getStakedPeriod(_stakeId);
       if(stakedPeriod < MIN_STACKING_PERIOD ) penalty= (_rewards*1)/2;
       else if (stakedPeriod >= MIN_STACKING_PERIOD && stakedPeriod < 2*MIN_STACKING_PERIOD)
       {
           penalty= (_rewards*4)/ 10 ;
       }
       else if (stakedPeriod >= 2*MIN_STACKING_PERIOD && stakedPeriod < 3*MIN_STACKING_PERIOD)
       {
           penalty= (_rewards*3)/ 10 ;
       }
       else if (stakedPeriod >= 3*MIN_STACKING_PERIOD && stakedPeriod < 4*MIN_STACKING_PERIOD)
       {
           penalty= (_rewards * 2)/ 10 ;
       }
       else if (stakedPeriod >= 4*MIN_STACKING_PERIOD && stakedPeriod < MAX_STACKING_PERIOD)
       {
           penalty= (_rewards *1 )/ 10 ;
       }
       else if(stakedPeriod > MAX_STACKING_PERIOD) penalty=0; 
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
