// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface ILenderVault {
    event Deposited(address indexed token, uint256 amount, uint256 timestamp);
    event Claimed(address indexed lender, address indexed token, uint256 amount);
    event ReceiptTokenMinted(address indexed lender, uint256 amount);
    
    function depositFor(address token, uint256 amount) external;
    function claim(address token) external;
    function claimAll() external;
    function getClaimableAmount(address lender, address token) external view returns (uint256);
    function getTotalDeposited(address token) external view returns (uint256);
    function getReceiptToken() external view returns (address);
}