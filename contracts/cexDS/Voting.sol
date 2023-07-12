// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "./CEXDefaultSwap.sol";
import "./SwapController.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "./interfaces/ICreditDefaultSwap.sol";
import "./interfaces/ISwapController.sol";
import "hardhat/console.sol";

/**
* @title CXDX Multi-sig Voter Contract
*
* @author Ebube
*/
contract Voting is AccessControl {
    bytes32 public constant SUPER_ADMIN = 'SUPER_ADMIN';
    bytes32 public constant VOTER_ROLE = 'VOTER_ROLE';

    struct VoterData {
        address voter;
        bool choice;
    }

    address[] public voterList;
    uint256 public lastVoterPaymentTimestamp;
    uint256 public totalVoterFee;
    address public controller;

    uint256 public VOTER_RECURRING_PAYMENT_INTERVAL;
    uint256 public PERCENTAGE_VOTERS_DEFAULT_FEE;
    uint256 public PERCENTAGE_VOTERS_RECURRING_FEE;
    uint8 public immutable NUMBER_OF_VOTERS_EXPECTED;

    mapping(address => VoterData[]) public poolVotes;
    mapping(address => uint8) public trueVoteCount;
    mapping(address => bool) public votingState;
    mapping(address => mapping(address => bool)) public voterHasVoted;
    mapping(address => uint256) public poolFees;

    event Vote(address indexed _pool, address _voter, bool _choice, uint256 _votePosition);
    event PayVoters(address[] _currencies, uint256[] _amountPaidOut);
    event AddVoter(address indexed _voter);
    event RemoveVoter(address indexed _voter);

    constructor(
        address secondSuperAdmin,
        address controllerAddress
    ) {
        _setupRole(SUPER_ADMIN, msg.sender);
        _setupRole(SUPER_ADMIN, secondSuperAdmin);
        _setRoleAdmin(VOTER_ROLE, SUPER_ADMIN);

        VOTER_RECURRING_PAYMENT_INTERVAL = 30 days;
        NUMBER_OF_VOTERS_EXPECTED = 7;
        PERCENTAGE_VOTERS_RECURRING_FEE = 2500;
        PERCENTAGE_VOTERS_DEFAULT_FEE = 3333;
        lastVoterPaymentTimestamp = block.timestamp;
        controller = controllerAddress;
    }

    /**
     * @notice Pay a percentage of accumulated voter fees to each individual voter. Can only be called by address with SUPER_ADMIN role.
     * Percentage is defined as `PERCENTAGE_VOTERS_RECURRING_FEE`, and interval must have passed `VOTER_RECURRING_PAYMENT_INTERVAL` after last payment.
     * @return pools Array containing the list of swap pools from which payment were made. Should naturally contain all pools
     * @return amountsPaidOut Array of amounts paid with indices matching index of pool in pools array from which amount was paid
     */
    function payRecurringVoterFees() 
        external 
        onlyRole(SUPER_ADMIN) 
        returns (address[] memory pools, uint256[] memory amountsPaidOut) {

        if(block.timestamp < lastVoterPaymentTimestamp + VOTER_RECURRING_PAYMENT_INTERVAL) revert("Recurring payment time not reached");

        pools = ISwapController(controller).swapList();
        amountsPaidOut = new uint256[](pools.length);

        for (uint256 i = 0; i < pools.length; i++) {
            address pool = pools[i];
            uint256 totalAmountToPay = CEXDefaultSwap(pool).totalVoterFeePaid() * PERCENTAGE_VOTERS_RECURRING_FEE;
            uint256 amountPerVoter = totalAmountToPay/(NUMBER_OF_VOTERS_EXPECTED * 10000);

            CEXDefaultSwap(pool).deductFromVoterFee(totalAmountToPay/10000);
            amountsPaidOut[i] = totalAmountToPay/10000;

            for (uint256 j = 0; j < NUMBER_OF_VOTERS_EXPECTED; j++) {
                CEXDefaultSwap(pool).currency().transfer(voterList[j], amountPerVoter);
            }
            
        }
        lastVoterPaymentTimestamp = block.timestamp;

        emit PayVoters(pools, amountsPaidOut);
    }

    /**
     * @notice Vote for default of a contract. Can only be called by address with VOTER_ROLE role.
     * Would call `executeFinalVote` to pay out benefits to the voters after the seventh vote is placed.
     * @param _poolAddress address of pool on which vote is being cast
     * @param choice Boolean indicated a 'Yes' or 'No' vote on the swap pool
     */
    function vote(
        address _poolAddress
        , bool choice
        ) external 
        onlyRole(VOTER_ROLE) {
        console.log("Vote: ", voterHasVoted[_poolAddress][msg.sender]);
        require(!voterHasVoted[_poolAddress][msg.sender], "Already voted in the current cycle");

        VoterData memory voterInfo = VoterData(msg.sender, choice);
        poolVotes[_poolAddress].push(voterInfo);

        voterHasVoted[_poolAddress][msg.sender] = true;
        VoterData[] memory votesForPool = poolVotes[_poolAddress];

        if (choice) trueVoteCount[_poolAddress] += 1;

        if (votesForPool.length == 2) {
            votingState[_poolAddress] = true;
            ICreditDefaultSwap(_poolAddress).pause();
        }

        if (votesForPool.length == NUMBER_OF_VOTERS_EXPECTED) {
            _executeFinalVote(_poolAddress);
        }

        emit Vote(_poolAddress, msg.sender, choice, votesForPool.length);
    }

    /**
     * @notice grant VOTER_ROLE role to voters to enable them engage in voting process. Must revert when `NUMBER_OF_VOTERS_EXPECTED` is reached.
     * @param voters List of voters to add to the contract
     */
    function whiteListVoters(
        address[] memory voters
        ) external 
        onlyRole(SUPER_ADMIN) {
        
        uint256 newVotersCount = voters.length;
        require(voterList.length + newVotersCount <= NUMBER_OF_VOTERS_EXPECTED, "Voters added exceed allowable number of voters");
        uint256 i;
        while (i < newVotersCount) {
            address voter = voters[i];
            _addVoter(voter);
            i++;
        }
    }

    /**
     * @notice Replace a voter with another since number of voters must always be maintained when a voter is to be removed.
     * @param oldVoter Voter address to be removed
     * @param replacement Voter replacement address
     */
    function replaceVoter(
        address oldVoter
        , address replacement
        ) external 
        onlyRole(SUPER_ADMIN) {
        
        _removeVoter(oldVoter);
        _addVoter(replacement);

    }

    /**
     * @notice Set interval for paying `PERCENTAGE_VOTERS_RECURRING_FEE` to voters.
     * @param _newInterval New time frequency for paying reward.
     */
    function setVoterRecurringPaymentInterval(
        uint256 _newInterval
        ) external 
        onlyRole(SUPER_ADMIN) {
        VOTER_RECURRING_PAYMENT_INTERVAL = _newInterval;
    }

    /**
     * @notice Set percentage fee to be paid to voters at the specified interval
     * @param _newValue New fee percentage to be paid.
     */
    function setPercentageVoterRecurringFee(
        uint256 _newValue
        ) external 
        onlyRole(SUPER_ADMIN) {
        PERCENTAGE_VOTERS_RECURRING_FEE = _newValue;
    }

    /**
     * @notice Set percentage of total pool fee to be accumulated for maker fee paid into the pool contracts.
     * @param _newValue New value for the fee.
     */
    function setPercentageVoterDefaultFee(
        uint256 _newValue
        ) external 
        onlyRole(SUPER_ADMIN) {
        
        PERCENTAGE_VOTERS_DEFAULT_FEE = _newValue;
    }

    // Internals

    // Handles implementation for the 7th vote of a particular cycle of votes
    function _executeFinalVote(address _poolAddress) private {
        VoterData[] memory votesForPool = poolVotes[_poolAddress];

        uint8 i = 0;
        bool payout;
        uint8 votersForTrue = trueVoteCount[_poolAddress];
        uint256 amountToPay = CEXDefaultSwap(_poolAddress).totalVoterFeePaid();
        
        // Unpause swap first as setDefaulted would revert if paused
        ICreditDefaultSwap(_poolAddress).unpause();
        if (votersForTrue > NUMBER_OF_VOTERS_EXPECTED/2) {
            payout = true;
            ICreditDefaultSwap(_poolAddress).setDefaulted();
        }

        // Reduce value of voter fee from the Pool Contract
        CEXDefaultSwap(_poolAddress).deductFromVoterFee(amountToPay);

        while (i < NUMBER_OF_VOTERS_EXPECTED) {
            if (votesForPool[i].choice == payout) {
                // Pay only to voters who are in the rational majority
                CEXDefaultSwap(_poolAddress).currency().transfer(votesForPool[i].voter, amountToPay/Math.max(votersForTrue, NUMBER_OF_VOTERS_EXPECTED - votersForTrue));
            }
            delete voterHasVoted[_poolAddress][votesForPool[i].voter];

            i++;
        }

        delete poolVotes[_poolAddress];
        delete votingState[_poolAddress];
        delete trueVoteCount[_poolAddress];
    }

    function _removeVoter(address _voter) private {
        _checkRole(VOTER_ROLE, _voter);
        uint i;
        bool reachedVoter;
        address[] memory voters = voterList;
        while (i < voters.length - 1) {
            if (voters[i] == _voter) reachedVoter = true;

            if (reachedVoter) voters[i] = voters[voters.length - 1];
            i++;
        }
        voterList = voters;
        voterList.pop();
        revokeRole(VOTER_ROLE, _voter);
        emit RemoveVoter(_voter);

    }

    function _addVoter(address _voter) private {
        require(!hasRole(VOTER_ROLE, _voter), "Already a voter");
        voterList.push(_voter);
        grantRole(VOTER_ROLE, _voter);
        emit AddVoter(_voter);
    }

    function getVoterList() external view returns (address[] memory) {
        return voterList;
    }
}