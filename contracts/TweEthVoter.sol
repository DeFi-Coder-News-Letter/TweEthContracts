// TODO(ND): mintandapprove
// TODO(ND): Test framework

pragma solidity ^0.4.24;

import "openzeppelin-solidity/contracts/math/SafeMath.sol";
import "openzeppelin-solidity/contracts/token/ERC20/ERC20Mintable.sol";

/// @title TweEthVoter
/// @author nemild mtlapinski

contract TweEthVoter { // CapWords
  using SafeMath for uint256;

  ERC20Mintable private tokenAddress;
  uint256 private votingLength = 10 minutes;
  uint256 private quorumTokensPercentage;
  uint256 private proposerAmount; // the amount the proposer has staked to submit the tweet
  uint256 bonusMultipler = 10000000000;

  struct Proposal {
    address proposer;
    uint256 startTime;
    bool open;
    mapping(address => uint256) noVotes;
    mapping(address => uint256) yesVotes;

    uint256 noTotal;
    uint256 yesTotal;
    uint256 bonus;

    bool yesWon;
    bool quorumPassed;
  }

  mapping(bytes32 => Proposal) public uuidToProposals;


  // Events
  event ProposalCreated(bytes32 id, address proposer);
  event ProposalFailed(bytes32 id, address proposer);
  event VoteLogged(bytes32 id, address voter, uint256 amount, bool yes);
  event ProposalClosed(bytes32 id, bool quorumPassed, bool yesWon, uint256 bonus);
  event Claim(address withdrawerAddress, uint256 tokenSum);

  /// @param _tokenAddress Address of ERC20 token contract
  /// @param _quorumTokensPercentage Percentage of tokens needed to reach quorum
  /// @param _proposerAmount Number of tokens required to submit a proposed tweet
  constructor(
    address _tokenAddress,
    uint256 _quorumTokensPercentage,
    uint256 _proposerAmount) public {
    tokenAddress = ERC20Mintable(_tokenAddress);
    quorumTokensPercentage = _quorumTokensPercentage;
    proposerAmount = _proposerAmount;
  }

//TODO - propose puts tokens into a yes vote -

  function propose(bytes32 id) external returns (bool success) {
    // Store
    // Add Events
    if(uuidToProposals[id].startTime == 0) { // test if ID does not exist
      if (proposerAmount > 0) {
        tokenAddress.transferFrom(msg.sender, this, proposerAmount);
      }

      uuidToProposals[id] = Proposal({
        proposer: msg.sender, // Added for transparency, not internal usage
        startTime: now,
        open: true,
        noTotal: 0,
        yesTotal: 0,
        bonus: 0,
        yesWon: false,
        quorumPassed: false
      });
      emit ProposalCreated(id, msg.sender);

      return true;
    }
    emit ProposalFailed(id, msg.sender);
    return false;
  }

  function vote(bytes32 id, uint256 amount, bool voteYes) external returns (bool success) {

    if(
      uuidToProposals[id].startTime != 0 &&
      uuidToProposals[id].open &&
      now < uuidToProposals[id].startTime + votingLength &&
      amount > 0
      ){
      tokenAddress.transferFrom(msg.sender, this, amount);

      if(voteYes){
        uuidToProposals[id].yesVotes[msg.sender] = uuidToProposals[id].yesVotes[msg.sender] + amount;
        uuidToProposals[id].yesTotal = uuidToProposals[id].yesTotal + amount;
      } else {
        uuidToProposals[id].noVotes[msg.sender] = uuidToProposals[id].noVotes[msg.sender] + amount;
        uuidToProposals[id].noTotal = uuidToProposals[id].noTotal + amount;
      }
      emit VoteLogged(id, msg.sender, amount, voteYes);
      return true;
    }

    return false;
  }

  function getYesVoteCnt(bytes32 id) external view returns (uint256 count){
    return uuidToProposals[id].yesVotes[msg.sender];
  }

  function getNoVoteCnt(bytes32 id) external view returns (uint256 count) {
    return uuidToProposals[id].noVotes[msg.sender];
  }

//TODO - close is only owner and 1/2 of the tokens to be givenout get sent to a a specified addr

  function close(bytes32 id) external returns (bool success) {
    if(
        uuidToProposals[id].startTime != 0 &&
        uuidToProposals[id].open &&
        uuidToProposals[id].startTime + votingLength < now
      ){
        // 1. Close
        uuidToProposals[id].open = false;

        // 2. Determine winner
        uint256 minTokensRequired = quorumTokensPercentage.mul(tokenAddress.totalSupply()).div(100);

        if((uuidToProposals[id].noTotal + uuidToProposals[id].yesTotal) > minTokensRequired) { // quorum passed
          uuidToProposals[id].quorumPassed = true;
          if(uuidToProposals[id].yesTotal > uuidToProposals[id].noTotal) { // yes votes won
            uuidToProposals[id].bonus = uuidToProposals[id].noTotal.mul(bonusMultipler).div(uuidToProposals[id].yesTotal);
            uuidToProposals[id].yesWon = true;
          } else { //no votes won
            uuidToProposals[id].bonus = uuidToProposals[id].yesTotal.div(uuidToProposals[id].noTotal);
            uuidToProposals[id].yesWon = false;
          }
        }

        emit ProposalClosed(id, uuidToProposals[id].quorumPassed, uuidToProposals[id].yesWon, uuidToProposals[id].bonus);
        return true;
      }
    return false;
  }

  function isProposalOpen(bytes32 id) external view returns (bool isOpen) {
    return uuidToProposals[id].open;
  }

  function getBonusAmount(bytes32 id) external view returns (uint256 bonusAmount) {
    return uuidToProposals[id].bonus;
  }

  function getNoTotal(bytes32 id) external view returns (uint256 noTotal) {
    return uuidToProposals[id].noTotal;
  }

  function getYesTotal(bytes32 id) external view returns (uint256 yesTotal) {
    return uuidToProposals[id].yesTotal;
  }

  function tweetThisID(bytes32 id) external view returns (bool yesWon) {
    uint256 minTokensRequired = quorumTokensPercentage.mul(tokenAddress.totalSupply()).div(100);
    if((uuidToProposals[id].noTotal + uuidToProposals[id].yesTotal) > minTokensRequired &&
      uuidToProposals[id].yesTotal > uuidToProposals[id].noTotal) {
      return true; //yes votes won
    }
    return false;
  }

  function claim(bytes32[] ids) external returns (bool sent) {
    uint256 tokenSum; //TODO memory??

    require(ids.length < 256);

    for (uint8 i = 0; i < ids.length; i++){
      if(uuidToProposals[ids[i]].startTime != 0) {

        if(!uuidToProposals[ids[i]].quorumPassed) {
          tokenSum = tokenSum +
            uuidToProposals[ids[i]].yesVotes[msg.sender] +
            uuidToProposals[ids[i]].noVotes[msg.sender];

            uuidToProposals[ids[i]].yesVotes[msg.sender] = 0;
            uuidToProposals[ids[i]].noVotes[msg.sender] = 0;
        } else if(uuidToProposals[ids[i]].yesWon) {
          tokenSum = tokenSum + // TODO: Move calculation of how much I can claim into a getter, by ID
                    uuidToProposals[ids[i]].yesVotes[msg.sender] +
                    uuidToProposals[ids[i]].bonus.mul(uuidToProposals[ids[i]].yesVotes[msg.sender]).div(bonusMultipler);

          uuidToProposals[ids[i]].yesVotes[msg.sender] = 0;
        } else {
          tokenSum = tokenSum +
                    uuidToProposals[ids[i]].noVotes[msg.sender] +
                    uuidToProposals[ids[i]].bonus.mul(uuidToProposals[ids[i]].noVotes[msg.sender]).div(bonusMultipler);
          uuidToProposals[ids[i]].noVotes[msg.sender] = 0;
        }
      }
    }

    if (tokenSum > 0) {
      tokenAddress.transferFrom(this, msg.sender, tokenSum);
      emit Claim(msg.sender, tokenSum);

      return true;
    }

    return false;
  }
}
