pragma solidity ^0.4.18;

import "./SafeMath.sol";
import "./OpportyToken.sol";
import "./Pausable.sol";
import "./OpportyWhiteListHold.sol";
import "./OpportyWhiteList.sol";

contract OpportySaleBonus is Ownable {
  using SafeMath for uint256;

  uint private startDate;

  /* bonus from time */
  uint private firstBonusPhase;
  uint private firstExtraBonus;
  uint private secondBonusPhase;
  uint private secondExtraBonus;
  uint private thirdBonusPhase;
  uint private thirdExtraBonus;
  uint private fourBonusPhase;
  uint private fourExtraBonus;
  uint private fifthBonusPhase;
  uint private fifthExtraBonus;
  uint private sixthBonusPhase;
  uint private sixthExtraBonus;

  /**
  * @dev constructor
  * 20% '1st 24 hours'
  * 15% '2-4 days'
  * 12% '5-9 days'
  * 10% '10-14 days'
  * 8%  '15-19 days'
  * 5%  '20-24 days'
  * 0%  '25-28 days'
  */
  function OpportySaleBonus(uint _startDate) public {
    startDate = _startDate;

    firstBonusPhase   = startDate.add(1 days);
    firstExtraBonus   = 20;
    secondBonusPhase  = startDate.add(4 days);
    secondExtraBonus  = 15;
    thirdBonusPhase   = startDate.add(9 days);
    thirdExtraBonus   = 12;
    fourBonusPhase    = startDate.add(14 days);
    fourExtraBonus    = 10;
    fifthBonusPhase   = startDate.add(19 days);
    fifthExtraBonus   = 8;
    sixthBonusPhase   = startDate.add(24 days);
    sixthExtraBonus   = 5;
  }

  /**
 * @dev Calculate bonus for hours
 * @return token bonus
 */
  function calculateBonusForHours(uint256 _tokens) public view returns(uint256) {
    if (now >= startDate && now <= firstBonusPhase ) {
      return _tokens.mul(firstExtraBonus).div(100);
    } else
    if (now <= secondBonusPhase ) {
      return _tokens.mul(secondExtraBonus).div(100);
    } else
    if (now <= thirdBonusPhase ) {
      return _tokens.mul(thirdExtraBonus).div(100);
    } else
    if (now <= fourBonusPhase ) {
      return _tokens.mul(fourExtraBonus).div(100);
    } else
    if (now <= fifthBonusPhase ) {
      return _tokens.mul(fifthExtraBonus).div(100);
    } else
    if (now <= sixthBonusPhase ) {
      return _tokens.mul(sixthExtraBonus).div(100);
    } else
    return 0;
  }

  function changeStartDate(uint _date) public onlyOwner {
    startDate = _date;
    firstBonusPhase   = startDate.add(1 days);
    secondBonusPhase  = startDate.add(4 days);
    thirdBonusPhase   = startDate.add(9 days);
    fourBonusPhase    = startDate.add(14 days);
    fifthBonusPhase   = startDate.add(19 days);
    sixthBonusPhase   = startDate.add(24 days);
  }

  /**
 * @dev return current bonus percent
 */
  function getBonus() public constant returns (uint) {
    if (now >= startDate && now <= firstBonusPhase ) {
      return firstExtraBonus;
    } else
    if ( now <= secondBonusPhase ) {
      return secondExtraBonus;
    } else
    if ( now <= thirdBonusPhase ) {
      return thirdExtraBonus;
    } else
    if ( now <= fourBonusPhase ) {
      return fourExtraBonus;
    } else
    if ( now <= fifthBonusPhase ) {
      return fifthExtraBonus;
    } else
    if ( now <= sixthBonusPhase ) {
      return sixthExtraBonus;
    } else
    return 0;
  }

}

