VOLARY.SOL :

Volary contract is a basic erc20 token contract with basic mint and transfer functionalities.

Stacking.SOL :

Stacking token contracts deals with the stacking functionalities of the volary token.

FUNCTIONS OF THE CONTRACT :

createStake : 
 This function allows a user to add a stake of volary tokens\

Each stake is a struct with the following parameters in it – address of the stake creator,duration - the time for which holder wish to stake the tokens,startTime - block.timestamp value at which the stake is created,stakeAmount- no.of.tokens the user is stacking.Each stake is identified by unique id(uint256)

Based on the amount of tokens staked by user theta are divided in 4 levels.
Based on the  duration each stake is categorised as either duration-bound-stake or not → every stake with non-zero duration is duration-bound-stake.

Every holder gets benefits(rewards in form of volary tokens) for stacking, these rewards are calculated on various factors and for duration-bound-stake duration-factor is also considered in reward calculation.


removeStake :

This lets the user remove tokens of his stake.

Users can remove an entire stake or a portion of stake.


If a user removes a stake there are two types of penalties imposed principal penalty(penalty imposed on the principal amount of tokens staked by holde and this is only duration bound stakes) and reward penalty(penalty imposed on the rewards earned by a stake).

Reward penalty imposement :

This penalty varies on the time for the stake remained staked i.e if the stake is removed before 4 weeks from the time staking then penalty is 50 of rewards earned if its more than 22 weeks then penalty is 0

Principal penalty imposement (only on duration bound stakes):

The penalty depends of duration factor and the stake amount that is being removed.if the duration factor is D and unstacked amount is A then principal penalty is 5% of (D*A)

All the penalties are transferred to treasury address


REWARDS POOL.SOL:

This contracts handles the rewards for the stakeholders

StartPool :

This function is to start the reward pool

In this reward pool structure there are two types of cycles namely : 1)EPOCH CYCLE 2)DISTRIBUTION CYCLE

As said previously each stake gets rewards based on various factors and this rewards are calculated during end of each epoch but this rewards are distributed on after 4 epoch cycles and this is called distribution cycle

During the start of each epoch 0.03% of reward pool volary balance is kept as rewards for stakes and this are divided among all the stakes based on their weightage

Calculate Reward weight :

Based on all the factors  passed this function calculates the reward of weight of a stake.

Let minting factor be M,referral factor R,engagement factor E,duration factor D and amount of tokens stakes A then Reward weight is M*R*E*D*A

Calculate Reward of Stake :

Stake of a reward is (rewardWeightOfThisStake/SumOfRewardsWeightsOfAllStakes)

But there is cap on the amount of rewards earned by the stake that the APY should be less than 60% and on calculation it is set that yield should be 0.9079502202


CLAIM REWARDS :

This lets any stakeholders withdraws all the rewards he earned.the rewards he can claim increase with time and are reflected in CLAIMABLE REWARDS MAPPING and whenever he claims rewards this value decreases where in CLAIMED REWARDS value increases
