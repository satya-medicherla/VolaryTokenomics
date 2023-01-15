// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

interface rewardPool{
    function imposeRewardPenalty(uint256 _stakeId,uint256 stakedPeriod,uint256 _removedStake,uint256 _totalStake) external returns(bool);
    function getCurrentEpoch() external view returns(uint256);
    function getDuration(uint256 _stakeId) view external returns(uint256);
    function totalStakeRemoved(uint256 _stakeId) external returns(bool);
}
contract StakingToken is Ownable {
    uint256 stakeId=0;
    uint256 constant MAX_STACKING_PERIOD = 13305600;
    mapping(address => bool) public isStakeHolder;
    mapping(address => uint256) internal rewards;
    mapping(address => uint256) internal recentWithdrawTime;
    mapping(address => string) stackerLevel;
    mapping(uint256 => bool) isPenalized;
    mapping(uint256 => uint256) penalizedStakePeriod;
    mapping(uint256 => uint256) addedInEpoch;

    address rewardPoolAddress;
    address tokenContract;
    address treasury;
    uint256 SILVER_LEVEL_TOKENS = 1667 * 10 ** 18;
    struct stake{
        address holder;
        uint256 stakeAmount;
        uint256 duration;
        uint256 stackingStartTime;
    }
    mapping(uint256 => stake) public getStakeById;
    mapping(address => uint256[]) public addressToStakes;
    mapping(uint256 => uint256) public stakedRemovedTime;
    mapping(uint256 => uint256) public stakesAddedInEpoch;
    mapping(uint256 => uint256) public stakesRemovedInEpoch;
    constructor(address _tokenContract) {
        treasury = msg.sender;
        tokenContract = _tokenContract;
    }
    
        
    function createStake(uint256 _stakeAmount,uint256 _duration)
        public
    { 
        require(rewardPoolAddress != address(0),"REWARD POOL NOT ADDED");
        uint256 CURRENT_EPOCH = rewardPool(rewardPoolAddress).getCurrentEpoch();
        addedInEpoch[stakeId] = CURRENT_EPOCH;
        stakesAddedInEpoch[CURRENT_EPOCH]++;
        bool result=IERC20(tokenContract).transferFrom(msg.sender,address(this),_stakeAmount);
        require(result,"stake transfer failed");
        stake storage newStake=getStakeById[stakeId];
        newStake.holder = msg.sender;
        newStake.stakeAmount = _stakeAmount;
        newStake.duration = _duration;
        newStake.stackingStartTime = block.timestamp;
        addressToStakes[msg.sender].push(stakeId);
        stakeId++;
        stackerLevel[msg.sender]=getStackerLevel(msg.sender);
        isStakeHolder[msg.sender]=true;
        
    }
    function getStackerLevel(address _stakeholder) public view returns(string memory level) {
    uint256 _stakeAmount = stakeOf(_stakeholder);
    if(_stakeAmount < SILVER_LEVEL_TOKENS)  level="none";
    else if (_stakeAmount  >= SILVER_LEVEL_TOKENS*1000)  level="platinum";
    else if (_stakeAmount  >= SILVER_LEVEL_TOKENS*100)  level="diamond";
    else if (_stakeAmount  >= SILVER_LEVEL_TOKENS*10)  level="gold";
    else   level="sliver";
       
}

    

    function removeStake(uint256 _stakeId,uint256 _stake)
        public returns(bool)
    {
        uint256 _totalStake=getStakeAmount(_stakeId);
        require(msg.sender == getHolderByStakeId(_stakeId),"only stake holder can remove the stake");
        require(_stake <= _totalStake,"can remove only amount less than staked");
        uint256 CURRENT_EPOCH = rewardPool(rewardPoolAddress).getCurrentEpoch();
        if( _stake == _totalStake)
        {
            stakesRemovedInEpoch[CURRENT_EPOCH]++;
            (bool success)=rewardPool(rewardPoolAddress).totalStakeRemoved(_stakeId);
            require(success,"staking : error while removing entire stake");
            
        }
        uint256 penalty=0;
        uint256 stakedPeriod= block.timestamp - getStartTimeOfStake(_stakeId);
        if(stakedPeriod < MAX_STACKING_PERIOD)
        {
            if(isDurationBound(_stakeId)){ 
                uint256 _factor = rewardPool(rewardPoolAddress).getDuration(_stakeId);
                penalty = (_factor*getPrincipalPenalty(_stake))/(10**6);
                IERC20(tokenContract).transfer(treasury,penalty);
                }
            
            rewardPool(rewardPoolAddress).imposeRewardPenalty(_stakeId,stakedPeriod,_stake,_totalStake);
            isPenalized[_stakeId]= true;
        }
        bool result=IERC20(tokenContract).transfer( msg.sender , _stake - penalty);
        require(result,"error transfering tokens to holder");
        stake storage temp = getStakeById[_stakeId];
        temp.stakeAmount= getStakeAmount(_stakeId) - _stake;
        if(stakeOf(msg.sender) == 0) isStakeHolder[msg.sender] = false;        
        return true;
    }

    function getPrincipalPenalty(uint256 _stake) internal  pure   returns(uint256 penalty){    
       penalty = _stake * 5 / 100 ;

    } 

    function stakeOf(address _stakeholder)
        public
        view
        returns(uint256 )
    {
        uint256 totalStake = 0;
        for(uint256 i=0;i<addressToStakes[_stakeholder].length;i++){
            uint256 temp= getStakeAmount(addressToStakes[_stakeholder][i]);
            totalStake+=temp;
        }
        return totalStake;
    }
    function getStartTimeOfStake(uint256 _stakeId) view public returns(uint256){
        stake memory temp = getStakeById[_stakeId];
        return temp.stackingStartTime;
    }

    function getHolderByStakeId(uint256 _stakeId) public view returns(address){
        stake memory temp = getStakeById[_stakeId];
        return temp.holder;
    }

    function isDurationBound(uint256 _stakeId) public view returns(bool){
        stake memory temp = getStakeById[_stakeId];
        if(temp.duration == 0) return false;
        return true;
    }

    function getStakeAmount(uint256 _stakeId) public view returns(uint256){
        stake memory temp = getStakeById[_stakeId];
        return temp.stakeAmount;
    }
    function getstakesTillEpoch(uint256 epochNumber) public view returns(uint256){
        uint256 result = 0;
        for(uint256 i=0;i<=epochNumber;i++){
            result+=stakesAddedInEpoch[i];
        }
        return result;
    }
    function getDuration(uint256 _stakeId) public view returns(uint256){
        stake memory temp = getStakeById[_stakeId];
        return temp.duration;
    }

    function getTotalNumberOfStakes() public view returns(uint256){
        return stakeId;
    }

    function getAddedEpoch(uint256 _stakeId) public view returns(uint256){
        return addedInEpoch[_stakeId];
    }

 

    
   
    function addRewardPoolAddress(address _rewardPool) public onlyOwner returns(bool){
        rewardPoolAddress=_rewardPool;
        return true;
    }
    
    function getactiveStakesTillEpoch(uint256 epoch) public view returns(uint256){
        uint256 result = 0;
        for(uint256 i=0;i<=epoch;i++){
            result = result + stakesAddedInEpoch[i] - stakesRemovedInEpoch[i];
        }
        return result;    
    }

    function getStakesOfAddress(address holder) public view returns(uint256[] memory){
          return addressToStakes[holder];
    }
}