contract OpportySale is Pausable {

  using SafeMath for uint256;

  OpportyToken public token;

  // minimum goal ETH
  uint private SOFTCAP;
  // maximum goal ETH
  uint private HARDCAP;

  // start and end timestamps where investments are allowed
  uint private startDate;
  uint private endDate;

  uint private price;

  // total ETH collected
  uint private ethRaised;
  // total token sales
  uint private totalTokens;
  // how many tokens sent to investors
  uint private withdrawedTokens;
  // minimum ETH investment amount
  uint minimalContribution;

  bool releasedTokens;

  // address where funds are collected
  address public wallet;
  // address where funds will be frozen
  OpportyWhiteListHold public holdContract;
  OpportyWhiteList private presale;
  OpportySaleBonus private bonus;

  //minimum of tokens that must be on the contract for the start
  uint private minimumTokensToStart = 150000000 * (10 ** 18);

  struct ContributorData {
    bool isActive;
    uint contributionAmount;// total ETH
    uint tokensIssued;// total token
    uint bonusAmount;// total bonus token
  }

  enum SaleState  { NEW, SALE, ENDED }
  SaleState private state;

  mapping(address => ContributorData) public contributorList;
  uint private nextContributorIndex;
  uint private nextContributorToClaim;
  uint private nextContributorToTransferTokens;

  mapping(uint => address) private contributorIndexes;
  mapping(address => bool) private hasClaimedEthWhenFail; //address who got a refund
  mapping(address => bool) private hasWithdrawedTokens; //address who got a tokens

  /* Events */
  event CrowdsaleStarted(uint blockNumber);
  event CrowdsaleEnded(uint blockNumber);
  event SoftCapReached(uint blockNumber);
  event HardCapReached(uint blockNumber);
  event FundTransfered(address contrib, uint amount);
  event TokensTransfered(address contributor , uint amount);
  event Refunded(address ref, uint amount);
  event ErrorSendingETH(address to, uint amount);
  event WithdrawedEthToWallet(uint amount);
  event ManualChangeStartDate(uint beforeDate, uint afterDate);
  event ManualChangeEndDate(uint beforeDate, uint afterDate);
  event TokensTransferedToHold(address hold, uint amount);
  event TokensTransferedToOwner(address hold, uint amount);
  event ChangeMinAmount(uint oldMinAmount, uint minAmount);
  event ChangePreSale(address preSale);

  function OpportySale(
    address tokenAddress,
    address walletAddress,
    uint start,
    uint end,
    address holdCont,
    address presaleCont) public
  {
    token = OpportyToken(tokenAddress);
    state = SaleState.NEW;
    SOFTCAP   = 1000 * 1 ether;
    HARDCAP   = 50000 * 1 ether;
    price     = 0.0002 * 1 ether;
    startDate = start;
    endDate   = end;
    minimalContribution = 0.3 * 1 ether;
    releasedTokens = false;

    wallet = walletAddress;
    holdContract = OpportyWhiteListHold(holdCont);
    presale = OpportyWhiteList(presaleCont);
    bonus   = new OpportySaleBonus(start);
  }

  /* Setters */

  function setStartDate(uint date) public onlyOwner {
    require(state == SaleState.NEW);
    require(date < endDate);
    uint oldStartDate = startDate;
    startDate = date;
    bonus.changeStartDate(date);
    ManualChangeStartDate(oldStartDate, date);
  }
  function setEndDate(uint date) public onlyOwner {
    require(state == SaleState.NEW || state == SaleState.SALE);
    require(date > now && date > startDate);
    uint oldEndDate = endDate;
    endDate = date;
    ManualChangeEndDate(oldEndDate, date);
  }
  function setSoftCap(uint softCap) public onlyOwner {
    require(state == SaleState.NEW);
    SOFTCAP = softCap;
  }
  function setHardCap(uint hardCap) public onlyOwner {
    require(state == SaleState.NEW);
    HARDCAP = hardCap;
  }
  function setMinimalContribution(uint minimumAmount) public onlyOwner {
    uint oldMinAmount = minimalContribution;
    minimalContribution = minimumAmount;
    ChangeMinAmount(oldMinAmount, minimalContribution);
  }
  function setPreSale(address preSaleAddress) public onlyOwner {
    require(preSaleAddress != 0x0);
    presale = OpportyWhiteList(preSaleAddress);
    ChangePreSale(preSaleAddress);
  }

  /* The function without name is the default function that is called whenever anyone sends funds to a contract */
  function() whenNotPaused public payable {
    require(msg.value != 0);

    if (state == SaleState.ENDED) {
      revert();
    }

    bool chstate = checkCrowdsaleState();

    if (state == SaleState.SALE) {
      processTransaction(msg.sender, msg.value);
    }
    else {
      refundTransaction(chstate);
    }
  }

  /**
   * @dev Checks if the goal or time limit has been reached and ends the campaign
   * @return false when contract does not accept tokens
   */
  function checkCrowdsaleState() internal returns (bool){
    if (getEthRaised() >= HARDCAP && state != SaleState.ENDED) {
      state = SaleState.ENDED;
      HardCapReached(block.number); // Close the crowdsale
      CrowdsaleEnded(block.number);
      return true;
    }

    if(now > startDate && now <= endDate) {
      if (state == SaleState.SALE && checkBalanceContract() >= minimumTokensToStart ) {
        return true;
      }
    } else {
      if (state != SaleState.ENDED && now > endDate) {
        state = SaleState.ENDED;
        CrowdsaleEnded(block.number);
        return true;
      }
    }
    return false;
  }

  /**
   * @dev Token purchase
   */
  function processTransaction(address _contributor, uint _amount) internal {

    require(msg.value >= minimalContribution);

    uint maxContribution = calculateMaxContribution();
    uint contributionAmount = _amount;
    uint returnAmount = 0;

    if (maxContribution < _amount) {
      contributionAmount = maxContribution;
      returnAmount = _amount - maxContribution;
    }
    uint ethrai = getEthRaised() ;
    if (ethrai + contributionAmount >= SOFTCAP && SOFTCAP > ethrai) {
      SoftCapReached(block.number);
    }

    if (contributorList[_contributor].isActive == false) {
      contributorList[_contributor].isActive = true;
      contributorList[_contributor].contributionAmount = contributionAmount;
      contributorIndexes[nextContributorIndex] = _contributor;
      nextContributorIndex++;
    } else {
      contributorList[_contributor].contributionAmount += contributionAmount;
    }

    ethRaised += contributionAmount;

    FundTransfered(_contributor, contributionAmount);

    uint tokenAmount  = contributionAmount.div(price);
    uint timeBonus    = bonus.calculateBonusForHours(tokenAmount);

    if (tokenAmount > 0) {
      contributorList[_contributor].tokensIssued += tokenAmount.add(timeBonus);
      contributorList[_contributor].bonusAmount += timeBonus;
      totalTokens += tokenAmount.add(timeBonus);
    }

    if (returnAmount != 0) {
      _contributor.transfer(returnAmount);
    }
  }

  /**
   * @dev It is necessary for a correct change of status in the event of completion of the campaign.
   * @param _stateChanged if true transfer ETH back
   */
  function refundTransaction(bool _stateChanged) internal {
    if (_stateChanged) {
      msg.sender.transfer(msg.value);
    } else{
      revert();
    }
  }

  /**
   * @dev transfer remains tokens after the completion of crowdsale
   */
  function releaseTokens() public onlyOwner {
    require (state == SaleState.ENDED);

    uint cbalance = checkBalanceContract();

    require (cbalance != 0);
    require (withdrawedTokens >= totalTokens || getEthRaised() < SOFTCAP);

    if (getEthRaised() >= SOFTCAP) {
      if (releasedTokens == true) {
        if (token.transfer(msg.sender, cbalance ) ) {
          TokensTransferedToOwner(msg.sender , cbalance );
        }
      } else {
        if (token.transfer(holdContract, cbalance ) ) {
          holdContract.addHolder(msg.sender, cbalance, 1, endDate.add(182 days) );
          releasedTokens = true;
          TokensTransferedToHold(holdContract , cbalance );
        }
      }
    } else {
      if (token.transfer(msg.sender, cbalance) ) {
        TokensTransferedToOwner(msg.sender , cbalance );
      }
    }
  }

  function checkBalanceContract() internal view returns (uint) {
    return token.balanceOf(this);
  }

  /**
   * @dev if crowdsale is successful, investors can claim token here
   */
  function getTokens() public whenNotPaused {
    uint er =  getEthRaised();
    require((now > endDate && er >= SOFTCAP )  || ( er >= HARDCAP)  );
    require(state == SaleState.ENDED);
    require(contributorList[msg.sender].tokensIssued > 0);
    require(!hasWithdrawedTokens[msg.sender]);

    uint tokenCount = contributorList[msg.sender].tokensIssued;

    if (token.transfer(msg.sender, tokenCount * (10 ** 18) )) {
      TokensTransfered(msg.sender , tokenCount * (10 ** 18) );
      withdrawedTokens += tokenCount;
      hasWithdrawedTokens[msg.sender] = true;
    }

  }
  function batchReturnTokens(uint _numberOfReturns) public onlyOwner whenNotPaused {
    uint er = getEthRaised();
    require((now > endDate && er >= SOFTCAP )  || (er >= HARDCAP)  );
    require(state == SaleState.ENDED);

    address currentParticipantAddress;
    uint tokensCount;

    for (uint cnt = 0; cnt < _numberOfReturns; cnt++) {
      currentParticipantAddress = contributorIndexes[nextContributorToTransferTokens];
      if (currentParticipantAddress == 0x0) return;
      if (!hasWithdrawedTokens[currentParticipantAddress]) {
        tokensCount = contributorList[currentParticipantAddress].tokensIssued;
        hasWithdrawedTokens[currentParticipantAddress] = true;
        if (token.transfer(currentParticipantAddress, tokensCount * (10 ** 18))) {
          TokensTransfered(currentParticipantAddress, tokensCount * (10 ** 18));
          withdrawedTokens += tokensCount;
          hasWithdrawedTokens[msg.sender] = true;
        }
      }
      nextContributorToTransferTokens += 1;
    }

  }

  /**
   * @dev if crowdsale is unsuccessful, investors can claim refunds here
   */
  function refund() public whenNotPaused {
    require(now > endDate && getEthRaised() < SOFTCAP);
    require(contributorList[msg.sender].contributionAmount > 0);
    require(!hasClaimedEthWhenFail[msg.sender]);

    uint ethContributed = contributorList[msg.sender].contributionAmount;
    hasClaimedEthWhenFail[msg.sender] = true;
    if (!msg.sender.send(ethContributed)) {
      ErrorSendingETH(msg.sender, ethContributed);
    } else {
      Refunded(msg.sender, ethContributed);
    }
  }
  function batchReturnEthIfFailed(uint _numberOfReturns) public onlyOwner whenNotPaused {
    require(now > endDate && getEthRaised() < SOFTCAP);
    address currentParticipantAddress;
    uint contribution;
    for (uint cnt = 0; cnt < _numberOfReturns; cnt++) {
      currentParticipantAddress = contributorIndexes[nextContributorToClaim];
      if (currentParticipantAddress == 0x0) return;
      if (!hasClaimedEthWhenFail[currentParticipantAddress]) {
        contribution = contributorList[currentParticipantAddress].contributionAmount;
        hasClaimedEthWhenFail[currentParticipantAddress] = true;

        if (!currentParticipantAddress.send(contribution)){
          ErrorSendingETH(currentParticipantAddress, contribution);
        } else {
          Refunded(currentParticipantAddress, contribution);
        }
      }
      nextContributorToClaim += 1;
    }
  }

  /**
   * @dev transfer funds ETH to multisig wallet if reached minimum goal
   */
  function withdrawEth() public {
    require(this.balance != 0);
    require(getEthRaised() >= SOFTCAP);
    require(msg.sender == wallet);
    uint bal = this.balance;
    wallet.transfer(bal);
    WithdrawedEthToWallet(bal);
  }

  function withdrawRemainingBalanceForManualRecovery() public onlyOwner {
    require(this.balance != 0);
    require(now > endDate);
    require(contributorIndexes[nextContributorToClaim] == 0x0);
    msg.sender.transfer(this.balance);
  }

  /**
   * @dev Manual start crowdsale.
   */
  function startCrowdsale() public onlyOwner  {
    require(now > startDate && now <= endDate);
    require(state == SaleState.NEW);
    require(checkBalanceContract() >= minimumTokensToStart);

    state = SaleState.SALE;
    CrowdsaleStarted(block.number);
  }

  /* Getters */

  function getAccountsNumber() public constant returns (uint) {
    return nextContributorIndex;
  }

  function getEthRaised() public constant returns (uint) {
    uint pre = presale.getEthRaised();
    return pre + ethRaised;
  }

  function getTokensTotal() public constant returns (uint) {
    return totalTokens;
  }

  function getWithdrawedToken() public constant returns (uint) {
    return withdrawedTokens;
  }

  function calculateMaxContribution() public constant returns (uint) {
    return HARDCAP - getEthRaised();
  }

  function getSoftCap() public constant returns(uint) {
    return SOFTCAP;
  }

  function getHardCap() public constant returns(uint) {
    return HARDCAP;
  }

  function getSaleStatus() public constant returns (uint) {
    return uint(state);
  }

  function getStartDate() public constant returns (uint) {
    return startDate;
  }

  function getEndDate() public constant returns (uint) {
    return endDate;
  }

  // @return true if crowdsale event has ended
  function hasEnded() public constant returns (bool) {
    return now > endDate || state == SaleState.ENDED;
  }

  function getTokenBalance() public constant returns (uint) {
    return token.balanceOf(this);
  }

  /**
   * @dev return current bonus percent
   */
  function getCurrentBonus() public constant returns (uint) {
    if(now > endDate || state == SaleState.ENDED) {
      return 0;
    }
    return bonus.getBonus();
  }
}
