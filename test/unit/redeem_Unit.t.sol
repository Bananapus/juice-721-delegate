// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import "../utils/UnitTestSetup.sol";

contract Test_redeem_Unit is UnitTestSetup {
    using stdStorage for StdStorage;

    function test_beforeRedeemContext_returnsCorrectAmount() public {
        uint256 weight;
        uint256 totalWeight;
        ForTest_JB721TiersHook hook = _initializeForTestHook(10);

        // Set up 10 tiers, with half of the supply minted for each one.
        for (uint256 i = 1; i <= 10; i++) {
            hook.test_store().ForTest_setTier(
                address(hook),
                i,
                JBStored721Tier({
                    price: uint104(i * 10),
                    remainingSupply: uint32(10 * i - 5 * i),
                    initialSupply: uint32(10 * i),
                    votingUnits: uint16(0),
                    reserveFrequency: uint16(0),
                    category: uint24(100),
                    discountPercent: uint8(0),
                    packedBools: hook.test_store().ForTest_packBools(false, false, false, false, false)
                })
            );
            totalWeight += (10 * i - 5 * i) * i * 10;
        }

        // Redeem as if the beneficiary has 1 NFT from each of the first five tiers.
        uint256[] memory tokenList = new uint256[](5);
        for (uint256 i; i < 5; i++) {
            uint256 tokenId = _generateTokenId(i + 1, 1);
            hook.ForTest_setOwnerOf(tokenId, beneficiary);
            tokenList[i] = tokenId;
            weight += (i + 1) * 10;
        }

        // Build the metadata with the tiers to redeem.
        bytes[] memory data = new bytes[](1);
        data[0] = abi.encode(tokenList);

        // Pass the hook ID.
        bytes4[] memory ids = new bytes4[](1);
        ids[0] = metadataHelper.getId("redeem", address(hookOrigin));

        // Generate the metadata.
        bytes memory hookMetadata = metadataHelper.createMetadata(ids, data);
        (uint256 redemptionRate,,, JBRedeemHookSpecification[] memory returnedHook) = hook.beforeRedeemRecordedWith(
            JBBeforeRedeemRecordedContext({
                terminal: address(0),
                holder: beneficiary,
                projectId: projectId,
                rulesetId: 0,
                redeemCount: 0,
                totalSupply: 0,
                surplus: JBTokenAmount({
                    token: address(0),
                    value: SURPLUS,
                    decimals: 18,
                    currency: uint32(uint160(JBConstants.NATIVE_TOKEN))
                }),
                useTotalSurplus: true,
                redemptionRate: REDEMPTION_RATE,
                metadata: hookMetadata
            })
        );

        // Check: does the reclaim amount match the expected value?
        assertEq(redemptionRate, REDEMPTION_RATE);
        // Check: does the returned hook address match the expected value?
        assertEq(address(returnedHook[0].hook), address(hook));
    }

    function test_beforeRedeemContext_returnsZeroAmountIfReserveFrequencyIsZero() public {
        uint256 surplus = 10e18;
        uint256 redemptionRate = 0;
        uint256 weight;
        uint256 totalWeight;
        JBRedeemHookSpecification[] memory returnedHook;

        ForTest_JB721TiersHook hook = _initializeForTestHook(10);

        // Set up 10 tiers, with half of the supply minted for each one.
        for (uint256 i = 1; i <= 10; i++) {
            hook.test_store().ForTest_setTier(
                address(hook),
                i,
                JBStored721Tier({
                    price: uint104(i * 10),
                    remainingSupply: uint32(10 * i - 5 * i),
                    initialSupply: uint32(10 * i),
                    votingUnits: uint16(0),
                    reserveFrequency: uint16(0),
                    category: uint24(100),
                    discountPercent: uint8(0),
                    packedBools: hook.test_store().ForTest_packBools(false, false, false, false, false)
                })
            );
            totalWeight += (10 * i - 5 * i) * i * 10;
        }

        // Redeem as if the beneficiary has 1 NFT from each of the first five tiers.
        uint256[] memory tokenList = new uint256[](5);
        for (uint256 i; i < 5; i++) {
            hook.ForTest_setOwnerOf(i + 1, beneficiary);
            tokenList[i] = i + 1;
            weight += (i + 1) * (i + 1) * 10;
        }

        (redemptionRate,,, returnedHook) = hook.beforeRedeemRecordedWith(
            JBBeforeRedeemRecordedContext({
                terminal: address(0),
                holder: beneficiary,
                projectId: projectId,
                rulesetId: 0,
                redeemCount: 0,
                totalSupply: 0,
                surplus: JBTokenAmount({
                    token: address(0),
                    value: surplus,
                    decimals: 18,
                    currency: uint32(uint160(JBConstants.NATIVE_TOKEN))
                }),
                useTotalSurplus: true,
                redemptionRate: redemptionRate,
                metadata: abi.encode(bytes32(0), type(IJB721Hook).interfaceId, tokenList)
            })
        );

        // Check: is the redemption rate zero?
        assertEq(redemptionRate, 0);
        // Check: does the returned hook address match the expected value?
        assertEq(address(returnedHook[0].hook), address(hook));
    }

    function test_beforeRedeemContext_returnsPartOfOverflowOwnedIfRedemptionRateIsMaximum() public {
        uint256 weight;
        uint256 totalWeight;

        ForTest_JB721TiersHook hook = _initializeForTestHook(10);

        // Set up 10 tiers, with half of the supply minted for each one.
        for (uint256 i = 1; i <= 10; i++) {
            hook.test_store().ForTest_setTier(
                address(hook),
                i,
                JBStored721Tier({
                    price: uint104(i * 10),
                    remainingSupply: uint32(10 * i - 5 * i),
                    initialSupply: uint32(10 * i),
                    votingUnits: uint16(0),
                    reserveFrequency: uint16(0),
                    category: uint24(100),
                    discountPercent: uint8(0),
                    packedBools: hook.test_store().ForTest_packBools(false, false, false, false, false)
                })
            );
            totalWeight += (10 * i - 5 * i) * i * 10;
        }

        // Redeem as if the beneficiary has 1 NFT from each of the first five tiers.
        uint256[] memory tokenList = new uint256[](5);
        for (uint256 i; i < 5; i++) {
            hook.ForTest_setOwnerOf(_generateTokenId(i + 1, 1), beneficiary);
            tokenList[i] = _generateTokenId(i + 1, 1);
            weight += (i + 1) * 10;
        }

        // Build the metadata with the tiers to redeem.
        bytes[] memory data = new bytes[](1);
        data[0] = abi.encode(tokenList);

        // Pass the hook ID.
        bytes4[] memory ids = new bytes4[](1);
        ids[0] = metadataHelper.getId("redeem", address(hookOrigin));

        // Generate the metadata.
        bytes memory hookMetadata = metadataHelper.createMetadata(ids, data);

        JBBeforeRedeemRecordedContext memory beforeRedeemContext = JBBeforeRedeemRecordedContext({
            terminal: address(0),
            holder: beneficiary,
            projectId: projectId,
            rulesetId: 0,
            redeemCount: 0,
            totalSupply: 0,
            surplus: JBTokenAmount({
                token: address(0),
                value: SURPLUS,
                decimals: 18,
                currency: uint32(uint160(JBConstants.NATIVE_TOKEN))
            }),
            useTotalSurplus: true,
            redemptionRate: JBConstants.MAX_REDEMPTION_RATE,
            metadata: hookMetadata
        });

        (uint256 redemptionRate,,, JBRedeemHookSpecification[] memory returnedHook) =
            hook.beforeRedeemRecordedWith(beforeRedeemContext);

        // Check: does the redemption rate match the expected value?
        assertEq(redemptionRate, JBConstants.MAX_REDEMPTION_RATE);
        // Check: does the returned hook address match the expected value?
        assertEq(address(returnedHook[0].hook), address(hook));
    }

    function test_beforeRedeemContext_revertIfNonZeroTokenCount(uint256 tokenCount) public {
        vm.assume(tokenCount > 0);

        // Expect a revert on account of the token count being non-zero while the total supply is zero.
        vm.expectRevert(abi.encodeWithSelector(JB721Hook.JB721Hook_UnexpectedTokenRedeemed.selector));

        hook.beforeRedeemRecordedWith(
            JBBeforeRedeemRecordedContext({
                terminal: address(0),
                holder: beneficiary,
                projectId: projectId,
                rulesetId: 0,
                redeemCount: tokenCount,
                totalSupply: 0,
                surplus: JBTokenAmount({
                    token: address(0),
                    value: 100,
                    decimals: 18,
                    currency: uint32(uint160(JBConstants.NATIVE_TOKEN))
                }),
                useTotalSurplus: true,
                redemptionRate: 100,
                metadata: new bytes(0)
            })
        );
    }

    function test_afterRedeemRecordedWith_burnRedeemedNft(uint256 numberOfNfts) public {
        ForTest_JB721TiersHook hook = _initializeForTestHook(5);

        // Has to all fit in tier 1 (excluding reserve mints).
        numberOfNfts = bound(numberOfNfts, 1, 90);

        // Mock the directory call.
        mockAndExpect(
            address(mockJBDirectory),
            abi.encodeWithSelector(IJBDirectory.isTerminalOf.selector, projectId, mockTerminalAddress),
            abi.encode(true)
        );

        uint256[] memory tokenList = new uint256[](numberOfNfts);

        bytes memory hookMetadata;
        bytes[] memory data;
        bytes4[] memory ids;

        for (uint256 i; i < numberOfNfts; i++) {
            uint16[] memory tierIdsToMint = new uint16[](1);
            tierIdsToMint[0] = 1;

            // Build the metadata using the tiers to mint and the overspending flag.
            data = new bytes[](1);
            data[0] = abi.encode(false, tierIdsToMint);

            // Pass the hook ID.
            ids = new bytes4[](1);
            ids[0] = metadataHelper.getId("pay", address(hook));

            // Generate the metadata.
            hookMetadata = metadataHelper.createMetadata(ids, data);

            // Mint the NFTs. Otherwise, the voting balance is not incremented,
            // which leads to an underflow upon redemption.
            vm.prank(mockTerminalAddress);
            JBAfterPayRecordedContext memory afterPayContext = JBAfterPayRecordedContext({
                payer: beneficiary,
                projectId: projectId,
                rulesetId: 0,
                amount: JBTokenAmount({
                    token: JBConstants.NATIVE_TOKEN,
                    value: 10,
                    decimals: 18,
                    currency: uint32(uint160(JBConstants.NATIVE_TOKEN))
                }),
                forwardedAmount: JBTokenAmount({
                    token: JBConstants.NATIVE_TOKEN,
                    value: 0,
                    decimals: 18,
                    currency: uint32(uint160(JBConstants.NATIVE_TOKEN))
                }), // 0
                // Forward to the hook.
                weight: 10 ** 18,
                projectTokenCount: 0,
                beneficiary: beneficiary,
                hookMetadata: new bytes(0),
                payerMetadata: hookMetadata
            });

            hook.afterPayRecordedWith(afterPayContext);

            tokenList[i] = _generateTokenId(1, i + 1);

            // Check: was a new NFT minted?
            assertEq(hook.balanceOf(beneficiary), i + 1);
        }

        // Build the metadata with the tiers to redeem.
        data = new bytes[](1);
        data[0] = abi.encode(tokenList);

        // Pass the hook ID.
        ids = new bytes4[](1);
        ids[0] = metadataHelper.getId("redeem", address(hook));

        // Generate the metadata.
        hookMetadata = metadataHelper.createMetadata(ids, data);

        vm.prank(mockTerminalAddress);
        hook.afterRedeemRecordedWith(
            JBAfterRedeemRecordedContext({
                holder: beneficiary,
                projectId: projectId,
                rulesetId: 1,
                redeemCount: 0,
                reclaimedAmount: JBTokenAmount({
                    token: address(0),
                    value: 0,
                    decimals: 18,
                    currency: uint32(uint160(JBConstants.NATIVE_TOKEN))
                }),
                forwardedAmount: JBTokenAmount({
                    token: address(0),
                    value: 0,
                    decimals: 18,
                    currency: uint32(uint160(JBConstants.NATIVE_TOKEN))
                }), // 0, forwarded to the hook.
                redemptionRate: 5000,
                beneficiary: payable(beneficiary),
                hookMetadata: bytes(""),
                redeemerMetadata: hookMetadata
            })
        );

        // Check: is the beneficiary's balance zero again?
        assertEq(hook.balanceOf(beneficiary), 0);

        // Check: was the number of burned NFTs recorded correctly (to match `numberOfNfts` in the first tier)?
        assertEq(hook.test_store().numberOfBurnedFor(address(hook), 1), numberOfNfts);
    }

    function test_afterRedeemRecordedWith_revertIfNotCorrectProjectId(uint8 wrongProjectId) public {
        vm.assume(wrongProjectId != projectId);

        uint256[] memory tokenList = new uint256[](1);
        tokenList[0] = 1;

        // Mock the directory call.
        mockAndExpect(
            address(mockJBDirectory),
            abi.encodeWithSelector(IJBDirectory.isTerminalOf.selector, projectId, mockTerminalAddress),
            abi.encode(true)
        );

        // Expect to revert on account of the project ID being incorrect.
        vm.expectRevert(abi.encodeWithSelector(JB721Hook.JB721Hook_InvalidRedeem.selector));

        vm.prank(mockTerminalAddress);
        hook.afterRedeemRecordedWith(
            JBAfterRedeemRecordedContext({
                holder: beneficiary,
                projectId: wrongProjectId,
                rulesetId: 1,
                redeemCount: 0,
                reclaimedAmount: JBTokenAmount({
                    token: address(0),
                    value: 0,
                    decimals: 18,
                    currency: uint32(uint160(JBConstants.NATIVE_TOKEN))
                }),
                forwardedAmount: JBTokenAmount({
                    token: address(0),
                    value: 0,
                    decimals: 18,
                    currency: uint32(uint160(JBConstants.NATIVE_TOKEN))
                }), // 0, forwarded to the hook.
                redemptionRate: 5000,
                beneficiary: payable(beneficiary),
                hookMetadata: bytes(""),
                redeemerMetadata: abi.encode(type(IJB721TiersHook).interfaceId, tokenList)
            })
        );
    }

    function test_afterRedeemRecordedWith_revertIfCallerIsNotATerminalOfTheProject() public {
        uint256[] memory tokenList = new uint256[](1);
        tokenList[0] = 1;

        // Mock the directory call.
        mockAndExpect(
            address(mockJBDirectory),
            abi.encodeWithSelector(IJBDirectory.isTerminalOf.selector, projectId, mockTerminalAddress),
            abi.encode(false)
        );

        // Expect to revert on account of the caller not being a terminal of the project.
        vm.expectRevert(abi.encodeWithSelector(JB721Hook.JB721Hook_InvalidRedeem.selector));

        vm.prank(mockTerminalAddress);
        hook.afterRedeemRecordedWith(
            JBAfterRedeemRecordedContext({
                holder: beneficiary,
                projectId: projectId,
                rulesetId: 1,
                redeemCount: 0,
                reclaimedAmount: JBTokenAmount({
                    token: address(0),
                    value: 0,
                    decimals: 18,
                    currency: uint32(uint160(JBConstants.NATIVE_TOKEN))
                }),
                forwardedAmount: JBTokenAmount({
                    token: address(0),
                    value: 0,
                    decimals: 18,
                    currency: uint32(uint160(JBConstants.NATIVE_TOKEN))
                }), // 0, forwarded to the hook.
                redemptionRate: 5000,
                beneficiary: payable(beneficiary),
                hookMetadata: bytes(""),
                redeemerMetadata: abi.encode(type(IJB721TiersHook).interfaceId, tokenList)
            })
        );
    }

    function test_afterRedeemRecordedWith_revertIfWrongHolder(address wrongHolder, uint8 tokenId) public {
        vm.assume(beneficiary != wrongHolder);
        vm.assume(tokenId != 0);

        ForTest_JB721TiersHook hook = _initializeForTestHook(1);

        hook.ForTest_setOwnerOf(tokenId, beneficiary);

        uint256[] memory tokenList = new uint256[](1);
        tokenList[0] = tokenId;

        // Build the metadata with the tiers to redeem.
        bytes[] memory data = new bytes[](1);
        data[0] = abi.encode(tokenList);

        // Pass the hook ID.
        bytes4[] memory ids = new bytes4[](1);
        ids[0] = metadataHelper.getId("redeem", address(hook));

        // Generate the metadata.
        bytes memory hookMetadata = metadataHelper.createMetadata(ids, data);

        // Mock the directory call.
        mockAndExpect(
            address(mockJBDirectory),
            abi.encodeWithSelector(IJBDirectory.isTerminalOf.selector, projectId, mockTerminalAddress),
            abi.encode(true)
        );

        vm.expectRevert(abi.encodeWithSelector(JB721Hook.JB721Hook_UnauthorizedToken.selector));

        vm.prank(mockTerminalAddress);
        hook.afterRedeemRecordedWith(
            JBAfterRedeemRecordedContext({
                holder: wrongHolder,
                projectId: projectId,
                rulesetId: 1,
                redeemCount: 0,
                reclaimedAmount: JBTokenAmount({
                    token: address(0),
                    value: 0,
                    decimals: 18,
                    currency: uint32(uint160(JBConstants.NATIVE_TOKEN))
                }),
                forwardedAmount: JBTokenAmount({
                    token: address(0),
                    value: 0,
                    decimals: 18,
                    currency: uint32(uint160(JBConstants.NATIVE_TOKEN))
                }), // 0, forwarded to the hook.
                redemptionRate: 5000,
                beneficiary: payable(wrongHolder),
                hookMetadata: bytes(""),
                redeemerMetadata: hookMetadata
            })
        );
    }
}
