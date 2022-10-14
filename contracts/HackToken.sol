// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "@openzeppelin/contracts@4.7.0/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts@4.7.0/token/ERC20/extensions/ERC20Burnable.sol";
import "@openzeppelin/contracts@4.7.0/access/AccessControl.sol";

import "./IHackToken.sol";

contract HackToken is ERC20, ERC20Burnable, AccessControl, IHackToken {
    uint256 private _totalMinted;
    uint256 private _totalBurned;
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");

    constructor() ERC20("Hack", "HACK") {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(MINTER_ROLE, msg.sender);
    }

    function decimals() public pure  override returns (uint8) {
		return 8;
	}

    function totalMinted() public view virtual returns (uint256) {
        return _totalMinted;
    }

    function totalBurned() public view virtual returns (uint256) {
        return _totalBurned;
    }

    function mint(address to, uint256 amount) public onlyRole(MINTER_ROLE) {
        _totalMinted += amount;
        _mint(to, amount);
    }

    function burnTokenFrom(address from, uint256 amount) external override returns (bool status) {
        _totalBurned += amount;
        burnFrom(from, amount);
        return true;
    }
}
