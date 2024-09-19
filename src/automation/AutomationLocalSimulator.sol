// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import {Test, Vm} from "forge-std/Test.sol";

import {CronExternal, Spec} from "./MockCron.sol";
import {MockAutomationForwarder} from "./MockAutomationForwarder.sol";

import {AutomationCompatibleInterface} from
    "@chainlink/contracts/src/v0.8/automation/interfaces/AutomationCompatibleInterface.sol";
import {EnumerableSet} from
    "@chainlink/contracts/src/v0.8/vendor/openzeppelin-solidity/v4.8.3/contracts/utils/structs/EnumerableSet.sol";

contract AutomationLocalSimulator is Test {
    using EnumerableSet for EnumerableSet.UintSet;

    enum TriggerType {
        CONDITION,
        LOG,
        TIME_BASED
    }

    struct MockTimeBasedUpkeep {
        address target;
        bytes4 performSelector;
        uint256 lastRun;
        uint256 performGas;
        bytes performData;
        string cronString;
        Spec spec;
    }

    bytes4 internal constant PERFORM_SELECTOR = AutomationCompatibleInterface.performUpkeep.selector;

    MockAutomationForwarder internal immutable i_forwarder;

    uint32 internal s_nonce; // Nonce for each upkeep created
    EnumerableSet.UintSet internal s_timeBasedUpkeepIds;

    mapping(uint256 => MockTimeBasedUpkeep) internal s_timeBasedUpkeeps;

    constructor() {
        i_forwarder = new MockAutomationForwarder();
    }

    function registerNewMockTimeBasedUpkeep(
        address target,
        bytes4 performSelector,
        bytes calldata performData,
        uint256 performGas,
        string calldata cronString
    ) external returns (uint256 id) {
        s_nonce++;
        id = _createID(TriggerType.TIME_BASED);
        s_timeBasedUpkeepIds.add(id);

        Spec memory spec = CronExternal.toSpec(cronString);
        s_timeBasedUpkeeps[id] = MockTimeBasedUpkeep({
            target: target,
            performSelector: performSelector,
            lastRun: block.timestamp,
            performGas: performGas,
            performData: performData,
            cronString: cronString,
            spec: spec
        });
    }

    //     function simulateTx(address targetContract, bytes memory abiEncodedFuncWithArguments, address msgSender)
    //     external
    //     returns (bytes memory)
    // {
    //     _preTxHook();

    //     vm.startPrank(msgSender);
    //     (bool ok, bytes memory returnData) = targetContract.call(abiEncodedFuncWithArguments);
    //     vm.stopPrank();
    //     require(ok);

    //     _postTxHook();

    //     return returnData;
    // }

    function increaseBlockTimestamp(uint256 numberOfSecondsToSkipForward) external {
        skip(numberOfSecondsToSkipForward);

        uint256 length = s_timeBasedUpkeepIds.length();
        for (uint256 i = 0; i < length; ++i) {
            MockTimeBasedUpkeep memory currentUpkeep = s_timeBasedUpkeeps[s_timeBasedUpkeepIds.at(i)];
            uint256 lastTick = CronExternal.lastTick(currentUpkeep.spec);

            if (lastTick > currentUpkeep.lastRun) {
                uint256 nextTick = CronExternal.nextTick(currentUpkeep.spec);
                uint256 interval = nextTick - lastTick;
                if (interval == 0) {
                    (bool success,) = _performUpkeep(
                        currentUpkeep.target,
                        currentUpkeep.performSelector,
                        currentUpkeep.performData,
                        currentUpkeep.performGas
                    );
                    require(success, "AutomationLocalSimulator: upkeep failed");
                } else {
                    uint256 numberOfTicksMissed = block.timestamp / interval;
                    for (uint256 j = 0; j < numberOfTicksMissed; ++j) {
                        (bool success,) = _performUpkeep(
                            currentUpkeep.target,
                            currentUpkeep.performSelector,
                            currentUpkeep.performData,
                            currentUpkeep.performGas
                        );
                        require(success, "AutomationLocalSimulator: upkeep failed");
                    }
                }

                currentUpkeep.lastRun = block.timestamp;
            }
        }
    }

    /**
     * @dev calls the Upkeep target with the performData param passed and the exact gas required by the Upkeep
     */
    function _performUpkeep(address target, bytes4 performSelector, bytes memory performData, uint256 performGas)
        internal
        returns (
            // nonReentrant
            bool success,
            uint256 gasUsed
        )
    {
        performData = abi.encodeWithSelector(performSelector, performData);
        return i_forwarder.forward(target, performGas, performData);
    }

    /**
     * @dev creates an ID for the upkeep based on the upkeep's type
     * @dev the format of the ID looks like this:
     * ****00000000000X****************
     * 4 bytes of entropy
     * 11 bytes of zeros
     * 1 identifying byte for the trigger type
     * 16 bytes of entropy
     * @dev this maintains the same level of entropy as eth addresses, so IDs will still be unique
     * @dev we add the "identifying" part in the middle so that it is mostly hidden from users who usually only
     * see the first 4 and last 4 hex values ex 0x1234...ABCD
     */
    function _createID(TriggerType triggerType) internal view returns (uint256) {
        bytes1 empty;
        bytes memory idBytes =
            abi.encodePacked(keccak256(abi.encode(keccak256(abi.encode(block.number - 1)), address(this), s_nonce)));
        for (uint256 idx = 4; idx < 15; idx++) {
            idBytes[idx] = empty;
        }
        idBytes[15] = bytes1(uint8(triggerType));
        return uint256(bytes32(idBytes));
    }

    function configuration() external view returns (address forwarder) {
        return address(i_forwarder);
    }
}
