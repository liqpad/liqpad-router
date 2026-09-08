// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

interface ILiqpadFactory {
    function isLiqpadLaunch(address token) external view returns (bool);
}

