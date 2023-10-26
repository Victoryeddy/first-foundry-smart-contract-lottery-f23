//SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {Test, console} from "forge-std/Test.sol";
import {Raffle} from "../../src/Raffle.sol";
import {DeployRaffle} from "../../script/DeployRaffle.s.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {Vm} from "forge-std/Vm.sol";
import {VRFCoordinatorV2Mock} from "@chainlink/contracts/src/v0.8/mocks/VRFCoordinatorV2Mock.sol";

contract RaffleTest is Test {
    /* Events */
    event EnterRaffle(address indexed player);
    event WinnerPicked(address indexed winner);

    Raffle raffle;
    HelperConfig helperConfig;

    uint256 entranceFee;
    uint256 interval;
    address vrfCoordinator;
    bytes32 gasLane;
    uint64 subscriptionId;
    uint32 callBackGasLimit;
    address link;

    address public PLAYER = makeAddr("player");
    uint256 public constant STARTING_USER_BALANCE = 10 ether;

    function setUp() external {
        DeployRaffle deployRaffle = new DeployRaffle();
        (raffle, helperConfig) = deployRaffle.run();

        (entranceFee, interval, vrfCoordinator, gasLane, subscriptionId, callBackGasLimit, link,) =
            helperConfig.activeNetworkConfig();
        vm.deal(PLAYER, STARTING_USER_BALANCE);
    }

    modifier raffleEnteredAndTimePassed() {
        vm.prank(PLAYER);
        raffle.enterRaffle{value: entranceFee}();
        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1);
        _;
    }

    function testRaffleInitializesInOpenState() public view {
        assert(raffle.getRaffleState() == Raffle.RaffleState.OPEN); //To explain this enum its simply saying that for any Raffle Contract get the enum RaffleState OPEN
    }

    /////// Testing EnterRaffleFunction //////

    function testYouDidNotEnterEnoughEth() public {
        // We always want to use the arrange , act , assert method when testing
        // Arrange
        vm.prank(PLAYER);
        // Act and Assert
        vm.expectRevert(Raffle.Raffle__notEnoughEthSent.selector);
        raffle.enterRaffle();
    }

    function testRaffleRecordsPlayersWhenTheyEnter() public {
        vm.prank(PLAYER);
        raffle.enterRaffle{value: entranceFee}();
        address playerRecorded = raffle.getPlayer(0);
        console.log(playerRecorded, PLAYER);
        assertEq(playerRecorded, PLAYER);
    }

    function emitsEventOnEntrance() public {
        vm.prank(PLAYER);
        vm.expectEmit(true, false, false, false, address(raffle));

        emit EnterRaffle(PLAYER);
        raffle.enterRaffle{value: entranceFee}();
    }

    function testCantEnterWhenRaffleIsCalculating() public raffleEnteredAndTimePassed {
        raffle.performUpkeep("");

        vm.expectRevert(Raffle.Raffle__notOpen.selector);
        vm.prank(PLAYER);
        raffle.enterRaffle{value: entranceFee}();
    }

    ///// check upkeep function
    function testCheckUpKeepReturnsFalseIfItHasNoBalance() public {
        //Arrange
        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1);

        // Act
        (bool upKeepNeeded,) = raffle.checkUpkeep("");

        //  Assert
        assert(!upKeepNeeded); //This is saying our conditions to perform upKeep has not been reached
    }

    function CheckUpkeepReturnsFalseWhenRaffleIsNotOpen() public raffleEnteredAndTimePassed {
        // Arrange

        raffle.performUpkeep("");

        // Act
        (bool upKeepNeeded,) = raffle.checkUpkeep("");

        // Assert
        assert(upKeepNeeded == false);
    }

    function testCheckUpkeepReturnsFalseIfTimeHasntPassed() public skipFork {
        // Arrange
        vm.warp(interval - block.timestamp);
        console.log(block.timestamp, "new time");
        vm.roll(block.number - 1);

        //Act
        (bool upKeepNeeded,) = raffle.checkUpkeep("");
        // // Assert
        assert(!upKeepNeeded);
    }

    function testCheckUpkeepReturnsTrueWhenParametersGood() public raffleEnteredAndTimePassed {
        // Act
        (bool upkeepNeeded,) = raffle.checkUpkeep("");

        // Assert
        assert(upkeepNeeded);
    }

    function testPerformUpkeepCanOnlyRunIfCheckUpKeepIsTrue() public raffleEnteredAndTimePassed {
        raffle.performUpkeep("");
    }

    function testPerformUpkeepRevertsIfCheckUpKeepIsFalse() public skipFork {
        // Arrange
        uint256 currentBalance = 0;
        uint256 numPlayers = 0;
        Raffle.RaffleState rState = raffle.getRaffleState();
        // Act / Assert
        vm.expectRevert(
            abi.encodeWithSelector(Raffle.Raffle_upKeepNotNeeded.selector, currentBalance, numPlayers, rState)
        );
        raffle.performUpkeep("");
        //what the abi.encodeWithSelector does is that it enables us to return a custom error if we have any
    }

    function testPerformUpkeepUpdatesRaffleStateAndEmitsRequestId() public raffleEnteredAndTimePassed {
        //  Act
        vm.recordLogs();
        raffle.performUpkeep(""); //We have to perform upkeep to request a random number in form of an ID
        Vm.Log[] memory entries = vm.getRecordedLogs(); //This saves all logs emitted into an array called entries

        // In order for us to access this log it has to be stored in a bytes32 type
        bytes32 requestId = entries[1].topics[1]; //the topics refers to the event emitted after requestingrandom number
        //the 0th topic will be the entire event
        console.log(uint256(requestId));

        Raffle.RaffleState rstate = raffle.getRaffleState();
        //Assert
        assert(uint256(requestId) > 0);

        assert(uint256(rstate) == 1); // 1 represents the enum calculating
    }

    modifier skipFork() {
        if (block.chainid != 31337) {
            return;
        }
        _;
    }

    function testFufillRandomWordsCanOnlyBeCalledAfterPerformUpkeep(uint256 randomRequestId)
        public
        raffleEnteredAndTimePassed
        skipFork
    {
        //
        vm.expectRevert("nonexistent request");

        VRFCoordinatorV2Mock(vrfCoordinator).fulfillRandomWords(randomRequestId, address(raffle)); // Here we are pretending to be the node operator and we are calling the fulfill random words function
    }

    function testFulfillRandomWordsPicksAWinnerResetsAndSendsMoney() public raffleEnteredAndTimePassed skipFork {
        //This test invovles us testing the full raffle contract

        // Arrange
        uint256 additionalEntrants = 5; //The entrants are actually 6 adding the PLAYER
        uint256 startingIndex = 1;

        for (uint256 i = startingIndex; i < additionalEntrants + startingIndex; i++) {
            address player = address(uint160(i));

            hoax(player, STARTING_USER_BALANCE);
            raffle.enterRaffle{value: entranceFee}();
        }

        uint256 prize = entranceFee * (additionalEntrants + 1);
        // This helps us record and get the requestId from the event
        vm.recordLogs();
        raffle.performUpkeep(""); //We have to perform upkeep to request a random number in form of an ID
        Vm.Log[] memory entries = vm.getRecordedLogs(); //This saves all logs emitted into an array called entries

        // The Vm.log counts everything as bytes 32
        // In order for us to access this log it has to be stored in a bytes32 type
        bytes32 requestId = entries[1].topics[1];

        uint256 previousLastTimeStamp = raffle.getLastTimeStamp();
        //  Now we pretend to be the chainlink nodes(vrfCoordinator)
        //to get random number and pick winner

        VRFCoordinatorV2Mock(vrfCoordinator).fulfillRandomWords(uint256(requestId), address(raffle)); // Here we are pretending to be the node operator and we are calling the fulfill random words function

        console.log(previousLastTimeStamp);
        console.log(raffle.getLastTimeStamp());

        // Assert
        assert(uint256(raffle.getRaffleState()) == 0);
        assert(raffle.getRecentWinner() != address(0));
        assert(raffle.getLengthOfPlayers() == 0);
        assert(previousLastTimeStamp < raffle.getLastTimeStamp());

        assert(raffle.getRecentWinner().balance == STARTING_USER_BALANCE + prize - entranceFee);
    }
}
