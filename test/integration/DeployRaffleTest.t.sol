//SPDX-License-Identifier:MIT
pragma solidity ^0.8.18;

import {Test, console} from "forge-std/Test.sol";
import {DeployRaffle} from "../../script/DeployRaffle.s.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";

contract DeployRaffleTest is Test {
    HelperConfig helperConfig;
    DeployRaffle deployRaffle;
    uint256 entranceFee;
    uint256 interval;
    address vrfCoordinator;
    bytes32 gasLane;
    uint64 subscriptionId;
    uint32 callBackGasLimit;
    address link;
    uint256 deployerKey;

    function setUp() external {
        deployRaffle = new DeployRaffle();
        (, helperConfig) = deployRaffle.run();

        (entranceFee, interval, vrfCoordinator, gasLane, subscriptionId, callBackGasLimit, link,) =
            helperConfig.activeNetworkConfig();
    }

    function testRaffleIsDeployed(uint256 index) public {
        vm.assume(index < 20);
        deployRaffle.run();
        assert(address(deployRaffle) != address(uint160(index)));
    }

}
