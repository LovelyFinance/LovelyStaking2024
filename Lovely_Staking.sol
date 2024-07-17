// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

/**
 * @dev Provides information about the current execution context, including the
 * sender of the transaction and its data. While these are generally available
 * via msg.sender and msg.data, they should not be accessed in such a direct
 * manner, since when dealing with meta-transactions the account sending and
 * paying for execution may not be the actual sender (as far as an application
 * is concerned).
 *
 * This contract is only required for intermediate, library-like contracts.
 */
abstract contract Context {
    function _msgSender() internal view virtual returns (address) {
        return msg.sender;
    }

    function _msgData() internal view virtual returns (bytes calldata) {
        return msg.data;
    }
}

/**
 * @dev Contract module which provides a basic access control mechanism, where
 * there is an account (an owner) that can be granted exclusive access to
 * specific functions.
 *
 * By default, the owner account will be the one that deploys the contract. This
 * can later be changed with {transferOwnership}.
 *
 * This module is used through inheritance. It will make available the modifier
 * `onlyOwner`, which can be applied to your functions to restrict their use to
 * the owner.
 */
abstract contract Ownable is Context {
    address private _owner;

    event OwnershipTransferred(
        address indexed previousOwner,
        address indexed newOwner
    );

    /**
     * @dev Initializes the contract setting the deployer as the initial owner.
     */
    constructor() {
        _transferOwnership(_msgSender());
    }

    /**
     * @dev Throws if called by any account other than the owner.
     */
    modifier onlyOwner() {
        _checkOwner();
        _;
    }

    /**
     * @dev Returns the address of the current owner.
     */
    function owner() public view virtual returns (address) {
        return _owner;
    }

    /**
     * @dev Throws if the sender is not the owner.
     */
    function _checkOwner() internal view virtual {
        require(owner() == _msgSender(), "Ownable: caller is not the owner");
    }

    /**
     * @dev Leaves the contract without owner. It will not be possible to call
     * `onlyOwner` functions anymore. Can only be called by the current owner.
     *
     * NOTE: Renouncing ownership will leave the contract without an owner,
     * thereby removing any functionality that is only available to the owner.
     */
    function renounceOwnership() public virtual onlyOwner {
        _transferOwnership(address(0));
    }

    /**
     * @dev Transfers ownership of the contract to a new account (`newOwner`).
     * Can only be called by the current owner.
     */
    function transferOwnership(address newOwner) public virtual onlyOwner {
        require(
            newOwner != address(0),
            "Ownable: new owner is the zero address"
        );
        _transferOwnership(newOwner);
    }

    /**
     * @dev Transfers ownership of the contract to a new account (`newOwner`).
     * Internal function without access restriction.
     */
    function _transferOwnership(address newOwner) internal virtual {
        address oldOwner = _owner;
        _owner = newOwner;
        emit OwnershipTransferred(oldOwner, newOwner);
    }
}
interface IERC20
{

    function balanceOf(address user) external view returns(uint256);
    function transfer(address _to, uint256 _amount) external returns (bool);
    function transferFrom(address _from, address _to, uint256 _amount) external returns (bool);
    function allowance(address _owner, address spender) external view returns (uint256);   

}

