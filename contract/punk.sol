pragma solidity ^0.6.11;

import "./openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "./openzeppelin/contracts/math/SafeMath.sol";

interface IToken {
    function transfer(address _to, uint256 _value) external returns (bool);
    function transferFrom(address _from, address _to, uint256 _value) external returns (bool);
}

contract Punk is ReentrancyGuard{
	using SafeMath for uint256;

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
	uint256 public constant punkDecimals = 6;
	uint256 public constant lpDecimals = 6;

	uint256 public stakingTimes = 0;
	
	uint256 public constant oneDay = 24 * 3600;
	//uint256 public oneDay = 600;

	address public owner;

	event SetOwner(address indexed to);
	event SetReward(uint256 value);
	event RegisterToken(address indexed tokenAddr, uint256 weight);
	event SetWeight(uint256 id, uint256 weight);


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

	function setOwner(address ownerAddress) external onlyOwner {
		require(ownerAddress != address(0), "owner can't be null");
		owner = ownerAddress;
		emit SetOwner(ownerAddress);
	}

	function setReward(uint256 reward) external onlyOwner {
		rewards = reward * (10 ** punkDecimals);
		emit SetReward(reward);
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

		//weights += weight;
		weights = weights.add(weight);

		emit RegisterToken(tokenAddr, weight);
	}

	function setWeight(uint256 id, uint256 weight) external onlyOwner {
		LpToken memory tokenById = tokens[id];
		require(tokenById.id != 0, "token not exists");
		require(weight != 0, "weight can't be zero");
		//weights -= tokenById.weight;
		//tokenById.weight = weight;
		//weights += weight;
		weights = weights.sub(tokenById.weight);
		tokenById.weight = weight;
		weights = weights.add(weight);

		emit SetWeight(id, weight);
	}

	function stake(uint256 id, uint256 amount) external nonReentrant {
		LpToken memory tokenById = tokens[id];
		require(amount > 0, "amount can't be smaller than 0");
		require(tokenById.id != 0, "token not exists");

		require(tokenById.token.transferFrom(msg.sender, address(this), amount), "transferFrom failed");

		if(tokens[id].users[msg.sender].id != 0) {   // user exists
			User memory userByAddr = tokens[id].users[msg.sender];
			//userByAddr.lpBalance += (userByAddr.balance * (now - userByAddr.lastTime) / (10 ** lpDecimals)); 
			userByAddr.lpBalance = userByAddr.lpBalance.add(userByAddr.balance.mul(now.sub(userByAddr.lastTime)).div(10 ** lpDecimals));
			//userByAddr.balance += amount;
			userByAddr.balance = userByAddr.balance.add(amount);
			userByAddr.lastTime = now;
		} else {
			tokenById.lastID++;
			User memory user = User({
				id: tokenById.lastID,
				balance: amount,
				lastTime: now,
				lpBalance: 0,
				withdrawTime: now
			});
			tokens[id].users[msg.sender] = user;
		}
		//tokenById.lpBalance += (tokenById.balance * (now - tokenById.lastTime) / (10 ** lpDecimals));
		tokenById.lpBalance = tokenById.lpBalance.add(tokenById.balance.mul(now.sub(tokenById.lastTime)).div(10 ** lpDecimals));
		tokenById.lastTime = now;
		//tokenById.balance += amount;
		tokenById.balance = tokenById.balance.add(amount);
		stakingTimes++;
	}

	function withdraw(uint256 id, uint256 amount) external nonReentrant {
		LpToken memory tokenById = tokens[id];
		require(amount > 0, "amount can't be smaller than 0");
		require(tokenById.id != 0, "token not exists");
		require(tokens[id].users[msg.sender].id != 0, "user not exists");
		require(tokens[id].users[msg.sender].balance >= amount, "balance not enough");

		require(tokenById.token.transfer(msg.sender, amount), "transfer failed");

		User memory userByAddr = tokens[id].users[msg.sender];

		//userByAddr.lpBalance += (userByAddr.balance * (now - userByAddr.lastTime) / (10 ** lpDecimals));
		userByAddr.lpBalance = userByAddr.lpBalance.add(userByAddr.balance.mul(now.sub(userByAddr.lastTime)).div(10 ** lpDecimals));
		//userByAddr.balance -= amount;
		userByAddr.balance = userByAddr.balance.sub(amount);
		userByAddr.lastTime = now;

		//tokenById.lpBalance += (tokenById.balance * (now - tokenById.lastTime) / (10 ** lpDecimals));
		tokenById.lpBalance = tokenById.lpBalance.add(tokenById.balance.mul(now.sub(tokenById.lastTime)).div(10 ** lpDecimals));
		tokenById.lastTime = now;
		tokenById.balance -= amount;
	}

	function withdrawPunk(uint256 id) external nonReentrant {
		LpToken memory tokenById = tokens[id];
		require(tokenById.id != 0, "token not exists");
		require(tokens[id].users[msg.sender].id != 0, "user not exists");
		require(now - createTime < 4 * 12 * 30 * oneDay, "only mined by 4 years");
		require(now - tokens[id].users[msg.sender].withdrawTime > oneDay, "withdraw once every day");

		User memory userByAddr = tokens[id].users[msg.sender];

		//tokenById.punkBalance += rewards * (now - tokenById.punkTime) * tokenById.weight / (weights * oneDay);
		tokenById.punkBalance = tokenById.punkBalance.add(rewards.mul(now.sub(tokenById.punkTime)).mul(tokenById.weight).div(weights.mul(oneDay)));
		tokenById.punkTime = now;

		//tokenById.lpBalance += (tokenById.balance * (now - tokenById.lastTime) / (10 ** lpDecimals));
		tokenById.lpBalance = tokenById.lpBalance.add(tokenById.balance.mul(now.sub(tokenById.lastTime)).div(10 ** lpDecimals));
		tokenById.lastTime = now;

		//userByAddr.lpBalance += (userByAddr.balance * (now - userByAddr.lastTime) / (10 ** lpDecimals));
		userByAddr.lpBalance = userByAddr.lpBalance.add(userByAddr.balance.mul(now.sub(userByAddr.lastTime)).div(10 ** lpDecimals));
		userByAddr.lastTime = now;
		userByAddr.withdrawTime = now;

		//uint256 amount = tokenById.punkBalance * userByAddr.lpBalance / tokenById.lpBalance;
		uint256 amount = tokenById.punkBalance.mul(userByAddr.lpBalance).div(tokenById.lpBalance);

		require(punkToken.transfer(msg.sender, amount), "transfer failed");

		//tokenById.punkBalance -= amount;
		tokenById.punkBalance = tokenById.punkBalance.sub(amount);
		//tokenById.lpBalance -= userByAddr.lpBalance;
		tokenById.lpBalance = tokenById.lpBalance.sub(userByAddr.lpBalance);
		userByAddr.lpBalance = 0;
	}

	function global() public view returns(uint256, uint256, uint256, uint256) {
		uint256 count = 0;
		for(uint256 i = 1; i <= lastID; i++) {
			count += tokens[i].lastID;
		}
		return (tokens[1].balance, count, rewards * (now - createTime) / (oneDay), stakingTimes);
	}

	function pool(uint256 id) public view returns(uint256, uint256, uint256, uint256, uint256) {
		LpToken memory tokenById = tokens[id];
		uint256 left = 0;
		uint256 myPunk = 0;
		if(tokenById.id != 0) {
			if(tokens[id].users[msg.sender].id != 0) {
				User memory userByAddr = tokens[id].users[msg.sender];
				// if(tokens[id].users[msg.sender].lpBalance != 0) {
				uint256 extraUser = (userByAddr.balance * (now - userByAddr.lastTime) / (10 ** lpDecimals));
				uint256 extraToken = (tokenById.balance * (now - tokenById.lastTime) / (10 ** lpDecimals));

				if(tokenById.lpBalance + extraToken > 0) {
					myPunk = (tokenById.punkBalance + rewards * (now - tokenById.punkTime) * tokenById.weight / (weights * oneDay)) * (userByAddr.lpBalance + extraUser) / (tokenById.lpBalance + extraToken);
				}
				// }
			}
		}
		if(now - tokens[id].users[msg.sender].withdrawTime > oneDay) {
			left = 0;
		} else {
			left = oneDay - (now - tokens[id].users[msg.sender].withdrawTime);
		}
		return (rewards * tokenById.weight / weights, tokenById.balance, myPunk, tokens[id].users[msg.sender].balance, left);
	}
}
