// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IERC20} from "@openzeppelin/contracts@4.7.0/token/ERC20/IERC20.sol";

interface IHackInterestToken is IERC20 {
    function mintInterest(address account, uint256 amount) external returns (bool);
    function burnTokenFrom(address account, uint256 amount) external returns (bool);
}