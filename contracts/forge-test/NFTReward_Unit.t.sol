pragma solidity 0.8.6;

import '../JBTieredLimitedNFTRewardDataSource.sol';
import '../interfaces/IJBTieredLimitedNFTRewardDataSource.sol';
import 'forge-std/Test.sol';

contract TestJBTieredNFTRewardDelegate is Test {
  using stdStorage for StdStorage;

  address beneficiary = address(69420);
  address owner = address(42069);
  address mockJBDirectory = address(100);
  address mockTokenUriResolver = address(102);
  address mockContributionToken = address(103);
  address mockTerminalAddress = address(104);

  uint256 projectId = 69;

  string name = 'NAME';
  string symbol = 'SYM';
  string baseUri = 'http://www.null.com';
  string contractUri = 'ipfs://null';

  string[] tokenUris = [
    'http://www.null.com/1',
    'http://www.null.com/2',
    'http://www.null.com/3',
    'http://www.null.com/4',
    'http://www.null.com/5',
    'http://www.null.com/6',
    'http://www.null.com/7',
    'http://www.null.com/8',
    'http://www.null.com/9',
    'http://www.null.com/10'
  ];

  JBNFTRewardTier[] tiers;

  JBTieredLimitedNFTRewardDataSource delegate;

  event Mint(
    uint256 indexed tokenId,
    uint256 indexed tierId,
    address indexed beneficiary,
    uint256 totalAmountContributed,
    uint256 numRewards,
    address caller
  );

  event Burn(uint256 indexed tokenId, address owner, address caller);

  function setUp() public {
    vm.label(beneficiary, 'beneficiary');
    vm.label(owner, 'owner');
    vm.label(mockJBDirectory, 'mockJBDirectory');
    vm.label(mockTokenUriResolver, 'mockTokenUriResolver');
    vm.label(mockContributionToken, 'mockContributionToken');
    vm.label(mockTerminalAddress, 'mockTerminalAddress');

    vm.etch(mockJBDirectory, new bytes(0x69));
    vm.etch(mockTokenUriResolver, new bytes(0x69));
    vm.etch(mockContributionToken, new bytes(0x69));
    vm.etch(mockTerminalAddress, new bytes(0x69));

    // Create 10 tiers, each with 100 tokens available to mint
    for (uint256 i; i < 10; i++) {
      tiers.push(
        JBNFTRewardTier({
          contributionFloor: uint128((i + 1) * 10),
          remainingQuantity: uint40(100),
          initialQuantity: uint40(100),
          votingUnits: uint16(0),
          reservedRate: uint16(0),
          tokenUri: tokenUris[i]
        })
      );
    }

    delegate = new JBTieredLimitedNFTRewardDataSource(
      projectId,
      IJBDirectory(mockJBDirectory),
      name,
      symbol,
      IJBTokenUriResolver(mockTokenUriResolver),
      contractUri,
      owner,
      mockContributionToken,
      tiers,
      false // _shouldMintByDefault
    );
  }

  function testJBTieredNFTRewardDelegate_constructor_deployIfTiersSorted(uint8 nbTiers) public {
    vm.assume(nbTiers < 10);

    // Create new tiers array
    JBNFTRewardTier[] memory _tiers = new JBNFTRewardTier[](nbTiers);
    for (uint256 i; i < nbTiers; i++) {
      _tiers[i] = JBNFTRewardTier({
        contributionFloor: uint128(i * 10),
        remainingQuantity: uint40(100),
        initialQuantity: uint40(100),
        votingUnits: uint16(0),
        reservedRate: uint16(0),
        tokenUri: tokenUris[i]
      });
    }

    JBTieredLimitedNFTRewardDataSource _delegate = new JBTieredLimitedNFTRewardDataSource(
      projectId,
      IJBDirectory(mockJBDirectory),
      name,
      symbol,
      IJBTokenUriResolver(mockTokenUriResolver),
      contractUri,
      owner,
      mockContributionToken,
      _tiers,
      false // _shouldMintByDefault
    );

    // Check: delegate has correct parameters?
    assertEq(_delegate.projectId(), projectId);
    assertEq(address(_delegate.directory()), mockJBDirectory);
    assertEq(_delegate.name(), name);
    assertEq(_delegate.symbol(), symbol);
    assertEq(address(_delegate.tokenUriResolver()), mockTokenUriResolver);
    assertEq(_delegate.contractUri(), contractUri);
    assertEq(_delegate.owner(), owner);
    assertEq(_delegate.contributionToken(), mockContributionToken);
    assertEq(_delegate.allTiers(), _tiers);
  }

  function testJBTieredNFTRewardDelegate_constructor_revertDeploymentIfTiersNonSorted(
    uint8 nbTiers,
    uint8 errorIndex
  ) public {
    vm.assume(nbTiers < 20);
    vm.assume(errorIndex < nbTiers); // Avoid overflow for the next assume
    vm.assume(errorIndex + 1 < nbTiers); // We'll create an error by inverting tiers[i] and [i+1] floor prices

    // Create new tiers array
    JBNFTRewardTier[] memory _tiers = new JBNFTRewardTier[](nbTiers);
    for (uint256 i; i < nbTiers; i++) {
      _tiers[i] = JBNFTRewardTier({
        contributionFloor: uint128(i * 10),
        remainingQuantity: uint40(100),
        initialQuantity: uint40(100),
        votingUnits: uint16(0),
        reservedRate: uint16(0),
        tokenUri: tokenUris[0]
      });
    }

    // Swap the contribution floors
    (_tiers[errorIndex].contributionFloor, _tiers[errorIndex + 1].contributionFloor) = (
      _tiers[errorIndex + 1].contributionFloor,
      _tiers[errorIndex].contributionFloor
    );

    // Expect the error at i+1 (as the floor is now smaller than i)
    vm.expectRevert(abi.encodeWithSignature('INVALID_PRICE_SORT_ORDER()'));
    new JBTieredLimitedNFTRewardDataSource(
      projectId,
      IJBDirectory(mockJBDirectory),
      name,
      symbol,
      IJBTokenUriResolver(mockTokenUriResolver),
      contractUri,
      owner,
      mockContributionToken,
      _tiers,
      false // _shouldMintByDefault
    );
  }

  function testJBTieredNFTRewardDelegate_totalSupply_returnsCorrectTotalSupply() external {
    ForTest_JBTieredLimitedNFTRewardDataSource _delegate = new ForTest_JBTieredLimitedNFTRewardDataSource(
      projectId,
      IJBDirectory(mockJBDirectory),
      name,
      symbol,
      IJBTokenUriResolver(mockTokenUriResolver),
      baseUri,
      contractUri,
      owner,
      mockContributionToken,
      tiers,
      false // _shouldMintByDefault
    );

    uint256 supply;

    // Different remaining allowance to simulate different tiers minted in the same time
    for (uint256 i = 1; i < tiers.length; i++) {
      _delegate.setTier(
        i,
        JBNFTRewardTier({
          contributionFloor: uint128(i * 10),
          remainingQuantity: uint40(i * 10),
          initialQuantity: uint40(100),
          votingUnits: uint16(0),
          reservedRate: uint16(0),
          tokenUri: tokenUris[0]
        })
      );

      supply += 100 - (i * 10);
    }

    assertEq(_delegate.totalSupply(), supply);
  }

  function testJBTieredNFTRewardDelegate_tierNumberOfToken_returnsCorrectTierNumber(
    uint8 _tierId,
    uint8 _tokenNumber
  ) external {
    vm.assume(_tierId > 0 && _tokenNumber > 0);
    uint256 tokenId = _generateTokenId(_tierId, _tokenNumber);

    assertEq(delegate.tierIdOfToken(tokenId), _tierId);
  }

  function testJBTieredNFTRewardDelegate_mint_mintIfCallerIsOwner(uint8 _tierId, uint8 _tokenNumber)
    external
  {
    vm.assume(_tierId > 0 && _tierId < 10);
    vm.assume(_tokenNumber > tiers[_tierId].initialQuantity);

    // Check: correct event
    vm.expectEmit(true, true, true, true, address(delegate));
    emit Mint(_generateTokenId(_tierId, _tokenNumber), _tierId, beneficiary, 0, 1, owner);

    // Actual call
    vm.prank(owner);
    //uint256 tokenId = delegate.mint(beneficiary, _tierId, _tokenNumber);

    // Check: tokenId?
    //assertEq(tokenId, _generateTokenId(_tierId, _tokenNumber));

    // Check: beneficiary balance
   // assertEq(delegate.totalOwnerBalance(beneficiary), 1);
  }

  function testJBTieredNFTRewardDelegate_mint_revertIfCallerIsNotOwner(
    address caller,
    uint32 _tierId,
    uint224 _tokenNumber
  ) external {
    vm.assume(caller != owner);

    vm.prank(caller);
    //vm.expectRevert(abi.encodePacked('Ownable: caller is not the owner'));
    //delegate.mint(beneficiary, _tierId, _tokenNumber);
  }

  function FixMEJBTieredNFTRewardDelegate_burn_burnIfCallerIsOwner(uint8 _tierId, uint8 _tokenNumber)
    external
  {
    vm.assume(_tierId > 0 && _tierId < 10);
    vm.assume(_tokenNumber > tiers[_tierId].initialQuantity);

    vm.prank(owner);
    //uint256 tokenId = delegate.mint(beneficiary, _tierId, _tokenNumber);

    // Check: correct event
    vm.expectEmit(true, false, false, true, address(delegate));
    //emit Burn(tokenId, beneficiary, owner);

    // Actual call
    vm.prank(owner);
    //delegate.burn(beneficiary, _generateTokenId(_tierId, _tokenNumber));

    // Check: allowance left - back to the original one (tiers are 1-indexed)
    assertEq(
      delegate.allTiers()[_tierId - 1].remainingQuantity,
      tiers[_tierId - 1].remainingQuantity
    );

    // Check: beneficiary balance
    //assertEq(delegate.totalOwnerBalance(beneficiary), 0);
  }

  function testJBTieredNFTRewardDelegate_burn_revertIfCallerIsNotOwner(
    address caller,
    uint8 _tierId,
    uint8 _tokenNumber
  ) external {
    vm.assume(caller != owner);
    vm.assume(_tierId > 0 && _tierId < 10);
    vm.assume(_tokenNumber > tiers[_tierId].initialQuantity);

    vm.prank(owner);
    //uint256 tokenId = delegate.mint(beneficiary, _tierId, _tokenNumber);

    vm.prank(caller);
    vm.expectRevert(abi.encodePacked('Ownable: caller is not the owner'));
   //delegate.burn(beneficiary, _generateTokenId(_tierId, _tokenNumber));
  }

  // Part of ERC721 now:
  //function testJBTieredNFTRewardDelegate_burn_revertIfTokenIsNotExisting(uint256 _tokenId);

  // If the amount payed is below the contributionFloor to receive an NFT the pay should not revert
  function testJBTieredNFTRewardDelegate_didPay_doesNotRevertOnAmountBelowContributionFloor()
    external
  {
    // Mock the directory call
    vm.mockCall(
      address(mockJBDirectory),
      abi.encodeWithSelector(IJBDirectory.isTerminalOf.selector, projectId, mockTerminalAddress),
      abi.encode(true)
    );

    uint256 _totalSupplyBeforePay = delegate.totalSupply();

    // The calldata is correct but the 'msg.sender' is not the '_expectedCaller'
    vm.prank(mockTerminalAddress);
    delegate.didPay(
      JBDidPayData(
        msg.sender,
        projectId,
        0,
        JBTokenAmount(mockContributionToken, tiers[0].contributionFloor - 1, 0, 0), // 1 wei below the minimum amount
        0,
        msg.sender,
        false,
        '',
        new bytes(0)
      )
    );

    // Make sure no new NFT was minted
    assertEq(_totalSupplyBeforePay, delegate.totalSupply());
  }

  // function testJBTieredNFTRewardDelegate_didPay_revertIfAllowanceRunsOut() external {
  //   // Create 10 tiers, each with 10 tokens available to mint
  //   for (uint256 i; i < 10; i++) {
  //     tiers.push(JBNFTRewardTier({
  //       contributionFloor: uint128((i + 1) * 10),
  //       remainingQuantity: uint40(10),
  //       initialQuantity: uint40(10),
  //       tokenUri: tokenUris[i]
  //     }));
  //   }

  //   // Mock the directory call
  //   vm.mockCall(
  //     address(mockJBDirectory),
  //     abi.encodeWithSelector(IJBDirectory.isTerminalOf.selector, projectId, mockTerminalAddress),
  //     abi.encode(true)
  //   );

  //   uint256 _supplyLeft = tiers[0].initialQuantity;
  //   while (true) {
  //     uint256 _totalSupplyBeforePay = delegate.totalSupply();

  //     // If there is no supply left this should revert
  //     if (_supplyLeft == 0) {
  //       vm.expectRevert(abi.encodeWithSignature('NOT_AVAILABLE()'));
  //     }

  //     uint256 _metadata;
  //     _metadata |= 1 << 32; // 1 reward
  //     _metadata |= 1 << 40; // tier 1

  //     // Perform the pay
  //     vm.prank(mockTerminalAddress);
  //     delegate.didPay(
  //       JBDidPayData(
  //         msg.sender,
  //         projectId,
  //         0,
  //         JBTokenAmount(mockContributionToken, tiers[0].contributionFloor, 0, 0),
  //         0,
  //         msg.sender,
  //         false,
  //         '',
  //         abi.encode(_metadata)
  //       )
  //     );

  //     // Make sure if there was no supply left there was no NFT minted
  //     if (_supplyLeft == 0) {
  //       assertEq(delegate.totalSupply(), _totalSupplyBeforePay);
  //       break;
  //     } else {
  //       assertEq(delegate.totalSupply(), _totalSupplyBeforePay + 1);
  //     }

  //     --_supplyLeft;
  //   }
  // }

  function testJBTieredNFTRewardDelegate_didPay_revertIfCallerIsNotATerminalOfProjectId(
    address _terminal
  ) external {
    vm.assume(_terminal != mockTerminalAddress);

    // Mock the directory call
    vm.mockCall(
      address(mockJBDirectory),
      abi.encodeWithSelector(IJBDirectory.isTerminalOf.selector, projectId, _terminal),
      abi.encode(false)
    );

    // The caller is the _expectedCaller however the terminal in the calldata is not correct
    vm.prank(_terminal);
    vm.expectRevert(abi.encodeWithSignature('INVALID_PAYMENT_EVENT()'));
    delegate.didPay(
      JBDidPayData(
        msg.sender,
        projectId,
        0,
        JBTokenAmount(address(0), 0, 0, 0),
        0,
        msg.sender,
        false,
        '',
        new bytes(0)
      )
    );
  }

  // Internal helpers

  // JBNFTRewardTier Array comparison
  function assertEq(JBNFTRewardTier[] memory first, JBNFTRewardTier[] memory second) private {
    assertEq(first.length, second.length);

    for (uint256 i; i < first.length; i++) {
      assertEq(first[i].contributionFloor, second[i].contributionFloor);
      // assertEq(first[i].idCeiling, second[i].idCeiling);
      assertEq(first[i].remainingQuantity, second[i].remainingQuantity);
      assertEq(first[i].initialQuantity, second[i].initialQuantity);
    }
  }

  // Generate tokenId's based on token number and tier
  function _generateTokenId(uint256 _tierId, uint256 _tokenNumber)
    internal
    returns (uint256 tokenId)
  {
    // The tier ID in the first 8 bits.
    tokenId = _tierId;

    // The token number in the rest.
    tokenId |= _tokenNumber << 8;
  }
}

// ForTest to manually set a tier at a given tiers index
contract ForTest_JBTieredLimitedNFTRewardDataSource is JBTieredLimitedNFTRewardDataSource {
  constructor(
    uint256 _projectId,
    IJBDirectory _directory,
    string memory _name,
    string memory _symbol,
    IJBTokenUriResolver _tokenUriResolver,
    string memory _baseUri,
    string memory _contractUri,
    address _owner,
    address _contributionToken,
    JBNFTRewardTier[] memory __tiers,
    bool _shouldMintByDefault
  )
    JBTieredLimitedNFTRewardDataSource(
      _projectId,
      _directory,
      _name,
      _symbol,
      _tokenUriResolver,
      _contractUri,
      _owner,
      _contributionToken,
      __tiers,
      _shouldMintByDefault
    )
  {}

  function setTier(uint256 index, JBNFTRewardTier calldata newTier) public {
    tiers[index] = newTier;
  }
}
