// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import "../utils/UnitTestSetup.sol";

contract TestJuice721dDelegate_afterPayRecordedWith_Unit is UnitTestSetup {
    using stdStorage for StdStorage;

    function test721TiersHook_afterPayRecorded_mintCorrectAmountsAndReserved(
        uint256 initialSupply,
        uint256 nftsToMint,
        uint256 reserveFrequency
    )
        public
    {
        initialSupply = 400;
        reserveFrequency = bound(reserveFrequency, 0, 200);
        nftsToMint = bound(nftsToMint, 1, 200);

        defaultTierConfig.initialSupply = uint32(initialSupply);
        defaultTierConfig.reserveFrequency = uint16(reserveFrequency);
        ForTest_JB721TiersHook hook = _initializeForTestHook(1); // Initialize with 1 default tier.

        // Mock the directory call.
        mockAndExpect(
            address(mockJBDirectory),
            abi.encodeWithSelector(IJBDirectory.isTerminalOf.selector, projectId, mockTerminalAddress),
            abi.encode(true)
        );

        uint16[] memory tierIdsToMint = new uint16[](nftsToMint);

        for (uint256 i; i < nftsToMint; i++) {
            tierIdsToMint[i] = uint16(1);
        }

        // Build the metadata using the tiers to mint and the overspending flag.
        bytes[] memory data = new bytes[](1);
        data[0] = abi.encode(false, tierIdsToMint);

        // Pass the hook ID.
        bytes4[] memory ids = new bytes4[](1);
        ids[0] = bytes4(bytes20(address(hook)));

        // Generate the metadata.
        bytes memory hookMetadata = metadataHelper.createMetadata(ids, data);

        JBAfterPayRecordedContext memory payContext = JBAfterPayRecordedContext({
            payer: beneficiary,
            projectId: projectId,
            rulesetId: 0,
            amount: JBTokenAmount(
                JBConstants.NATIVE_TOKEN, 10 * nftsToMint, 18, uint32(uint160(JBConstants.NATIVE_TOKEN))
                ),
            forwardedAmount: JBTokenAmount(JBConstants.NATIVE_TOKEN, 0, 18, uint32(uint160(JBConstants.NATIVE_TOKEN))), // 0, forwarded to the hook.
            weight: 10 ** 18,
            projectTokenCount: 0,
            beneficiary: beneficiary,
            hookMetadata: bytes(""),
            payerMetadata: hookMetadata
        });

        vm.prank(mockTerminalAddress);
        hook.afterPayRecordedWith(payContext);

        assertEq(hook.balanceOf(beneficiary), nftsToMint);

        if (reserveFrequency > 0 && initialSupply - nftsToMint > 0) {
            uint256 _reservedToken = nftsToMint / reserveFrequency;
            if (nftsToMint % reserveFrequency > 0) _reservedToken += 1;

            assertEq(hook.STORE().numberOfPendingReservesFor(address(hook), 1), _reservedToken);

            vm.prank(owner);
            hook.mintPendingReservesFor(1, _reservedToken);
            assertEq(hook.balanceOf(reserveBeneficiary), _reservedToken);
        } else {
            assertEq(hook.balanceOf(reserveBeneficiary), 0);
        }
    }

    // If the amount paid is less than the NFT's price, the payment should revert if overspending is not allowed and no metadata was passed.
    function test721TiersHook_afterPayRecorded_doesRevertOnAmountBelowPriceIfNoMetadataIfPreventOverspending(
    )
        public
    {
        JB721TiersHook hook = _initHookDefaultTiers(10, true);

        // Mock the directory call.
        mockAndExpect(
            address(mockJBDirectory),
            abi.encodeWithSelector(IJBDirectory.isTerminalOf.selector, projectId, mockTerminalAddress),
            abi.encode(true)
        );

        vm.expectRevert(abi.encodeWithSelector(JB721TiersHook.OVERSPENDING.selector));

        vm.prank(mockTerminalAddress);
        hook.afterPayRecordedWith(
            JBAfterPayRecordedContext({
                payer: msg.sender,
                projectId: projectId,
                rulesetId: 0,
                // 1 wei below the minimum amount
                amount: JBTokenAmount(JBConstants.NATIVE_TOKEN, tiers[0].price - 1, 18, uint32(uint160(JBConstants.NATIVE_TOKEN))), 
                forwardedAmount: JBTokenAmount(JBConstants.NATIVE_TOKEN, 0, 18, uint32(uint160(JBConstants.NATIVE_TOKEN))), // 0, forwarded to the hook.
                weight: 10 ** 18,
                projectTokenCount: 0,
                beneficiary: msg.sender,
                hookMetadata: new bytes(0),
                payerMetadata: new bytes(0)
            })
        );
    }

    // If the amount paid is less than the NFT's price, the payment should not revert if overspending is allowed and no metadata was passed.
    function test721TiersHook_afterPayRecorded_doesNotRevertOnAmountBelowPriceIfNoMetadata() public {
        // Mock the directory call.
        mockAndExpect(
            address(mockJBDirectory),
            abi.encodeWithSelector(IJBDirectory.isTerminalOf.selector, projectId, mockTerminalAddress),
            abi.encode(true)
        );

        vm.prank(mockTerminalAddress);
        hook.afterPayRecordedWith(
            JBAfterPayRecordedContext({
                payer: msg.sender,
                projectId: projectId,
                rulesetId: 0,
                // 1 wei below the minimum amount
                amount: JBTokenAmount(JBConstants.NATIVE_TOKEN, tiers[0].price - 1, 18, uint32(uint160(JBConstants.NATIVE_TOKEN))), 
                forwardedAmount: JBTokenAmount(JBConstants.NATIVE_TOKEN, 0, 18, uint32(uint160(JBConstants.NATIVE_TOKEN))), // 0, forwarded to the hook.
                weight: 10 ** 18,
                projectTokenCount: 0,
                beneficiary: msg.sender,
                hookMetadata: new bytes(0),
                payerMetadata: new bytes(0)
            })
        );

        assertEq(hook.payCreditsOf(msg.sender), tiers[0].price - 1);
    }

    // If a tier is passed and the amount paid exceeds that NFT's price, mint as many NFTs as possible.
    function test721TiersHook_afterPayRecorded_mintCorrectTier() public {
        // Mock the directory call.
        mockAndExpect(
            address(mockJBDirectory),
            abi.encodeWithSelector(IJBDirectory.isTerminalOf.selector, projectId, mockTerminalAddress),
            abi.encode(true)
        );

        uint256 totalSupplyBeforePay = hook.STORE().totalSupplyOf(address(hook));

        bool allowOverspending;
        uint16[] memory tierIdsToMint = new uint16[](3);
        tierIdsToMint[0] = 1;
        tierIdsToMint[1] = 1;
        tierIdsToMint[2] = 2;

        // Build the metadata using the tiers to mint and the overspending flag.
        bytes[] memory data = new bytes[](1);
        data[0] = abi.encode(allowOverspending, tierIdsToMint);

        // Pass the hook ID.
        bytes4[] memory ids = new bytes4[](1);
        ids[0] = bytes4(bytes20(address(hook)));

        // Generate the metadata.
        bytes memory hookMetadata = metadataHelper.createMetadata(ids, data);
        vm.prank(mockTerminalAddress);
        hook.afterPayRecordedWith(
            JBAfterPayRecordedContext({
                payer: msg.sender,
                projectId: projectId,
                rulesetId: 0,
                amount: JBTokenAmount(JBConstants.NATIVE_TOKEN, tiers[0].price * 2 + tiers[1].price, 18, uint32(uint160(JBConstants.NATIVE_TOKEN))),
                forwardedAmount: JBTokenAmount(JBConstants.NATIVE_TOKEN, 0, 18, uint32(uint160(JBConstants.NATIVE_TOKEN))), // 0, forwarded to the hook.
                weight: 10 ** 18,
                projectTokenCount: 0,
                beneficiary: msg.sender,
                hookMetadata: new bytes(0),
                payerMetadata: hookMetadata
            })
        );

        // Make sure a new NFT was minted.
        assertEq(totalSupplyBeforePay + 3, hook.STORE().totalSupplyOf(address(hook)));

        // Check: has the correct number of NFTs been minted in each tier?
        assertEq(hook.ownerOf(_generateTokenId(1, 1)), msg.sender);
        assertEq(hook.ownerOf(_generateTokenId(1, 2)), msg.sender);
        assertEq(hook.ownerOf(_generateTokenId(2, 1)), msg.sender);
    }

    // If no tiers are passed, no NFTs should be minted.
    function test721TiersHook_afterPayRecorded_mintNoneIfNonePassed(uint8 amount) public {
        // Mock the directory call.
        mockAndExpect(
            address(mockJBDirectory),
            abi.encodeWithSelector(IJBDirectory.isTerminalOf.selector, projectId, mockTerminalAddress),
            abi.encode(true)
        );

        uint256 totalSupplyBeforePay = hook.STORE().totalSupplyOf(address(hook));

        bool allowOverspending = true;
        uint16[] memory tierIdsToMint = new uint16[](0);
        bytes memory metadata =
            abi.encode(bytes32(0), bytes32(0), type(IJB721TiersHook).interfaceId, allowOverspending, tierIdsToMint);

        vm.prank(mockTerminalAddress);
        hook.afterPayRecordedWith(
            JBAfterPayRecordedContext({
                payer: msg.sender,
                projectId: projectId,
                rulesetId: 0,
                amount: JBTokenAmount(JBConstants.NATIVE_TOKEN, amount, 18, uint32(uint160(JBConstants.NATIVE_TOKEN))),
                forwardedAmount: JBTokenAmount(JBConstants.NATIVE_TOKEN, 0, 18, uint32(uint160(JBConstants.NATIVE_TOKEN))), // 0, forwarded to the hook.
                weight: 10 ** 18,
                projectTokenCount: 0,
                beneficiary: msg.sender,
                hookMetadata: new bytes(0),
                payerMetadata: metadata
            })
        );

        // Make sure no new NFTs were minted.
        assertEq(totalSupplyBeforePay, hook.STORE().totalSupplyOf(address(hook)));
    }

    function test721TiersHook_afterPayRecorded_mintTierAndTrackLeftover() public {
        uint256 leftover = tiers[0].price - 1;
        uint256 amount = tiers[0].price + leftover;

        // Mock the directory call.
        mockAndExpect(
            address(mockJBDirectory),
            abi.encodeWithSelector(IJBDirectory.isTerminalOf.selector, projectId, mockTerminalAddress),
            abi.encode(true)
        );

        bool allowOverspending = true;
        uint16[] memory tierIdsToMint = new uint16[](1);
        tierIdsToMint[0] = uint16(1);

        // Build the metadata using the tiers to mint and the overspending flag.
        bytes[] memory data = new bytes[](1);
        data[0] = abi.encode(allowOverspending, tierIdsToMint);

        // Pass the hook ID.
        bytes4[] memory ids = new bytes4[](1);
        ids[0] = bytes4(bytes20(address(hook)));

        // Generate the metadata.
        bytes memory hookMetadata = metadataHelper.createMetadata(ids, data);

        // Calculate the new pay credits.
        uint256 newPayCredits = leftover + hook.payCreditsOf(beneficiary);

        vm.expectEmit(true, true, true, true, address(hook));
        emit AddPayCredits(newPayCredits, newPayCredits, beneficiary, mockTerminalAddress);

        vm.prank(mockTerminalAddress);
        hook.afterPayRecordedWith(
            JBAfterPayRecordedContext({
                payer: msg.sender,
                projectId: projectId,
                rulesetId: 0,
                amount: JBTokenAmount(JBConstants.NATIVE_TOKEN, amount, 18, uint32(uint160(JBConstants.NATIVE_TOKEN))),
                forwardedAmount: JBTokenAmount(JBConstants.NATIVE_TOKEN, 0, 18, uint32(uint160(JBConstants.NATIVE_TOKEN))), // 0, forwarded to the hook.
                weight: 10 ** 18,
                projectTokenCount: 0,
                beneficiary: beneficiary,
                hookMetadata: new bytes(0),
                payerMetadata: hookMetadata
            })
        );

        // Check: has the pay credit balance been updated appropriately?
        assertEq(hook.payCreditsOf(beneficiary), leftover);
    }

    // Mint various tiers, leaving leftovers, and use the resulting pay credits to mint more NFTs.
    function test721TiersHook_afterPayRecorded_mintCorrectTiersWhenUsingPartialCredits() public {
        uint256 leftover = tiers[0].price + 1; // + 1 to avoid rounding error
        uint256 amount = tiers[0].price * 2 + tiers[1].price + leftover / 2;

        // Mock the directory call.
        mockAndExpect(
            address(mockJBDirectory),
            abi.encodeWithSelector(IJBDirectory.isTerminalOf.selector, projectId, mockTerminalAddress),
            abi.encode(true)
        );

        bool allowOverspending = true;
        uint16[] memory tierIdsToMint = new uint16[](3);
        tierIdsToMint[0] = 1;
        tierIdsToMint[1] = 1;
        tierIdsToMint[2] = 2;

        // Build the metadata using the tiers to mint and the overspending flag.
        bytes[] memory data = new bytes[](1);
        data[0] = abi.encode(allowOverspending, tierIdsToMint);

        // Pass the hook ID.
        bytes4[] memory ids = new bytes4[](1);
        ids[0] = bytes4(bytes20(address(hook)));

        // Generate the metadata.
        bytes memory hookMetadata = metadataHelper.createMetadata(ids, data);

        uint256 payCredits = hook.payCreditsOf(beneficiary);

        leftover = leftover / 2 + payCredits; //left over amount

        vm.expectEmit(true, true, true, true, address(hook));
        emit AddPayCredits(leftover - payCredits, leftover, beneficiary, mockTerminalAddress);

        // First call will mint the 3 tiers requested + accumulate half of the first price in pay credits.
        vm.prank(mockTerminalAddress);
        hook.afterPayRecordedWith(
            JBAfterPayRecordedContext({
                payer: beneficiary,
                projectId: projectId,
                rulesetId: 0,
                amount: JBTokenAmount(JBConstants.NATIVE_TOKEN, amount, 18, uint32(uint160(JBConstants.NATIVE_TOKEN))),
                forwardedAmount: JBTokenAmount(JBConstants.NATIVE_TOKEN, 0, 18, uint32(uint160(JBConstants.NATIVE_TOKEN))), // 0, forwarded to the hook.
                weight: 10 ** 18,
                projectTokenCount: 0,
                beneficiary: beneficiary,
                hookMetadata: new bytes(0),
                payerMetadata: hookMetadata
            })
        );

        uint256 totalSupplyBefore = hook.STORE().totalSupplyOf(address(hook));
        {
            // We now attempt to mint an additional NFT from tier 1 using the pay credits we collected.
            uint16[] memory moreTierIdsToMint = new uint16[](4);
            moreTierIdsToMint[0] = 1;
            moreTierIdsToMint[1] = 1;
            moreTierIdsToMint[2] = 2;
            moreTierIdsToMint[3] = 1;

            data[0] = abi.encode(allowOverspending, moreTierIdsToMint);

            // Generate the metadata.
            hookMetadata = metadataHelper.createMetadata(ids, data);
        }

        // Fetch existing credits.
        payCredits = hook.payCreditsOf(beneficiary);
        vm.expectEmit(true, true, true, true, address(hook));
        emit UsePayCredits(
            payCredits,
            0, // No stashed credits.
            beneficiary,
            mockTerminalAddress
        );

        // Second call will mint another 3 tiers requested and mint from the first tier using pay credits.
        vm.prank(mockTerminalAddress);
        hook.afterPayRecordedWith(
            JBAfterPayRecordedContext({
                payer: beneficiary,
                projectId: projectId,
                rulesetId: 0,
                amount: JBTokenAmount(JBConstants.NATIVE_TOKEN, amount, 18, uint32(uint160(JBConstants.NATIVE_TOKEN))),
                forwardedAmount: JBTokenAmount(JBConstants.NATIVE_TOKEN, 0, 18, uint32(uint160(JBConstants.NATIVE_TOKEN))), // 0, forwarded to the hook.
                weight: 10 ** 18,
                projectTokenCount: 0,
                beneficiary: beneficiary,
                hookMetadata: new bytes(0),
                payerMetadata: hookMetadata
            })
        );

        // Check: has the total supply increased?
        assertEq(totalSupplyBefore + 4, hook.STORE().totalSupplyOf(address(hook)));

        // Check: have the correct tiers been minted?
        // ... From the first payment?
        assertEq(hook.ownerOf(_generateTokenId(1, 1)), beneficiary);
        assertEq(hook.ownerOf(_generateTokenId(1, 2)), beneficiary);
        assertEq(hook.ownerOf(_generateTokenId(2, 1)), beneficiary);

        // ... From the second payment?
        assertEq(hook.ownerOf(_generateTokenId(1, 3)), beneficiary);
        assertEq(hook.ownerOf(_generateTokenId(1, 4)), beneficiary);
        assertEq(hook.ownerOf(_generateTokenId(1, 5)), beneficiary);
        assertEq(hook.ownerOf(_generateTokenId(2, 2)), beneficiary);

        // Ensure that no credits are left.
        assertEq(hook.payCreditsOf(beneficiary), 0);
    }

    function test721TiersHook_afterPayRecorded_doNotMintWithSomeoneElseCredit() public {
        uint256 leftover = tiers[0].price + 1; // + 1 to avoid rounding error
        uint256 amount = tiers[0].price * 2 + tiers[1].price + leftover / 2;

        // Mock the directory call.
        mockAndExpect(
            address(mockJBDirectory),
            abi.encodeWithSelector(IJBDirectory.isTerminalOf.selector, projectId, mockTerminalAddress),
            abi.encode(true)
        );

        bool allowOverspending = true;
        uint16[] memory tierIdsToMint = new uint16[](3);
        tierIdsToMint[0] = 1;
        tierIdsToMint[1] = 1;
        tierIdsToMint[2] = 2;

        // Build the metadata using the tiers to mint and the overspending flag.
        bytes[] memory data = new bytes[](1);
        data[0] = abi.encode(allowOverspending, tierIdsToMint);

        // Pass the hook ID.
        bytes4[] memory ids = new bytes4[](1);
        ids[0] = bytes4(bytes20(address(hook)));

        // Generate the metadata.
        bytes memory hookMetadata = metadataHelper.createMetadata(ids, data);

        // The first call will mint the 3 tiers requested and accumulate half of the first price as pay credits.
        vm.prank(mockTerminalAddress);
        hook.afterPayRecordedWith(
            JBAfterPayRecordedContext({
                payer: beneficiary,
                projectId: projectId,
                rulesetId: 0,
                amount: JBTokenAmount(JBConstants.NATIVE_TOKEN, amount, 18, uint32(uint160(JBConstants.NATIVE_TOKEN))),
                forwardedAmount: JBTokenAmount(JBConstants.NATIVE_TOKEN, 0, 18, uint32(uint160(JBConstants.NATIVE_TOKEN))), // 0, forwarded to the hook.
                weight: 10 ** 18,
                projectTokenCount: 0,
                beneficiary: beneficiary,
                hookMetadata: new bytes(0),
                payerMetadata: hookMetadata
            })
        );

        uint256 totalSupplyBefore = hook.STORE().totalSupplyOf(address(hook));
        uint256 payCreditsBefore = hook.payCreditsOf(beneficiary);

        // The second call will mint another 3 tiers requested but NOT with the pay credits.
        vm.prank(mockTerminalAddress);
        hook.afterPayRecordedWith(
            JBAfterPayRecordedContext({
                payer: msg.sender,
                projectId: projectId,
                rulesetId: 0,
                amount: JBTokenAmount(JBConstants.NATIVE_TOKEN, amount, 18, uint32(uint160(JBConstants.NATIVE_TOKEN))),
                forwardedAmount: JBTokenAmount(JBConstants.NATIVE_TOKEN, 0, 18, uint32(uint160(JBConstants.NATIVE_TOKEN))), // 0, forwarded to the hook.
                weight: 10 ** 18,
                projectTokenCount: 0,
                beneficiary: beneficiary,
                hookMetadata: new bytes(0),
                payerMetadata: hookMetadata
            })
        );

        // Check: has the total supply has increased by 3 NFTs?
        assertEq(totalSupplyBefore + 3, hook.STORE().totalSupplyOf(address(hook)));

        // Check: were the correct tiers minted?
        // ... From the first payment?
        assertEq(hook.ownerOf(_generateTokenId(1, 1)), beneficiary);
        assertEq(hook.ownerOf(_generateTokenId(1, 2)), beneficiary);
        assertEq(hook.ownerOf(_generateTokenId(2, 1)), beneficiary);

        // ... From the second payment (without extras from the pay credits)?
        assertEq(hook.ownerOf(_generateTokenId(1, 3)), beneficiary);
        assertEq(hook.ownerOf(_generateTokenId(1, 4)), beneficiary);
        assertEq(hook.ownerOf(_generateTokenId(2, 2)), beneficiary);

        // Check: are pay credits from both payments left over?
        assertEq(hook.payCreditsOf(beneficiary), payCreditsBefore * 2);
    }

    // The terminal uses currency 1 with 18 decimals, and the hook uses currency 2 with 9 decimals.
    // The conversion rate is set at 1:2.
    function test721TiersHook_afterPayRecorded_mintCorrectTierWithAnotherCurrency() public {
        address jbPrice = address(bytes20(keccak256("MockJBPrice")));
        vm.etch(jbPrice, new bytes(1));

        // Currency 2, with 9 decimals.
        JB721TiersHook hook = _initHookDefaultTiers(10, false, 2, 9, jbPrice);

        // Mock the directory call.
        mockAndExpect(
            address(mockJBDirectory),
            abi.encodeWithSelector(IJBDirectory.isTerminalOf.selector, projectId, mockTerminalAddress),
            abi.encode(true)
        );

        // Mock the price oracle call.
        uint256 amountInEth = (tiers[0].price * 2 + tiers[1].price) * 2;
        mockAndExpect(
            jbPrice,
            abi.encodeCall(IJBPrices.pricePerUnitOf, (projectId, uint32(uint160(JBConstants.NATIVE_TOKEN)), 2, 18)),
            abi.encode(2 * 10 ** 9)
        );

        uint256 totalSupplyBeforePay = hook.STORE().totalSupplyOf(address(hook));

        bool allowOverspending = true;
        uint16[] memory tierIdsToMint = new uint16[](3);
        tierIdsToMint[0] = 1;
        tierIdsToMint[1] = 1;
        tierIdsToMint[2] = 2;

        // Build the metadata using the tiers to mint and the overspending flag.
        bytes[] memory data = new bytes[](1);
        data[0] = abi.encode(allowOverspending, tierIdsToMint);

        // Pass the hook ID.
        bytes4[] memory ids = new bytes4[](1);
        ids[0] = bytes4(bytes20(address(hook)));

        // Generate the metadata.
        bytes memory hookMetadata = metadataHelper.createMetadata(ids, data);

        vm.prank(mockTerminalAddress);
        hook.afterPayRecordedWith(
            JBAfterPayRecordedContext({
                payer: msg.sender,
                projectId: projectId,
                rulesetId: 0,
                amount: JBTokenAmount(JBConstants.NATIVE_TOKEN, amountInEth, 18, uint32(uint160(JBConstants.NATIVE_TOKEN))),
                forwardedAmount: JBTokenAmount(JBConstants.NATIVE_TOKEN, 0, 18, uint32(uint160(JBConstants.NATIVE_TOKEN))), // 0, forwarded to the hook.
                weight: 10 ** 18,
                projectTokenCount: 0,
                beneficiary: msg.sender,
                hookMetadata: new bytes(0),
                payerMetadata: hookMetadata
            })
        );

        // Make sure 3 new NFTs were minted.
        assertEq(totalSupplyBeforePay + 3, hook.STORE().totalSupplyOf(address(hook)));

        // Check: have the correct NFT tiers been minted?
        assertEq(hook.ownerOf(_generateTokenId(1, 1)), msg.sender);
        assertEq(hook.ownerOf(_generateTokenId(1, 2)), msg.sender);
        assertEq(hook.ownerOf(_generateTokenId(2, 1)), msg.sender);
    }

    // If the tier has been removed, revert.
    function test721TiersHook_afterPayRecorded_revertIfTierRemoved() public {
        // Mock the directory call.
        mockAndExpect(
            address(mockJBDirectory),
            abi.encodeWithSelector(IJBDirectory.isTerminalOf.selector, projectId, mockTerminalAddress),
            abi.encode(true)
        );

        uint256 totalSupplyBeforePay = hook.STORE().totalSupplyOf(address(hook));

        bool allowOverspending;
        uint16[] memory tierIdsToMint = new uint16[](3);
        tierIdsToMint[0] = 1;
        tierIdsToMint[1] = 1;
        tierIdsToMint[2] = 2;

        // Build the metadata using the tiers to mint and the overspending flag.
        bytes[] memory data = new bytes[](1);
        data[0] = abi.encode(allowOverspending, tierIdsToMint);

        // Pass the hook ID.
        bytes4[] memory ids = new bytes4[](1);
        ids[0] = bytes4(bytes20(address(hook)));

        // Generate the metadata.
        bytes memory hookMetadata = metadataHelper.createMetadata(ids, data);

        uint256[] memory toRemove = new uint256[](1);
        toRemove[0] = 1;

        vm.prank(owner);
        hook.adjustTiers(new JB721TierConfig[](0), toRemove);

        vm.expectRevert(abi.encodeWithSelector(JB721TiersHookStore.TIER_REMOVED.selector));

        vm.prank(mockTerminalAddress);
        hook.afterPayRecordedWith(
            JBAfterPayRecordedContext({
                payer: msg.sender,
                projectId: projectId,
                rulesetId: 0,
                amount: JBTokenAmount(
                    JBConstants.NATIVE_TOKEN,
                    tiers[0].price * 2 + tiers[1].price,
                    18,
                    uint32(uint160(JBConstants.NATIVE_TOKEN))
                    ),
                forwardedAmount: JBTokenAmount(JBConstants.NATIVE_TOKEN, 0, 18, uint32(uint160(JBConstants.NATIVE_TOKEN))), // 0, forwarded to the hook.
                weight: 10 ** 18,
                projectTokenCount: 0,
                beneficiary: msg.sender,
                hookMetadata: new bytes(0),
                payerMetadata: hookMetadata
            })
        );

        // Make sure no new NFTs were minted.
        assertEq(totalSupplyBeforePay, hook.STORE().totalSupplyOf(address(hook)));
    }

    function test721TiersHook_afterPayRecorded_revertIfNonExistingTier(uint256 invalidTier) public {
        invalidTier = bound(invalidTier, tiers.length + 1, type(uint16).max);

        // Mock the directory call.
        mockAndExpect(
            address(mockJBDirectory),
            abi.encodeWithSelector(IJBDirectory.isTerminalOf.selector, projectId, mockTerminalAddress),
            abi.encode(true)
        );

        uint256 totalSupplyBeforePay = hook.STORE().totalSupplyOf(address(hook));

        bool allowOverspending;
        uint16[] memory tierIdsToMint = new uint16[](1);
        tierIdsToMint[0] = uint16(invalidTier);

        // Build the metadata using the tiers to mint and the overspending flag.
        bytes[] memory data = new bytes[](1);
        data[0] = abi.encode(allowOverspending, tierIdsToMint);

        // Pass the hook ID.
        bytes4[] memory ids = new bytes4[](1);
        ids[0] = bytes4(bytes20(address(hook)));

        // Generate the metadata.
        bytes memory hookMetadata = metadataHelper.createMetadata(ids, data);

        uint256[] memory toRemove = new uint256[](1);
        toRemove[0] = 1;

        vm.prank(owner);
        hook.adjustTiers(new JB721TierConfig[](0), toRemove);

        vm.expectRevert(abi.encodeWithSelector(JB721TiersHookStore.INVALID_TIER.selector));

        vm.prank(mockTerminalAddress);
        hook.afterPayRecordedWith(
            JBAfterPayRecordedContext({
                payer: msg.sender,
                projectId: projectId,
                rulesetId: 0,
                amount: JBTokenAmount(
                    JBConstants.NATIVE_TOKEN,
                    tiers[0].price * 2 + tiers[1].price,
                    18,
                    uint32(uint160(JBConstants.NATIVE_TOKEN))
                    ),
                forwardedAmount: JBTokenAmount(JBConstants.NATIVE_TOKEN, 0, 18, uint32(uint160(JBConstants.NATIVE_TOKEN))), // 0, forwarded to the hook.
                weight: 10 ** 18,
                projectTokenCount: 0,
                beneficiary: msg.sender,
                hookMetadata: new bytes(0),
                payerMetadata: hookMetadata
            })
        );

        // Make sure no new NFTs were minted.
        assertEq(totalSupplyBeforePay, hook.STORE().totalSupplyOf(address(hook)));
    }

    // If the amount is not enought to pay for all of the requested tiers, revert.
    function test721TiersHook_afterPayRecorded_revertIfAmountTooLow() public {
        // Mock the directory call.
        mockAndExpect(
            address(mockJBDirectory),
            abi.encodeWithSelector(IJBDirectory.isTerminalOf.selector, projectId, mockTerminalAddress),
            abi.encode(true)
        );

        uint256 totalSupplyBeforePay = hook.STORE().totalSupplyOf(address(hook));

        bool allowOverspending;
        uint16[] memory tierIdsToMint = new uint16[](3);
        tierIdsToMint[0] = 1;
        tierIdsToMint[1] = 1;
        tierIdsToMint[2] = 2;

        // Build the metadata using the tiers to mint and the overspending flag.
        bytes[] memory data = new bytes[](1);
        data[0] = abi.encode(allowOverspending, tierIdsToMint);

        // Pass the hook ID.
        bytes4[] memory ids = new bytes4[](1);
        ids[0] = bytes4(bytes20(address(hook)));

        // Generate the metadata.
        bytes memory hookMetadata = metadataHelper.createMetadata(ids, data);

        vm.expectRevert(abi.encodeWithSelector(JB721TiersHookStore.PRICE_EXCEEDS_AMOUNT.selector));

        vm.prank(mockTerminalAddress);
        hook.afterPayRecordedWith(
            JBAfterPayRecordedContext({
                payer: msg.sender,
                projectId: projectId,
                rulesetId: 0,
                amount: JBTokenAmount(
                    JBConstants.NATIVE_TOKEN,
                    tiers[0].price * 2 + tiers[1].price - 1,
                    18,
                    uint32(uint160(JBConstants.NATIVE_TOKEN))
                    ),
                forwardedAmount: JBTokenAmount(JBConstants.NATIVE_TOKEN, 0, 18, uint32(uint160(JBConstants.NATIVE_TOKEN))), // 0, forwarded to the hook.
                weight: 10 ** 18,
                projectTokenCount: 0,
                beneficiary: msg.sender,
                hookMetadata: new bytes(0),
                payerMetadata: hookMetadata
            })
        );

        // Make sure no new NFTs were minted.
        assertEq(totalSupplyBeforePay, hook.STORE().totalSupplyOf(address(hook)));
    }

    function test721TiersHook_afterPayRecorded_revertIfAllowanceRunsOutInParticularTier() public {
        // Mock the directory call.
        mockAndExpect(
            address(mockJBDirectory),
            abi.encodeWithSelector(IJBDirectory.isTerminalOf.selector, projectId, mockTerminalAddress),
            abi.encode(true)
        );

        uint256 supplyLeft = tiers[0].initialSupply;

        while (true) {
            uint256 totalSupplyBeforePay = hook.STORE().totalSupplyOf(address(hook));

            bool allowOverspending = true;

            uint16[] memory tierSelected = new uint16[](1);
            tierSelected[0] = 1;

            // Build the metadata using the tiers to mint and the overspending flag.
            bytes[] memory data = new bytes[](1);
            data[0] = abi.encode(allowOverspending, tierSelected);

            // Pass the hook ID.
            bytes4[] memory ids = new bytes4[](1);
            ids[0] = bytes4(bytes20(address(hook)));

            // Generate the metadata.
            bytes memory hookMetadata = metadataHelper.createMetadata(ids, data);

            // If there is no remaining supply, this should revert.
            if (supplyLeft == 0) {
                vm.expectRevert(abi.encodeWithSelector(JB721TiersHookStore.INSUFFICIENT_SUPPLY_REMAINING.selector));
            }

            // Execute the payment.
            vm.prank(mockTerminalAddress);
            hook.afterPayRecordedWith(
                JBAfterPayRecordedContext({
                    payer: msg.sender,
                    projectId: projectId,
                    rulesetId: 0,
                    amount: JBTokenAmount(JBConstants.NATIVE_TOKEN, tiers[0].price, 18, uint32(uint160(JBConstants.NATIVE_TOKEN))),
                    forwardedAmount: JBTokenAmount(JBConstants.NATIVE_TOKEN, 0, 18, uint32(uint160(JBConstants.NATIVE_TOKEN))), // 0, forwarded to the hook.
                    weight: 10 ** 18,
                    projectTokenCount: 0,
                    beneficiary: msg.sender,
                    hookMetadata: new bytes(0),
                    payerMetadata: hookMetadata
                })
            );
            // Make sure that if there was no remaining supply, no NFTs were minted.
            if (supplyLeft == 0) {
                assertEq(hook.STORE().totalSupplyOf(address(hook)), totalSupplyBeforePay);
                break;
            } else {
                assertEq(hook.STORE().totalSupplyOf(address(hook)), totalSupplyBeforePay + 1);
            }
            --supplyLeft;
        }
    }

    function test721TiersHook_afterPayRecorded_revertIfCallerIsNotATerminalOfProjectId(
        address terminal
    )
        public
    {
        vm.assume(terminal != mockTerminalAddress);

        // Mock the directory call.
        mockAndExpect(
            address(mockJBDirectory),
            abi.encodeWithSelector(IJBDirectory.isTerminalOf.selector, projectId, terminal),
            abi.encode(false)
        );

        // The caller is the `_expectedCaller`. However, the terminal in the calldata is not correct.
        vm.prank(terminal);

        vm.expectRevert(abi.encodeWithSelector(JB721Hook.INVALID_PAY.selector));

        hook.afterPayRecordedWith(
            JBAfterPayRecordedContext({
                payer: msg.sender,
                projectId: projectId,
                rulesetId: 0,
                amount: JBTokenAmount(address(0), 0, 18, uint32(uint160(JBConstants.NATIVE_TOKEN))),
                forwardedAmount: JBTokenAmount(JBConstants.NATIVE_TOKEN, 0, 18, uint32(uint160(JBConstants.NATIVE_TOKEN))), // 0, forwarded to the hook.
                weight: 10 ** 18,
                projectTokenCount: 0,
                beneficiary: msg.sender,
                hookMetadata: new bytes(0),
                payerMetadata: new bytes(0)
            })
        );
    }

    function test721TiersHook_afterPayRecorded_doNotMintIfNotUsingCorrectToken(address token) public {
        vm.assume(token != JBConstants.NATIVE_TOKEN);

        // Mock the directory call.
        mockAndExpect(
            address(mockJBDirectory),
            abi.encodeWithSelector(IJBDirectory.isTerminalOf.selector, projectId, mockTerminalAddress),
            abi.encode(true)
        );

        // The caller is the `_expectedCaller`. However, the terminal in the calldata is not correct.
        vm.prank(mockTerminalAddress);
        hook.afterPayRecordedWith(
            JBAfterPayRecordedContext({
                payer: msg.sender,
                projectId: projectId,
                rulesetId: 0,
                amount: JBTokenAmount(token, 0, 18, uint32(uint160(JBConstants.NATIVE_TOKEN))),
                forwardedAmount: JBTokenAmount(JBConstants.NATIVE_TOKEN, 0, 18, uint32(uint160(JBConstants.NATIVE_TOKEN))), // 0, forwarded to the hook.
                weight: 10 ** 18,
                projectTokenCount: 0,
                beneficiary: msg.sender,
                hookMetadata: new bytes(0),
                payerMetadata: new bytes(0)
            })
        );

        // Check: ensure that nothing has been minted.
        assertEq(hook.STORE().totalSupplyOf(address(hook)), 0);
    }

    function test721TiersHook_afterPayRecorded_mintTiersWhenUsingExistingCredits_when_existing_credits_more_than_new_credits(
    )
        public
    {
        uint256 leftover = tiers[0].price + 1; // + 1 to avoid rounding error.
        uint256 amount = tiers[0].price * 2 + tiers[1].price + leftover / 2;

        // Mock the directory call.
        mockAndExpect(
            address(mockJBDirectory),
            abi.encodeWithSelector(IJBDirectory.isTerminalOf.selector, projectId, mockTerminalAddress),
            abi.encode(true)
        );

        bool allowOverspending = true;
        uint16[] memory tierIdsToMint = new uint16[](3);
        tierIdsToMint[0] = 1;
        tierIdsToMint[1] = 1;
        tierIdsToMint[2] = 2;

        // Build the metadata using the tiers to mint and the overspending flag.
        bytes[] memory data = new bytes[](1);
        data[0] = abi.encode(allowOverspending, tierIdsToMint);

        // Pass the hook ID.
        bytes4[] memory ids = new bytes4[](1);
        ids[0] = bytes4(bytes20(address(hook)));

        // Generate the metadata.
        bytes memory hookMetadata = metadataHelper.createMetadata(ids, data);

        uint256 credits = hook.payCreditsOf(beneficiary);
        leftover = leftover / 2 + credits; // Leftover amount.

        vm.expectEmit(true, true, true, true, address(hook));
        emit AddPayCredits(leftover - credits, leftover, beneficiary, mockTerminalAddress);

        // The first call will mint the 3 tiers requested and accumulate half of the first price as pay credits.
        vm.prank(mockTerminalAddress);
        hook.afterPayRecordedWith(
            JBAfterPayRecordedContext({
                payer: beneficiary,
                projectId: projectId,
                rulesetId: 0,
                amount: JBTokenAmount(JBConstants.NATIVE_TOKEN, amount, 18, uint32(uint160(JBConstants.NATIVE_TOKEN))),
                forwardedAmount: JBTokenAmount(JBConstants.NATIVE_TOKEN, 0, 18, uint32(uint160(JBConstants.NATIVE_TOKEN))), // 0, forwarded to the hook.
                weight: 10 ** 18,
                projectTokenCount: 0,
                beneficiary: beneficiary,
                hookMetadata: new bytes(0),
                payerMetadata: hookMetadata
            })
        );

        uint256 totalSupplyBefore = hook.STORE().totalSupplyOf(address(hook));
        {
            // We now attempt to mint an additional NFT from tier 1 by using the pay credits we collected from the last payment.
            uint16[] memory moreTierIdsToMint = new uint16[](1);
            moreTierIdsToMint[0] = 1;

            data[0] = abi.encode(allowOverspending, moreTierIdsToMint);

            // Generate the metadata.
            hookMetadata = metadataHelper.createMetadata(ids, data);
        }

        // Fetch the existing pay credits.
        credits = hook.payCreditsOf(beneficiary);

        // Use existing credits to mint.
        leftover = tiers[0].price - 1 - credits;
        vm.expectEmit(true, true, true, true, address(hook));
        emit UsePayCredits(credits - leftover, leftover, beneficiary, mockTerminalAddress);

        // Mint with leftover pay credits.
        vm.prank(mockTerminalAddress);
        hook.afterPayRecordedWith(
            JBAfterPayRecordedContext({
                payer: beneficiary,
                projectId: projectId,
                rulesetId: 0,
                amount: JBTokenAmount(
                    JBConstants.NATIVE_TOKEN, tiers[0].price - 1, 18, uint32(uint160(JBConstants.NATIVE_TOKEN))
                    ),
                forwardedAmount: JBTokenAmount(JBConstants.NATIVE_TOKEN, 0, 18, uint32(uint160(JBConstants.NATIVE_TOKEN))), // 0, forwarded to the hook.
                weight: 10 ** 18,
                projectTokenCount: 0,
                beneficiary: beneficiary,
                hookMetadata: new bytes(0),
                payerMetadata: hookMetadata
            })
        );

        // Total supply increases.
        assertEq(totalSupplyBefore + 1, hook.STORE().totalSupplyOf(address(hook)));
    }

    function test721TiersHook_afterPayRecorded_revertIfUnexpectedLeftover() public {
        uint256 leftover = tiers[1].price - 1;
        uint256 amount = tiers[0].price + leftover;

        // Mock the directory call.
        mockAndExpect(
            address(mockJBDirectory),
            abi.encodeWithSelector(IJBDirectory.isTerminalOf.selector, projectId, mockTerminalAddress),
            abi.encode(true)
        );
        bool allowOverspending;
        uint16[] memory tierIdsToMint = new uint16[](0);

        // Build the metadata using the tiers to mint and the overspending flag.
        bytes[] memory data = new bytes[](1);
        data[0] = abi.encode(allowOverspending, tierIdsToMint);

        // Pass the hook ID.
        bytes4[] memory ids = new bytes4[](1);
        ids[0] = bytes4(bytes20(address(hook)));

        // Generate the metadata.
        bytes memory hookMetadata = metadataHelper.createMetadata(ids, data);
        vm.prank(mockTerminalAddress);
        vm.expectRevert(abi.encodeWithSelector(JB721TiersHook.OVERSPENDING.selector));
        hook.afterPayRecordedWith(
            JBAfterPayRecordedContext({
                payer: msg.sender,
                projectId: projectId,
                rulesetId: 0,
                amount: JBTokenAmount(JBConstants.NATIVE_TOKEN, amount, 18, uint32(uint160(JBConstants.NATIVE_TOKEN))),
                forwardedAmount: JBTokenAmount(JBConstants.NATIVE_TOKEN, 0, 18, uint32(uint160(JBConstants.NATIVE_TOKEN))), // 0, forwarded to the hook.
                weight: 10 ** 18,
                projectTokenCount: 0,
                beneficiary: beneficiary,
                hookMetadata: new bytes(0),
                payerMetadata: hookMetadata
            })
        );
    }

    function test721TiersHook_afterPayRecorded_revertIfUnexpectedLeftoverAndPrevented(bool prevent)
        public
    {
        uint256 leftover = tiers[1].price - 1;
        uint256 amount = tiers[0].price + leftover;

        // Mock the directory call.
        mockAndExpect(
            address(mockJBDirectory),
            abi.encodeWithSelector(IJBDirectory.isTerminalOf.selector, projectId, mockTerminalAddress),
            abi.encode(true)
        );

        // Get the current flags.
        JB721TiersHookFlags memory flags = hook.STORE().flagsOf(address(hook));

        // Set the prevent flag to the given value.
        flags.preventOverspending = prevent;

        // Mock the call to return the new flags.
        mockAndExpect(
            address(hook.STORE()),
            abi.encodeWithSelector(IJB721TiersHookStore.flagsOf.selector, address(hook)),
            abi.encode(flags)
        );

        bool allowOverspending = true;
        uint16[] memory tierIdsToMint = new uint16[](0);

        bytes memory metadata =
            abi.encode(bytes32(0), bytes32(0), type(IJB721TiersHook).interfaceId, allowOverspending, tierIdsToMint);

        // If prevent is enabled the call should revert. Otherwise, we should receive pay credits.
        if (prevent) {
            vm.expectRevert(abi.encodeWithSelector(JB721TiersHook.OVERSPENDING.selector));
        } else {
            uint256 payCredits = hook.payCreditsOf(beneficiary);
            uint256 stashedPayCredits = payCredits;
            // Calculating new pay credit balance (since leftover is non-zero).
            uint256 newPayCredits = tiers[0].price + leftover + stashedPayCredits;
            vm.expectEmit(true, true, true, true, address(hook));
            emit AddPayCredits(newPayCredits - payCredits, newPayCredits, beneficiary, mockTerminalAddress);
        }
        vm.prank(mockTerminalAddress);
        hook.afterPayRecordedWith(
            JBAfterPayRecordedContext({
                payer: msg.sender,
                projectId: projectId,
                rulesetId: 0,
                amount: JBTokenAmount(JBConstants.NATIVE_TOKEN, amount, 18, uint32(uint160(JBConstants.NATIVE_TOKEN))),
                forwardedAmount: JBTokenAmount(JBConstants.NATIVE_TOKEN, 0, 18, uint32(uint160(JBConstants.NATIVE_TOKEN))), // 0, forwarded to the hook.
                weight: 10 ** 18,
                projectTokenCount: 0,
                beneficiary: beneficiary,
                hookMetadata: new bytes(0),
                payerMetadata: metadata
            })
        );
    }

    // If transfers are paused, transfers which do not involve the zero address are reverted, as long as the `transfersPausable` flag must be true.
    // Transfers involving the zero address (minting and burning) are not affected.
    function test721TiersHook_beforeTransferHook_revertTransferIfTransferPausedInRuleset() public {
        defaultTierConfig.transfersPausable = true;
        JB721TiersHook hook = _initHookDefaultTiers(10);

        // Mock the directory call.
        mockAndExpect(
            address(mockJBDirectory),
            abi.encodeWithSelector(IJBDirectory.isTerminalOf.selector, projectId, mockTerminalAddress),
            abi.encode(true)
        );

        mockAndExpect(
            mockJBRulesets,
            abi.encodeCall(IJBRulesets.currentOf, projectId),
            abi.encode(
                JBRuleset({
                    cycleNumber: 1,
                    id: block.timestamp,
                    basedOnId: 0,
                    start: block.timestamp,
                    duration: 600,
                    weight: 10e18,
                    decayRate: 0,
                    approvalHook: IJBRulesetApprovalHook(address(0)),
                    metadata: JBRulesetMetadataResolver.packRulesetMetadata(
                        JBRulesetMetadata({
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
                            useDataHookForPay: true,
                            useDataHookForRedeem: true,
                            dataHook: address(hook),
                            metadata: 1 // 001_2
                        })
                        )
                })
            )
        );

        bool allowOverspending;
        uint16[] memory tierIdsToMint = new uint16[](3);
        tierIdsToMint[0] = 1;
        tierIdsToMint[1] = 1;
        tierIdsToMint[2] = 2;

        // Build the metadata using the tiers to mint and the overspending flag.
        bytes[] memory data = new bytes[](1);
        data[0] = abi.encode(allowOverspending, tierIdsToMint);

        // Pass the hook ID.
        bytes4[] memory ids = new bytes4[](1);
        ids[0] = bytes4(bytes20(address(hook)));

        // Generate the metadata.
        bytes memory hookMetadata = metadataHelper.createMetadata(ids, data);

        vm.prank(mockTerminalAddress);
        hook.afterPayRecordedWith(
            JBAfterPayRecordedContext({
                payer: msg.sender,
                projectId: projectId,
                rulesetId: 0,
                amount: JBTokenAmount(
                    JBConstants.NATIVE_TOKEN,
                    tiers[0].price * 2 + tiers[1].price,
                    18,
                    uint32(uint160(JBConstants.NATIVE_TOKEN))
                    ),
                forwardedAmount: JBTokenAmount(JBConstants.NATIVE_TOKEN, 0, 18, uint32(uint160(JBConstants.NATIVE_TOKEN))), // 0, forwarded to the hook.
                weight: 10 ** 18,
                projectTokenCount: 0,
                beneficiary: msg.sender,
                hookMetadata: new bytes(0),
                payerMetadata: hookMetadata
            })
        );

        uint256 tokenId = _generateTokenId(1, 1);

        vm.expectRevert(JB721TiersHook.TIER_TRANSFERS_PAUSED.selector);

        vm.prank(msg.sender);
        IERC721(hook).transferFrom(msg.sender, beneficiary, tokenId);
    }

    // If the ruleset metadata has `pauseTransfers` enabled,
    // BUT the tier being transferred has `transfersPausable` disabled,
    // transfer are not paused (this bypasses the call to `JBRulesets`).
    function test721TiersHook_beforeTransferHook_pauseFlagOverrideRulesetTransferPaused() public {
        // Mock the directory call.
        mockAndExpect(
            address(mockJBDirectory),
            abi.encodeWithSelector(IJBDirectory.isTerminalOf.selector, projectId, mockTerminalAddress),
            abi.encode(true)
        );

        JB721TiersHook hook = _initHookDefaultTiers(10);

        bool allowOverspending;
        uint16[] memory tierIdsToMint = new uint16[](3);
        tierIdsToMint[0] = 1;
        tierIdsToMint[1] = 1;
        tierIdsToMint[2] = 2;

        // Build the metadata using the tiers to mint and the overspending flag.
        bytes[] memory data = new bytes[](1);
        data[0] = abi.encode(allowOverspending, tierIdsToMint);

        // Pass the hook ID.
        bytes4[] memory ids = new bytes4[](1);
        ids[0] = bytes4(bytes20(address(hook)));

        // Generate the metadata.
        bytes memory hookMetadata = metadataHelper.createMetadata(ids, data);

        vm.prank(mockTerminalAddress);
        hook.afterPayRecordedWith(
            JBAfterPayRecordedContext({
                payer: msg.sender,
                projectId: projectId,
                rulesetId: 0,
                amount: JBTokenAmount(
                    JBConstants.NATIVE_TOKEN,
                    tiers[0].price * 2 + tiers[1].price,
                    18,
                    uint32(uint160(JBConstants.NATIVE_TOKEN))
                    ),
                forwardedAmount: JBTokenAmount(JBConstants.NATIVE_TOKEN, 0, 18, uint32(uint160(JBConstants.NATIVE_TOKEN))), // 0, forwarded to the hook.
                weight: 10 ** 18,
                projectTokenCount: 0,
                beneficiary: msg.sender,
                hookMetadata: new bytes(0),
                payerMetadata: hookMetadata
            })
        );

        uint256 tokenId = _generateTokenId(1, 1);
        vm.prank(msg.sender);
        IERC721(hook).transferFrom(msg.sender, beneficiary, tokenId);
        // Check: was the NFT transferred?
        assertEq(IERC721(hook).ownerOf(tokenId), beneficiary);
    }

    // Redeem an NFT, even if transfers are paused in the ruleset metadata. This should bypass the call to `JBRulesets`.
    function test721TiersHook_beforeTransferHook_redeemEvenIfTransferPausedInRuleset() public {
        address holder = address(bytes20(keccak256("holder")));

        JB721TiersHook hook = _initHookDefaultTiers(10);

        // Mock the directory call.
        mockAndExpect(
            address(mockJBDirectory),
            abi.encodeWithSelector(IJBDirectory.isTerminalOf.selector, projectId, mockTerminalAddress),
            abi.encode(true)
        );

        // Build the metadata which will be used to mint.
        bytes memory hookMetadata;
        bytes[] memory data = new bytes[](1);
        bytes4[] memory ids = new bytes4[](1);

        {
            // Craft the metadata: mint the specified tier.
            uint16[] memory rawMetadata = new uint16[](1);
            rawMetadata[0] = uint16(1); // 1 indexed

            // Build the metadata using the tiers to mint and the overspending flag.
            data[0] = abi.encode(true, rawMetadata);

            // Pass the hook ID.
            ids[0] = bytes4(bytes20(address(hook)));

            // Generate the metadata.
            hookMetadata = metadataHelper.createMetadata(ids, data);
        }

        // Mint the NFTs. Otherwise, the voting balance is not incremented which leads to an underflow upon redemption.
        vm.prank(mockTerminalAddress);
        hook.afterPayRecordedWith(
            JBAfterPayRecordedContext({
                payer: holder,
                projectId: projectId,
                rulesetId: 0,
                amount: JBTokenAmount(
                    JBConstants.NATIVE_TOKEN, tiers[0].price, 18, uint32(uint160(JBConstants.NATIVE_TOKEN))
                    ),
                forwardedAmount: JBTokenAmount(JBConstants.NATIVE_TOKEN, 0, 18, uint32(uint160(JBConstants.NATIVE_TOKEN))), // 0, forwarded to the hook.
                weight: 10 ** 18,
                projectTokenCount: 0,
                beneficiary: holder,
                hookMetadata: new bytes(0),
                payerMetadata: hookMetadata
            })
        );

        uint256[] memory tokenToRedeem = new uint256[](1);
        tokenToRedeem[0] = _generateTokenId(1, 1);

        // Build the metadata with the tiers to redeem.
        data[0] = abi.encode(tokenToRedeem);

        // Pass the hook ID.
        ids[0] = bytes4(bytes20(address(hook)));

        // Generate the metadata.
        hookMetadata = metadataHelper.createMetadata(ids, data);

        vm.prank(mockTerminalAddress);
        hook.afterRedeemRecordedWith(
            JBAfterRedeemRecordedContext({
                holder: holder,
                projectId: projectId,
                rulesetId: 1,
                redeemCount: 0,
                reclaimedAmount: JBTokenAmount({
                    token: address(0),
                    value: 0,
                    decimals: 18,
                    currency: uint32(uint160(JBConstants.NATIVE_TOKEN))
                }),
                forwardedAmount: JBTokenAmount({token: address(0), value: 0, decimals: 18, currency: uint32(uint160(JBConstants.NATIVE_TOKEN)) }), // 0, forwarded to the hook.
                redemptionRate: 5000,
                beneficiary: payable(holder),
                hookMetadata: bytes(""),
                redeemerMetadata: hookMetadata
            })
        );

        // Balance should be 0 again.
        assertEq(hook.balanceOf(holder), 0);
    }
}