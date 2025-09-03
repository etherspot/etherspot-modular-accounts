    // SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ModularEtherspotWallet} from "../../src/wallet/ModularEtherspotWallet.sol";
import {HookType} from "../../src/common/Enums.sol";
import {HookMultiPlexer} from "../../src/modules/hooks/HookMultiPlexer.sol";
import {CredibleAccountModule} from "../../src/modules/validators/CredibleAccountModule.sol";
import {ResourceLockValidator} from "../../src/modules/validators/ResourceLockValidator.sol";
import {InvoiceManager} from "../../src/invoice_manager/InvoiceManager.sol";
import {
    EXPECTED_HOOK_MULTIPLEXER_ADDRESS,
    EXPECTED_CREDIBLE_ACCOUNT_MODULE_ADDRESS,
    EXPECTED_RESOURCE_LOCK_VALIDATOR_ADDRESS,
    EXPECTED_INVOICE_MANAGER_ADDRESS
} from "./utils/PulseConstants.sol";

contract PULSE_HealthCheck is Script {
    HookMultiPlexer public hookMultiPlexer;
    CredibleAccountModule public credibleAccountModule;
    ResourceLockValidator public resourceLockValidator;
    InvoiceManager public invoiceManager;

    // Test wallets to check
    address[] public checkWallets = [0x25eE95a6eE844Cae2c7A925e33b2BA20E945F5D7];

    // Test solvers to check
    address[] public checkSolvers = [
        0x3333333333333333333333333333333333333333,
        0x7C84F10502FcDea2E403b70feA96a4aE990a34DF,
        0xbc4aECba01E015fb88527AF0c65B37C874b2b1fE,
        0x56e0d1120B54368017b591dAD42770D2843f2184
    ];

    function run() external {
        hookMultiPlexer = HookMultiPlexer(EXPECTED_HOOK_MULTIPLEXER_ADDRESS);
        credibleAccountModule = CredibleAccountModule(EXPECTED_CREDIBLE_ACCOUNT_MODULE_ADDRESS);
        resourceLockValidator = ResourceLockValidator(EXPECTED_RESOURCE_LOCK_VALIDATOR_ADDRESS);
        invoiceManager = InvoiceManager(EXPECTED_INVOICE_MANAGER_ADDRESS);

        console2.log("=== SYSTEM HEALTH CHECK ===");
        console2.log("Timestamp:", block.timestamp);
        console2.log("Block number:", block.number);
        console2.log("");

        /*//////////////////////////////////////////////////////////////
                          CredibleAccountModule Health
          //////////////////////////////////////////////////////////////*/

        console2.log("=== CREDIBLE ACCOUNT MODULE ===");
        console2.log("Address:", address(credibleAccountModule));

        // Check configuration
        address camRLV = credibleAccountModule.resourceLockValidator();
        address camIM = credibleAccountModule.invoiceManager();

        console2.log("ResourceLockValidator:", camRLV);
        console2.log("InvoiceManager:", camIM);

        bool camConfigured = (camRLV != address(0) && camIM != address(0));
        console2.log("Configuration status:", camConfigured ? "HEALTHY" : "UNHEALTHY");

        // Check constants
        console2.log("MAX_SESSION_KEYS:", credibleAccountModule.MAX_SESSION_KEYS());
        console2.log("MAX_LOCKED_TOKENS:", credibleAccountModule.MAX_LOCKED_TOKENS());
        console2.log("DISABLE_SESSION_KEY_TIME_BUFFER:", credibleAccountModule.DISABLE_SESSION_KEY_TIME_BUFFER());

        // Check session key disablers
        address[] memory disablers = credibleAccountModule.getSessionKeyDisablers();
        console2.log("Session key disablers:", disablers.length);

        console2.log("");

        /*//////////////////////////////////////////////////////////////
                          ResourceLockValidator Health
          //////////////////////////////////////////////////////////////*/

        console2.log("=== RESOURCE LOCK VALIDATOR ===");
        console2.log("Address:", address(resourceLockValidator));

        // Check configuration
        address rlvOwner = resourceLockValidator.owner();
        address rlvCAM = resourceLockValidator.getCredibleAccountModule();

        console2.log("Owner:", rlvOwner);
        console2.log("CredibleAccountModule:", rlvCAM);

        bool rlvConfigured = (rlvCAM != address(0));
        console2.log("Configuration status:", rlvConfigured ? "HEALTHY" : "UNHEALTHY");

        console2.log("");

        /*//////////////////////////////////////////////////////////////
                             InvoiceManager Health
          //////////////////////////////////////////////////////////////*/

        console2.log("=== INVOICE MANAGER ===");
        console2.log("Address:", address(invoiceManager));

        // Check configuration
        address feeReceiver = invoiceManager.feeReceiver();
        console2.log("Fee receiver:", feeReceiver);

        // Check whitelisted tokens
        address[] memory whitelistedTokens = invoiceManager.getWhitelistedTokens();
        console2.log("Whitelisted tokens:", whitelistedTokens.length);

        for (uint256 i; i < whitelistedTokens.length; ++i) {
            address token = whitelistedTokens[i];
            console2.log("  Token:", token);
        }

        console2.log("");

        /*//////////////////////////////////////////////////////////////
                                Cross-Contract Links
          //////////////////////////////////////////////////////////////*/

        console2.log("=== CROSS-CONTRACT VERIFICATION ===");

        bool camRLVMatch = (camRLV == address(resourceLockValidator));
        bool camIMMatch = (camIM == address(invoiceManager));
        bool rlvCAMMatch = (rlvCAM == address(credibleAccountModule));

        console2.log("CAM -> RLV link:", camRLVMatch ? "HEALTHY" : "UNHEALTHY");
        console2.log("CAM -> IM link:", camIMMatch ? "HEALTHY" : "UNHEALTHY");
        console2.log("RLV -> CAM link:", rlvCAMMatch ? "HEALTHY" : "UNHEALTHY");

        bool allLinksHealthy = camRLVMatch && camIMMatch && rlvCAMMatch;
        console2.log("Overall link status:", allLinksHealthy ? "HEALTHY" : "UNHEALTHY");

        console2.log("");

        /*//////////////////////////////////////////////////////////////
                             Wallet Statistics
          //////////////////////////////////////////////////////////////*/

        console2.log("=== WALLET STATISTICS ===");

        for (uint256 i; i < checkWallets.length; ++i) {
            address wallet = checkWallets[i];
            console2.log("Wallet:", wallet);
            console2.log("Checking Pulse modules installed correctly...");

            // If script fails here check that wallet being checked is valid ModularEtherspotWallet
            ModularEtherspotWallet scw = ModularEtherspotWallet(payable(wallet));
            // Check its a valid wallet
            // RLV, CAM as Hook, CAM,
            bool hmpInit = (address(hookMultiPlexer) == scw.getActiveHook());
            console2.log("  HMP initialized:", hmpInit);
            bool camHookInit = hookMultiPlexer.hasHook(wallet, address(credibleAccountModule), HookType.GLOBAL);
            console2.log("  CAM as GlobalHook initialized:", camHookInit);
            bool camValInit = credibleAccountModule.isInitialized(wallet);
            console2.log("  CAM as Validator initialized:", camValInit);
            bool rlvInit = resourceLockValidator.isInitialized(wallet);
            console2.log("  RLV initialized:", rlvInit);

            address[] memory sessionKeys = credibleAccountModule.getSessionKeysByWallet(wallet);
            address[] memory liveKeys = credibleAccountModule.getLiveSessionKeysForWallet(wallet);
            address[] memory expiredKeys = credibleAccountModule.getExpiredSessionKeysForWallet(wallet);

            console2.log("  Total session keys:", sessionKeys.length);
            console2.log("  Live session keys:", liveKeys.length);
            console2.log("  Expired session keys:", expiredKeys.length);
        }

        console2.log("");

        /*//////////////////////////////////////////////////////////////
                              Solver Statistics
          //////////////////////////////////////////////////////////////*/

        console2.log("=== SOLVER STATISTICS ===");

        for (uint256 i; i < checkSolvers.length; ++i) {
            address solver = checkSolvers[i];
            console2.log("Solver:", solver);

            (string memory name, bool isActive, uint256 successfulSettlements, uint256 activeInvoices, uint256 pulseFee)
            = invoiceManager.getSolverData(solver);

            console2.log("  Name:", name);
            console2.log("  Active:", isActive);
            console2.log("  Successful settlements:", successfulSettlements);
            console2.log("  Active invoices:", activeInvoices);
            console2.log("  Pulse fee (cents):", pulseFee);
        }

        console2.log("");
        console2.log("=== HEALTH CHECK COMPLETE ===");
    }
}
