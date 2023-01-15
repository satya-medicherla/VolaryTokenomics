const stackingContract = artifacts.require("contracts/stacking.sol:StakingToken");
const rewardsContract = artifacts.require("contracts/rewards.sol:rewardPool");
const tokenContract = artifacts.require("Volary");
const { assert } = require('chai');
const truffleAssert = require('truffle-assertions');
const { ethers, config } = require("hardhat");
const { signMessage } = require('../scripts/sign');

const epochTime = 604800;
const oneDay = 86400;

const wallets = config.networks.hardhat.accounts;
const index = 0; // first wallet, increment for next wallets
const wallet1 = ethers.Wallet.fromMnemonic(wallets.mnemonic, wallets.path + `/${index}`);
let privateKey = wallet1.privateKey;
privateKey = privateKey.slice(2,);

describe('test volary contract deployment',(accounts) => {
    let volary, balance, stacking, rewardPool;
    let ZERO_ADDRESS = "0x0000000000000000000000000000000000000000";

    before(async function () {
        accounts = await web3.eth.getAccounts();
        volary = await tokenContract.new();
        stacking = await stackingContract.new(volary.address);
        rewardPool = await rewardsContract.new(volary.address,stacking.address,
        volary.address,volary.address,accounts[0]);
        await truffleAssert.reverts(stacking.createStake("1900",0),"REWARD POOL NOT ADDED")
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
         * step 1 : 
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
        const sampleSign = "0x993dab3dd91f5c6dc28e17439be475478f5635c92a56e17e82349d3fb2f166196f466c0b4e0c146f285204f0dcb13e5ae67bc33f4b888ec32dfe0a063e8f3f781b"
        await truffleAssert.reverts(rewardPool.rewardOfStake(0,"12345",sampleSign),"POOL NOT STARTED");
        await truffleAssert.reverts(rewardPool.rewardOfStakeByAdmin(0,"12345","23"),"POOL NOT STARTED");

        await truffleAssert.reverts(rewardPool.startPool({from : accounts[1]}))
        await rewardPool.startPool();
        await truffleAssert.reverts(rewardPool.startPool(),"POOL ALREADY STARTED")
        assert.equal(await rewardPool.CURRENT_EPOCH(),1);
        
        
        assert.equal(await stacking.getstakesTillEpoch(1),2);

        await truffleAssert.reverts(rewardPool.finishEpoch(),"epoch not completed");
         
        /*
        reward pool reverts when all the stakes rewards are not calculated
        **/

        const signers = await ethers.getSigners();
        const netId = await rewardPool.getChainId();
        let stakeOneRewards = "7890000000000000";

        let stakeOneSign 

        let currentEpoch = await rewardPool.CURRENT_EPOCH();

        stakeOneSign = await signMessage(privateKey,netId,rewardPool.address,stakeOneRewards,0,currentEpoch);



        let errorSign = await signMessage(privateKey,netId,rewardPool.address,"769237",0,currentEpoch);


        await truffleAssert.reverts(rewardPool.rewardOfStake(stakeOneRewards,0,stakeOneSign,{from : accounts[1]}),"ACCESS RESTRICTED FOR USERS NOW");
        await ethers.provider.send('evm_increaseTime', [epochTime]);
        await ethers.provider.send('evm_mine');
        await truffleAssert.reverts(rewardPool.rewardOfStake(stakeOneRewards,0,stakeOneSign),"not stake holder");
        await truffleAssert.reverts(rewardPool.rewardOfStake(stakeOneRewards,0,errorSign,{from : accounts[1]}),"signature mismatch");

        errorSign = await signMessage(privateKey,netId,rewardPool.address,stakeOneRewards,1,currentEpoch);
        await truffleAssert.reverts(rewardPool.rewardOfStake(stakeOneRewards,0,errorSign,{from : accounts[1]}),"signature mismatch");


        await rewardPool.rewardOfStake(stakeOneRewards,0,stakeOneSign,{from : accounts[1]});

        await truffleAssert.reverts(rewardPool.rewardOfStake(stakeOneRewards,0,stakeOneSign,{from : accounts[1]}),"signature can be used only once")
        stakeOneSign = await signMessage(privateKey,netId,rewardPool.address,"9801",0,currentEpoch);
        await truffleAssert.reverts(rewardPool.rewardOfStake("9801",0,stakeOneSign,{from : accounts[1]}),"REWARD FOR THIS EPOCH IS SET")
        
        



        balance = await rewardPool.ACCUMALATED_REWARDS(0);

        assert.equal(balance.toString(),stakeOneRewards);        
        await truffleAssert.reverts(rewardPool.finishEpoch(),"VM Exception while processing transaction: reverted with reason string 'ALL STAKE REWARDS ARE NOT CALCULATED'");
        

        let stakeTwoRewards = "127665435260000";

        let stakeTwoSign = await await signMessage(privateKey,netId,rewardPool.address,stakeTwoRewards,1,currentEpoch);
        
        await truffleAssert.reverts(rewardPool.rewardOfStake(stakeTwoRewards,1,stakeOneSign,{from : accounts[2]}),"signature mismatch");

        await rewardPool.rewardOfStake(stakeTwoRewards,1,stakeTwoSign,{from : accounts[2]});
        
        balance = await rewardPool.ACCUMALATED_REWARDS(1);

        assert.equal(balance.toString(),stakeTwoRewards); 

        await truffleAssert.reverts(rewardPool.finishEpoch({from : accounts[1]}));

        await rewardPool.finishEpoch();
       

        assert.equal(await rewardPool.CURRENT_EPOCH(),2);
        assert.equal(await stacking.getstakesTillEpoch(2),2)
    
        
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

        assert.equal(balance.toString(),"50000063832717630000")
        balance=await rewardPool.ACCUMALATED_REWARDS(1)
        assert.equal(balance.toString(),"63832717630000");

        /**
         * second epoch testing
         */
        currentEpoch = await rewardPool.CURRENT_EPOCH();
        stakeOneRewards = "89763200000000";
        stakeOneSign =  await signMessage(privateKey,netId,rewardPool.address,stakeOneRewards,0,currentEpoch);
        let gasFeePenalty = "12008"
        assert.equal( await rewardPool.getCurrentEpoch(),2)
        await truffleAssert.reverts(rewardPool.rewardOfStake(stakeOneRewards,0,stakeOneSign,{from : accounts[1]}),"ACCESS RESTRICTED FOR USERS NOW");
        await truffleAssert.reverts(rewardPool.rewardOfStakeByAdmin(0,stakeOneRewards,gasFeePenalty),"ACCESS RESTRICTED FOR ADMIN NOW");
        await ethers.provider.send('evm_increaseTime', [epochTime]);
        await ethers.provider.send('evm_mine');

        await rewardPool.rewardOfStake(stakeOneRewards,0,stakeOneSign,{from : accounts[1]});

        balance = await rewardPool.ACCUMALATED_REWARDS(0);
        assert.equal(balance.toString(),"7979763200000000");

        balance = await rewardPool.CLAIMABLE_REWARDS(0);
        assert.equal(balance.toString(),"3989881600000000");

        stakeTwoRewards = "1256700000000000";
        stakeTwoSign = await signMessage(privateKey,netId,rewardPool.address,stakeTwoRewards,1,currentEpoch);



        await truffleAssert.reverts(rewardPool.rewardOfStakeByAdmin(1,stakeOneRewards,gasFeePenalty,{from : accounts[1]}),"Ownable: caller is not the owner");
        await truffleAssert.reverts(rewardPool.rewardOfStakeByAdmin(1,stakeOneRewards,gasFeePenalty),"ACCESS RESTRICTED FOR ADMIN NOW");

        await ethers.provider.send('evm_increaseTime', [oneDay]);
        await ethers.provider.send('evm_mine');

        await truffleAssert.reverts(rewardPool.rewardOfStakeByAdmin(0,stakeOneRewards,gasFeePenalty),"REWARD FOR THIS EPOCH IS SET");
        await truffleAssert.reverts(rewardPool.rewardOfStake(stakeOneRewards,1,stakeOneSign),"ACCESS RESTRICTED FOR USERS NOW")
        await rewardPool.rewardOfStakeByAdmin(1,stakeOneRewards,gasFeePenalty);

        await ethers.provider.send('evm_increaseTime', [oneDay]);
        await ethers.provider.send('evm_mine');
       
        await truffleAssert.reverts(rewardPool.rewardOfStakeByAdmin(0,stakeOneRewards,gasFeePenalty),"ACCESS RESTRICTED FOR ADMIN NOW");


        balance = await rewardPool.ACCUMALATED_REWARDS(1);
        assert.equal(balance.toString(),"153595917617992");

        balance = await rewardPool.CLAIMABLE_REWARDS(1);
        assert.equal(balance.toString(),"76797958808996");

        await rewardPool.finishEpoch();

        /**
         * epoch 3 testing
         */

         currentEpoch = await rewardPool.CURRENT_EPOCH();

         assert.equal( await rewardPool.getCurrentEpoch(),3)

         stakeOneRewards = "670000000000000";
         stakeOneSign = await signMessage(privateKey,netId,rewardPool.address,stakeOneRewards,0,currentEpoch);
         gasFeePenalty = "17908"
 
         await truffleAssert.reverts(rewardPool.rewardOfStake(stakeOneRewards,0,stakeOneSign,{from : accounts[1]}),"ACCESS RESTRICTED FOR USERS NOW");
         await truffleAssert.reverts(rewardPool.rewardOfStakeByAdmin(0,stakeOneRewards,gasFeePenalty),"ACCESS RESTRICTED FOR ADMIN NOW");

         await ethers.provider.send('evm_increaseTime', [epochTime-2*oneDay]);
         await ethers.provider.send('evm_mine');
 
         await rewardPool.rewardOfStake(stakeOneRewards,0,stakeOneSign,{from : accounts[1]});
 
         balance = await rewardPool.ACCUMALATED_REWARDS(0);
         assert.equal(balance.toString(),"8649763200000000");
 
         balance = await rewardPool.CLAIMABLE_REWARDS(0);
         assert.equal(balance.toString(),"3989881600000000");
 
         stakeTwoRewards = "987000000000000";
         stakeTwoSign = await signMessage(privateKey,netId,rewardPool.address,stakeTwoRewards,1,currentEpoch);
 
         await truffleAssert.reverts(rewardPool.rewardOfStakeByAdmin(1,stakeOneRewards,gasFeePenalty,{from : accounts[1]}),"Ownable: caller is not the owner");

         await ethers.provider.send('evm_increaseTime', [oneDay]);
         await ethers.provider.send('evm_mine');
 
         await truffleAssert.reverts(rewardPool.rewardOfStakeByAdmin(0,stakeOneRewards,gasFeePenalty),"REWARD FOR THIS EPOCH IS SET");
 
         await rewardPool.rewardOfStakeByAdmin(1,stakeOneRewards,gasFeePenalty);
 
         balance = await rewardPool.ACCUMALATED_REWARDS(1);
         assert.equal(balance.toString(),"823595917600084");
 
         balance = await rewardPool.CLAIMABLE_REWARDS(1);
         assert.equal(balance.toString(),"76797958808996");
 
         await rewardPool.finishEpoch();

         /**
          * into fourth epoch
          */

         currentEpoch = await rewardPool.CURRENT_EPOCH();
         assert.equal( await rewardPool.getCurrentEpoch(),4)

         let activeStakes = await stacking.getactiveStakesTillEpoch(4);
         assert.equal(activeStakes,2)

         const totalStakeOfFirst = await stacking.getStakeAmount(0);
         
         await stacking.removeStake(0,totalStakeOfFirst.toString(),{from : accounts[1]});

         activeStakes = await stacking.getactiveStakesTillEpoch(4);
         assert.equal(activeStakes,1);

         balance = await stacking.getStakeAmount(0)

         assert.equal(balance.toString(),0);

         await ethers.provider.send('evm_increaseTime', [epochTime - oneDay]);
         await ethers.provider.send('evm_mine');

         stakeOneSign = await signMessage(privateKey,netId,rewardPool.address,"9801",0,currentEpoch);

         await truffleAssert.reverts(rewardPool.rewardOfStake("9801",0,stakeOneSign,{from : accounts[1]}),"STAKE DOESNT EXISTS");

         await ethers.provider.send('evm_increaseTime', [oneDay]);
         await ethers.provider.send('evm_mine');

         await truffleAssert.reverts(rewardPool.rewardOfStakeByAdmin(0,stakeOneRewards,gasFeePenalty),"STAKE DOESNT EXISTS");
         
         const claimable = await rewardPool.CLAIMABLE_REWARDS(0);

         await truffleAssert.reverts(rewardPool.claimRewards(0,"3989881600000000"),"ONLY HOLDER CLAIM REWARDS");
         await truffleAssert.reverts(rewardPool.claimRewards(0,claimable+1,{from : accounts[1]}),"cant withdraw more than claimble rewards");

         await rewardPool.claimRewards(0,claimable,{from : accounts[1]});

         assert.equal(await rewardPool.CLAIMABLE_REWARDS(0),0);

         balance = await rewardPool.CLAIMED_REWARDS(0);

         assert.equal(balance.toString(),claimable);

         await rewardPool.rewardOfStakeByAdmin(1,stakeOneRewards,"0");

         await rewardPool.finishEpoch();

         /*
           into 5th epoch
         */

        assert.equal( await rewardPool.getCurrentEpoch(),5);

        activeStakes = await stacking.getactiveStakesTillEpoch(5);

        assert.equal(activeStakes,1)

        const totalStakeOfSecond = await stacking.getStakeAmount(1);
         
        await stacking.removeStake(1,totalStakeOfSecond.toString(),{from : accounts[2]});

        activeStakes = await stacking.getactiveStakesTillEpoch(5);
        assert.equal(activeStakes,0);

        balance = await stacking.getStakeAmount(1)

        assert.equal(balance.toString(),0);

        await stacking.getDuration(0);

        assert.equal(await stacking.getTotalNumberOfStakes(),2);

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
        assert.equal(await stacking.getAddedEpoch(4),5); 
        const activeResult= await stacking.getactiveStakesTillEpoch(5);
        assert.equal(activeResult.toString(),"4");   

    })

    it("tests different claimed reward percentages",async()=>{
        const volaryNew = await tokenContract.new();
        const stackingNew = await stackingContract.new(volaryNew.address);
        const rewardPoolNew = await rewardsContract.new(volaryNew.address,stackingNew.address,
        volaryNew.address,volaryNew.address,accounts[0]);
        await volaryNew.transfer(rewardPoolNew.address,"1000000000000000000000");
        await volaryNew.transfer(accounts[3],"200000000000000000000");
        await volaryNew.approve(stackingNew.address,"200000000000000000000",{from : accounts[3]});
        await stackingNew.addRewardPoolAddress(rewardPoolNew.address)
        await stackingNew.createStake("200000000000000000000",0,{from : accounts[3]});
        await rewardPoolNew.startPool();
        const reward = "50000000000";
        let sign
        let currentEpoch
        const netId = await rewardPoolNew.getChainId();
         for(let i=0;i<50;i++){
            await ethers.provider.send('evm_increaseTime', [epochTime]);
            await ethers.provider.send('evm_mine');
            currentEpoch = await rewardPoolNew.CURRENT_EPOCH();
            sign =  await signMessage(privateKey,netId,rewardPoolNew.address,reward,0,currentEpoch);
            await rewardPoolNew.rewardOfStake(reward,0,sign,{from : accounts[3]});
            await rewardPoolNew.finishEpoch();
         }

        const epoch = await rewardPoolNew.getCurrentEpoch()
        
        assert.equal(epoch.toString(),51)

    })

    it("tests imposed penalities",async()=>{

        const volaryPenalty = await tokenContract.new();
        const stackingPenalty = await stackingContract.new(volaryPenalty.address);
        const rewardPenalty = await rewardsContract.new(volaryPenalty.address,stackingPenalty.address,
        volaryPenalty.address,volaryPenalty.address,accounts[0]);
        await volaryPenalty.transfer(rewardPenalty.address,"1000000000000000000000");
        await volaryPenalty.transfer(accounts[4],"200000000000000000000");
        await volaryPenalty.approve(stackingPenalty.address,"200000000000000000000",{from : accounts[4]});
        await truffleAssert.reverts(stackingPenalty.createStake("200000000000000000000","13315600",{from : accounts[4]}),"REWARD POOL NOT ADDED");
        await stackingPenalty.addRewardPoolAddress(rewardPenalty.address)
        await stackingPenalty.createStake("200000000000000000000","13315600",{from : accounts[4]});
        await rewardPenalty.startPool();
        let reward = "0";
        const signers = await ethers.getSigners();
        let sign = await signers[0].signMessage(reward)
        for(let i=0;i<51;i++){
            await ethers.provider.send('evm_increaseTime', [epochTime]);
            await ethers.provider.send('evm_mine');
            await stackingPenalty.removeStake(0,i,{from : accounts[4]});
   }


        // await ethers.provider.send('evm_increaseTime', [epochTime]);
        // await ethers.provider.send('evm_mine');

        // await rewardPenalty.rewardOfStake(0,"0",sign,{from : accounts[4]});

        await stackingPenalty.removeStake(0,"10",{from : accounts[4]});

        const penalty = await rewardPenalty.getRewardPenalty(10,epochTime*23,10,100);
        const activeStakes = await stackingPenalty.getactiveStakesTillEpoch(51);

        assert.equal(activeStakes.toString(),1)

        await truffleAssert.reverts(rewardPenalty.imposeRewardPenalty(0,"12345",10,100),"Only stacking contract can impose penalty")

        assert.equal(0,penalty);

        const epoch = await rewardPenalty.getCurrentEpoch()
        
        assert.equal(epoch.toString(),1);

        const StakeAmount = await stackingPenalty.getStakeAmount(0);

        await stackingPenalty.removeStake(0,StakeAmount,{from : accounts[4]});

        const stakesOfAddress = await stackingPenalty.getStakesOfAddress(accounts[4]);
        
        const accStakes = await stackingPenalty.stakeOf(accounts[4]);
        assert.equal(accStakes.toString(),"0");

        await truffleAssert.reverts(rewardPenalty.totalStakeRemoved(0),"not stacking contract");
        
        
    })

    

})