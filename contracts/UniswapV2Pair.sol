pragma solidity =0.5.16;

import './interfaces/IUniswapV2Pair.sol';
import './UniswapV2ERC20.sol';
import './libraries/Math.sol';
import './libraries/UQ112x112.sol';
import './interfaces/IERC20.sol';
import './interfaces/IUniswapV2Factory.sol';
import './interfaces/IUniswapV2Callee.sol';

// IUniswapV2Pair是实现、UniswapV2ERC20是继承
// 交易对合约，主要用于更新一些数据、做一些交易之类的操作
contract UniswapV2Pair is IUniswapV2Pair, UniswapV2ERC20 {
    // 把库函数应用到unit类型，下面代码中的uint类型的函数可以直接调用safemath中的方法
    using SafeMath  for uint;
    using UQ112x112 for uint224;

    //TODO 最小流动性，需要解释
    uint public constant MINIMUM_LIQUIDITY = 10**3;
    // function transfer(address to, uint value) external returns (bool) ，UniswapV2ERC20种的一个方法
    //TODO 这里的调用方式要关注下，比较特殊呀
    bytes4 private constant SELECTOR = bytes4(keccak256(bytes('transfer(address,uint256)')));

    address public factory;
    // token0的地址
    address public token0;
    address public token1;

    // 恒定乘积中的资产数量（reserve0代表token0的资产数量）
    uint112 private reserve0;           // uses single storage slot, accessible via getReserves
    uint112 private reserve1;           // uses single storage slot, accessible via getReserves

    // 最近的一次交易区块提交时间戳
    uint32  private blockTimestampLast; // uses single storage slot, accessible via getReserves

    // 历史交易价格累计值，应该是用来做预言机留的参数
    uint public price0CumulativeLast;
    uint public price1CumulativeLast;
    // 恒定乘积
    uint public kLast; // reserve0 * reserve1, as of immediately after the most recent liquidity event

    // 交易锁
    uint private unlocked = 1;
    // modifier是函数修饰器，lock被修饰了
    // 这里主要是作为交易时的锁使用，防止重入。
    modifier lock() {
        require(unlocked == 1, 'UniswapV2: LOCKED');
        unlocked = 0;
        /* 
            执行被修饰的函数体
            TODO 详细了解一下_;的执行逻辑
        */
        _;
        unlocked = 1;
    }

    /*
        获取资产数量以及最近一次交易时间
    */
    function getReserves() public view returns (uint112 _reserve0, uint112 _reserve1, uint32 _blockTimestampLast) {
        _reserve0 = reserve0;
        _reserve1 = reserve1;
        _blockTimestampLast = blockTimestampLast;
    }

    /*
        调用UniswapV2ERC20中的transfer函数
        TODO transfer是干啥的
    */
    function _safeTransfer(address token, address to, uint value) private {
        (bool success, bytes memory data) = token.call(abi.encodeWithSelector(SELECTOR, to, value));
        require(success && (data.length == 0 || abi.decode(data, (bool))), 'UniswapV2: TRANSFER_FAILED');
    }

    event Mint(address indexed sender, uint amount0, uint amount1);
    event Burn(address indexed sender, uint amount0, uint amount1, address indexed to);
    event Swap(
        address indexed sender,
        uint amount0In,
        uint amount1In,
        uint amount0Out,
        uint amount1Out,
        address indexed to
    );
    event Sync(uint112 reserve0, uint112 reserve1);

    constructor() public {
        factory = msg.sender;
    }

    // called once by the factory at time of deployment
    function initialize(address _token0, address _token1) external {
        // 只有工厂协议能够调用这个协议
        require(msg.sender == factory, 'UniswapV2: FORBIDDEN'); // sufficient check
        // 因为factory合约使用create2函数创建交易对合约，无法向构造器传递参数，所以这里写了一个初始化函数用来记录合约中两种代币的地址。
        token0 = _token0;
        token1 = _token1;
    }      

    // update reserves and, on the first call per block, price accumulators
    // 用于更新恒定乘积的两个乘数，以及最近一次区块提交的时间
    function _update(uint balance0, uint balance1, uint112 _reserve0, uint112 _reserve1) private {
        require(balance0 <= uint112(-1) && balance1 <= uint112(-1), 'UniswapV2: OVERFLOW');
        // block.timestamp当前区块时间戳
        uint32 blockTimestamp = uint32(block.timestamp % 2**32);
        // 本次区块提交时间与上次的差值
        // TODO 溢出已考虑，这个地方值得细看
        uint32 timeElapsed = blockTimestamp - blockTimestampLast; // overflow is desired、
        // 不是同一个区块、并且恒定乘积不是0
        if (timeElapsed > 0 && _reserve0 != 0 && _reserve1 != 0) {
            // * never overflows, and + overflow is desired
            price0CumulativeLast += uint(UQ112x112.encode(_reserve1).uqdiv(_reserve0)) * timeElapsed;
            price1CumulativeLast += uint(UQ112x112.encode(_reserve0).uqdiv(_reserve1)) * timeElapsed;
        }
        // 把恒定乘积的乘数更新成余额
        reserve0 = uint112(balance0);
        reserve1 = uint112(balance1);
        blockTimestampLast = blockTimestamp;
        emit Sync(reserve0, reserve1);
    }

    // if fee is on, mint liquidity equivalent to 1/6th of the growth in sqrt(k)
    // 如果feeTo开关打开，则需要讲
    function _mintFee(uint112 _reserve0, uint112 _reserve1) private returns (bool feeOn) {
        // 获取feeTo地址状态
        address feeTo = IUniswapV2Factory(factory).feeTo();
        // 如果不是零地址，则表示feeTo开关打开
        feeOn = feeTo != address(0);
        // 局部变量有助于减少gas费
        uint _kLast = kLast; // gas savings
        /*
            TODO 这里没看太懂
        */
        if (feeOn) {
            if (_kLast != 0) {
                // 当前流动性
                uint rootK = Math.sqrt(uint(_reserve0).mul(_reserve1));
                // 上一次流动性的平方
                uint rootKLast = Math.sqrt(_kLast);
                if (rootK > rootKLast) {
                    uint numerator = totalSupply.mul(rootK.sub(rootKLast));
                    uint denominator = rootK.mul(5).add(rootKLast);
                    uint liquidity = numerator / denominator;
                    if (liquidity > 0) _mint(feeTo, liquidity);
                }
            }
        } else if (_kLast != 0) {
            kLast = 0;
        }
    }

    // this low-level function should be called from a contract which performs important safety checks
    // 用户给pair提供流动性时，给对应用户mint uniwap代币的函数
    function mint(address to) external lock returns (uint liquidity) {
        (uint112 _reserve0, uint112 _reserve1,) = getReserves(); // gas savings
        // 获取这个合约地址下的token0代币的余额，此时在上层方法已经完成了转账
        uint balance0 = IERC20(token0).balanceOf(address(this));
        uint balance1 = IERC20(token1).balanceOf(address(this));
        // 那当前账户余额-恒定乘积的reserve0，注入资产数量
        uint amount0 = balance0.sub(_reserve0);
        uint amount1 = balance1.sub(_reserve1);

        bool feeOn = _mintFee(_reserve0, _reserve1);
        // 该合约直接继承了UniswapV2ERC20合约，因此可以直接调用UniswapV2ERC20合约中定义的totalSupply，这个值时指的uni代币的总供应量
        uint _totalSupply = totalSupply; // gas savings, must be defined here since totalSupply can update in _mintFee
        if (_totalSupply == 0) {
            // 提供的流动性-最小流动性，为啥这样算出来是流动性
            liquidity = Math.sqrt(amount0.mul(amount1)).sub(MINIMUM_LIQUIDITY);
           _mint(address(0), MINIMUM_LIQUIDITY); // permanently lock the first MINIMUM_LIQUIDITY tokens
        } else {
            liquidity = Math.min(amount0.mul(_totalSupply) / _reserve0, amount1.mul(_totalSupply) / _reserve1);
        }
        require(liquidity > 0, 'UniswapV2: INSUFFICIENT_LIQUIDITY_MINTED');
        // 根据提供的流动性，进行铸币
        _mint(to, liquidity);

        // 更新乘积的乘数
        _update(balance0, balance1, _reserve0, _reserve1);
        if (feeOn) kLast = uint(reserve0).mul(reserve1); // reserve0 and reserve1 are up-to-date
        emit Mint(msg.sender, amount0, amount1);
    }

    // this low-level function should be called from a contract which performs important safety checks
    // 提取资产同时燃烧mint函数mint的代币
    function burn(address to) external lock returns (uint amount0, uint amount1) {
        (uint112 _reserve0, uint112 _reserve1,) = getReserves(); // gas savings
        address _token0 = token0;                                // gas savings
        address _token1 = token1;                                // gas savings
        uint balance0 = IERC20(_token0).balanceOf(address(this));
        uint balance1 = IERC20(_token1).balanceOf(address(this));
        uint liquidity = balanceOf[address(this)];

        bool feeOn = _mintFee(_reserve0, _reserve1);
        uint _totalSupply = totalSupply; // gas savings, must be defined here since totalSupply can update in _mintFee
        amount0 = liquidity.mul(balance0) / _totalSupply; // using balances ensures pro-rata distribution
        amount1 = liquidity.mul(balance1) / _totalSupply; // using balances ensures pro-rata distribution
        require(amount0 > 0 && amount1 > 0, 'UniswapV2: INSUFFICIENT_LIQUIDITY_BURNED');
        // 根据流动性燃烧代币
        _burn(address(this), liquidity);
        // 提取token1 token0
        _safeTransfer(_token0, to, amount0);
        _safeTransfer(_token1, to, amount1);
        balance0 = IERC20(_token0).balanceOf(address(this));
        balance1 = IERC20(_token1).balanceOf(address(this));

        // 更新池子里面的数据
        _update(balance0, balance1, _reserve0, _reserve1);
        if (feeOn) kLast = uint(reserve0).mul(reserve1); // reserve0 and reserve1 are up-to-date
        emit Burn(msg.sender, amount0, amount1, to);
    }

    // this low-level function should be called from a contract which performs important safety checks
    // 购买的token0的数量，购买的token1的数量，接收者地址，接收后执行回调时的传递数据。
    // TODO 看不太懂，需要看上层调用的逻辑再来看
    // 这里调用的时候传参并没有指定是哪个交易对。调用的时候选择对应的交易对地址，应该就已经选择了是哪个交易对。此时token是啥已经固定了。
    function swap(uint amount0Out, uint amount1Out, address to, bytes calldata data) external lock {
        // 二者只要有一个>0既可。如果俩都>0是否会产生漏洞？
        require(amount0Out > 0 || amount1Out > 0, 'UniswapV2: INSUFFICIENT_OUTPUT_AMOUNT');
        (uint112 _reserve0, uint112 _reserve1,) = getReserves(); // gas savings
        require(amount0Out < _reserve0 && amount1Out < _reserve1, 'UniswapV2: INSUFFICIENT_LIQUIDITY');

        uint balance0;
        uint balance1;
        { // scope for _token{0,1}, avoids stack too deep errors
        address _token0 = token0;
        address _token1 = token1;
        require(to != _token0 && to != _token1, 'UniswapV2: INVALID_TO');
        if (amount0Out > 0) _safeTransfer(_token0, to, amount0Out); // optimistically transfer tokens
        if (amount1Out > 0) _safeTransfer(_token1, to, amount1Out); // optimistically transfer tokens
        if (data.length > 0) IUniswapV2Callee(to).uniswapV2Call(msg.sender, amount0Out, amount1Out, data);
        // 兑换后的token0与token1的余额，获取的是交易对中两种代币的合约数量
        balance0 = IERC20(_token0).balanceOf(address(this));
        balance1 = IERC20(_token1).balanceOf(address(this));
        }
        /*
            这里记录的是对方注入池子的代币数量
            余额>储备量-提取量，意味着对方注入了多出来的这部分代币。否则对方未注入代币。
            这里是先给to地址发送代币后，再检查对面是否注入交换的代币，目的是什么？看起来代币都是同一种哇。看不出来是token0与token1的交换
        */
        uint amount0In = balance0 > _reserve0 - amount0Out ? balance0 - (_reserve0 - amount0Out) : 0;
        uint amount1In = balance1 > _reserve1 - amount1Out ? balance1 - (_reserve1 - amount1Out) : 0;
        // 只校验了两者其中一个>0但是没有校验具体大了多少，会不会产生少给的问题？这个问题是不是在上层合约中已经处理过了。
        require(amount0In > 0 || amount1In > 0, 'UniswapV2: INSUFFICIENT_INPUT_AMOUNT');
        { // scope for reserve{0,1}Adjusted, avoids stack too deep errors
        uint balance0Adjusted = balance0.mul(1000).sub(amount0In.mul(3));
        uint balance1Adjusted = balance1.mul(1000).sub(amount1In.mul(3));
        require(balance0Adjusted.mul(balance1Adjusted) >= uint(_reserve0).mul(_reserve1).mul(1000**2), 'UniswapV2: K');
        }

        _update(balance0, balance1, _reserve0, _reserve1);
        emit Swap(msg.sender, amount0In, amount1In, amount0Out, amount1Out, to);
    }

    // force balances to match reserves
    function skim(address to) external lock {
        address _token0 = token0; // gas savings
        address _token1 = token1; // gas savings
        _safeTransfer(_token0, to, IERC20(_token0).balanceOf(address(this)).sub(reserve0));
        _safeTransfer(_token1, to, IERC20(_token1).balanceOf(address(this)).sub(reserve1));
    }

    // force reserves to match balances
    function sync() external lock {
        _update(IERC20(token0).balanceOf(address(this)), IERC20(token1).balanceOf(address(this)), reserve0, reserve1);
    }
}
