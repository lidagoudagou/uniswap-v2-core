pragma solidity =0.5.16;

import './interfaces/IUniswapV2ERC20.sol';
import './libraries/SafeMath.sol';

contract UniswapV2ERC20 is IUniswapV2ERC20 {
    using SafeMath for uint;

    string public constant name = 'Uniswap V2';
    string public constant symbol = 'UNI-V2';
    uint8 public constant decimals = 18;
    // TDOD uni代币的总供应量
    uint  public totalSupply;
    // 记录uni代币的各账户（流动性提供者）uni代币的余额
    mapping(address => uint) public balanceOf;
    // 允许提取的数量？
    mapping(address => mapping(address => uint)) public allowance;

    bytes32 public DOMAIN_SEPARATOR;
    // keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)");
    // 这一行代码根据事先约定使用permit函数的部分定义计算哈希值，重建消息签名时使用？
    bytes32 public constant PERMIT_TYPEHASH = 0x6e71edae12b1b97f4d1f60370fef10105fa2faae0126114a169c64845d6126c9;
    mapping(address => uint) public nonces;

    event Approval(address indexed owner, address indexed spender, uint value);
    event Transfer(address indexed from, address indexed to, uint value);

    constructor() public {
        uint chainId;
        assembly {
            // 当前链的ID，注意因为Solidity不支持直接获取该值，所以使用了内嵌汇编来获取。
            chainId := chainid
        }
        // 计算DOMAIN_SEPARATOR值，这个值具体干啥用，得继续看
        DOMAIN_SEPARATOR = keccak256(
            abi.encode(
                keccak256('EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)'),
                keccak256(bytes(name)),
                keccak256(bytes('1')),
                chainId,
                address(this)
            )
        );
    }

    function _mint(address to, uint value) internal {
        // 增加uni代币总供应量
        totalSupply = totalSupply.add(value);
        // mint uni代币，给to地址增加对应的余额
        balanceOf[to] = balanceOf[to].add(value);
        emit Transfer(address(0), to, value);
    }

    function _burn(address from, uint value) internal {
        // 燃烧uni代币，从对应账户减掉对应数量的代币余额
        balanceOf[from] = balanceOf[from].sub(value);
        // 减少total Supply的值
        totalSupply = totalSupply.sub(value);
        emit Transfer(from, address(0), value);
    }

    function _approve(address owner, address spender, uint value) private {
        // 设置授权
        allowance[owner][spender] = value;
        emit Approval(owner, spender, value);
    }

    // 转移uni代币
    function _transfer(address from, address to, uint value) private {
        balanceOf[from] = balanceOf[from].sub(value);
        balanceOf[to] = balanceOf[to].add(value);
        emit Transfer(from, to, value);
    }

    // 对spender进行授权，授予它花费sender账户里的value个uni代币资产
    function approve(address spender, uint value) external returns (bool) {
        _approve(msg.sender, spender, value);
        return true;
    }

    // 从合约调用者账户转移value个uni代币给to地址
    function transfer(address to, uint value) external returns (bool) {
        _transfer(msg.sender, to, value);
        return true;
    }

    // 代币授权转移，由其他合约转移from账户资产到to账户
    function transferFrom(address from, address to, uint value) external returns (bool) {
        // 外部函数调用，如果这个外部调用合约得到from账户授权，那么他就可以从from账户转移value个资产到to账户
        // 注意这里没有require条件，是不是在其他操作里面隐含了require。
        if (allowance[from][msg.sender] != uint(-1)) {
            // 减少授权的代币数量
            // sub方法中的require会进行安全检查
            allowance[from][msg.sender] = allowance[from][msg.sender].sub(value);
        }
        _transfer(from, to, value);
        return true;
    }

    function permit(address owner, address spender, uint value, uint deadline, uint8 v, bytes32 r, bytes32 s) external {
        require(deadline >= block.timestamp, 'UniswapV2: EXPIRED');
        bytes32 digest = keccak256(
            abi.encodePacked(
                '\x19\x01',
                DOMAIN_SEPARATOR,
                keccak256(abi.encode(PERMIT_TYPEHASH, owner, spender, value, nonces[owner]++, deadline))
            )
        );
        address recoveredAddress = ecrecover(digest, v, r, s);
        require(recoveredAddress != address(0) && recoveredAddress == owner, 'UniswapV2: INVALID_SIGNATURE');
        _approve(owner, spender, value);
    }
}
