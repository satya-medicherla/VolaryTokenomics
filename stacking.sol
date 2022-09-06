// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
contract StakingToken is ERC20, Ownable {
    uint256 stakeId=0;
    mapping(address => bool) public isStakeHolder;
    mapping(address => uint256) internal rewards;
    mapping(address => uint256) internal recentWithdrawTime;
    mapping(address => string) stackerLevel;
    mapping(uint256 => bool) isPenalized;
    mapping(uint256 => uint256) penalizedStakePeriod;
    mapping(uint256 => uint256) stakeRemoved;
    address treasury;
    uint256 SILVER_LEVEL_TOKENS = 1667 * 10 ** 18;
    struct stake{
        address holder;
        uint256 stakeAmount;
        uint256 duration;
        uint256 stackingStartTime;
    }
    mapping(uint256 => stake) public getStakeById;
    mapping(address => stake[]) public getStakesOfAddress;
    mapping(uint256 => uint256) public stakedPeriod;
    constructor(address _treasury)  ERC20("Volary", "VLRY")
    { 
        treasury=_treasury;
        _mint(treasury, 1000000000 * 10 ** decimals());
    }

    function createStake(uint256 _stakeAmount,uint256 _duration)
        public
    {
        bool result=transfer(address(this),_stakeAmount);
        require(result,"stake transfer failed");
        stake storage newStake=getStakeById[stakeId];
        newStake.holder = msg.sender;
        newStake.stakeAmount = _stakeAmount;
        newStake.duration = _duration;
        newStake.stackingStartTime = block.timestamp;
        stakeId++;
        getStakesOfAddress[msg.sender].push(newStake);
        stackerLevel[msg.sender]=getStackerLevel(msg.sender);
        isStakeHolder[msg.sender]=true;
        
    }
    function updateStake(uint256 _stakeId,uint256 _addStake) public returns(bool){
          require(stakeId > _stakeId,"stake doesnt exist");
          require(msg.sender == getHolderByStakeId(_stakeId),"only stakeholder can update stake");
          stake storage temp = getStakeById[_stakeId];
          bool result=transfer(address(this),_addStake);
          require(result,"stake transfer failed");
          temp.stakeAmount=temp.stakeAmount + _addStake;
          return true;
    }
    function getStackerLevel(address _stakeholder) public view returns(string memory level) {
        if(stakeOf(_stakeholder) < SILVER_LEVEL_TOKENS)  level="none";
        else if (stakeOf(_stakeholder)  >= SILVER_LEVEL_TOKENS)  level="siver";
        else if (stakeOf(_stakeholder)  >= SILVER_LEVEL_TOKENS*10)  level="gold";
        else if (stakeOf(_stakeholder)  >= SILVER_LEVEL_TOKENS*100)  level="diamond";
        else if (stakeOf(_stakeholder)  >= SILVER_LEVEL_TOKENS*1000)  level="platinum";

        return level;   
    }

    

    function removeStake(uint256 _stakeId,uint256 _stake)
        public returns(bool)
    {
        require(msg.sender == getHolderByStakeId(_stakeId),"only stake holder can remove the stake");
        require(_stake <= getStakeAmount(_stakeId),"can remove only amount less than staked");
        uint256 penalty=0;
        if(isDurationBound(_stakeId)){
                 penalty = getPrincipalPenalty(_stakeId,_stake);
                 isPenalized[_stakeId]= true;
                 if(stakedPeriod[_stakeId]==0)stakedPeriod[_stakeId]=block.timestamp;
        }
        bool result=transfer( msg.sender , _stake - penalty);
        require(result,"error transfering tokens to holder");
        stake storage temp = getStakeById[_stakeId];
        temp.stakeAmount= getStakeAmount(_stakeId) - _stake;
        if(stakeOf(msg.sender) == 0) isStakeHolder[msg.sender] = false;
        stakeRemoved[_stakeId] += _stake;
        
        return true;
    }

    function getPrincipalPenalty(uint256 _stakeId,uint256 _stake) internal  view  returns(uint256 penalty){
       if(getStakedPeriod(_stakeId) >= getDuration(_stakeId)) penalty=0;
       else {
           penalty = _stake * 5 / 100;
       }

    } 

    function stakeOf(address _stakeholder)
        public
        view
        returns(uint256 )
    {
        uint256 totalStake = 0;
        for(uint256 i=0;i<getStakesOfAddress[_stakeholder].length;i++){
            stake memory temp=getStakesOfAddress[_stakeholder][i];
            totalStake+=temp.stakeAmount;
        }
        return totalStake;
    }

    function totalStakes()
        public
        view
        returns(uint256)
    {
        uint256 _totalStakes = 0;
        for(uint256 i = 0; i<stakeId; i++){
            _totalStakes=_totalStakes+getStakeAmount(stakeId);
        }
        return _totalStakes;
    }

    function rewardOf(address _stakeholder) 
        public
        view
        returns(uint256)
    {
        return rewards[_stakeholder];
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

    function getDuration(uint256 _stakeId) public view returns(uint256){
        stake memory temp = getStakeById[_stakeId];
        return temp.duration;
    }

    function getTotalNumberOfStakes() public view returns(uint256){
        return stakeId;
    }

    function getStakeRemoved(uint256 _stakeId) public view returns(uint256){
    
        return stakeRemoved[_stakeId];
    }

    function resetStakeRemoved(uint256 _stakeId) public onlyOwner returns(bool){
        stakeRemoved[_stakeId] = 0;
        return true;
    }

    function getStakedPeriod(uint256 _stakeId) public view returns(uint256){
         return stakedPeriod[_stakeId];
    }

    function resetStakedPeriod(uint256 _stakeId) public onlyOwner returns(bool){
        stakedPeriod[_stakeId] = 0;
        return true;
    }

}