contract LovelyStaking is Ownable {    
    struct poolData
    {
        uint256 poolTime;
        uint256 APY;
        uint256 rewardspersec;
        uint256 totalTokens;
    }    
    mapping (uint => poolData) public poolInfo;
    uint public poolLength;
    struct stakingData
    {       
        uint256 amount;
        uint256 stakeTime;
        uint256 stakeEndTime;
        uint256 lastRewardTime;
        uint256 rewardsEarnerd;
    }
    //user's pool wise stakingInfo
    mapping(address => mapping(uint =>stakingData)) public stakeInfo;
    mapping(address => uint256) public pendingRewards;
    mapping(address=> uint256) public earnings;
    struct contractValues
    {
        uint  maxDaysToClose;
        uint256  maxTokens;
        IERC20  stakeToken;
        uint256  totalStaked;        
        uint256  launchTime;
        uint256 rewardFund;
    }
   
    contractValues public contractInfo;
    
    //events
    event EvStake(address indexed staker, uint256 amount, uint poolId, uint256 _staketime);
    event EvUnStake(address indexed staker, uint256 amount, uint256 unstaketime);
    event EvWithdrawRewards(address indexed staker, uint256 rewards, uint poolId, uint256 withdrawtime);
    event EvRewardRefund(address indexed sender, uint256 amount, uint256 refundtime);
    /* These valuese cannot be update after deploy.
        poolDays arrays of days for pool
        _poolApy APY %  - value should be multiply by 100.. for 3.5 - 350
        first pools will be flexible
        _poolDays = [0,15,60,120,365]
        _poolApy = [350,600,2000,3500,6000]    
        _maxDaysToClose - 5 
        _maxTokens - 1000000 * decimal
    */
    constructor(address _stakeToken, uint256 _maxDaysToClose, uint256 _maxTokens, uint256[] memory _poolDays, uint256[] 

memory _poolApy)  {
        require(_stakeToken != address(0),"Invalid token address");
        require(_poolDays.length == _poolApy.length, "Length not matched");
        for(uint i=0;i<_poolDays.length;i++)
        {
            poolInfo[i].poolTime = _poolDays[i] * 86400;
            poolInfo[i].APY = _poolApy[i];
            if(_poolDays[i] > 0)
            {
                poolInfo[i].rewardspersec = _poolApy[i] * 1e12 / (_poolDays[i] * 86400) ;
            }
            else 
            {
                poolInfo[i].rewardspersec = _poolApy[i] * 1e12 / (365 * 86400) ;
            }
        }        
        poolLength = _poolDays.length;
        contractInfo.maxDaysToClose = _maxDaysToClose * 86400;
        contractInfo.maxTokens = _maxTokens;
        contractInfo.stakeToken = IERC20(_stakeToken);
        contractInfo.launchTime = block.timestamp;        
   }

   function stake(uint poolId, uint256 tokenamount) external 
   {
        require(tokenamount > 0, "Token amount is zero");
        require((poolId == 0 || (contractInfo.launchTime + contractInfo.maxDaysToClose >= block.timestamp)),"StakeTime is over");
        require((poolId == 0 || (poolInfo[poolId].totalTokens + tokenamount) <= contractInfo.maxTokens), "Pool is full");
        require(contractInfo.stakeToken.balanceOf(msg.sender) >= tokenamount, "Not enough tokens");
        require(contractInfo.stakeToken.allowance(msg.sender, address(this)) >= tokenamount,"Not enough allowances");
        
        if(stakeInfo[msg.sender][poolId].amount == 0)
        {            
            stakeInfo[msg.sender][poolId].lastRewardTime = block.timestamp;
            stakeInfo[msg.sender][poolId].stakeTime = block.timestamp;
            stakeInfo[msg.sender][poolId].stakeEndTime = block.timestamp + poolInfo[poolId].poolTime;
        }
        _withdrawRewards(poolId, true);
        
        poolInfo[poolId].totalTokens += tokenamount;
        stakeInfo[msg.sender][poolId].amount += tokenamount;   
        contractInfo.totalStaked += tokenamount;             
        contractInfo.stakeToken.transferFrom(msg.sender, address(this), tokenamount);

        emit EvStake(msg.sender, tokenamount, poolId, block.timestamp);
   }
   
   function withdrawRewards(uint poolId) public
    {            
        _withdrawRewards(poolId, false);                    
    }
    function unstake(uint poolId) external {
        uint256 stakedamount = stakeInfo[msg.sender][poolId].amount;
        require(stakedamount > 0, "Invalid stake");        
        require(stakeInfo[msg.sender][poolId].stakeEndTime <= block.timestamp,"Cannot unstake early");
        _withdrawRewards(poolId, true);
        stakeInfo[msg.sender][poolId].amount = 0;
        stakeInfo[msg.sender][poolId].stakeTime = 0;
        poolInfo[poolId].totalTokens -= stakedamount;
        contractInfo.totalStaked -= stakedamount;
        contractInfo.stakeToken.transfer(msg.sender, stakedamount);
        emit EvUnStake(msg.sender, stakedamount, block.timestamp);
    }
    
    function sendRewardToken(uint256 amount) external  
    {
        contractInfo.rewardFund += amount;
        contractInfo.stakeToken.transferFrom(msg.sender, address(this), amount);
        emit EvRewardRefund(msg.sender, amount, block.timestamp);
    }

   //Owner Function

    function rescueRewardFund(uint256 amount) external onlyOwner
    {
	require(contractInfo.rewardFund >= amount,"Not enough reward fund");
	contractInfo.rewardFund -= amount;
	contractInfo.stakeToken.transfer(msg.sender, amount);
    }

    //view functions
    //show rewards of a staker for pool
    function viewRewards(address staker, uint poolId) public view returns(uint256 vRewards)
    {
        uint256 endTime = stakeInfo[staker][poolId].stakeEndTime;
        vRewards = pendingRewards[staker];
        if(endTime > block.timestamp || poolId == 0)
        {
            endTime = block.timestamp;
        }
        if(stakeInfo[staker][poolId].amount > 0 && endTime > stakeInfo[staker][poolId].lastRewardTime)
        {
            vRewards += (endTime - stakeInfo[staker][poolId].lastRewardTime) * ((stakeInfo[staker][poolId].amount * poolInfo

[poolId].rewardspersec) / 1e16) ;
        }
    }

    //show all pools rewards of a staker
    function viewAllRewards(address staker) public view returns(uint256 vRewards)
    {
        for(uint i=0; i < poolLength;i++)
        {
            vRewards += viewRewards(staker, i);
        }
    }   

    //internal function
    function _withdrawRewards(uint poolId, bool isForced)  internal 
   {
        uint256 rewards =viewRewards(msg.sender, poolId); 
        if(!isForced)
        {
            require(rewards >0,"No rewards to withdraw");
        }
        if(rewards > 0 && contractInfo.rewardFund >= rewards && contractInfo.stakeToken.balanceOf(address(this)) >= 

rewards)
        {            
            stakeInfo[msg.sender][poolId].lastRewardTime = block.timestamp;
            stakeInfo[msg.sender][poolId].rewardsEarnerd += rewards;
            pendingRewards[msg.sender] = 0;
            earnings[msg.sender] += rewards;
            contractInfo.rewardFund -= rewards;
            contractInfo.stakeToken.transfer(msg.sender, rewards);
            emit EvWithdrawRewards(msg.sender, rewards, poolId, block.timestamp);
        }
        else {
            stakeInfo[msg.sender][poolId].lastRewardTime = block.timestamp;
            pendingRewards[msg.sender] = rewards;
        }    
   }
}
