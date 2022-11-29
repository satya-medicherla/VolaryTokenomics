const stackingContract = artifacts.require("contracts/stacking.sol:StakingToken");
const rewardsContract = artifacts.require("contracts/rewards.sol:rewardPool");
const tokenContract = artifacts.require("Volary")
const { assert } = require('chai');
const truffleAssert = require('truffle-assertions');
const { ethers, network } = require("hardhat");

const epochTime = 604800


describe('test volary contract deployment',(accounts) => {
    let volary, balance, stacking, rewardPool;
    let ZERO_ADDRESS = "0x0000000000000000000000000000000000000000";

    before(async function () {
        accounts = await web3.eth.getAccounts();
        volary = await tokenContract.new();
        stacking = await stackingContract.new(volary.address);
        rewardPool = await rewardsContract.new(volary.address,stacking.address,
            volary.address,volary.address,accounts[0]);
            await truffleAssert.reverts(stacking.createStake("1900",0))
            await truffleAssert.reverts(stacking.addRewardPoolAddress(rewardPool.address,{from : accounts[8]}))
            await stacking.addRewardPoolAddress(rewardPool.address)
            await truffleAssert.reverts(stacking.createStake("1900",0))
            await volary.transfer(rewardPool.address,"1000000000000000000000");
            await volary.transfer(accounts[1],"200000000000000000000");
            await volary.transfer(accounts[2],"100000000000000000000");

    });

    it('checks if deployed address is owner',async()=>{
        const owner=await volary.owner.call();
        assert.equal(owner,accounts[0]);
    })

    it('check if it mints tokens to owner account',async()=>{
        const bal=await volary.balanceOf(accounts[0]);
        assert.equal(bal.toString(),"999998700000000000000000000");
        
    })

    it("stacking and reward testing",async()=>{
        /**
         * adding stakes two stakes 
         * one with duration and other with no stakes
         */
        await volary.approve(stacking.address,"200000000000000000000",{from : accounts[1]})
        await volary.approve(stacking.address,"100000000000000000000",{from : accounts[2]})
        await stacking.createStake("200000000000000000000",0,{from : accounts[1]});
        assert.equal(await stacking.isStakeHolder(accounts[1]),true);
        balance = await stacking.getStakeAmount(0)
        assert.equal(balance.toString(),"200000000000000000000");
        await stacking.createStake("100000000000000000000",13305900,{from : accounts[2]});
        assert.equal(await stacking.isStakeHolder(accounts[2]),true);
        assert.equal(await stacking.getStakeAmount(1),"100000000000000000000");
        assert.equal(await rewardPool.CURRENT_EPOCH(),0);
        await truffleAssert.reverts(rewardPool.startPool({from : accounts[1]}))
        await rewardPool.startPool();
        assert.equal(await rewardPool.CURRENT_EPOCH(),1);
        
        await ethers.provider.send('evm_increaseTime', [epochTime-2]);
        await ethers.provider.send('evm_mine');
        assert.equal(await stacking.getstakesTillEpoch(1),2)
        /*
        reward pool reverts when all the stakes rewards are not calculated
        **/
        await truffleAssert.reverts(rewardPool.calculateRewardWeight(0,1100000,1200000,1000000,1000000),"VM Exception while processing transaction: reverted with reason string ' epoch not completed'");
        await truffleAssert.reverts(rewardPool.finishEpoch(),"VM Exception while processing transaction: reverted with reason string 'ALL STAKE REWARDS ARE NOT CALCULATED'");
        await ethers.provider.send('evm_increaseTime', [epochTime]);
        await ethers.provider.send('evm_mine');
        await rewardPool.calculateRewardWeight(0,1100000,1200000,1000000,1000000);
        /**
         * cant finish the epoch before the rewards of all the stakes are calculated
         */
        await truffleAssert.reverts(rewardPool.finishEpoch());
        await rewardPool.calculateRewardWeight(1,1300000,1500000,1000000,2432670);
        await rewardPool.rewardOfStake(0);
        await rewardPool.rewardOfStake(1);
        await truffleAssert.reverts(rewardPool.finishEpoch({from : accounts[2]}));
        await rewardPool.finishEpoch();
        /**
         *  accumalted rewards after epoch is finished
         */
        assert.equal(await rewardPool.CURRENT_EPOCH(),2);
        assert.equal(await stacking.getstakesTillEpoch(2),2)
        balance= await rewardPool.ACCUMALATED_REWARDS(0)
        assert.equal(balance.toString(),"750842412276273440")
        balance=await rewardPool.ACCUMALATED_REWARDS(1)
        assert.equal(balance.toString(),"907950220200000000")
        
        /**
         *  checks only valid stakeholder can remove valid stake amount
         */
        await truffleAssert.reverts(stacking.removeStake(1,"50000000000000000000"),"VM Exception while processing transaction: reverted with reason string 'only stake holder can remove the stake'");
        await truffleAssert.reverts(stacking.removeStake(1,"100000000000000000001",{from : accounts[2]}),"VM Exception while processing transaction: reverted with reason string 'can remove only amount less than staked'");
        /**
         * remove stake functionality check
         */
        await stacking.removeStake(1,"50000000000000000000",{from : accounts[2]});
        /**
         * checks if principal and reward penalty is implemented correctly
         */
        balance= await volary.balanceOf(accounts[2]);

        assert.equal(balance.toString(),"44372300110100000000")
        balance=await rewardPool.ACCUMALATED_REWARDS(1)
        assert.equal(balance.toString(),"453975110100000000");
       /**
        * second epoch testing
        */
        assert.equal(await rewardPool.CURRENT_EPOCH(),2);
        // await ethers.provider.send('evm_increaseTime', [epochTime-2]);
        // await ethers.provider.send('evm_mine');
        let time 
        time = await rewardPool.POOL_START_TIME()
        let time1 = await rewardPool.EPOCH_TO_START_TIME(1);
        assert.equal(time.toString(),time1.toString());
        let time2 = await rewardPool.EPOCH_TO_START_TIME(2);
        let difTime = time2-time1;
        let blockTime = await rewardPool.getBlockStamp();
        
        assert.equal(blockTime >= time1+604800,true);
        //await truffleAssert.reverts(rewardPool.calculateRewardWeight(0,1100000,1200000,1000000,1000000),"VM Exception while processing transaction: reverted with reason string ' epoch not completed'");
        await truffleAssert.reverts(rewardPool.finishEpoch());
        await ethers.provider.send('evm_increaseTime', [epochTime]);
        await ethers.provider.send('evm_mine');
         
        await rewardPool.calculateRewardWeight(0,1100000,1200000,1000000,1000000);
        await rewardPool.calculateRewardWeight(1,1300000,1500000,1000000,2432670);
        await rewardPool.rewardOfStake(0);
        await rewardPool.rewardOfStake(1);
        await rewardPool.finishEpoch();
        assert.equal(await rewardPool.DISTRIBUTION_CYCLE(),2)
        balance= await rewardPool.CLAIMABLE_REWARDS(0)
        assert.equal(balance.toString(),"927348539605053374")
        balance=await rewardPool.CLAIMABLE_REWARDS(1)
        assert.equal(balance.toString(),"453975110100000000")
        assert.equal(await rewardPool.CURRENT_EPOCH(),3);
        balance= await rewardPool.ACCUMALATED_REWARDS(0)
        assert.equal(balance.toString(),"1854697079210106748")
        balance=await rewardPool.ACCUMALATED_REWARDS(1)
        assert.equal(balance.toString(),"907950220200000000")
        
        truffleAssert.reverts(rewardPool.claimRewards(0,"927348539605053374",{from:accounts[0]}));
        truffleAssert.reverts(rewardPool.claimRewards(1,"927348539605053375",{from:accounts[0]}));
        truffleAssert.reverts(rewardPool.claimRewards(0,"927348539605053375",{from:accounts[1]}));

        await rewardPool.claimRewards(0,"927348539605053374",{from:accounts[1]})

        balance = await rewardPool.CLAIMABLE_REWARDS(0);
        assert.equal(balance.toString(),0);
        balance = await rewardPool.CLAIMED_REWARDS(0);
        assert.equal(balance.toString(),"927348539605053374");
        

        assert.equal(await rewardPool.CURRENT_EPOCH(),3);
        await ethers.provider.send('evm_increaseTime', [epochTime-2]);
        await ethers.provider.send('evm_mine');
        await truffleAssert.reverts(rewardPool.rewardOfStake(0));
        await truffleAssert.reverts(rewardPool.finishEpoch());
        await ethers.provider.send('evm_increaseTime', [epochTime]);
        await ethers.provider.send('evm_mine');
        await truffleAssert.reverts(rewardPool.rewardOfStake(0));
        await rewardPool.calculateRewardWeight(0,1100000,1200000,1000000,1000000);
        await rewardPool.calculateRewardWeight(1,1300000,1500000,1000000,2432670);
        await rewardPool.rewardOfStake(0);
        await truffleAssert.reverts(rewardPool.rewardOfStake(0));
        await rewardPool.rewardOfStake(1);
        await truffleAssert.reverts(rewardPool.rewardOfStake(9));
        await rewardPool.finishEpoch();
        assert.equal(await rewardPool.CURRENT_EPOCH(),4);

        balance= await rewardPool.ACCUMALATED_REWARDS(0)
        assert.equal(balance.toString(),"2956233651343379006")
        balance=await rewardPool.ACCUMALATED_REWARDS(1)
        assert.equal(balance.toString(),"1361925330300000000")

        assert.equal(await rewardPool.CURRENT_EPOCH(),4);
        await ethers.provider.send('evm_increaseTime', [epochTime-2]);
        await ethers.provider.send('evm_mine');
        await truffleAssert.reverts(rewardPool.rewardOfStake(0));
        await truffleAssert.reverts(rewardPool.finishEpoch());
        await ethers.provider.send('evm_increaseTime', [epochTime]);
        await ethers.provider.send('evm_mine');
        await rewardPool.calculateRewardWeight(0,1100000,1200000,1000000,1000000);
        await rewardPool.calculateRewardWeight(1,1300000,1500000,1000000,2432670);
        await rewardPool.rewardOfStake(0);
        await rewardPool.rewardOfStake(1);
        await rewardPool.finishEpoch();
        assert.equal(await rewardPool.CURRENT_EPOCH(),5);

        balance= await rewardPool.ACCUMALATED_REWARDS(0)
        assert.equal(balance.toString(),"4055456996675171392")
        balance=await rewardPool.ACCUMALATED_REWARDS(1)
        assert.equal(balance.toString(),"1815900440400000000")

        // await rewardPool.distributeRewards();

        balance= await rewardPool.CLAIMABLE_REWARDS(0)
        assert.equal(balance.toString(),"1100379958732532322")
        balance=await rewardPool.CLAIMABLE_REWARDS(1)
        assert.equal(balance.toString(),"907950220200000000")

        balance= await rewardPool.CLAIMED_REWARDS(0)
        assert.equal(balance.toString(),"927348539605053374")
        balance=await rewardPool.CLAIMED_REWARDS(1)
        assert.equal(balance.toString(),"0")
        await truffleAssert.reverts(rewardPool.startPool());
        balance= await stacking.getStartTimeOfStake(0);
        assert.equal(await stacking.isDurationBound(1),true);
        balance = await stacking.getStakeAmount(0)
        assert.equal(balance.toString(),"200000000000000000000")
        balance = await stacking.getStakeAmount(1)
        assert.equal(balance.toString(),"50000000000000000000")
        balance = await stacking.getDuration(1)
        assert.equal(balance.toString(),"13305900")
        assert.equal(await stacking.getStackerLevel(accounts[0]),"none");
        await volary.transfer(accounts[1],"1667000000000000000000000");
        await volary.approve(stacking.address,"1667000000000000000000000",{from : accounts[1]})
        await stacking.createStake("1667000000000000000000",0,{from : accounts[1]});
        assert.equal(await stacking.getStackerLevel(accounts[1]),"sliver");
        await stacking.createStake("16670000000000000000000",0,{from : accounts[1]});
        assert.equal(await stacking.getStackerLevel(accounts[1]),"gold");
        await stacking.createStake("166700000000000000000000",0,{from : accounts[1]});
        assert.equal(await stacking.getStackerLevel(accounts[1]),"diamond");
        await volary.transfer(accounts[1],"1667000000000000000000000");
        await volary.approve(stacking.address,"1667000000000000000000000",{from : accounts[1]})
        await stacking.createStake("1667000000000000000000000",0,{from : accounts[1]});
        assert.equal(await stacking.getStackerLevel(accounts[1]),"platinum");
        
        assert.equal(await stacking.getTotalNumberOfStakes(),6);
        assert.equal(await stacking.isDurationBound(6),false);
        assert.equal(await stacking.stakedPeriod(16),false);
        balance =await stacking.getStakeAmount(1);
        assert.equal(balance.toString(),"50000000000000000000");
        

        

    })

})
