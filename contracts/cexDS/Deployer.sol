// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "./CEXDefaultSwap.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "./interfaces/ICreditDefaultSwap.sol";

contract SwapController is AccessControl {

    bytes32 public constant SUPER_ADMIN = 'SUPER_ADMIN';
    bytes32 public constant ADMIN_CONTROLLER = 'ADMIN_CONTROLLER';
    bytes32 public constant VOTER_ROLE = 'VOTER_ROLE';

    struct VoterData {
        address voter;
        bool choice;
    }

    struct PoolContribution {
        uint256 voterFee;
        uint256 treasuryFee;
    }

    address[] public swapList;
    address[] public voterList;
    uint256 public lastVoterPaymentTimestamp;
    uint256 public totalVoterFee;

    uint256 public VOTER_RECURRING_PAYMENT_INTERVAL;
    uint256 public PERCENTAGE_VOTERS_DEFAULT_FEE;
    uint256 public PERCENTAGE_VOTERS_RECURRING_FEE;
    uint8 public immutable NUMBER_OF_VOTERS_EXPECTED;

    mapping(address => VoterData[]) public poolVotes;
    mapping(address => uint8) private trueVoteCount;
    mapping(address => bool) votingState;
    mapping(address => mapping(address => bool)) public voterHasVoted;
    mapping(address => PoolContribution) public poolContributions;

    event Vote(address indexed _pool, address _voter, bool _choice, uint256 _votePosition);
    event PayVoters(address[] _currencies, uint256[] _amountPaidOut);
    event AddVoter(address indexed _voter);
    event RemoveVoter(address indexed _voter);

    constructor(
        address secondSuperAdmin
    ) {
        _setupRole(SUPER_ADMIN, msg.sender);
        _setupRole(SUPER_ADMIN, secondSuperAdmin);
        _setRoleAdmin(ADMIN_CONTROLLER, SUPER_ADMIN);
        _setRoleAdmin(VOTER_ROLE, SUPER_ADMIN);

        VOTER_RECURRING_PAYMENT_INTERVAL = 30 days;
        NUMBER_OF_VOTERS_EXPECTED = 7;
        PERCENTAGE_VOTERS_RECURRING_FEE = 2500;
        PERCENTAGE_VOTERS_DEFAULT_FEE = 3333;
    }

    modifier isAdmin() {
        if(!hasRole(ADMIN_CONTROLLER, msg.sender) && !hasRole(SUPER_ADMIN, msg.sender)) revert("Caller does not have any of the admin roles");
        _;
    }

    function createSwapContract(
        string memory _entityName,
        address _currency,
        uint256 _premium,
        uint256 _initialMaturityDate,
        uint256 _epochDays

    ) public isAdmin {

        CEXDefaultSwap swapContract = new CEXDefaultSwap(
            _entityName,
            _currency,
            _premium,
            _initialMaturityDate,
            _epochDays
        );

        address contractAddress = address(swapContract);

        //Add to master list
        swapList.push(contractAddress);
    }

    function payRecurringVoterFees() external onlyRole(SUPER_ADMIN) returns (address[] memory pools, uint256[] memory amountsPaidOut) {

        if(block.timestamp < lastVoterPaymentTimestamp + VOTER_RECURRING_PAYMENT_INTERVAL) revert("Recurring payment time not reached");

        pools = new address[](swapList.length);
        amountsPaidOut = new uint256[](swapList.length);

        for (uint256 i = 0; i < swapList.length; i++) {
            address pool = swapList[i];
            uint256 totalAmountToPay = poolContributions[pool].voterFee * PERCENTAGE_VOTERS_RECURRING_FEE;
            uint256 amountPerVoter = totalAmountToPay/(NUMBER_OF_VOTERS_EXPECTED * 10000);
            poolContributions[pool].voterFee = (poolContributions[pool].voterFee * (10000 - PERCENTAGE_VOTERS_RECURRING_FEE))/10000;

            pools[i] = pool;
            amountsPaidOut[i] = totalAmountToPay/10000;

            for (uint256 j = 0; j < NUMBER_OF_VOTERS_EXPECTED; j++) {
                CEXDefaultSwap(pool).currency().transfer(voterList[j], amountPerVoter);
            }
            
        }

        emit PayVoters(pools, amountsPaidOut);

    }

    // function to be called by Swap Contract when paying maker fees
    function payFees(uint256 _amountPaid) external {
        address pool = msg.sender;

        bool transferSuccess = CEXDefaultSwap(pool).currency().transferFrom(pool, address(this), _amountPaid);

        if (!transferSuccess) revert("ERC20: Transfer Failed");

        uint256 voterFee = _amountPaid * PERCENTAGE_VOTERS_DEFAULT_FEE;
        uint256 treasuryFee = (_amountPaid * 10000) - voterFee;

        poolContributions[pool] = PoolContribution(voterFee/10000, treasuryFee);
    }

    function vote(address _poolAddress, bool choice) external onlyRole(VOTER_ROLE) {

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

    function whiteListVoters(address[] memory voters) external onlyRole(SUPER_ADMIN) {
        uint256 newVotersCount = voters.length;
        require(voterList.length + newVotersCount <= NUMBER_OF_VOTERS_EXPECTED, "Voters added exceed allowable number of voters");
        uint256 i;
        while (i < newVotersCount) {
            address voter = voters[i];
            _addVoter(voter);
            i++;
        }
    }

    function replaceVoter(address oldVoter, address replacement) external onlyRole(SUPER_ADMIN) {
        _removeVoter(oldVoter);
        _addVoter(replacement);

    }

    function setPoolPaused(address _add) external onlyRole(SUPER_ADMIN) {
        ICreditDefaultSwap(_add).pause();
    }

    function setPoolUnpaused(address _add) external onlyRole(SUPER_ADMIN) {
        ICreditDefaultSwap(_add).unpause();
    }
    
    function resetPoolAfterDefault(address _add, uint256 _newMaturityDate) external onlyRole(SUPER_ADMIN) {
        ICreditDefaultSwap(_add).resetAfterDefault(_newMaturityDate);
    }

    function setVoterRecurringPaymentInterval(uint256 _newInterval) external onlyRole(SUPER_ADMIN) {
        VOTER_RECURRING_PAYMENT_INTERVAL = _newInterval;
    }

    function setPercentageVoterRecurringFee(uint256 _newValue) external onlyRole(SUPER_ADMIN) {
        PERCENTAGE_VOTERS_RECURRING_FEE = _newValue;
    }

    function setPercentageVoterDefaultFee(uint256 _newValue) external onlyRole(SUPER_ADMIN) {
        PERCENTAGE_VOTERS_DEFAULT_FEE = _newValue;
    }

    // Internals

    // Handles implementation for the 7th vote of a particular cycle of votes
    function _executeFinalVote(address _poolAddress) internal {
        VoterData[] memory votesForPool = poolVotes[_poolAddress];

        uint8 i = 0;
        bool payout;
        uint8 votersForTrue = trueVoteCount[_poolAddress];
        uint256 amountToPay = poolContributions[_poolAddress].voterFee/Math.max(votersForTrue, NUMBER_OF_VOTERS_EXPECTED - votersForTrue);
        if (votersForTrue > NUMBER_OF_VOTERS_EXPECTED/2) {
            payout = true;
            ICreditDefaultSwap(_poolAddress).setDefaulted();
        } else {
            ICreditDefaultSwap(_poolAddress).unpause();
        }

        while (i < NUMBER_OF_VOTERS_EXPECTED) {
            if (votesForPool[i].choice == payout) {
                // Pay only to voters who are in the rational majority
                poolContributions[_poolAddress].voterFee = 0;
                CEXDefaultSwap(_poolAddress).currency().transfer(votesForPool[i].voter, amountToPay);
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
        }
        voterList = voters;
        voterList.pop();
        emit RemoveVoter(_voter);

    }

    function _addVoter(address _voter) private {
        require(!hasRole(VOTER_ROLE, _voter), "Already a voter");
        voterList.push(_voter);
        grantRole(VOTER_ROLE, _voter);
        emit AddVoter(_voter);
    }

    function getSwapList() external view returns (address[] memory) {
        return swapList;
    }

    function getVoterList() external view returns (address[] memory) {
        return voterList;
    }
}
