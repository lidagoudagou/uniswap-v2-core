pragma solidity =0.5.16;

import './interfaces/IUniswapV2Factory.sol';
import './UniswapV2Pair.sol';

contract UniswapV2Factory is IUniswapV2Factory {
    // 零地址则代表开发团队手续费不收取、非零地址则代表开发团队手续费收取（0/3%的1/6给开发者团队）
    address public feeTo;
    // 记录feeTo变量的设置者
    address public feeToSetter;

    // 交易对存储 Token1的ERC20代币合约地址、Token2的ERC20代币合约地址、交易对地址
    // 默认小地址作为key，大地址作为value
    mapping(address => mapping(address => address)) public getPair;
    address[] public allPairs;

    // 创建交易对的时候触发事件
    event PairCreated(address indexed token0, address indexed token1, address pair, uint);

    // 合约创建的时候，就确定好谁能决定feeTo开关的开闭
    constructor(address _feeToSetter) public {
        feeToSetter = _feeToSetter;
    }

    // 返回有多少个交易对
    function allPairsLength() external view returns (uint) {
        return allPairs.length;
    }

    // 创建交易对
    function createPair(address tokenA, address tokenB) external returns (address pair) {
        // 要求TokenA的合约地址不能等于TokenB的合约地址，即要求两个Token不能是同种代币
        require(tokenA != tokenB, 'UniswapV2: IDENTICAL_ADDRESSES');
        // 给俩token地址排序
        (address token0, address token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        // 要求低地址的token不能是零地址，这个要求了之后，高地址的token自然也会复合这个要求
        require(token0 != address(0), 'UniswapV2: ZERO_ADDRESS');
        // 如果从getPair的Map中取出的地址不是零地址，意味着这个交易对存在，不进行下面的创建操作
        require(getPair[token0][token1] == address(0), 'UniswapV2: PAIR_EXISTS'); // single check is sufficient
        // 调用UniswapV2Pair合约中的创建逻辑
        bytes memory bytecode = type(UniswapV2Pair).creationCode;
        bytes32 salt = keccak256(abi.encodePacked(token0, token1));
        assembly {
            // 返回创建后的交易对地址
            pair := create2(0, add(bytecode, 32), mload(bytecode), salt)
        }
        // 初始化交易对
        IUniswapV2Pair(pair).initialize(token0, token1);
        // 存储创建后的交易对地址
        getPair[token0][token1] = pair;
        getPair[token1][token0] = pair; // populate mapping in the reverse direction
        //往allPairs数组中加入这个交易对地址
        allPairs.push(pair);
        // 发送交易对创建事件
        emit PairCreated(token0, token1, pair, allPairs.length);
    }

    function setFeeTo(address _feeTo) external {
        // 只有feeToSetter才能设置feeTo开关
        require(msg.sender == feeToSetter, 'UniswapV2: FORBIDDEN');
        feeTo = _feeTo;
    }

    function setFeeToSetter(address _feeToSetter) external {
        // 只有feeToSetter才能指定下一个feeToSetter
        require(msg.sender == feeToSetter, 'UniswapV2: FORBIDDEN');
        feeToSetter = _feeToSetter;
    }
}
