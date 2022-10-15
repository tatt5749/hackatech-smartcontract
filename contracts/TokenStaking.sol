// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {ReentrancyGuard} from "@openzeppelin/contracts@4.7.0/security/ReentrancyGuard.sol";
import {IERC20, SafeERC20} from "@openzeppelin/contracts@4.7.0/token/ERC20/utils/SafeERC20.sol";

import {IHackToken} from "./IHackToken.sol";
import {IHackInterestToken} from "./IHackInterestToken.sol";

/**
 * @title TokenStaking
 * @notice It handles the staking of Hack token.
 */
contract TokenStaking is ReentrancyGuard {
    using SafeERC20 for IERC20;
    using SafeERC20 for IHackToken;
    using SafeERC20 for IHackInterestToken;


    struct StakeInfo {
        uint256 dateStaked;
        uint256 initialAmount;
        uint256 balanceAmount;
        uint256 redeemedAmount;
        uint256 interestAmount;
        uint256 buybackAmount;
    }

    struct UserInfo {
        uint256 totalInitialAmount;
        uint256 totalBalanceAmount;
        uint256 totalRedeemedAmount;
        uint256 totalBuybackAmount;
        uint256 totalInterestAmount;
    }

    struct RedeemInfo {
        uint256 buybackAmount;
        uint256 interestAmount;
        uint256 redeemableAmount;
    }


    // Precision factor for calculating rewards
    uint256 public constant PRECISION_FACTOR = 10**8;
    uint256 public buybackRate = 2;
    uint256 public interestRate = 9;
    uint256 public stakeLimit = 5000000 * PRECISION_FACTOR ;

    IHackToken public immutable HackToken;
    IHackInterestToken public immutable HackInterestToken;

    // Total amount staked
    uint256 public totalAmountStaked;

    mapping(address => UserInfo) public userMapping;
    mapping(address => StakeInfo[]) public stakeMapping;

    event Deposit(address indexed user, uint256 amount);
    event Unstake(address indexed user, uint256 amount);
    event RedeemInterest(address indexed user);
    event UpdateDateTest(address indexed user, uint256 day, uint256 index);

    /**
     * @notice Constructor
     * @param _HackToken token address
     * @param _HackInterestToken token address
     */
    constructor(
        address _HackToken,
        address _HackInterestToken
    ) {

        HackToken = IHackToken(_HackToken);
        HackInterestToken = IHackInterestToken(_HackInterestToken);
    }

    /**
     * @notice Deposit staked tokens and earn interest
     * @param amount amount to deposit (in HACK)
     */
    function deposit(uint256 amount) external nonReentrant {
        require(amount > 0, "Deposit: Amount must be > 0");

        // Transfer HACK tokens to this contract
        HackToken.safeTransferFrom(msg.sender, address(this), amount);

        userMapping[msg.sender].totalInitialAmount += amount;
        userMapping[msg.sender].totalBalanceAmount += amount;
        stakeMapping[msg.sender].push(StakeInfo(block.timestamp, amount, amount, 0, 0, 0));
        
        // Increase totalAmountStaked
        totalAmountStaked += (amount);

        emit Deposit(msg.sender, amount);
    }

    function redeemInterest() external nonReentrant {

        RedeemInfo memory redeemResult = calculateTotalRedeemable(msg.sender);
        
        require(redeemResult.redeemableAmount != 0, "Interest: Nothing to redeem");

        if (redeemResult.interestAmount != 0) {
            HackInterestToken.mintInterest(msg.sender, redeemResult.interestAmount);
        } 

        if (redeemResult.buybackAmount != 0) {
            HackToken.safeTransfer(msg.sender, redeemResult.buybackAmount);
        } 
        
        HackToken.burnTokenFrom(msg.sender, redeemResult.buybackAmount);
        HackInterestToken.burnTokenFrom(msg.sender, redeemResult.interestAmount);

        for (uint i = 0; i < stakeMapping[msg.sender].length; i++) {
            uint buybackCount = uint(block.timestamp - stakeMapping[msg.sender][i].dateStaked) / (86400 * 30);
            if (buybackCount > (100 / buybackRate) ) {
                buybackCount = 100 / buybackRate;
            }
            uint buyback = uint(buybackRate * stakeMapping[msg.sender][i].initialAmount * buybackCount) / 100; 
            uint balance = stakeMapping[msg.sender][i].initialAmount;
            uint interest = 0;
            for (uint j = 0; j < buybackCount; j++) {
                interest += uint(interestRate * balance) / 100 / 12 ; 
                balance -= uint(buybackRate * stakeMapping[msg.sender][i].initialAmount) / 100;
            }
            uint buybackAmount = buyback - stakeMapping[msg.sender][i].buybackAmount;
            uint interestAmount = interest - stakeMapping[msg.sender][i].interestAmount;

            stakeMapping[msg.sender][i].balanceAmount -= buybackAmount;
            userMapping[msg.sender].totalBalanceAmount -= buybackAmount;

            stakeMapping[msg.sender][i].interestAmount += interestAmount;
            userMapping[msg.sender].totalInterestAmount += interestAmount;

            stakeMapping[msg.sender][i].buybackAmount += buybackAmount;
            userMapping[msg.sender].totalBuybackAmount += buybackAmount;

            stakeMapping[msg.sender][i].redeemedAmount += buybackAmount + interestAmount;
            userMapping[msg.sender].totalRedeemedAmount += buybackAmount + interestAmount;
        }

        emit RedeemInterest(msg.sender);
    }


    /**
     * @notice Withdraw all staked tokens and collect tokens
     */
    function unstake(uint stakeId) external nonReentrant {

        RedeemInfo memory redeemResult = calculateRedeemable(msg.sender, stakeId);
        
        require(redeemResult.redeemableAmount == 0, "Unstake: Redeemable token unclaim");

        require(stakeMapping[msg.sender][stakeId].balanceAmount > 0, "Withdraw: Amount must be > 0");

        uint256 amountToTransfer = stakeMapping[msg.sender][stakeId].balanceAmount;
        
        // Adjust total amount staked
        totalAmountStaked = totalAmountStaked - stakeMapping[msg.sender][stakeId].balanceAmount;

        userMapping[msg.sender].totalInitialAmount -= stakeMapping[msg.sender][stakeId].balanceAmount;
        userMapping[msg.sender].totalBalanceAmount -= stakeMapping[msg.sender][stakeId].balanceAmount;

        stakeLimit = stakeLimit + stakeMapping[msg.sender][stakeId].balanceAmount;

        for(uint i = stakeId; i < stakeMapping[msg.sender].length - 1; i++){
            stakeMapping[msg.sender][i] = stakeMapping[msg.sender][i + 1];      
        }
        stakeMapping[msg.sender].pop();

        // Transfer HACK tokens to the sender
        HackToken.safeTransfer(msg.sender, amountToTransfer);

        emit Unstake(msg.sender, amountToTransfer);
    }

    function getTotalRedeemableAmount(address account) external view returns (RedeemInfo memory) {

        RedeemInfo memory redeemResult = calculateTotalRedeemable(account);

        return redeemResult;
        
    }

    function getRedeemableAmount(address account, uint256 index) external view returns (string[] memory, RedeemInfo memory) {

        RedeemInfo memory redeemResult = calculateRedeemable(account, index);

        string[]  memory category = new string[](3);
        category[0] = string('buybackAmount');
        category[1] = string('interestAmount');
        category[2] = string('redeemableAmount');

        return (category, redeemResult);
        
    }

    function getStakeCount(address account) external view returns (uint) {

        return stakeMapping[account].length;
        
    }

    function calculateTotalRedeemable(address account) internal view returns (RedeemInfo memory) {

        uint256 buybackAmount = 0;
        uint256 interestAmount = 0;

        for (uint i = 0; i < stakeMapping[account].length; i++) {

            RedeemInfo memory redeemResult = calculateRedeemable(account, i);

            buybackAmount += redeemResult.buybackAmount;
            interestAmount += redeemResult.interestAmount;
        }

        RedeemInfo memory totalRedeemResult = RedeemInfo(buybackAmount, interestAmount, buybackAmount + interestAmount);

        return totalRedeemResult;

    }

    function calculateRedeemable(address account, uint256 index) internal view returns (RedeemInfo memory) {

        uint buybackCount = uint(block.timestamp - stakeMapping[account][index].dateStaked) / (86400 * 30);
        uint buyback = uint(buybackRate * stakeMapping[account][index].initialAmount * buybackCount) / 100; 
        uint balance = stakeMapping[account][index].initialAmount;
        uint interest = 0;
        for (uint j = 0; j < buybackCount; j++) {
            interest += uint(interestRate * balance) / 100 / 12 ; 
            balance -= uint(buybackRate * stakeMapping[account][index].initialAmount) / 100;
        }

        uint buybackAmount = buyback - stakeMapping[account][index].buybackAmount;
        uint interestAmount = interest - stakeMapping[account][index].interestAmount;

        RedeemInfo memory redeemResult = RedeemInfo(buybackAmount, interestAmount, buybackAmount + interestAmount);

        return redeemResult;
    }


    function updateDateTest(uint256 day, uint256 index) external nonReentrant {

        stakeMapping[msg.sender][index].dateStaked -= 86400 * day;

        emit UpdateDateTest(msg.sender, day, index);
    }

}