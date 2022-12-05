pragma solidity =0.5.16;

// a library for performing overflow-safe math, courtesy of DappHub (https://github.com/dapphub/ds-math)

library SafeMath {
    function add(uint x, uint y) internal pure returns (uint z) {
        require((z = x + y) >= x, 'ds-math-add-overflow');
    }

    function sub(uint x, uint y) internal pure returns (uint z) {
        // 这里会对x-y < x进行检查，这是个无符号整数，因此如果不满足这个条件，则意味着溢出了，x-y的时候小于了0，因此就会导致x-y>x，当出现这个情况是，意味着交易需要回滚
        // TODO 合约很多地方用到了这里的require做检查
        require((z = x - y) <= x, 'ds-math-sub-underflow');
    }

    function mul(uint x, uint y) internal pure returns (uint z) {
        require(y == 0 || (z = x * y) / y == x, 'ds-math-mul-overflow');
    }
}
