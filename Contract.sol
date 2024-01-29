// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract GovernanceToken is ERC20, Ownable {
    event ProposalCreated(uint256 proposalId, address indexed proposer, string description);
    event Voted(uint256 proposalId, address indexed voter, bool inSupport);
    event ProposalExecuted(uint256 proposalId);
    event ProposalCanceled(uint256 proposalId);
    event Delegated(address indexed from, address indexed to);
    
    uint256 public constant MIN_VOTE_DURATION = 1 days;
    uint256 public constant VOTE_DURATION = 7 days;
    uint256 public constant MIN_SUPPORT_PERCENTAGE = 50; // Minimum percentage of votes required for a proposal to pass
    uint256 public constant PROPOSAL_THRESHOLD = 100; // Minimum number of tokens required to create a proposal
    
    enum ProposalState { Pending, Active, Executed, Canceled }

    struct Proposal {
        string description;
        uint256 startTime;
        uint256 endTime;
        uint256 forVotes;
        uint256 againstVotes;
        ProposalState state;
        mapping(address => bool) voted;
    }

    struct Voter {
        uint256 balance;
        uint256 delegatedPower;
        address delegate;
    }

    mapping(address => Voter) public voters;
    Proposal[] public proposals;

    constructor() ERC20("Governance Token", "GOV") {
        _mint(msg.sender, 1000000 * (10**uint256(decimals())));
    }

    function propose(string memory description) external {
        require(balanceOf(msg.sender) >= PROPOSAL_THRESHOLD, "Must have enough tokens to create a proposal");

        uint256 proposalId = proposals.length;
        proposals.push(Proposal({
            description: description,
            startTime: block.timestamp,
            endTime: block.timestamp + VOTE_DURATION,
            forVotes: 0,
            againstVotes: 0,
            state: ProposalState.Pending
        }));

        emit ProposalCreated(proposalId, msg.sender, description);
    }

    function vote(uint256 proposalId, bool inSupport) external {
        Proposal storage proposal = proposals[proposalId];
        require(proposal.state == ProposalState.Pending, "Proposal must be in pending state");
        require(block.timestamp < proposal.endTime, "Voting has ended");
        require(!proposal.voted[msg.sender], "Cannot vote more than once");

        uint256 votingPower = getVotingPower(msg.sender);
        if (inSupport) {
            proposal.forVotes += votingPower;
        } else {
            proposal.againstVotes += votingPower;
        }

        proposal.voted[msg.sender] = true;

        emit Voted(proposalId, msg.sender, inSupport);
    }

    function executeProposal(uint256 proposalId) external onlyOwner {
        Proposal storage proposal = proposals[proposalId];
        require(proposal.state == ProposalState.Pending, "Proposal must be in pending state");
        require(block.timestamp >= proposal.endTime, "Voting has not ended");

        if ((proposal.forVotes * 100) / (proposal.forVotes + proposal.againstVotes) >= MIN_SUPPORT_PERCENTAGE) {
            proposal.state = ProposalState.Executed;
            _mint(owner(), proposal.forVotes); // Mint new tokens as a result of the governance decision

            emit ProposalExecuted(proposalId);
        }
    }

    function cancelProposal(uint256 proposalId) external {
        Proposal storage proposal = proposals[proposalId];
        require(proposal.state == ProposalState.Pending, "Proposal must be in pending state");
        require(msg.sender == proposalId, "Only proposer can cancel their proposal");

        proposal.state = ProposalState.Canceled;

        emit ProposalCanceled(proposalId);
    }

    function delegate(address to) external {
        require(to != address(0), "Cannot delegate to the zero address");

        voters[msg.sender].delegate = to;

        emit Delegated(msg.sender, to);
    }

    function getVotingPower(address voterAddress) public view returns (uint256) {
        Voter storage voter = voters[voterAddress];
        uint256 delegatedPower = getDelegatedPower(voter.delegate, 0);
        return voter.balance + delegatedPower;
    }

    function getDelegatedPower(address delegate, uint256 depth) internal view returns (uint256) {
        if (delegate == address(0) || depth > 5) {
            return 0; // Avoid potential circular delegation or deep recursion
        }

        Voter storage delegatedVoter = voters[delegate];
        uint256 directDelegatedPower = delegatedVoter.balance;
        uint256 indirectDelegatedPower = getDelegatedPower(delegatedVoter.delegate, depth + 1);

        return directDelegatedPower + indirectDelegatedPower;
    }

    function balanceOf(address account) public view override returns (uint256) {
        return voters[account].balance;
    }

    function transfer(address recipient, uint256 amount) public override returns (bool) {
        _transfer(msg.sender, recipient, amount);
        return true;
    }

    function transferFrom(address sender, address recipient, uint256 amount) public override returns (bool) {
        _transfer(sender, recipient, amount);
        _approve(sender, msg.sender, allowance(sender, msg.sender) - amount);
        return true;
    }

    function _transfer(address sender, address recipient, uint256 amount) internal override {
        require(sender != address(0), "Transfer from the zero address");
        require(recipient != address(0), "Transfer to the zero address");

        uint256 senderBalance = voters[sender].balance;
        require(senderBalance >= amount, "Insufficient balance");

        voters[sender].balance = senderBalance - amount;
        voters[recipient].balance += amount;

        emit Transfer(sender, recipient, amount);
    }

    function mint(address account, uint256 amount) external onlyOwner {
        _mint(account, amount);
    }

    function burn(address account, uint256 amount) external onlyOwner {
        _burn(account, amount);
    }
}
