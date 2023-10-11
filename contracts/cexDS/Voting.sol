// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "./CEXDefaultSwap.sol";
import "./SwapController.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "./interfaces/ICreditDefaultSwap.sol";
import "./interfaces/ISwapController.sol";
import "./interfaces/IOracle.sol";

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
    address public oracleAddress;

    mapping(address => address[]) public poolVoters;
    mapping(address => mapping(address => bool)) public isPoolVoter;
    mapping(address => VoterData[]) public poolVotes;
    mapping(address => uint8) public trueVoteCount;
    mapping(address => bool) public votingState;
    mapping(address => mapping(address => bool)) public voterHasVoted;
    mapping(address => bool) public poolHasSpecificVoters;

    event Vote(address indexed _pool, address _voter, bool _choice, uint256 _votePosition);
    event PayVoters(address[] _currencies, uint256[] _amountPaidOut);
    event AddVoter(address indexed _voter);
    event RemoveVoter(address indexed _voter);

    constructor(
        address secondSuperAdmin,
        address controllerAddress,
        address oracle
    ) {
        _setupRole(SUPER_ADMIN, msg.sender);
        _setupRole(SUPER_ADMIN, secondSuperAdmin);
        _setRoleAdmin(VOTER_ROLE, SUPER_ADMIN);
        lastVoterPaymentTimestamp = block.timestamp;
        controller = controllerAddress;
        oracleAddress = oracle;
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

        pools = ISwapController(controller).swapList();
        amountsPaidOut = new uint256[](pools.length);

        for (uint256 i = 0; i < pools.length; i++) {
            address pool = pools[i];
            if(block.timestamp < lastVoterPaymentTimestamp + IOracle(oracleAddress).getRecurringPaymentInterval(pool)) continue;
            address[] memory votersToPay = poolVoters[pool];
            if (votersToPay.length == 0) votersToPay = voterList;

            uint256 totalAmountToPay = IOracle(oracleAddress).getRecurringFeeAmount(CEXDefaultSwap(pool).totalVoterFeePaid(), pool); 
            uint256 amountPerVoter = totalAmountToPay/(votersToPay.length * 10000);

            CEXDefaultSwap(pool).deductFromVoterFee(totalAmountToPay/10000);
            amountsPaidOut[i] = totalAmountToPay/10000;

            for (uint256 j = 0; j < votersToPay.length; j++) {
                CEXDefaultSwap(pool).currency().transfer(votersToPay[j], amountPerVoter);
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
        ) external {
        
        require(poolHasSpecificVoters[_poolAddress] && isPoolVoter[_poolAddress][msg.sender] || 
        (!poolHasSpecificVoters[_poolAddress] && hasRole(VOTER_ROLE, msg.sender))
        , "Not authorized to vote for this Swap");
        require(!voterHasVoted[_poolAddress][msg.sender], "Already voted in the current cycle");

        uint8 trueVotes = trueVoteCount[_poolAddress];
        if(trueVotes < 2 && choice == false) revert("Requires first 2 votes to be true");

        VoterData memory voterInfo = VoterData(msg.sender, choice);
        poolVotes[_poolAddress].push(voterInfo);

        voterHasVoted[_poolAddress][msg.sender] = true;
        VoterData[] memory votesForPool = poolVotes[_poolAddress];

        if (choice) trueVoteCount[_poolAddress] += 1;

        if (votesForPool.length == 2) {
            votingState[_poolAddress] = true;
            ICreditDefaultSwap(_poolAddress).pause();
        }

        if (votesForPool.length == IOracle(oracleAddress).getNumberOfVotersRequired(_poolAddress)) {
            _executeFinalVote(_poolAddress);
        }
        

        emit Vote(_poolAddress, msg.sender, choice, votesForPool.length);
    }

    /**
     * @notice add voters to a third-party pool, either at pool creation of after.
     * @param voters List of voters to add to the contract.
     * @param pool Third-party pool address on which to add the voters.
     */
    function setVotersForPool(address[] memory voters, address pool) external {
        if (msg.sender != controller && !hasRole(SUPER_ADMIN, msg.sender) && !hasRole(ISwapController(controller).getPoolOwnerRole(pool), msg.sender)) revert("Not authorized");
        if (pool == address(0)) revert("No zero address pool");

        poolHasSpecificVoters[pool] = true;
        _whiteListVoters(voters, pool);
        
    }

    /**
     * @notice grant VOTER_ROLE role to voters to enable them engage in voting process. Must revert when `NUMBER_OF_VOTERS_EXPECTED` is reached.
     * @param voters List of voters to add to the contract
     */
    function whiteListVoters(
        address[] memory voters
        ) external
        onlyRole(SUPER_ADMIN) {
        
        _whiteListVoters(voters, address(0));
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
        
        replaceVoter(oldVoter, replacement, address(0));

    }

    /**
     * @notice Replace a voter with another since number of voters must always be maintained when a voter is to be removed.
     * @param oldVoter Voter address to be removed
     * @param replacement Voter replacement address
     */
    function replaceVoter(
        address oldVoter
        , address replacement
        , address _pool
        ) public {
        if (!hasRole(SUPER_ADMIN, msg.sender) && !hasRole(ISwapController(controller).getPoolOwnerRole(_pool), msg.sender)) revert("Not authorized");

        _removeVoter(oldVoter, _pool);
        _addVoter(replacement, _pool);
    }

    function clearVotingData(address _poolAddress) external {
        if (msg.sender != controller) revert("Unauthorized.");
        uint8 voterCount = IOracle(oracleAddress).getNumberOfVotersRequired(_poolAddress);
        VoterData[] memory votesForPool = poolVotes[_poolAddress];
        if (votesForPool.length != voterCount) revert("Vote Cycle has not ended.");

        uint256 i;
        while (i < voterCount) {
            delete voterHasVoted[_poolAddress][votesForPool[i].voter];

            i++;
        }

        delete poolVotes[_poolAddress];
        delete votingState[_poolAddress];
        delete trueVoteCount[_poolAddress];
    }

    // Internals

    // Handles implementation for the 7th vote of a particular cycle of votes
    function _executeFinalVote(address _poolAddress) private {
        VoterData[] memory votesForPool = poolVotes[_poolAddress];
        uint8 voterCount = IOracle(oracleAddress).getNumberOfVotersRequired(_poolAddress);
        uint8 i = 0;
        uint8 votersForTrue = trueVoteCount[_poolAddress];
        bool payout;

        if (poolHasSpecificVoters[_poolAddress]) {
            payout = votersForTrue > poolVoters[_poolAddress].length/2;
        } else {
            payout = votersForTrue > voterCount/2;
        }
        
        uint256 amountToPay = CEXDefaultSwap(_poolAddress).totalVoterFeePaid();

        // Reduce value of voter fee from the Pool Contract
        CEXDefaultSwap(_poolAddress).deductFromVoterFee(amountToPay);

        if (payout) {
            ICreditDefaultSwap(_poolAddress).setDefaulted();
        } else {
            ICreditDefaultSwap(_poolAddress).unpause();
            delete poolVotes[_poolAddress];
            delete votingState[_poolAddress];
            delete trueVoteCount[_poolAddress];
        } 

        while (i < voterCount) {
            if (votesForPool[i].choice == payout) {
                // Pay only to voters who are in the rational majority
                CEXDefaultSwap(_poolAddress).currency().transfer(votesForPool[i].voter, amountToPay/Math.max(votersForTrue, voterCount - votersForTrue));
            }

            if (!payout) delete voterHasVoted[_poolAddress][votesForPool[i].voter];

            i++;
        }
        
    }

    function _whiteListVoters(
        address[] memory voters
        , address _pool
        ) internal {
        
        uint256 newVotersCount = voters.length;

        address[] memory previousVoters = voterList;
        if (poolHasSpecificVoters[_pool]) previousVoters = poolVoters[_pool];
        require(previousVoters.length + newVotersCount <= IOracle(oracleAddress).getNumberOfVotersRequired(_pool), "Voters added exceed allowable number of voters");
        uint256 i;
        while (i < newVotersCount) {
            address voter = voters[i];
            _addVoter(voter, _pool);
            i++;
        }
    }

    function _removeVoter(address _voter, address _poolAddress) private {

        uint i;
        bool reachedVoter;
        address[] memory voters = voterList;
        if (poolHasSpecificVoters[_poolAddress]) voters = poolVoters[_poolAddress];
        while (i < voters.length - 1) {
            if (voters[i] == _voter) reachedVoter = true;

            if (reachedVoter) voters[i] = voters[voters.length - 1];
            i++;
        }

        if (poolHasSpecificVoters[_poolAddress]) {
            poolVoters[_poolAddress] = voters;
            poolVoters[_poolAddress].pop();
        } else {
            voterList = voters;
            voterList.pop();
            revokeRole(VOTER_ROLE, _voter);
        }
        
        emit RemoveVoter(_voter);

    }

    function _addVoter(address _voter, address _poolAddress) private {
        if (poolHasSpecificVoters[_poolAddress]) {
            poolVoters[_poolAddress].push(_voter);
        } else {
            voterList.push(_voter);
            grantRole(VOTER_ROLE, _voter);
        }
        
        emit AddVoter(_voter);
    }

    function getVoterList(address _poolAddress) external view returns (address[] memory) {
        if (poolHasSpecificVoters[_poolAddress]) return poolVoters[_poolAddress];
        return voterList;
    }
}