// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import {AutomationLocalSimulator} from "@chainlink/local/src/automation/AutomationLocalSimulator.sol";

import {
    MockExchange,
    MockExchangeRateLimiter,
    ExampleConsumer
} from "../../../src/test/automation/MockExchangeRateLimiter.sol";

contract MockCustomLogicAutomationTest is Test {
    AutomationLocalSimulator public automationLocalSimulator;

    MockExchange public mockExchange;
    MockExchangeRateLimiter public mockExchangeRateLimiter;
    ExampleConsumer public exampleConsumer;

    address alice;

    function setUp() public {
        automationLocalSimulator = new AutomationLocalSimulator();
        address forwarder = automationLocalSimulator.configuration();

        alice = makeAddr("alice");

        vm.startPrank(alice);
        mockExchange = new MockExchange();
        mockExchangeRateLimiter = new MockExchangeRateLimiter();
        exampleConsumer = new ExampleConsumer(address(mockExchangeRateLimiter));

        uint256 performGas = 100_000;

        automationLocalSimulator.registerNewMockCustomLogicUpkeep(
            address(mockExchangeRateLimiter), performGas, abi.encode(address(mockExchange))
        );
        mockExchangeRateLimiter.setAutomationForwarder(forwarder);
        vm.stopPrank();
    }

    function test_abiEncodeWithSelector() external {
        uint256 prevRate = exampleConsumer.getLatestExchangeRate();

        uint256 newRate = 1 ether;

        automationLocalSimulator.simulateTx(
            address(mockExchange), abi.encodeWithSelector(mockExchange.setExchangeRate.selector, newRate), alice
        );

        uint256 latestRate = exampleConsumer.getLatestExchangeRate();
        assertNotEq(prevRate, latestRate);
        assertEq(latestRate, newRate);
    }

    function test_abiEncodeWithSignature() external {
        uint256 prevRate = exampleConsumer.getLatestExchangeRate();

        uint256 newRate = 1 ether;

        automationLocalSimulator.simulateTx(
            address(mockExchange), abi.encodeWithSignature("setExchangeRate(uint256)", newRate), alice
        );

        uint256 latestRate = exampleConsumer.getLatestExchangeRate();
        assertNotEq(prevRate, latestRate);
        assertEq(latestRate, newRate);
    }
}
