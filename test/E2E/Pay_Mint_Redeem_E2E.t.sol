// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "lib/juice-address-registry/src/JBAddressRegistry.sol";

import "src/JB721TiersHook.sol";
import "src/JB721TiersHookProjectDeployer.sol";
import "src/JB721TiersHookDeployer.sol";
import "src/JB721TiersHookStore.sol";

import "../utils/TestBaseWorkflow.sol";
import "src/interfaces/IJB721TiersHook.sol";
import {MetadataResolverHelper} from "lib/juice-contracts-v4/test/helpers/MetadataResolverHelper.sol";

contract Test_TiersHook_E2E is TestBaseWorkflow {
    using JBRulesetMetadataResolver for JBRuleset;

    address reserveBeneficiary = address(bytes20(keccak256("reserveBeneficiary")));

    JB721TiersHook hook;

    MetadataResolverHelper metadataHelper;

    event Mint(
        uint256 indexed tokenId,
        uint256 indexed tierId,
        address indexed beneficiary,
        uint256 totalAmountPaid,
        address caller
    );
    event Burn(uint256 indexed tokenId, address owner, address caller);

    string name = "NAME";
    string symbol = "SYM";
    string baseUri = "http://www.null.com/";
    string contractUri = "ipfs://null";
    //QmWmyoMoctfbAaiEs2G46gpeUmhqFRDW6KWo64y5r581Vz
    bytes32[] tokenUris = [
        bytes32(0x7D5A99F603F231D53A4F39D1521F98D2E8BB279CF29BEBFD0687DC98458E7F89),
        bytes32(0x7D5A99F603F231D53A4F39D1521F98D2E8BB279CF29BEBFD0687DC98458E7F89),
        bytes32(0x7D5A99F603F231D53A4F39D1521F98D2E8BB279CF29BEBFD0687DC98458E7F89),
        bytes32(0x7D5A99F603F231D53A4F39D1521F98D2E8BB279CF29BEBFD0687DC98458E7F89),
        bytes32(0x7D5A99F603F231D53A4F39D1521F98D2E8BB279CF29BEBFD0687DC98458E7F89),
        bytes32(0x7D5A99F603F231D53A4F39D1521F98D2E8BB279CF29BEBFD0687DC98458E7F89),
        bytes32(0x7D5A99F603F231D53A4F39D1521F98D2E8BB279CF29BEBFD0687DC98458E7F89),
        bytes32(0x7D5A99F603F231D53A4F39D1521F98D2E8BB279CF29BEBFD0687DC98458E7F89),
        bytes32(0x7D5A99F603F231D53A4F39D1521F98D2E8BB279CF29BEBFD0687DC98458E7F89),
        bytes32(0x7D5A99F603F231D53A4F39D1521F98D2E8BB279CF29BEBFD0687DC98458E7F89)
    ];

    JB721TiersHookProjectDeployer deployer;
    JBAddressRegistry addressRegistry;

    function setUp() public override {
        super.setUp();
        hook = new JB721TiersHook(jbDirectory, jbPermissions);
        addressRegistry = new JBAddressRegistry();
        JB721TiersHookDeployer hookDeployer = new JB721TiersHookDeployer(hook, addressRegistry);
        deployer =
            new JB721TiersHookProjectDeployer(IJBDirectory(jbDirectory), IJBPermissions(jbPermissions), hookDeployer);

        metadataHelper = new MetadataResolverHelper();
    }

    function testLaunchProjectAndAddHookToRegistry() external {
        (JBDeploy721TiersHookConfig memory tiersHookConfig, JBLaunchProjectConfig memory launchProjectConfig) =
            createData();
        uint256 projectId = deployer.launchProjectFor(projectOwner, tiersHookConfig, launchProjectConfig, jbController);
        // Check: is the first project's ID 1?
        assertEq(projectId, 1);
        // Check: was the hook added to the address registry?
        address dataHook = jbRulesets.currentOf(projectId).dataHook();
        assertEq(addressRegistry.deployerOf(dataHook), address(deployer.HOOK_DEPLOYER()));
    }

    function testMintOnPayIfOneTierIsPassed(uint256 valueSent) external {
        valueSent = bound(valueSent, 10, 2000);
        // Cap the highest tier ID possible to 10.
        uint256 highestTier = valueSent <= 100 ? (valueSent / 10) : 10;
        (JBDeploy721TiersHookConfig memory tiersHookConfig, JBLaunchProjectConfig memory launchProjectConfig) =
            createData();
        uint256 projectId = deployer.launchProjectFor(projectOwner, tiersHookConfig, launchProjectConfig, jbController);

        // Crafting the payment metadata: add the highest tier ID.
        uint16[] memory rawMetadata = new uint16[](1);
        rawMetadata[0] = uint16(highestTier);

        // Build the metadata using the tiers to mint and the overspending flag.
        bytes[] memory data = new bytes[](1);
        data[0] = abi.encode(true, rawMetadata);

        address dataHook = jbRulesets.currentOf(projectId).dataHook();

        // Pass the hook ID.
        bytes4[] memory ids = new bytes4[](1);
        ids[0] = bytes4(bytes20(address(dataHook)));

        // Generate the metadata.
        bytes memory hookMetadata = metadataHelper.createMetadata(ids, data);

        // Check: was an NFT with the correct tier ID and token ID minted?
        vm.expectEmit(true, true, true, true);
        emit Mint(
            _generateTokenId(highestTier, 1),
            highestTier,
            beneficiary,
            valueSent,
            address(jbMultiTerminal) // msg.sender
        );

        // Pay the terminal to mint the NFTs.
        vm.prank(caller);
        jbMultiTerminal.pay{value: valueSent}({
            projectId: projectId,
            amount: 100,
            token: JBConstants.NATIVE_TOKEN,
            beneficiary: beneficiary,
            minReturnedTokens: 0,
            memo: "Take my money!",
            metadata: hookMetadata
        });
        uint256 tokenId = _generateTokenId(highestTier, 1);
        // Check: did the beneficiary receive the NFT?
        if (valueSent < 10) {
            assertEq(IERC721(dataHook).balanceOf(beneficiary), 0);
        } else {
            assertEq(IERC721(dataHook).balanceOf(beneficiary), 1);
        }

        // Check: is the beneficiary the first owner of the NFT?
        assertEq(IERC721(dataHook).ownerOf(tokenId), beneficiary);
        assertEq(IJB721TiersHook(dataHook).firstOwnerOf(tokenId), beneficiary);

        // Check: after a transfer, are the `firstOwnerOf` and `ownerOf` still correct?
        vm.prank(beneficiary);
        IERC721(dataHook).transferFrom(beneficiary, address(696_969_420), tokenId);
        assertEq(IERC721(dataHook).ownerOf(tokenId), address(696_969_420));
        assertEq(IJB721TiersHook(dataHook).firstOwnerOf(tokenId), beneficiary);

        // Check: is the same true after a second transfer?
        vm.prank(address(696_969_420));
        IERC721(dataHook).transferFrom(address(696_969_420), address(123_456_789), tokenId);
        assertEq(IERC721(dataHook).ownerOf(tokenId), address(123_456_789));
        assertEq(IJB721TiersHook(dataHook).firstOwnerOf(tokenId), beneficiary);
    }

    function testMintOnPayIfMultipleTiersArePassed() external {
        (JBDeploy721TiersHookConfig memory tiersHookConfig, JBLaunchProjectConfig memory launchProjectConfig) =
            createData();
        uint256 projectId = deployer.launchProjectFor(projectOwner, tiersHookConfig, launchProjectConfig, jbController);

        // Prices of the first 5 tiers (10 * `tierId`)
        uint256 amountNeeded = 50 + 40 + 30 + 20 + 10;
        uint16[] memory rawMetadata = new uint16[](5);

        // Mint one NFT per tier from the first 5 tiers.
        for (uint256 i = 0; i < 5; i++) {
            rawMetadata[i] = uint16(i + 1); // Start at `tierId` 1.
            // Check: correct tier IDs and token IDs?
            vm.expectEmit(true, true, true, true);
            emit Mint(
                _generateTokenId(i + 1, 1),
                i + 1,
                beneficiary,
                amountNeeded,
                address(jbMultiTerminal) // `msg.sender`
            );
        }

        // Build the metadata using the tiers to mint and the overspending flag.
        bytes[] memory data = new bytes[](1);
        data[0] = abi.encode(true, rawMetadata);

        address dataHook = jbRulesets.currentOf(projectId).dataHook();

        // Pass the hook ID.
        bytes4[] memory ids = new bytes4[](1);
        ids[0] = bytes4(bytes20(address(dataHook)));

        // Generate the metadata.
        bytes memory hookMetadata = metadataHelper.createMetadata(ids, data);

        // Pay the terminal to mint the NFTs.
        vm.prank(caller);
        jbMultiTerminal.pay{value: amountNeeded}({
            projectId: projectId,
            amount: amountNeeded,
            token: JBConstants.NATIVE_TOKEN,
            beneficiary: beneficiary,
            minReturnedTokens: 0,
            memo: "Take my money!",
            metadata: hookMetadata
        });

        // Check: were the NFTs actually received?
        assertEq(IERC721(dataHook).balanceOf(beneficiary), 5);
        for (uint256 i = 1; i <= 5; i++) {
            uint256 tokenId = _generateTokenId(i, 1);
            assertEq(IJB721TiersHook(dataHook).firstOwnerOf(tokenId), beneficiary);
            // Check: are `firstOwnerOf` and `ownerOf` correct after a transfer?
            vm.prank(beneficiary);
            IERC721(dataHook).transferFrom(beneficiary, address(696_969_420), tokenId);
            assertEq(IERC721(dataHook).ownerOf(tokenId), address(696_969_420));
            assertEq(IJB721TiersHook(dataHook).firstOwnerOf(tokenId), beneficiary);
        }
    }

    function testNoMintOnPayWhenNotIncludingTierIds(uint256 valueSent) external {
        valueSent = bound(valueSent, 10, 2000);
        (JBDeploy721TiersHookConfig memory tiersHookConfig, JBLaunchProjectConfig memory launchProjectConfig) =
            createData();
        uint256 projectId = deployer.launchProjectFor(projectOwner, tiersHookConfig, launchProjectConfig, jbController);

        address dataHook = jbRulesets.currentOf(projectId).dataHook();

        // Build the metadata with no tiers specified and the overspending flag.
        bool allowOverspending = true;
        uint16[] memory rawMetadata = new uint16[](0);
        bytes memory metadata =
            abi.encode(bytes32(0), bytes32(0), type(IJB721TiersHook).interfaceId, allowOverspending, rawMetadata);

        // Pay the terminal and pass the metadata.
        vm.prank(caller);
        jbMultiTerminal.pay{value: valueSent}({
            projectId: projectId,
            amount: 100,
            token: JBConstants.NATIVE_TOKEN,
            beneficiary: beneficiary,
            minReturnedTokens: 0,
            memo: "Take my money!",
            metadata: metadata
        });

        // Ensure that no NFT was minted.
        assertEq(IERC721(dataHook).balanceOf(beneficiary), 0);

        // Ensure the beneficiary received pay credits (since no NFTs were minted).
        assertEq(IJB721TiersHook(dataHook).payCreditsOf(beneficiary), valueSent);
    }

    function testNoMintOnPayWhenNotIncludingMetadata(uint256 valueSent) external {
        valueSent = bound(valueSent, 10, 2000);
        (JBDeploy721TiersHookConfig memory tiersHookConfig, JBLaunchProjectConfig memory launchProjectConfig) =
            createData();
        uint256 projectId = deployer.launchProjectFor(projectOwner, tiersHookConfig, launchProjectConfig, jbController);
        address dataHook = jbRulesets.currentOf(projectId).dataHook();

        // Pay the terminal with empty metadata (`bytes(0)`).
        vm.prank(caller);
        jbMultiTerminal.pay{value: valueSent}({
            projectId: projectId,
            amount: 100,
            token: JBConstants.NATIVE_TOKEN,
            beneficiary: beneficiary,
            minReturnedTokens: 0,
            memo: "Take my money!",
            metadata: new bytes(0)
        });

        // Ensure that no NFTs were minted.
        assertEq(IERC721(dataHook).balanceOf(beneficiary), 0);

        // Ensure that the beneficiary received pay credits (since no NFTs were minted).
        assertEq(IJB721TiersHook(dataHook).payCreditsOf(beneficiary), valueSent);
    }

    function testMintReservedNft(uint256 valueSent) external {
        // cheapest tier is worth 10
        valueSent = bound(valueSent, 10, 20 ether);

        // Cap the highest tier ID possible to 10.
        uint256 highestTier = valueSent <= 100 ? valueSent / 10 : 10;

        (JBDeploy721TiersHookConfig memory tiersHookConfig, JBLaunchProjectConfig memory launchProjectConfig) =
            createData();
        uint256 projectId = deployer.launchProjectFor(projectOwner, tiersHookConfig, launchProjectConfig, jbController);
        address dataHook = jbRulesets.currentOf(projectId).dataHook();

        // Check: Ensure no pending reserves at start (since no minting has happened).
        assertEq(IJB721TiersHook(dataHook).STORE().numberOfPendingReservesFor(dataHook, highestTier), 0);

        // Check: cannot mint pending reserves (since none should be pending)?
        vm.expectRevert(abi.encodeWithSelector(JB721TiersHookStore.INSUFFICIENT_PENDING_RESERVES.selector));
        vm.prank(projectOwner);
        IJB721TiersHook(dataHook).mintPendingReservesFor(highestTier, 1);

        // Crafting the payment metadata: add the highest tier ID.
        uint16[] memory rawMetadata = new uint16[](1);
        rawMetadata[0] = uint16(highestTier);

        // Build the metadata using the tiers to mint and the overspending flag.
        bytes[] memory data = new bytes[](1);
        data[0] = abi.encode(true, rawMetadata);

        // Pass the hook ID.
        bytes4[] memory ids = new bytes4[](1);
        ids[0] = bytes4(bytes20(address(dataHook)));

        // Generate the metadata.
        bytes memory hookMetadata = metadataHelper.createMetadata(ids, data);

        // Check: were an NFT with the correct tier ID and token ID minted?
        vm.expectEmit(true, true, true, true);
        emit Mint(
            _generateTokenId(highestTier, 1), // First one
            highestTier,
            beneficiary,
            valueSent,
            address(jbMultiTerminal) // msg.sender
        );

        // Pay the terminal to mint the NFTs.
        vm.prank(caller);
        jbMultiTerminal.pay{value: valueSent}({
            projectId: projectId,
            amount: 100,
            token: JBConstants.NATIVE_TOKEN,
            beneficiary: beneficiary,
            minReturnedTokens: 0,
            memo: "Take my money!",
            metadata: hookMetadata
        });

        // Check: is there now 1 pending reserve? 1 mint should yield 1 pending reserve, due to rounding up.
        assertEq(IJB721TiersHook(dataHook).STORE().numberOfPendingReservesFor(dataHook, highestTier), 1);

        JB721Tier memory tierBeforeMintingReserves =
            JB721TiersHook(dataHook).STORE().tierOf(dataHook, highestTier, false);

        // Mint the pending reserve NFT.
        vm.prank(projectOwner);
        IJB721TiersHook(dataHook).mintPendingReservesFor(highestTier, 1);
        // Check: did the reserve beneficiary receive the NFT?
        assertEq(IERC721(dataHook).balanceOf(reserveBeneficiary), 1);

        JB721Tier memory tierAfterMintingReserves =
            JB721TiersHook(dataHook).STORE().tierOf(dataHook, highestTier, false);
        // The tier's remaining supply should have decreased by 1.
        assertLt(tierAfterMintingReserves.remainingSupply, tierBeforeMintingReserves.remainingSupply);

        // Check: there should now be 0 pending reserves.
        assertEq(IJB721TiersHook(dataHook).STORE().numberOfPendingReservesFor(dataHook, highestTier), 0);
        // Check: it should not be possible to mint pending reserves now (since there are none left).
        vm.expectRevert(abi.encodeWithSelector(JB721TiersHookStore.INSUFFICIENT_PENDING_RESERVES.selector));
        vm.prank(projectOwner);
        IJB721TiersHook(dataHook).mintPendingReservesFor(highestTier, 1);
    }

    // - Mint an NFT.
    // - Check the number of pending reserve mints available within that NFT's tier, which should be non-zero due to
    // rounding up.
    // - Burn an NFT from that tier.
    // - Check the number of pending reserve mints available within the NFT's tier again.
    // This number should be back to 0, since the NFT was burned.
    function testRedeemToken(uint256 valueSent) external {
        valueSent = bound(valueSent, 10, 2000);

        // Cap the highest tier ID possible to 10.
        uint256 highestTier = valueSent <= 100 ? (valueSent / 10) : 10;
        (JBDeploy721TiersHookConfig memory tiersHookConfig, JBLaunchProjectConfig memory launchProjectConfig) =
            createData();
        uint256 projectId = deployer.launchProjectFor(projectOwner, tiersHookConfig, launchProjectConfig, jbController);

        // Craft the metadata: buy 1 NFT from the highest tier.
        bytes memory hookMetadata;
        bytes[] memory data;
        bytes4[] memory ids;
        address dataHook = jbRulesets.currentOf(projectId).dataHook();
        {
            uint16[] memory rawMetadata = new uint16[](1);
            rawMetadata[0] = uint16(highestTier);

            // Build the metadata using the tiers to mint and the overspending flag.
            data = new bytes[](1);
            data[0] = abi.encode(true, rawMetadata);

            // Pass the hook ID.
            ids = new bytes4[](1);
            ids[0] = bytes4(bytes20(address(dataHook)));

            // Generate the metadata.
            hookMetadata = metadataHelper.createMetadata(ids, data);
        }

        // Pay the terminal to mint the NFTs.
        vm.prank(caller);
        jbMultiTerminal.pay{value: valueSent}({
            projectId: projectId,
            amount: 100,
            token: JBConstants.NATIVE_TOKEN,
            beneficiary: beneficiary,
            minReturnedTokens: 0,
            memo: "Take my money!",
            metadata: hookMetadata
        });

        {
            // Get the token ID of the NFT that was minted.
            uint256 tokenId = _generateTokenId(highestTier, 1);

            // Craft the metadata: redeem the `tokenId` which was minted.
            uint256[] memory redemptionId = new uint256[](1);
            redemptionId[0] = tokenId;

            // Build the metadata with the tiers to redeem.
            data[0] = abi.encode(redemptionId);

            // Pass the hook ID.
            ids[0] = bytes4(bytes20(address(dataHook)));

            // Generate the metadata.
            hookMetadata = metadataHelper.createMetadata(ids, data);
        }

        // Get the new NFT balance of the beneficiary.
        uint256 nftBalance = IERC721(dataHook).balanceOf(beneficiary);

        // Redeem the NFT.
        vm.prank(beneficiary);
        jbMultiTerminal.redeemTokensOf({
            holder: beneficiary,
            projectId: projectId,
            tokenToReclaim: JBConstants.NATIVE_TOKEN,
            redeemCount: 0,
            minTokensReclaimed: 0,
            beneficiary: payable(beneficiary),
            metadata: hookMetadata
        });

        // Check: was the beneficiary's NFT balance decreased by 1?
        assertEq(IERC721(dataHook).balanceOf(beneficiary), nftBalance - 1);

        // Check: was the burn accounted for in the store?
        assertEq(IJB721TiersHook(dataHook).STORE().numberOfBurnedFor(dataHook, highestTier), 1);

        // Determine whether we are rounding up or not (used to verify `numberOfPendingReservesFor` below).
        uint256 rounding;
        {
            JB721Tier memory tier = IJB721TiersHook(dataHook).STORE().tierOf(dataHook, highestTier, false);
            // `reserveTokensMinted` is 0 here
            uint256 numberOfNonReservesMinted = tier.initialSupply - tier.remainingSupply;
            rounding = numberOfNonReservesMinted % tier.reserveFrequency > 0 ? 1 : 0;
        }

        // Check: the number of pending reserves should be equal to the calculated figure which accounts for rounding.
        assertEq(
            IJB721TiersHook(dataHook).STORE().numberOfPendingReservesFor(dataHook, highestTier),
            (nftBalance / tiersHookConfig.tiersConfig.tiers[highestTier - 1].reserveFrequency + rounding)
        );
    }

    // - Mint 5 NFTs from a tier.
    // - Check the remaining supply within that NFT's tier. (highest tier == 10, reserved rate is maximum -> 5)
    // - Burn all of the corresponding token from that tier
    function testRedeemAll() external {
        (JBDeploy721TiersHookConfig memory tiersHookConfig, JBLaunchProjectConfig memory launchProjectConfig) =
            createData();
        uint256 tier = 10;
        uint256 tierPrice = tiersHookConfig.tiersConfig.tiers[tier - 1].price;
        uint256 projectId = deployer.launchProjectFor(projectOwner, tiersHookConfig, launchProjectConfig, jbController);

        // Craft the metadata: buy 5 NFTs from tier 10.
        uint16[] memory rawMetadata = new uint16[](5);
        for (uint256 i; i < rawMetadata.length; i++) {
            rawMetadata[i] = uint16(tier);
        }

        // Build the metadata using the tiers to mint and the overspending flag.
        bytes[] memory data = new bytes[](1);
        data[0] = abi.encode(true, rawMetadata);

        address dataHook = jbRulesets.currentOf(projectId).dataHook();

        // Pass the hook ID.
        bytes4[] memory ids = new bytes4[](1);
        ids[0] = bytes4(bytes20(address(dataHook)));

        // Generate the metadata.
        bytes memory hookMetadata = metadataHelper.createMetadata(ids, data);

        // Pay the terminal to mint the NFTs.
        vm.prank(caller);
        jbMultiTerminal.pay{value: tierPrice * rawMetadata.length}({
            projectId: projectId,
            amount: 100,
            token: JBConstants.NATIVE_TOKEN,
            beneficiary: beneficiary,
            minReturnedTokens: 0,
            memo: "Take my money!",
            metadata: hookMetadata
        });

        // Get the beneficiary's new NFT balance.
        uint256 nftBalance = IERC721(dataHook).balanceOf(beneficiary);
        // Check: how many pending reserve mints are available for the tier?
        uint256 pendingReserves = IJB721TiersHook(dataHook).STORE().numberOfPendingReservesFor(dataHook, tier);
        // Check: are the NFT balance and pending reserves correct?
        assertEq(rawMetadata.length, nftBalance);
        // Add 1 to the pending reserves check, as we round up for non-null values.
        assertEq(pendingReserves, (nftBalance / tiersHookConfig.tiersConfig.tiers[tier - 1].reserveFrequency) + 1);
        // Craft the metadata to redeem the `tokenId`s.
        uint256[] memory redemptionId = new uint256[](5);
        for (uint256 i; i < rawMetadata.length; i++) {
            uint256 tokenId = _generateTokenId(tier, i + 1);
            redemptionId[i] = tokenId;
        }

        // Build the metadata with the tiers to redeem.
        data[0] = abi.encode(redemptionId);

        // Pass the hook ID.
        ids[0] = bytes4(bytes20(address(dataHook)));

        // Generate the metadata.
        hookMetadata = metadataHelper.createMetadata(ids, data);

        // Redeem the NFTs.
        vm.prank(beneficiary);
        jbMultiTerminal.redeemTokensOf({
            holder: beneficiary,
            projectId: projectId,
            tokenToReclaim: JBConstants.NATIVE_TOKEN,
            redeemCount: 0,
            minTokensReclaimed: 0,
            beneficiary: payable(beneficiary),
            metadata: hookMetadata
        });

        // Check: did the beneficiary's NFT balance decrease by 5 (to 0)?
        assertEq(IERC721(dataHook).balanceOf(beneficiary), 0);
        // Check: were the NFT burns accounted for in the store?
        assertEq(IJB721TiersHook(dataHook).STORE().numberOfBurnedFor(dataHook, tier), 5);
        // Check: did the number of pending reserves return to 0?
        assertEq(IJB721TiersHook(dataHook).STORE().numberOfPendingReservesFor(dataHook, tier), 0);

        // Build the metadata using the tiers to mint and the overspending flag.
        data[0] = abi.encode(true, rawMetadata);

        // Pass the hook ID.
        ids[0] = bytes4(bytes20(address(dataHook)));

        // Generate the metadata.
        hookMetadata = metadataHelper.createMetadata(ids, data);

        // Check: can more NFTs be minted (now that the previous ones were burned)?
        vm.prank(caller);
        jbMultiTerminal.pay{value: tierPrice * rawMetadata.length}({
            projectId: projectId,
            amount: 100,
            token: JBConstants.NATIVE_TOKEN,
            beneficiary: beneficiary,
            minReturnedTokens: 0,
            memo: "Take my money!",
            metadata: hookMetadata
        });

        // Get the new NFT balance.
        nftBalance = IERC721(dataHook).balanceOf(beneficiary);
        // The number of pending reserves should be equal to the previously calculated figure which accounts for
        // rounding.
        pendingReserves = IJB721TiersHook(dataHook).STORE().numberOfPendingReservesFor(dataHook, tier);
        // Check: are the NFT balance and pending reserves correct?
        assertEq(rawMetadata.length, nftBalance);
        // Add 1 to the pending reserves check, as we round up for non-null values.
        assertEq(pendingReserves, (nftBalance / tiersHookConfig.tiersConfig.tiers[tier - 1].reserveFrequency) + 1);
    }

    // ----- internal helpers ------
    // Creates a `launchProjectFor(...)` payload.
    function createData()
        internal
        returns (JBDeploy721TiersHookConfig memory tiersHookConfig, JBLaunchProjectConfig memory launchProjectConfig)
    {
        JB721TierConfig[] memory tierConfigs = new JB721TierConfig[](10);
        for (uint256 i; i < 10; i++) {
            tierConfigs[i] = JB721TierConfig({
                price: uint104((i + 1) * 10),
                initialSupply: uint32(10),
                votingUnits: uint32((i + 1) * 10),
                reserveFrequency: 10,
                reserveBeneficiary: reserveBeneficiary,
                encodedIPFSUri: tokenUris[i],
                category: uint24(100),
                allowOwnerMint: false,
                useReserveBeneficiaryAsDefault: false,
                transfersPausable: false,
                useVotingUnits: false,
                cannotBeRemoved: false
            });
        }
        tiersHookConfig = JBDeploy721TiersHookConfig({
            name: name,
            symbol: symbol,
            rulesets: jbRulesets,
            baseUri: baseUri,
            tokenUriResolver: IJB721TokenUriResolver(address(0)),
            contractUri: contractUri,
            tiersConfig: JB721InitTiersConfig({
                tiers: tierConfigs,
                currency: uint32(uint160(JBConstants.NATIVE_TOKEN)),
                decimals: 18,
                prices: IJBPrices(address(0))
            }),
            reserveBeneficiary: reserveBeneficiary,
            store: new JB721TiersHookStore(),
            flags: JB721TiersHookFlags({
                preventOverspending: false,
                noNewTiersWithReserves: false,
                noNewTiersWithVotes: false,
                noNewTiersWithOwnerMinting: true
            })
        });

        JBPayDataHookRulesetMetadata memory metadata = JBPayDataHookRulesetMetadata({
            reservedRate: 5000, //50%
            redemptionRate: 5000, //50%
            baseCurrency: uint32(uint160(JBConstants.NATIVE_TOKEN)),
            pausePay: false,
            pauseCreditTransfers: false,
            allowOwnerMinting: true,
            allowTerminalMigration: false,
            allowSetTerminals: false,
            allowControllerMigration: false,
            allowSetController: false,
            holdFees: false,
            useTotalSurplusForRedemptions: false,
            useDataHookForRedeem: true,
            metadata: 0x00
        });

        JBPayDataHookRulesetConfig[] memory rulesetConfigurations = new JBPayDataHookRulesetConfig[](1);
        // Package up the ruleset configuration.
        rulesetConfigurations[0].mustStartAtOrAfter = 0;
        rulesetConfigurations[0].duration = 14;
        rulesetConfigurations[0].weight = 1000 * 10 ** 18;
        rulesetConfigurations[0].decayRate = 450_000_000;
        rulesetConfigurations[0].approvalHook = IJBRulesetApprovalHook(address(0));
        rulesetConfigurations[0].metadata = metadata;

        JBTerminalConfig[] memory terminalConfigurations = new JBTerminalConfig[](1);
        address[] memory tokensToAccept = new address[](1);
        tokensToAccept[0] = JBConstants.NATIVE_TOKEN;
        terminalConfigurations[0] = JBTerminalConfig({terminal: jbMultiTerminal, tokensToAccept: tokensToAccept});

        launchProjectConfig = JBLaunchProjectConfig({
            projectUri: projectUri,
            rulesetConfigurations: rulesetConfigurations,
            terminalConfigurations: terminalConfigurations,
            memo: ""
        });
    }

    // Generate `tokenId`s based on the tier ID and token number provided.
    function _generateTokenId(uint256 tierId, uint256 tokenNumber) internal pure returns (uint256) {
        return (tierId * 1_000_000_000) + tokenNumber;
    }
}
