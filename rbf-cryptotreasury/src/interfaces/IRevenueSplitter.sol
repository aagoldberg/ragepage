// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IRevenueSplitter {
    event SplitExecuted(address indexed token, uint256 toLenders, uint256 toTreasury, uint256 totalPaid);
    event CapReached(uint256 totalPaid);
    event SafetyRailTriggered(string reason);
    
    function onRevenue(address token, uint256 amount) external;
    function isCapReached() external view returns (bool);
    function isPaused() external view returns (bool);
    function getTotalPaid() external view returns (uint256);
    function getRemainingCap() external view returns (uint256);
    function pause() external;
    function unpause() external;
    function setDailyCap(uint256 newCap) external;
    function setTransactionCap(uint256 newCap) external;
}