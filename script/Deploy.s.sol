// SPDX-License-Identifier: MIT

pragma solidity ^0.8.10;

import "forge-std/Script.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/proxy/transparent/TransparentUpgradeableProxy.sol";
import {IERC20Upgradeable} from "@openzeppelin-upgradeable/interfaces/IERC20Upgradeable.sol";

import "../src/ATokenVault.sol";
import {console2} from "forge-std/Test.sol";

// forge script script/Deploy.s.sol:Deploy --rpc-url $ARBITRUM_RPC_URL --private-key $PRIVATE_KEY --broadcast -vvvv

contract Deploy is Script {

    address constant OWNER = 0x1F3D49c350BE3e63940c22f0560eEE3c34A717F9;

    address constant USDC_ARBITRUM = 0xaf88d065e77c8cC2239327C5EDb3A432268e5831;
    address constant POOL_ADDRESSES_PROVIDER_ARBITRUM = 0xa97684ead0e402dC232d5A977953DF7ECBaB3CDb;   

    // USDC: https://arbiscan.io/address/0xaf88d065e77c8cC2239327C5EDb3A432268e5831
    // Pool Address Provider: https://arbiscan.io/address/0xa97684ead0e402dC232d5A977953DF7ECBaB3CDb

    // DEPLOYMENT PARAMETERS - CHANGE THESE FOR YOUR VAULT
    // ===================================================
    address UNDERLYING_ASSET_ADDRESS = USDC_ARBITRUM; // Underlying asset listed in the Aave Protocol
    uint16 REFERRAL_CODE = 0; // Referral code to use
    address AAVE_POOL_ADDRESSES_PROVIDER_ADDRESS = POOL_ADDRESSES_PROVIDER_ARBITRUM; // PoolAddressesProvider contract of the Aave Pool
    address constant PROXY_ADMIN_ADDRESS = address(0); // Address of the proxy admin
    address constant OWNER_ADDRESS = OWNER; // Address of the vault owner
    string constant SHARE_NAME = "AAVE VAULT USDC"; // Name of the token shares
    string constant SHARE_SYMBOL = "avUSDC"; // Symbol of the token shares
    uint256 constant FEE = 0; // Vault Fee bps in wad (e.g. 0.1e18 results in 10%)
    uint256 constant INITIAL_LOCK_DEPOSIT = 1e6; // Initial deposit on behalf of the vault
    // ===================================================

    ATokenVault public vault;

    function getChainId() public view returns (uint256) {
        uint256 chainId;
        assembly {
            chainId := chainid()
        }
        return chainId;
    }

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        address deployerAddress = vm.addr(deployerPrivateKey);
        console2.log("Deployer address: ", deployerAddress);
        console2.log("Deployer balance: ", deployerAddress.balance);
        console2.log("BlockNumber: ", block.number);
        console2.log("ChainId: ", getChainId());
        console2.log("Deploying vault...");

        require(
            INITIAL_LOCK_DEPOSIT != 0,
            "Initial deposit not set. This prevents a frontrunning attack, please set a non-trivial initial deposit."
        );

        vm.startBroadcast(deployerPrivateKey);

        // Deploy the implementation, which disables initializers on construction
        vault = new ATokenVault(
            UNDERLYING_ASSET_ADDRESS,
            REFERRAL_CODE,
            IPoolAddressesProvider(AAVE_POOL_ADDRESSES_PROVIDER_ADDRESS)
        );
        console.log("Vault impl deployed at: ", address(vault));

        console.log("Deploying proxy...");
        // Encode the initializer call
        bytes memory data = abi.encodeWithSelector(
            ATokenVault.initialize.selector,
            OWNER_ADDRESS,
            FEE,
            SHARE_NAME,
            SHARE_SYMBOL,
            INITIAL_LOCK_DEPOSIT
        );
        console.logBytes(data);

        address proxyAddr = computeCreateAddress(deployerAddress, vm.getNonce(deployerAddress) + 1);
        IERC20Upgradeable(UNDERLYING_ASSET_ADDRESS).approve(proxyAddr, INITIAL_LOCK_DEPOSIT);
        console.log("Precomputed proxy address: ", proxyAddr);
        console.log("Allowance for proxy: ", IERC20Upgradeable(UNDERLYING_ASSET_ADDRESS).allowance(deployerAddress, proxyAddr));

        // Deploy and initialize the proxy
        TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(address(vault), PROXY_ADMIN_ADDRESS, data);
        console.log("Vault proxy deployed and initialized at: ", address(proxy));

        vm.stopBroadcast();

        console.log("\nVault data:");
        vault = ATokenVault(address(proxy));
        console.log("POOL_ADDRESSES_PROVIDER:", address(vault.POOL_ADDRESSES_PROVIDER()));
        console.log("REFERRAL_CODE:", vault.REFERRAL_CODE());
        console.log("UNDERLYING:", address(vault.UNDERLYING()));
        console.log("ATOKEN:", address(vault.ATOKEN()));
        console.log("Name:", vault.name());
        console.log("Symbol:", vault.symbol());
        console.log("Owner:", vault.owner());
        console.log("Fee:", vault.getFee());
    }
}
