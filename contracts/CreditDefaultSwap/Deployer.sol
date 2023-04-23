//SPDX-License-Identifier: Unlicensed
pragma solidity ^0.8.18;

import "./CreditDefaultSwap.sol";

contract Deployer {
    CreditDefaultSwap public swapContract;

    address[] public swapList;

    mapping(address => address[]) public userSwaps;

    mapping(uint256 => bool) public deployedLoanIDs;

    function createSwapContract(
        string memory _loanName,
        address _currency,
        uint256 _interestRate,
        uint256 _maturityDate,
        string memory _status,
        uint256 _premium,
        uint256 _loanID,
        string memory _loanURL
    ) public {
        require(!deployedLoanIDs[_loanID], "Loan has been already issued");

        bool statusCurrent;

        if (bytes(_status).length == bytes("current").length) {
            statusCurrent = (keccak256(abi.encodePacked(_loanID)) ==
                keccak256(abi.encodePacked(_loanID)));
        }
        require(statusCurrent, "Loan is not Current");

        swapContract = new CreditDefaultSwap(
            _loanName,
            _currency,
            _interestRate,
            _maturityDate,
            _status,
            _premium,
            _loanID,
            _loanURL
        );

        //Add loan ID to mapping so that it cannot be re-deployed
        deployedLoanIDs[_loanID] = true;

        address contractAddress = address(swapContract);

        //Add to master list
        swapList.push(contractAddress);

        //Add to list searchable by user
        userSwaps[msg.sender].push(contractAddress);
    }

    function getSwapList() external view returns (address[] memory) {
        return swapList;
    }
}
