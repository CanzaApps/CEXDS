// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import "./CreditDefaultSwap.sol";

contract deployer {
    CreditDefaultSwap public swapContract;

    address[] public swapList;
    mapping(address => address[]) public userSwaps;

    mapping(string => bool) public deployedLoanIDs;

    function createSwapContract(
        string memory _loanName,
        address _currency,
        uint256 _interestRate,
        uint256 _maturity_day,
        uint256 _maturity_month,
        uint256 _maturity_year,
        string memory _status,
        uint256 _premium,
        string memory _loanID,
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
            _maturity_day,
            _maturity_month,
            _maturity_year,
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
