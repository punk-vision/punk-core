pragma solidity >=0.4.23 <0.6.12;

import "./openzeppelin/contracts/utils/ReentrancyGuard.sol";

interface IToken {
    function transfer(address _to, uint256 _value) external returns (bool);
    function transferFrom(address _from, address _to, uint256 _value) external returns (bool);
}

contract Punk is ReentrancyGuard{
	struct User {
		uint256 id;
		uint256 balance;
		uint256 lastTime;
		uint256 lpBalance;  // lpBalance for the user
		uint256 withdrawTime;  // withdraw once every day
	}

	struct LpToken {
		uint256 id;
		IToken token;		
		uint256 weight;

		uint256 balance;

		uint256 lastTime;
		uint256 lpBalance;     // lpBalance for the pool

		uint256 punkBalance;
		uint256 punkTime;

		uint256 lastID;
		mapping(address => User) users;
	}

	uint public lastID = 0;
	mapping(uint256 => LpToken) public tokens;
	mapping(address => uint256) public addrToTokens;
	uint256 public weights;
	uint256 public createTime;
	IToken public punkToken;
	uint256 public rewards;   // per day
	uint256 public punkDecimals = 6;
	uint256 public lpDecimals = 6;

	uint256 public stakingTimes = 0;
	
	uint256 public oneDay = 24 * 3600;
	//uint256 public oneDay = 600;

	address public owner;


	constructor(address ownerAddress, address punkAddr) public {
		require(ownerAddress != address(0), "owner can't be null");
		require(punkAddr != address(0), "punk can't be null");

		owner = ownerAddress;
		rewards = 15000 * (10 ** punkDecimals);
		punkToken = IToken(punkAddr);
		createTime = now;
	}

	modifier onlyOwner() {
	    require(msg.sender == owner);
	    _;
	}

	function setOwner(address ownerAddress) public onlyOwner {
		require(ownerAddress != address(0), "owner can't be null");
		owner = ownerAddress;
	}

	function setReward(uint256 reward) public onlyOwner {
		rewards = reward * (10 ** punkDecimals);
	}

	function registerToken(address tokenAddr, uint256 weight) external onlyOwner {
		require(tokenAddr != address(0), "token can't be zero");
		require(weight != 0, "weight can't be zero");
		require(addrToTokens[tokenAddr] == 0, "token exists");

		lastID++;
		LpToken memory token = LpToken({
			id: lastID,
			token: IToken(tokenAddr),
			weight: weight,
			balance: 0,
			lastTime: 0,
			lpBalance: 0,
			punkBalance: 0,
			punkTime: createTime,
			lastID: 0
		});

		tokens[lastID] = token;
		addrToTokens[tokenAddr] = lastID;

		weights += weight;
	}

	function setWeight(uint256 id, uint256 weight) external onlyOwner {
		require(tokens[id].id != 0, "token not exists");
		require(weight != 0, "weight can't be zero");
		weights -= tokens[id].weight;
		tokens[id].weight = weight;
		weights += weight;
	}

	function stake(uint256 id, uint256 amount) external nonReentrant {
		require(amount > 0, "amount can't be smaller than 0");
		require(tokens[id].id != 0, "token not exists");

		require(tokens[id].token.transferFrom(msg.sender, address(this), amount), "transferFrom failed");

		if(tokens[id].users[msg.sender].id != 0) {   // user exists
			tokens[id].users[msg.sender].lpBalance += (tokens[id].users[msg.sender].balance * (now - tokens[id].users[msg.sender].lastTime) / (10 ** lpDecimals)); 
			tokens[id].users[msg.sender].balance += amount;
			tokens[id].users[msg.sender].lastTime = now;
		} else {
			tokens[id].lastID++;
			User memory user = User({
				id: tokens[id].lastID,
				balance: amount,
				lastTime: now,
				lpBalance: 0,
				withdrawTime: now
			});
			tokens[id].users[msg.sender] = user;
		}
		tokens[id].lpBalance += (tokens[id].balance * (now - tokens[id].lastTime) / (10 ** lpDecimals));
		tokens[id].lastTime = now;
		tokens[id].balance += amount;

		stakingTimes++;
	}

	function withdraw(uint256 id, uint256 amount) external nonReentrant {
		require(amount > 0, "amount can't be smaller than 0");
		require(tokens[id].id != 0, "token not exists");
		require(tokens[id].users[msg.sender].id != 0, "user not exists");
		require(tokens[id].users[msg.sender].balance > amount, "balance not enough");

		require(tokens[id].token.transfer(msg.sender, amount), "transfer failed");

		tokens[id].users[msg.sender].lpBalance += (tokens[id].users[msg.sender].balance * (now - tokens[id].users[msg.sender].lastTime) / (10 ** lpDecimals));
		tokens[id].users[msg.sender].balance -= amount;
		tokens[id].users[msg.sender].lastTime = now;

		tokens[id].lpBalance += (tokens[id].balance * (now - tokens[id].lastTime) / (10 ** lpDecimals));
		tokens[id].lastTime = now;
		tokens[id].balance -= amount;
	}

	function withdrawPunk(uint256 id) external nonReentrant {
		require(tokens[id].id != 0, "token not exists");
		require(tokens[id].users[msg.sender].id != 0, "user not exists");
		require(now - createTime < 4 * 12 * 30 * oneDay, "only mined by 4 years");
		require(now - tokens[id].users[msg.sender].withdrawTime > oneDay, "withdraw once every day");

		tokens[id].punkBalance += rewards * (now - tokens[id].punkTime) * tokens[id].weight / (weights * oneDay);
		tokens[id].punkTime = now;

		tokens[id].lpBalance += (tokens[id].balance * (now - tokens[id].lastTime) / (10 ** lpDecimals));
		tokens[id].lastTime = now;

		tokens[id].users[msg.sender].lpBalance += (tokens[id].users[msg.sender].balance * (now - tokens[id].users[msg.sender].lastTime) / (10 ** lpDecimals));
		tokens[id].users[msg.sender].lastTime = now;
		tokens[id].users[msg.sender].withdrawTime = now;

		uint256 amount = tokens[id].punkBalance * tokens[id].users[msg.sender].lpBalance / tokens[id].lpBalance;

		require(punkToken.transfer(msg.sender, amount), "transfer failed");

		tokens[id].punkBalance -= amount;
		tokens[id].lpBalance -= tokens[id].users[msg.sender].lpBalance;
		tokens[id].users[msg.sender].lpBalance = 0;
	}

	function global() public view returns(uint256, uint256, uint256, uint256) {
		uint256 count = 0;
		for(uint256 i = 1; i <= lastID; i++) {
			count += tokens[i].lastID;
		}
		return (tokens[1].balance, count, rewards * (now - createTime) / (oneDay), stakingTimes);
	}

	function pool(uint256 id) public view returns(uint256, uint256, uint256, uint256, uint256) {
		uint256 left = 0;
		uint256 myPunk = 0;
		if(tokens[id].id != 0) {
			if(tokens[id].users[msg.sender].id != 0) {
				// if(tokens[id].users[msg.sender].lpBalance != 0) {
				uint256 extraUser = (tokens[id].users[msg.sender].balance * (now - tokens[id].users[msg.sender].lastTime) / (10 ** lpDecimals));
				uint256 extraToken = (tokens[id].balance * (now - tokens[id].lastTime) / (10 ** lpDecimals));

				if(tokens[id].lpBalance + extraToken > 0) {
					myPunk = (tokens[id].punkBalance + rewards * (now - tokens[id].punkTime) * tokens[id].weight / (weights * oneDay)) * (tokens[id].users[msg.sender].lpBalance + extraUser) / (tokens[id].lpBalance + extraToken);
				}
				// }
			}
		}
		if(now - tokens[id].users[msg.sender].withdrawTime > oneDay) {
			left = 0;
		} else {
			left = oneDay - (now - tokens[id].users[msg.sender].withdrawTime);
		}
		return (rewards * tokens[id].weight / weights, tokens[id].balance, myPunk, tokens[id].users[msg.sender].balance, left);
	}
}
