// Layout of Contract:
// version
// imports
// errors
// interfaces, libraries, contracts
// Type declarations
// State variables
// Events
// Modifiers
// Functions

// Layout of Functions:
// constructor
// receive function (if exists)
// fallback function (if exists)
// external
// public
// internal
// private
// internal & private view & pure functions
// external & public view & pure functions
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {VRFCoordinatorV2Interface} from "@chainlink/contracts/src/v0.8/interfaces/VRFCoordinatorV2Interface.sol";
import {VRFConsumerBaseV2} from "@chainlink/contracts/src/v0.8/VRFConsumerBaseV2.sol";

/**
 * @title A sample raffle contract
 * @author Victory Ndu
 * @notice This contract is for creating a sample raffle
 * @dev Implements Chainlink VRFv2 raffle
 */
contract Raffle is VRFConsumerBaseV2 {
    error Raffle__notEnoughEthSent();
    error Raffle__TransferFailed();
    error Raffle__notOpen();
    error Raffle_upKeepNotNeeded(uint256 currentBalance, uint256 numberOfPlayers, uint256 raffleState);

    /**
     * Type Declaration
     */
    enum RaffleState
    // the first valur defaults to 0
    // second value defaults to 1
    // third value defaults to 2 like that
    {
        OPEN, // 0
        CALCULATING // 1
    }

    /**
     * State Variables
     */
    uint16 private constant REQUEST_CONFIRMATIONS = 3;
    uint32 private constant NUM_OF_WORDS = 1;
    uint256 private immutable i_entranceFee;
    // when we deploy this contract we want to set an interval once
    uint256 private immutable i_interval;
    VRFCoordinatorV2Interface private immutable i_vrfCoordinator;
    bytes32 private immutable i_gasLane;
    uint64 private immutable i_subscriptionId;
    uint32 private immutable i_callBackGasLimit;

    address payable[] private s_players;

    uint256 private s_lastTimeStamp;
    address private s_recentWinner;
    RaffleState private s_raffleState;

    event EnteredRaffle(address indexed player);
    event WinnerPicked(address indexed winner);
    event RequestedRaffleWinner(uint256 indexed requestId);

    constructor(
        uint256 entranceFee,
        uint256 interval,
        address vrfCoordinator,
        bytes32 gasLane,
        uint64 subscriptionId,
        uint32 callBackGasLimit
    ) VRFConsumerBaseV2(vrfCoordinator) {
        i_entranceFee = entranceFee;
        i_interval = interval;
        i_vrfCoordinator = VRFCoordinatorV2Interface(vrfCoordinator);
        i_gasLane = gasLane;
        i_subscriptionId = subscriptionId;
        i_callBackGasLimit = callBackGasLimit;

        s_raffleState = RaffleState.OPEN;
        s_lastTimeStamp = block.timestamp;
    }

    function enterRaffle() external payable {
        if (msg.value < i_entranceFee) revert Raffle__notEnoughEthSent();

        if (s_raffleState != RaffleState.OPEN) revert Raffle__notOpen();
        s_players.push(payable(msg.sender));

        emit EnteredRaffle(msg.sender);
    }

    /**
     * @dev This is the function that chainlink Automation nodes call to see if its time to perform an upkeep
     * The following should be true for this to return true:
     * 1. The time interval has passed between runs
     * 2  The raffle is in an open STATE
     * 3. The contract has ETH (aka Players)
     * 4. The subscription is funded with LINK
     */
    function checkUpkeep(bytes memory)
        /**
         * checkData
         */
        public
        view
        returns (bool upkeepNeeded, bytes memory /* performData */ )
    {
        bool timeHasPassed = (block.timestamp - s_lastTimeStamp > i_interval);
        bool isOpened = RaffleState.OPEN == s_raffleState;
        bool hasBalance = address(this).balance > 0;
        bool hasPlayers = s_players.length > 0;

        upkeepNeeded = (timeHasPassed && isOpened && hasBalance && hasPlayers);
        return (upkeepNeeded, "0x0");
    }

    // pick a number
    // Use that random number to pick a player
    // automatically call the function
    function performUpkeep(bytes calldata /* performData */ ) external {
        (bool upKeepNeeded,) = checkUpkeep(""); // This line indicates it is time for an upkeep when it is true
        if (!upKeepNeeded) {
            revert Raffle_upKeepNotNeeded(address(this).balance, s_players.length, uint256(s_raffleState));
        }

        s_raffleState = RaffleState.CALCULATING;

        uint256 requestId = i_vrfCoordinator.requestRandomWords(
            i_gasLane, i_subscriptionId, REQUEST_CONFIRMATIONS, i_callBackGasLimit, NUM_OF_WORDS
        );

        emit RequestedRaffleWinner(requestId);
    }

    function fulfillRandomWords(
        uint256,
        /**
         * requestId
         */
        uint256[] memory randomWords
    ) internal override {
        //   painting a picture , lets say we have s_players.length = 10;
        // We grab the randomWords at index of 0 and we do randomWords % 10 to get a random number
        uint256 indexOfWinner = randomWords[0] % s_players.length;
        address payable winner = s_players[indexOfWinner];
        s_recentWinner = winner;
        s_raffleState = RaffleState.OPEN;
        s_players = new address payable[](0);
        s_lastTimeStamp = block.timestamp;
        (bool success,) = winner.call{value: address(this).balance}("");
        if (!success) revert Raffle__TransferFailed();

        emit WinnerPicked(winner);
    }

    /**
     * Getter Functions
     */

    function getEntranceFee() external view returns (uint256) {
        return i_entranceFee;
    }

    function getRaffleState() external view returns (RaffleState) {
        return s_raffleState;
    }

    function getPlayer(uint256 playerIndex) external view returns (address) {
        return s_players[playerIndex];
    }

    function getLastTimeStamp() external view returns (uint256) {
        return s_lastTimeStamp;
    }

    function getRecentWinner() external view returns (address) {
        return s_recentWinner;
    }

    function getLengthOfPlayers() external view returns (uint256) {
        return s_players.length;
    }
}
