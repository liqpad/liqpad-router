// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

interface IAerodromeRouter {
    struct Route {
        address from;
        address to;
        bool stable;
        address factory;
    }
    function swapExactETHForTokens(uint256, Route[] calldata, address, uint256)
        external
        payable
        returns (uint256[] memory);
    function swapExactTokensForTokens(uint256, uint256, Route[] calldata, address, uint256)
        external
        returns (uint256[] memory);
    function swapExactTokensForETH(uint256, uint256, Route[] calldata, address, uint256)
        external
        returns (uint256[] memory);
}
