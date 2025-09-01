// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IDefaultVault {
    event CollateralDeposited(address indexed token, uint256 amount);
    event DefaultDeclared(uint256 remainingPaid, uint256 timestamp);
    event CollateralReleased(address indexed token, uint256 amount, address indexed recipient);
    event CurePeriodStarted(uint256 timestamp);
    
    function depositCollateral(address token, uint256 amount) external payable;
    function declareDefault() external;
    function startCurePeriod() external;
    function releaseCollateral(address recipient) external;
    function getCollateralBalance(address token) external view returns (uint256);
    function isDefaulted() external view returns (bool);
    function canDeclareDefault() external view returns (bool);
    function getRemainingCurePeriod() external view returns (uint256);
}