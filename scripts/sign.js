const sigUtil = require('eth-sig-util');

const signMessage = async (privateKey,netId,contractAddress,rewards,stakeId,currentEpoch) => {
    const msgParams = {
      types: {
        EIP712Domain: [
          { name: 'name', type: 'string' },
          { name: 'version', type: 'string' },
          { name: 'chainId', type: 'uint256' },
          { name: 'verifyingContract', type: 'address' },
        ],
        volarySign: [
          { name: 'rewards', type: 'uint256' },
          { name: 'stakeId', type: 'uint256' },
          { name: 'currentEpoch', type: 'uint256' },
        ],
      },
      //make sure to replace verifyingContract with address of deployed contract
      primaryType: 'volarySign',
      domain: {
        name: 'volaryTokenomics',
        version: '1',
        chainId: netId,
        verifyingContract: contractAddress,
      },
      message: {
        rewards: rewards,
        stakeId: stakeId,
        currentEpoch: currentEpoch,
      },
    };
    const signature = sigUtil.signTypedMessage(
      new Buffer.from(privateKey, 'hex'),
      { data: msgParams },
      'V3'
    );
    return signature;
}

module.exports = {
    signMessage
}