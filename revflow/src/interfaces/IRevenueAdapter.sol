// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IRevenueAdapter {
    event Forwarded(address indexed token, uint256 amount, bool toSplitter);
    
    function sweep(address token) external;
    function sweepBatch(address[] calldata tokens) external;
    function claimAndForward() external;
    function setSplitter(address newSplitter) external;
    function setTreasury(address newTreasury) external;
    function splitter() external view returns (address);
    function treasury() external view returns (address);
}