// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import "./CXDefaultSwap.sol";
import "./SwapController.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "./interfaces/ICreditDefaultSwap.sol";
import "./interfaces/ISwapController.sol";
import "./interfaces/IOracle.sol";

/**
* @title CXDS Multi-sig Voter Contract
*
* @author Ebube
*/
contract Voting is AccessControl {
    using Address for address;
    using SafeERC20 for IERC20;
    bytes32 public constant SUPER_ADMIN = 'SUPER_ADMIN';
    bytes32 public constant VOTER_ROLE = 'VOTER_ROLE';

    struct VoterData {
        address voter;
        bool choice;
    }

    address[] public voterList;
    address public controller;
    address public oracleAddress;

    mapping(address => uint256) public lastVoterPaymentTimestamp;
    mapping(address => address[]) public poolVoters;
    mapping(address => mapping(address => bool)) public isPoolVoter;
    mapping(address => VoterData[]) private poolVotes;
    mapping(address => uint8) public trueVoteCount;
    mapping(address => bool) public votingState;
    mapping(address => mapping(address => bool)) public voterHasVoted;
    mapping(address => bool) public poolHasSpecificVoters;
    // keeps track of voter replacement information to try to prevent a replacement from voting where the previous already voted
    // maps the replacement voter to the previous voter
    mapping(address => address) private replacementVoters;
    // maps the pool address to the replacement voter and then to the previous voter
    // this is specifically for 3rd party pools
    mapping(address => mapping(address => address)) private replacementVotersPerPool;
    mapping(address => mapping(address => uint256)) public voterPerPoolAccumulatedRewards;

    event Vote(address indexed _pool, address _voter, uint256 _votePosition);
    event PayVoters(address poolPaying, uint256 overallAmountPaid, address[] voters, bool isDefaultRewards);
    event WithdrawVoterRewards(address indexed _voter, address _pool, uint256 amountWithdrawn);
    event AddVoter(address indexed _voter, address _pool, address _caller);
    event RemoveVoter(address indexed _voter, address _pool, address _caller);
    event WithdrawReserve(address indexed _pool, uint256 reserveAmount, address _recipient, address _caller);
    event ClearVotingData(address indexed _poolAddress, VoterData[] poolVotes, bool wasDefault);
    event SetController(address _controllerAddress);
    event SetOracle(address _oracleAddress);

    constructor(
        address secondSuperAdmin,
        address controllerAddress,
        address oracle
    ) {
        _setupRole(SUPER_ADMIN, msg.sender);
        _setupRole(SUPER_ADMIN, secondSuperAdmin);
        _setRoleAdmin(VOTER_ROLE, SUPER_ADMIN);
        controller = controllerAddress;
        oracleAddress = oracle;
    }

    /**
     * @notice Pay a percentage of accumulated voter fees to each individual voter. Can only be called by address with SUPER_ADMIN role.
     * @dev Percentage of reserve to pay is received from Oracle.getRecurringFeeAmount 
     */
    function payRecurringVoterFee() external {

        address poolPaying = msg.sender;
        if(block.timestamp < lastVoterPaymentTimestamp[poolPaying] + (CXDefaultSwap(poolPaying).epochDays() * 86400)) revert("Can not pay at this time");
        address[] memory votersToPay = poolVoters[poolPaying];
        if (votersToPay.length == 0) votersToPay = voterList;

        uint256 totalAmountToPay = IOracle(oracleAddress).getRecurringFeeAmount(CXDefaultSwap(poolPaying).totalVoterFeeRemaining(), poolPaying);
        CXDefaultSwap(poolPaying).deductFromVoterReserve(totalAmountToPay/10000);

        for (uint256 j = 0; j < votersToPay.length; j++) {
            voterPerPoolAccumulatedRewards[votersToPay[j]][poolPaying] += totalAmountToPay/votersToPay.length;
        }
        lastVoterPaymentTimestamp[poolPaying] = block.timestamp;

        emit PayVoters(poolPaying, totalAmountToPay, votersToPay, false);
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
        require(!voterHasVoted[_poolAddress][msg.sender] && !voterHasVoted[_poolAddress][replacementVoters[msg.sender]]
        && !voterHasVoted[_poolAddress][replacementVotersPerPool[_poolAddress][msg.sender]], "Already voted in the current cycle");


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
        

        emit Vote(_poolAddress, msg.sender, votesForPool.length);
    }

    /**
     * @notice allow voter to withdraw from the rewards accumulated overtime.
     * @param _pool Pool on which the rewards were accumulated.
     * @param _amountToWithdraw Amount to be withdrawn.
     */
    function withdrawVoterRewards(address _pool, uint256 _amountToWithdraw) external {

        uint256 totalAccumulated = voterPerPoolAccumulatedRewards[msg.sender][_pool];
        require(totalAccumulated < _amountToWithdraw, "Not sufficient available to withdraw");

        totalAccumulated -= _amountToWithdraw;
        voterPerPoolAccumulatedRewards[msg.sender][_pool] = totalAccumulated;
        CXDefaultSwap(_pool).currency().safeTransfer(msg.sender, _amountToWithdraw);

        emit WithdrawVoterRewards(msg.sender, _pool, _amountToWithdraw);
    }

    /**
     * @notice add voters to a third-party pool at pool creation.
      Must be called by controller contract, when creating a pool, by an admin.
     * @param voters List of voters to add to the contract.
     * @param pool Third-party pool address on which to add the voters.
     */
    function setVotersForPool(address[] memory voters, address pool) external {
        if (msg.sender != controller && !hasRole(SUPER_ADMIN, msg.sender)) revert("Not authorized");
        if (pool == address(0)) revert("No zero address pool");
        uint8 requiredVoterCount = IOracle(oracleAddress).getNumberOfVotersRequired(pool);
        if (voters.length != requiredVoterCount) revert("Incorrect number of voters supplied");

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

        _removeVoter(oldVoter, address(0));
        _addVoter(replacement, address(0));

        replacementVoters[replacement] = oldVoter;
    }

    /**
     * @notice Replace a voter with another since number of voters must always be maintained when a voter is to be removed.
     * @param oldVoter Voter address to be removed
     * @param replacement Voter replacement address
     */
    function replaceVoterOnPool(
        address oldVoter
        , address replacement
        , address _pool
        ) external {
        if (!hasRole(SUPER_ADMIN, msg.sender) && !ISwapController(controller).isPoolOwner(_pool, msg.sender)) revert("Not authorized");

        _removeVoter(oldVoter, _pool);
        _addVoter(replacement, _pool);

        replacementVotersPerPool[_pool][replacement] = oldVoter;
    }

    /**
     * @notice provides a way to clear all votes data in storage for a specific pool after a default, to allow restarting a new cycle with empty mappings.
     * Functionality is only available to the controller contract at {SwapController.resetPoolAfterDefault}
     * @param _poolAddress the address of the swap pool whose data is to be cleared.
     */
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
        emit ClearVotingData(_poolAddress, poolVotes[_poolAddress], true);
        delete poolVotes[_poolAddress];
        delete votingState[_poolAddress];
        delete trueVoteCount[_poolAddress];
    }

    /**
     * @notice Allows admin to withdraw any voter reserve that has not been paid yet if no default is reached in a really long time.
     * Implementation only exists so that funds do not get locked within contract, especially if pool is closed.
     * @param _poolAddress the swap pool for which the voter fee reserve is to be withdrawn.
     * @param _recipient address which should receive the withdrawn reserved tokens.
     */
    function withdrawPendingReserve(address _poolAddress, address _recipient) external onlyRole(SUPER_ADMIN) {
        uint256 reserveAvailable = CXDefaultSwap(_poolAddress).totalVoterFeeRemaining();

        CXDefaultSwap(_poolAddress).currency().safeTransfer(_recipient, reserveAvailable);

        CXDefaultSwap(_poolAddress).deductFromVoterReserve(reserveAvailable);

        emit WithdrawReserve(_poolAddress, reserveAvailable, _recipient, msg.sender);
    }

    function setControllerContract(address _address) external onlyRole(SUPER_ADMIN) {
        if (!_address.isContract()) revert("Attempting to set invalid address. Check that it is not zero address, and that it is for a contract");
        if (_address == controller) revert("Already set");

        controller = _address;
        emit SetController(_address);
    }

    function setOracleContract(address _address) external onlyRole(SUPER_ADMIN) {
        if (!_address.isContract()) revert("Attempting to set invalid address. Check that it is not zero address, and that it is for a contract");
        if (_address == oracleAddress) revert("Already set");

        oracleAddress = _address;
        emit SetOracle(_address);
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
        
        uint256 amountToPay = CXDefaultSwap(_poolAddress).totalVoterFeeRemaining();

        // Reduce value of voter fee from the Pool Contract
        CXDefaultSwap(_poolAddress).deductFromVoterReserve(amountToPay);

        if (payout) {
            ICreditDefaultSwap(_poolAddress).setDefaulted(10000);
        } else {
            ICreditDefaultSwap(_poolAddress).unpause();
            emit ClearVotingData(_poolAddress, poolVotes[_poolAddress], false);
            delete poolVotes[_poolAddress];
            delete votingState[_poolAddress];
            delete trueVoteCount[_poolAddress];
        } 

        while (i < voterCount) {
            VoterData memory voterInfo = votesForPool[i];
            if (voterInfo.choice == payout) {
                // Pay only to voters who are in the rational majority
                
                voterPerPoolAccumulatedRewards[voterInfo.voter][_poolAddress] += amountToPay/Math.max(votersForTrue, voterCount - votersForTrue);
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
            if ((poolHasSpecificVoters[_pool] && isPoolVoter[_pool][voter]) || (!poolHasSpecificVoters[_pool] && hasRole(VOTER_ROLE, voter))) 
            revert(string(
                    abi.encodePacked(
                        "Address ",
                        Strings.toHexString(voter),
                        " already has voting privileges for pool ",
                        Strings.toHexString(_pool)
                    )
                ));
            _addVoter(voter, _pool);
            i++;
        }
    }

    function _removeVoter(address _voter, address _poolAddress) private {

        uint i;
        bool reachedVoter;
        address[] memory voters = voterList;
        if (poolHasSpecificVoters[_poolAddress]) voters = poolVoters[_poolAddress];
        while (i < voters.length) {
            if (voters[i] == _voter) reachedVoter = true;

            if (reachedVoter) {
                voters[i] = voters[voters.length - 1];
                break;
            }
            i++;
        }

        if (!reachedVoter) revert("Address being removed is not a voter");

        if (poolHasSpecificVoters[_poolAddress]) {
            poolVoters[_poolAddress] = voters;
            poolVoters[_poolAddress].pop();
            isPoolVoter[_poolAddress][_voter] = false;
        } else {
            voterList = voters;
            voterList.pop();
            revokeRole(VOTER_ROLE, _voter);
        }
        
        emit RemoveVoter(_voter, _poolAddress, msg.sender);

    }

    function _addVoter(address _voter, address _poolAddress) private {
        if (poolHasSpecificVoters[_poolAddress]) {
            poolVoters[_poolAddress].push(_voter);
            isPoolVoter[_poolAddress][_voter] = true;
        } else {
            voterList.push(_voter);
            grantRole(VOTER_ROLE, _voter);
        }
        
        emit AddVoter(_voter, _poolAddress, msg.sender);
    }

    function getVoterList(address _poolAddress) external view returns (address[] memory) {
        if (poolHasSpecificVoters[_poolAddress]) return poolVoters[_poolAddress];
        return voterList;
    }
}