// SPDX-License-Identifier: BUSL 1.1
// Valorem Labs Inc. (c) 2022.
pragma solidity 0.8.16;

import "solmate/utils/FixedPointMathLib.sol";
import "forge-std/Test.sol";
import {IERC20} from "forge-std/interfaces/IERC20.sol";
import "./utils/BaseEngineTest.sol";

contract OptionSettlementUnitTest is BaseEngineTest {
    /*//////////////////////////////////////////////////////////////
    //  function option(uint256 tokenId) external view returns (Option memory optionInfo);
    //////////////////////////////////////////////////////////////*/

    function test_unitOptionRevertsWhenDoesNotExist() public {
        uint256 badOptionId = 123;
        vm.expectRevert(abi.encodeWithSelector(IOptionSettlementEngine.TokenNotFound.selector, badOptionId));
        engine.option(badOptionId);
    }

    function test_unitOptionReturnsOptionInfo() public {
        IOptionSettlementEngine.Option memory optionInfo = engine.option(testOptionId);
        assertEq(optionInfo.underlyingAsset, testUnderlyingAsset);
        assertEq(optionInfo.underlyingAmount, testUnderlyingAmount);
        assertEq(optionInfo.exerciseAsset, testExerciseAsset);
        assertEq(optionInfo.exerciseAmount, testExerciseAmount);
        assertEq(optionInfo.exerciseTimestamp, testExerciseTimestamp);
        assertEq(optionInfo.expiryTimestamp, testExpiryTimestamp);
    }

    /*//////////////////////////////////////////////////////////////
    //  function claim(uint256 claimId) external view returns (Claim memory claimInfo);
    //////////////////////////////////////////////////////////////*/

    function test_unitClaimRevertsWhenClaimDoesNotExist() public {
        uint256 badClaimId = testOptionId + 69;
        vm.expectRevert(abi.encodeWithSelector(IOptionSettlementEngine.TokenNotFound.selector, badClaimId));
        engine.claim(badClaimId);
    }

    function test_unitClaimWrittenOnce() public {
        uint112 amountWritten = 69;
        vm.prank(ALICE);
        uint256 claimId = engine.write(testOptionId, amountWritten);

        IOptionSettlementEngine.Claim memory claim = engine.claim(claimId);
        assertEq(claim.amountWritten, amountWritten * WAD);
        assertEq(claim.amountExercised, 0);
        assertEq(claim.optionId, testOptionId);
        // TODO(Why do we need this if claim() reverts when it does not exist?) See L64 below
        assertEq(claim.unredeemed, true);

        vm.warp(testOption.exerciseTimestamp);
        vm.prank(ALICE);
        engine.exercise(testOptionId, 1);

        claim = engine.claim(claimId);
        assertEq(claim.amountWritten, amountWritten * WAD);
        assertEq(claim.amountExercised, 1 * WAD);
        assertEq(claim.optionId, testOptionId);

        vm.warp(testOption.exerciseTimestamp);
        vm.prank(ALICE);
        engine.exercise(testOptionId, 68);

        claim = engine.claim(claimId);
        assertEq(claim.amountWritten, amountWritten * WAD);
        assertEq(claim.amountExercised, amountWritten * WAD);
        assertEq(claim.optionId, testOptionId);

        vm.warp(testOption.expiryTimestamp);
        vm.prank(ALICE);
        engine.redeem(claimId);

        vm.expectRevert(abi.encodeWithSelector(IOptionSettlementEngine.TokenNotFound.selector, claimId));
        claim = engine.claim(claimId);
    }

    function test_unitClaimWrittenMultiple() public {
        uint112 amountWritten = 69;
        vm.prank(ALICE);
        uint256 claimId = engine.write(testOptionId, amountWritten);

        IOptionSettlementEngine.Claim memory claim = engine.claim(claimId);
        assertEq(claim.amountWritten, amountWritten * WAD);
        assertEq(claim.amountExercised, 0);
        assertEq(claim.optionId, testOptionId);

        vm.warp(testOption.exerciseTimestamp);
        vm.prank(ALICE);
        engine.exercise(testOptionId, 1);

        claim = engine.claim(claimId);
        assertEq(claim.amountWritten, amountWritten * WAD);
        assertEq(claim.amountExercised, 1 * WAD);
        assertEq(claim.optionId, testOptionId);

        vm.prank(ALICE);
        engine.write(claimId, amountWritten);

        claim = engine.claim(claimId);
        assertEq(claim.amountWritten, amountWritten * 2 * WAD);
        assertEq(claim.amountExercised, 1 * WAD);
        assertEq(claim.optionId, testOptionId);

        vm.prank(ALICE);
        engine.exercise(testOptionId, 137);

        claim = engine.claim(claimId);
        assertEq(claim.amountWritten, amountWritten * 2 * WAD);
        assertEq(claim.amountExercised, amountWritten * 2 * WAD);
        assertEq(claim.optionId, testOptionId);

        vm.warp(testOption.expiryTimestamp);
        vm.prank(ALICE);
        engine.redeem(claimId);

        vm.expectRevert(abi.encodeWithSelector(IOptionSettlementEngine.TokenNotFound.selector, claimId));
        claim = engine.claim(claimId);
    }

    function test_unitClaimWrittenMultipleMultipleClaims() public {
        vm.startPrank(ALICE);

        uint256 claimId1 = engine.write(testOptionId, 1);
        IOptionSettlementEngine.Claim memory claim1 = engine.claim(claimId1);
        assertEq(claim1.amountWritten, WAD);
        assertEq(claim1.amountExercised, 0);

        uint256 claimId2 = engine.write(testOptionId, 1);
        IOptionSettlementEngine.Claim memory claim2 = engine.claim(claimId2);
        assertEq(claim1.amountWritten, WAD);
        assertEq(claim1.amountExercised, 0);
        assertEq(claim2.amountWritten, WAD);
        assertEq(claim2.amountExercised, 0);

        engine.write(claimId2, 1);
        claim2 = engine.claim(claimId2);
        assertEq(claim1.amountWritten, WAD);
        assertEq(claim1.amountExercised, 0);
        assertEq(claim2.amountWritten, 2 * WAD);
        assertEq(claim2.amountExercised, 0);

        vm.warp(testExerciseTimestamp);

        engine.exercise(testOptionId, 2);
        claim1 = engine.claim(claimId1);
        claim2 = engine.claim(claimId2);
        assertEq(claim1.amountWritten, WAD);
        // exercised ratio in the bucket is 2/3
        assertEq(
            // 1 option is written in this claim, two options are exercised in the bucket, and in
            // total, 3 options are written
            claim1.amountExercised,
            FixedPointMathLib.divWadDown(1 * 2, 3)
        );
        assertEq(claim2.amountWritten, 2 * WAD);
        assertEq(
            // 2 options are written in this claim, two options are exercised in the bucket, and in
            // total, 3 options are written
            claim2.amountExercised,
            FixedPointMathLib.divWadDown(2 * 2, 3)
        );
    }

    /*//////////////////////////////////////////////////////////////
    //  function position(uint256 tokenId) external view returns (Position memory positionInfo);
    //////////////////////////////////////////////////////////////*/

    function test_unitPositionRevertsTokenNotFound() public {
        vm.expectRevert(abi.encodeWithSelector(IOptionSettlementEngine.TokenNotFound.selector, 1));
        engine.position(1);
    }

    function test_unitPositionOption() public {
        IOptionSettlementEngine.Position memory position = engine.position(testOptionId);
        assertEq(position.underlyingAsset, testUnderlyingAsset);
        assertEq(position.underlyingAmount, int256(uint256(testUnderlyingAmount)));
        assertEq(position.exerciseAsset, testExerciseAsset);
        assertEq(position.exerciseAmount, -int256(uint256(testExerciseAmount)));

        vm.warp(testOption.expiryTimestamp);
        // The token is now expired/worthless, and this should revert.
        vm.expectRevert(
            abi.encodeWithSelector(IOptionSettlementEngine.ExpiredOption.selector, testOptionId, testExpiryTimestamp)
        );
        position = engine.position(testOptionId);
    }

    function test_unitPositionUnexercisedClaim() public {
        uint112 amountWritten = 69;
        vm.prank(ALICE);
        uint256 claimId = engine.write(testOptionId, amountWritten);

        IOptionSettlementEngine.Position memory position = engine.position(claimId);
        assertEq(position.underlyingAsset, testUnderlyingAsset);
        assertEq(position.underlyingAmount, int256(uint256(testUnderlyingAmount) * amountWritten));
        assertEq(position.exerciseAsset, testExerciseAsset);
        assertEq(position.exerciseAmount, int256(0));
    }

    function test_unitPositionPartiallyExercisedClaim() public {
        uint112 amountWritten = 69;
        vm.prank(ALICE);
        uint256 claimId = engine.write(testOptionId, amountWritten);

        vm.prank(ALICE);
        engine.exercise(testOptionId, 1);

        vm.prank(ALICE);
        engine.write(claimId, amountWritten);

        amountWritten = amountWritten * 2;

        IOptionSettlementEngine.Position memory position = engine.position(claimId);
        assertEq(position.underlyingAsset, testUnderlyingAsset);
        assertEq(
            position.underlyingAmount,
            int256(uint256((amountWritten - 1) * testUnderlyingAmount * amountWritten) / amountWritten)
        );
        assertEq(position.exerciseAsset, testExerciseAsset);
        assertEq(position.exerciseAmount, int256(uint256(1 * testExerciseAmount * amountWritten) / amountWritten));
    }

    function test_unitPositionExercisedClaim() public {
        uint112 amountWritten = 69;
        vm.prank(ALICE);
        uint256 claimId = engine.write(testOptionId, amountWritten);

        vm.prank(ALICE);
        engine.exercise(testOptionId, amountWritten);

        IOptionSettlementEngine.Position memory position = engine.position(claimId);
        assertEq(position.underlyingAsset, testUnderlyingAsset);
        assertEq(position.underlyingAmount, int256(uint256(0)));
        assertEq(position.exerciseAsset, testExerciseAsset);
        assertEq(position.exerciseAmount, int256(uint256(amountWritten * testExerciseAmount)));
    }

    /*//////////////////////////////////////////////////////////////
    //  function tokenType(uint256 tokenId) external view returns (TokenType typeOfToken);
    //////////////////////////////////////////////////////////////*/

    function test_unitTokenTypeReturnsNone() public {
        _assertTokenIsNone(127);
    }

    function test_unitTokenTypeReturnsOption() public {
        _assertTokenIsOption(testOptionId);
    }

    function test_unitTokenTypeReturnsClaim() public {
        vm.prank(ALICE);
        uint256 claimId = engine.write(testOptionId, 1);
        _assertTokenIsClaim(claimId);
    }

    /*//////////////////////////////////////////////////////////////
    //  function tokenURIGenerator() external view returns (ITokenURIGenerator uriGenerator);
    //////////////////////////////////////////////////////////////*/

    function test_unitTokenURIGenerator() public view {
        assert(address(engine.tokenURIGenerator()) == address(generator));
    }

    /*//////////////////////////////////////////////////////////////
    //  function feeBalance(address token) external view returns (uint256);
    //////////////////////////////////////////////////////////////*/

    function test_unitFeeBalanceFeeOn() public {
        assertEq(engine.feeBalance(testUnderlyingAsset), 0);
        assertEq(engine.feeBalance(testExerciseAsset), 0);

        vm.prank(ALICE);
        engine.write(testOptionId, 2);

        // Fee is recorded on the exercise asset
        uint256 underlyingAmount = 2 * testUnderlyingAmount;
        uint256 underlyingFee = (underlyingAmount * engine.feeBps()) / 10_000;
        assertEq(engine.feeBalance(address(WETHLIKE)), underlyingFee);

        vm.prank(ALICE);
        engine.safeTransferFrom(ALICE, BOB, testOptionId, 2, "");

        // Bob exercises 2
        vm.warp(testExerciseTimestamp);
        vm.prank(BOB);
        engine.exercise(testOptionId, 2);

        // Fee is recorded on the exercise asset
        uint256 exerciseAmount = 2 * testExerciseAmount;
        uint256 exerciseFee = (exerciseAmount * engine.feeBps()) / 10_000;
        assertEq(engine.feeBalance(address(DAILIKE)), exerciseFee);
    }

    function test_unitFeeBalanceFeeOff() public {
        assertEq(engine.feeBalance(testUnderlyingAsset), 0);
        assertEq(engine.feeBalance(testExerciseAsset), 0);

        vm.prank(FEE_TO);
        engine.setFeesEnabled(false);

        vm.prank(ALICE);
        engine.write(testOptionId, 2);

        assertEq(engine.feeBalance(address(WETHLIKE)), 0);

        vm.prank(ALICE);
        engine.safeTransferFrom(ALICE, BOB, testOptionId, 2, "");

        // Bob exercises 2
        vm.warp(testExerciseTimestamp);
        vm.prank(BOB);
        engine.exercise(testOptionId, 2);

        assertEq(engine.feeBalance(address(DAILIKE)), 0);
    }

    function test_unitFeeBalanceMinimum() public {
        vm.startPrank(ALICE);
        uint256 optionId = engine.newOptionType(
            address(ERC20A), 1, address(ERC20B), 15, uint40(block.timestamp), uint40(block.timestamp + 30 days)
        );
        engine.write(optionId, 1);
        assertEq(engine.feeBalance(address(ERC20A)), 1);

        engine.safeTransferFrom(ALICE, BOB, optionId, 1, "");
        vm.stopPrank();

        // Warp right before expiry time and Bob exercises
        vm.warp(block.timestamp + 30 days - 1 seconds);
        vm.prank(BOB);
        engine.exercise(optionId, 1);

        // Check balances after exercise
        assertEq(engine.feeBalance(address(ERC20B)), 1);
    }

    /*//////////////////////////////////////////////////////////////
    //  function feeBps() external view returns (uint8 fee);
    //////////////////////////////////////////////////////////////*/

    function test_unitFeeBps() public {
        assertEq(engine.feeBps(), 5);
    }

    /*//////////////////////////////////////////////////////////////
    //  function feesEnabled() external view returns (bool enabled);
    //////////////////////////////////////////////////////////////*/

    function test_unitFeesEnabled() public {
        assertEq(engine.feesEnabled(), true);
    }

    /*//////////////////////////////////////////////////////////////
    //  function feeTo() external view returns (address);
    //////////////////////////////////////////////////////////////*/

    function test_unitFeeTo() public {
        assertEq(engine.feeTo(), FEE_TO);
    }

    /*//////////////////////////////////////////////////////////////
    // function newOptionType(
    //        address underlyingAsset,
    //        uint96 underlyingAmount,
    //        address exerciseAsset,
    //        uint96 exerciseAmount,
    //        uint40 exerciseTimestamp,
    //        uint40 expiryTimestamp
    //    ) external returns (uint256 optionId);
    //////////////////////////////////////////////////////////////*/

    function test_unitNewOptionType() public {
        IOptionSettlementEngine.Option memory optionInfo = IOptionSettlementEngine.Option({
            underlyingAsset: address(DAILIKE),
            underlyingAmount: testUnderlyingAmount,
            exerciseAsset: address(WETHLIKE),
            exerciseAmount: testExerciseAmount,
            exerciseTimestamp: testExerciseTimestamp,
            expiryTimestamp: testExpiryTimestamp,
            settlementSeed: 0,
            nextClaimKey: 0
        });

        uint256 expectedOptionId = _createOptionIdFromStruct(optionInfo);

        vm.expectEmit(true, true, true, true);
        emit NewOptionType(
            expectedOptionId,
            address(WETHLIKE),
            address(DAILIKE),
            testExerciseAmount,
            testUnderlyingAmount,
            testExerciseTimestamp,
            testExpiryTimestamp
            );

        engine.newOptionType(
            address(DAILIKE),
            testUnderlyingAmount,
            address(WETHLIKE),
            testExerciseAmount,
            testExerciseTimestamp,
            testExpiryTimestamp
        );
    }

    // Fail tests

    function test_unitRevertNewOptionTypeWhenOptionsTypeExists() public {
        vm.expectRevert(abi.encodeWithSelector(IOptionSettlementEngine.OptionsTypeExists.selector, testOptionId));
        _createNewOptionType({
            underlyingAsset: address(WETHLIKE),
            underlyingAmount: testUnderlyingAmount,
            exerciseAsset: address(DAILIKE),
            exerciseAmount: testExerciseAmount,
            exerciseTimestamp: testExerciseTimestamp,
            expiryTimestamp: testExpiryTimestamp
        });
    }

    function test_unitRevertNewOptionTypeWhenExpiryWindowTooShort() public {
        uint40 tooSoonExpiryTimestamp = uint40(block.timestamp + 1 days - 1 seconds);
        IOptionSettlementEngine.Option memory option = IOptionSettlementEngine.Option({
            underlyingAsset: address(DAILIKE),
            underlyingAmount: testUnderlyingAmount,
            exerciseAsset: address(WETHLIKE),
            exerciseAmount: testExerciseAmount,
            exerciseTimestamp: uint40(block.timestamp),
            expiryTimestamp: tooSoonExpiryTimestamp,
            settlementSeed: 0, // default zero for settlement seed
            nextClaimKey: 0 // default zero for next claim id
        });
        _createOptionIdFromStruct(option);

        vm.expectRevert(
            abi.encodeWithSelector(IOptionSettlementEngine.ExpiryWindowTooShort.selector, testExpiryTimestamp - 1)
        );
        engine.newOptionType({
            underlyingAsset: address(WETHLIKE),
            underlyingAmount: testUnderlyingAmount,
            exerciseAsset: address(DAILIKE),
            exerciseAmount: testExerciseAmount,
            exerciseTimestamp: testExerciseTimestamp,
            expiryTimestamp: testExpiryTimestamp - 1
        });
    }

    function test_unitRevertNewOptionTypeWhenExerciseWindowTooShort() public {
        vm.expectRevert(
            abi.encodeWithSelector(IOptionSettlementEngine.ExerciseWindowTooShort.selector, uint40(block.timestamp + 1))
        );
        engine.newOptionType({
            underlyingAsset: address(WETHLIKE),
            underlyingAmount: testUnderlyingAmount,
            exerciseAsset: address(DAILIKE),
            exerciseAmount: testExerciseAmount,
            exerciseTimestamp: uint40(block.timestamp + 1),
            expiryTimestamp: testExpiryTimestamp
        });
    }

    function test_unitRevertNewOptionTypeWhenInvalidAssets() public {
        vm.expectRevert(
            abi.encodeWithSelector(IOptionSettlementEngine.InvalidAssets.selector, address(DAILIKE), address(DAILIKE))
        );
        _createNewOptionType({
            underlyingAsset: address(DAILIKE),
            underlyingAmount: testUnderlyingAmount,
            exerciseAsset: address(DAILIKE),
            exerciseAmount: testExerciseAmount,
            exerciseTimestamp: testExerciseTimestamp,
            expiryTimestamp: testExpiryTimestamp
        });
    }

    function test_unitRevertNewOptionTypeWhenTotalSuppliesAreTooLowToExercise() public {
        uint96 underlyingAmountExceedsTotalSupply = uint96(IERC20(address(DAILIKE)).totalSupply() + 1);

        vm.expectRevert(
            abi.encodeWithSelector(IOptionSettlementEngine.InvalidAssets.selector, address(DAILIKE), address(WETHLIKE))
        );

        _createNewOptionType({
            underlyingAsset: address(DAILIKE),
            underlyingAmount: underlyingAmountExceedsTotalSupply,
            exerciseAsset: address(WETHLIKE),
            exerciseAmount: testExerciseAmount,
            exerciseTimestamp: testExerciseTimestamp,
            expiryTimestamp: testExpiryTimestamp
        });

        uint96 exerciseAmountExceedsTotalSupply = uint96(IERC20(address(USDCLIKE)).totalSupply() + 1);

        vm.expectRevert(
            abi.encodeWithSelector(IOptionSettlementEngine.InvalidAssets.selector, address(USDCLIKE), address(WETHLIKE))
        );

        _createNewOptionType({
            underlyingAsset: address(USDCLIKE),
            underlyingAmount: testUnderlyingAmount,
            exerciseAsset: address(WETHLIKE),
            exerciseAmount: exerciseAmountExceedsTotalSupply,
            exerciseTimestamp: testExerciseTimestamp,
            expiryTimestamp: testExpiryTimestamp
        });
    }

    /*//////////////////////////////////////////////////////////////
    // function write(uint256 tokenId, uint112 amount) external returns (uint256 claimId);
    //////////////////////////////////////////////////////////////*/

    function test_unitWriteWhenNewClaim() public {
        uint256 expectedFeeAccruedAmount = ((testUnderlyingAmount / 10_000) * engine.feeBps());

        vm.expectEmit(true, true, true, true);
        emit FeeAccrued(testOptionId, address(WETHLIKE), ALICE, expectedFeeAccruedAmount);

        vm.expectEmit(true, true, true, true);
        emit OptionsWritten(testOptionId, ALICE, testOptionId + 1, 1);

        vm.prank(ALICE);
        engine.write(testOptionId, 1);
    }

    function test_unitWriteWhenExistingClaim() public {
        uint256 expectedFeeAccruedAmount = ((testUnderlyingAmount / 10_000) * engine.feeBps());

        vm.prank(ALICE);
        uint256 claimId = engine.write(testOptionId, 1);

        vm.expectEmit(true, true, true, true);
        emit FeeAccrued(testOptionId, address(WETHLIKE), ALICE, expectedFeeAccruedAmount);

        vm.expectEmit(true, true, true, true);
        emit OptionsWritten(testOptionId, ALICE, claimId, 1);

        vm.prank(ALICE);
        engine.write(claimId, 1);
    }

    function test_unitWriteFeeOff() public {
        vm.prank(FEE_TO);
        engine.setFeesEnabled(false);

        vm.expectEmit(true, true, true, true);
        emit OptionsWritten(testOptionId, ALICE, testOptionId + 1, 1);

        vm.prank(ALICE);
        engine.write(testOptionId, 1);
    }

    // Fail tests

    function test_unitRevertWriteWhenAmountWrittenCannotBeZero() public {
        uint112 invalidWriteAmount = 0;

        vm.expectRevert(IOptionSettlementEngine.AmountWrittenCannotBeZero.selector);

        engine.write(testOptionId, invalidWriteAmount);
    }

    function test_unitRevertWriteWhenInvalidOption() public {
        // Option ID not 0 in lower 96 b
        uint256 invalidOptionId = testOptionId + 1;
        // Option ID not initialized
        invalidOptionId = encodeTokenId(0x1, 0x0);
        vm.expectRevert(abi.encodeWithSelector(IOptionSettlementEngine.InvalidOption.selector, invalidOptionId));
        engine.write(invalidOptionId, 1);
    }

    function test_unitRevertWriteWhenExpiredOption() public {
        vm.warp(testExpiryTimestamp + 1 seconds);

        vm.expectRevert(
            abi.encodeWithSelector(IOptionSettlementEngine.ExpiredOption.selector, testOptionId, testExpiryTimestamp)
        );

        vm.prank(ALICE);
        engine.write(testOptionId, 1);
    }

    function test_unitRevertWriteWhenCallerDoesNotOwnClaimId() public {
        vm.startPrank(ALICE);
        uint256 claimId = engine.write(testOptionId, 1);
        vm.stopPrank();

        vm.expectRevert(abi.encodeWithSelector(IOptionSettlementEngine.CallerDoesNotOwnClaimId.selector, claimId));

        vm.prank(BOB);
        engine.write(claimId, 1);
    }

    /*//////////////////////////////////////////////////////////////
    // function redeem(uint256 claimId) external;
    //////////////////////////////////////////////////////////////*/

    function test_unitRedeemUnexercised() public {
        vm.startPrank(ALICE);
        uint256 amountWritten = 7;
        uint256 claimId = engine.write(testOptionId, uint112(amountWritten));
        uint256 expectedUnderlyingAmount = testUnderlyingAmount * amountWritten;

        vm.warp(testExpiryTimestamp);

        vm.expectEmit(true, true, true, true);
        emit ClaimRedeemed(
            claimId,
            testOptionId,
            ALICE,
            0, // no one has exercised
            expectedUnderlyingAmount
            );

        engine.redeem(claimId);
    }

    function testRedeemPartialExercise() public {
        vm.startPrank(ALICE);
        uint256 amountWritten = 7;
        uint256 claimId = engine.write(testOptionId, uint112(amountWritten));
        uint256 expectedExerciseAmount = testExerciseAmount * 3;

        vm.warp(testExerciseTimestamp);

        engine.exercise(testOptionId, 3);

        uint256 expectedUnderlyingAmount = testUnderlyingAmount * 11;

        engine.write(claimId, uint112(amountWritten));

        vm.warp(testExpiryTimestamp);

        vm.expectEmit(true, true, true, true);
        emit ClaimRedeemed(claimId, testOptionId, ALICE, expectedExerciseAmount, expectedUnderlyingAmount);

        engine.redeem(claimId);
    }

    function testRedeemExercised() public {
        vm.startPrank(ALICE);
        uint256 amountWritten = 7;
        uint256 claimId = engine.write(testOptionId, uint112(amountWritten));
        uint256 expectedExerciseAmount = testExerciseAmount * amountWritten;

        vm.warp(testExerciseTimestamp);

        engine.exercise(testOptionId, uint112(amountWritten));

        vm.warp(testExpiryTimestamp);

        vm.expectEmit(true, true, true, true);
        emit ClaimRedeemed(claimId, testOptionId, ALICE, expectedExerciseAmount, 0);

        engine.redeem(claimId);
    }

    // Fail tests

    function test_unitRevertRedeemWhenInvalidClaim() public {
        uint256 badClaimId = encodeTokenId(0xDEADBEEF, 0);

        vm.expectRevert(abi.encodeWithSelector(IOptionSettlementEngine.InvalidClaim.selector, badClaimId));

        vm.prank(ALICE);
        engine.redeem(badClaimId);
    }

    function test_unitRevertRedeemWhenCallerDoesNotOwnClaimId() public {
        // Alice writes and transfers to Bob, then Alice tries to redeem
        vm.startPrank(ALICE);
        uint256 claimId = engine.write(testOptionId, 1);
        engine.safeTransferFrom(ALICE, BOB, claimId, 1, "");

        vm.warp(testExpiryTimestamp);

        vm.expectRevert(abi.encodeWithSelector(IOptionSettlementEngine.CallerDoesNotOwnClaimId.selector, claimId));

        engine.redeem(claimId);
        vm.stopPrank();

        // Carol feels left out and tries to redeem what she can't
        vm.expectRevert(abi.encodeWithSelector(IOptionSettlementEngine.CallerDoesNotOwnClaimId.selector, claimId));

        vm.prank(CAROL);
        engine.redeem(claimId);

        // Bob redeems, which burns the Claim NFT, and then is unable to redeem a second time
        vm.startPrank(BOB);
        engine.redeem(claimId);

        vm.expectRevert(abi.encodeWithSelector(IOptionSettlementEngine.CallerDoesNotOwnClaimId.selector, claimId));

        engine.redeem(claimId);
        vm.stopPrank();
    }

    function test_unitRevertRedeemWhenClaimTooSoon() public {
        vm.startPrank(ALICE);
        uint256 claimId = engine.write(testOptionId, 1);

        vm.warp(testExerciseTimestamp - 1 seconds);

        vm.expectRevert(
            abi.encodeWithSelector(IOptionSettlementEngine.ClaimTooSoon.selector, claimId, testExpiryTimestamp)
        );

        engine.redeem(claimId);
    }

    /*//////////////////////////////////////////////////////////////
    // function exercise(uint256 optionId, uint112 amount) external;
    //////////////////////////////////////////////////////////////*/

    /*//////////////////////////////////////////////////////////////
    // function setFeesEnabled(bool enabled) external;
    //////////////////////////////////////////////////////////////*/

    /*//////////////////////////////////////////////////////////////
    // function setFeeTo(address newFeeTo) external;
    //////////////////////////////////////////////////////////////*/

    /*//////////////////////////////////////////////////////////////
    // function setTokenURIGenerator(address newTokenURIGenerator) external;
    //////////////////////////////////////////////////////////////*/

    /*//////////////////////////////////////////////////////////////
    // function sweepFees(address[] memory tokens) external;
    //////////////////////////////////////////////////////////////*/

    // TODO(Categorize and dedup/audit tests below this line)

    function testExerciseBeforeExpiry() public {
        // Alice writes
        vm.startPrank(ALICE);
        engine.write(testOptionId, 1);
        engine.safeTransferFrom(ALICE, BOB, testOptionId, 1, "");
        vm.stopPrank();

        // Fast-forward to just before expiry
        vm.warp(testExpiryTimestamp - 1);

        // Bob exercises
        vm.startPrank(BOB);
        engine.exercise(testOptionId, 1);
        vm.stopPrank();

        assertEq(engine.balanceOf(BOB, testOptionId), 0);
    }

    function testWriteExerciseAddBuckets() public {
        vm.startPrank(ALICE);
        uint256[7] memory claimRatios;
        uint112 targetBuckets = 7;
        uint256 i;
        for (i = 0; i < targetBuckets; i++) {
            engine.write(testOptionId, targetBuckets);
            engine.exercise(testOptionId, 1);
        }

        // 49 written, 7 exercised
        for (i = 1; i <= targetBuckets; i++) {
            IOptionSettlementEngine.Claim memory claimData = engine.claim(testOptionId + i);
            uint256 claimRatio = FixedPointMathLib.divWadDown(claimData.amountExercised, claimData.amountWritten);
            emit log_named_uint("amount written WAD     ", claimData.amountWritten);
            emit log_named_uint("amount exercised WAD   ", claimData.amountExercised);
            // dividing by the amount written in the claim recovers the bucket ratio WAD
            emit log_named_uint("claim ratio WAD        ", claimRatio);
            claimRatios[i - 1] = claimRatio;
        }

        uint256 bucketRatio0 = FixedPointMathLib.divWadDown(3, 7);
        uint256 bucketRatio1 = FixedPointMathLib.divWadDown(2, 7);
        uint256 bucketRatio2 = 0;

        // Claim 1 is exercised in a ratio of 3/7
        assertEq(claimRatios[0], bucketRatio0);

        // Claims 2 and 3 are exercised in a ratio of 2/7
        assertEq(claimRatios[1], bucketRatio1);
        assertEq(claimRatios[2], bucketRatio1);

        // Claims 4, 5, 6, and 7 are not exercised (0/7)
        assertEq(claimRatios[3], bucketRatio2);
        assertEq(claimRatios[4], bucketRatio2);
        assertEq(claimRatios[5], bucketRatio2);
        assertEq(claimRatios[6], bucketRatio2);
    }

    function testWriteMultipleWriteSameOptionType() public {
        // Alice writes a few options and later decides to write more
        vm.startPrank(ALICE);
        uint256 claimId1 = engine.write(testOptionId, 69);
        vm.warp(block.timestamp + 100);
        uint256 claimId2 = engine.write(testOptionId, 100);
        vm.stopPrank();

        assertEq(engine.balanceOf(ALICE, testOptionId), 169);
        assertEq(engine.balanceOf(ALICE, claimId1), 1);
        assertEq(engine.balanceOf(ALICE, claimId2), 1);

        IOptionSettlementEngine.Position memory claimPosition = engine.position(claimId1);
        (uint160 _optionId, uint96 claimIdx) = decodeTokenId(claimId1);
        uint256 optionId = uint256(_optionId) << 96;
        assertEq(optionId, testOptionId);
        assertEq(claimIdx, 1);
        assertEq(uint256(claimPosition.underlyingAmount), 69 * testUnderlyingAmount);
        _assertClaimAmountExercised(claimId1, 0);

        claimPosition = engine.position(claimId2);
        (optionId, claimIdx) = decodeTokenId(claimId2);
        optionId = uint256(_optionId) << 96;
        assertEq(optionId, testOptionId);
        assertEq(claimIdx, 2);
        assertEq(uint256(claimPosition.underlyingAmount), 100 * testUnderlyingAmount);
        _assertClaimAmountExercised(claimId2, 0);
    }

    function testTokenURI() public view {
        engine.uri(testOptionId);
    }

    function testExerciseMultipleWriteSameChain() public {
        uint256 wethBalanceEngine = WETHLIKE.balanceOf(address(engine));
        uint256 wethBalanceA = WETHLIKE.balanceOf(ALICE);
        uint256 wethBalanceB = WETHLIKE.balanceOf(BOB);
        uint256 daiBalanceEngine = DAILIKE.balanceOf(address(engine));
        uint256 daiBalanceA = DAILIKE.balanceOf(ALICE);
        uint256 daiBalanceB = DAILIKE.balanceOf(BOB);

        // Alice writes 1, decides to write another, and sends both to Bob to exercise
        vm.startPrank(ALICE);
        engine.write(testOptionId, 1);
        engine.write(testOptionId, 1);
        engine.safeTransferFrom(ALICE, BOB, testOptionId, 2, "");
        vm.stopPrank();

        assertEq(engine.balanceOf(ALICE, testOptionId), 0);
        assertEq(engine.balanceOf(BOB, testOptionId), 2);

        // Fees
        uint256 writeAmount = 2 * testUnderlyingAmount;
        uint256 writeFee = (writeAmount / 10000) * engine.feeBps();

        uint256 exerciseAmount = 2 * testExerciseAmount;
        uint256 exerciseFee = (exerciseAmount / 10000) * engine.feeBps();

        assertEq(WETHLIKE.balanceOf(address(engine)), wethBalanceEngine + writeAmount + writeFee);

        vm.warp(testExpiryTimestamp - 1);
        // Bob exercises
        vm.prank(BOB);
        engine.exercise(testOptionId, 2);
        assertEq(engine.balanceOf(BOB, testOptionId), 0);

        assertEq(WETHLIKE.balanceOf(address(engine)), wethBalanceEngine + writeFee);
        assertEq(WETHLIKE.balanceOf(ALICE), wethBalanceA - writeAmount - writeFee);
        assertEq(WETHLIKE.balanceOf(BOB), wethBalanceB + writeAmount);
        assertEq(DAILIKE.balanceOf(address(engine)), daiBalanceEngine + exerciseAmount + exerciseFee);
        assertEq(DAILIKE.balanceOf(ALICE), daiBalanceA);
        assertEq(DAILIKE.balanceOf(BOB), daiBalanceB - exerciseAmount - exerciseFee);
    }

    function testExerciseIncompleteExercise() public {
        // Alice writes
        vm.startPrank(ALICE);
        engine.write(testOptionId, 100);
        engine.safeTransferFrom(ALICE, BOB, testOptionId, 100, "");
        vm.stopPrank();

        // Fast-forward to just before expiry
        vm.warp(testExpiryTimestamp - 1);

        // Bob exercises
        vm.startPrank(BOB);
        engine.exercise(testOptionId, 50);

        // Bob exercises again
        engine.exercise(testOptionId, 50);
        vm.stopPrank();

        assertEq(engine.balanceOf(BOB, testOptionId), 0);
    }

    // NOTE: This test needed as testFuzz_redeem does not check if exerciseAmount == 0
    function testRedeemNotExercised() public {
        IOptionSettlementEngine.Position memory claimPosition;
        uint256 wethBalanceEngine = WETHLIKE.balanceOf(address(engine));
        uint256 wethBalanceA = WETHLIKE.balanceOf(ALICE);
        // Alice writes 7 and no one exercises
        vm.startPrank(ALICE);
        uint256 claimId = engine.write(testOptionId, 7);

        vm.warp(testExpiryTimestamp + 1);

        claimPosition = engine.position(claimId);
        assertTrue(claimPosition.underlyingAmount != 0);

        engine.redeem(claimId);
        vm.expectRevert(abi.encodeWithSelector(IOptionSettlementEngine.TokenNotFound.selector, claimId));
        engine.position(claimId);

        // Fees
        uint256 writeAmount = 7 * testUnderlyingAmount;
        uint256 writeFee = (writeAmount / 10000) * engine.feeBps();
        assertEq(WETHLIKE.balanceOf(ALICE), wethBalanceA - writeFee);
        assertEq(WETHLIKE.balanceOf(address(engine)), wethBalanceEngine + writeFee);
    }

    function testExerciseWithDifferentDecimals() public {
        // Write an option where one of the assets isn't 18 decimals
        (uint256 newOptionId,) = _createNewOptionType({
            underlyingAsset: address(USDCLIKE),
            underlyingAmount: 100,
            exerciseAsset: address(DAILIKE),
            exerciseAmount: testExerciseAmount,
            exerciseTimestamp: testExerciseTimestamp,
            expiryTimestamp: testExpiryTimestamp
        });

        // Alice writes
        vm.startPrank(ALICE);
        engine.write(newOptionId, 1);
        engine.safeTransferFrom(ALICE, BOB, newOptionId, 1, "");
        vm.stopPrank();

        // Bob owns 1 of these options
        assertEq(engine.balanceOf(BOB, newOptionId), 1);

        // Fast-forward to just before expiry
        vm.warp(testExpiryTimestamp - 1 seconds);

        // Bob exercises
        vm.startPrank(BOB);
        engine.exercise(newOptionId, 1);
        vm.stopPrank();

        // Now Bob owns 0 of these options
        assertEq(engine.balanceOf(BOB, newOptionId), 0);
    }

    function testWriteAfterFullyExercisingDay() public {
        uint256 claim1 = _writeAndExerciseOption(testOptionId, ALICE, BOB, 1, 1);
        uint256 claim2 = _writeAndExerciseOption(testOptionId, ALICE, BOB, 1, 1);

        IOptionSettlementEngine.Position memory position = engine.position(claim1);
        _assertPosition(position.underlyingAmount, 0);
        _assertPosition(position.exerciseAmount, testExerciseAmount);

        position = engine.position(claim2);
        _assertPosition(position.underlyingAmount, 0);
        _assertPosition(position.exerciseAmount, testExerciseAmount);
    }

    // **********************************************************************
    //                            PROTOCOL ADMIN
    // **********************************************************************

    function testSetFeesEnabled() public {
        // precondition check -- in test suite, fee switch is enabled by default
        assertTrue(engine.feesEnabled());

        // disable
        vm.startPrank(FEE_TO);
        engine.setFeesEnabled(false);

        assertFalse(engine.feesEnabled());

        // enable
        engine.setFeesEnabled(true);

        assertTrue(engine.feesEnabled());
    }

    function testEventSetFeesEnabled() public {
        vm.expectEmit(true, true, true, true);
        emit FeeSwitchUpdated(FEE_TO, false);

        // disable
        vm.startPrank(FEE_TO);
        engine.setFeesEnabled(false);

        vm.expectEmit(true, true, true, true);
        emit FeeSwitchUpdated(FEE_TO, true);

        // enable
        engine.setFeesEnabled(true);
    }

    function testRevertSetFeesEnabledWhenNotFeeTo() public {
        vm.expectRevert(abi.encodeWithSelector(IOptionSettlementEngine.AccessControlViolation.selector, ALICE, FEE_TO));

        vm.prank(ALICE);
        engine.setFeesEnabled(true);
    }

    function testRevertConstructorWhenFeeToIsZeroAddress() public {
        TokenURIGenerator localGenerator = new TokenURIGenerator();

        vm.expectRevert(abi.encodeWithSelector(IOptionSettlementEngine.InvalidAddress.selector, address(0)));

        new OptionSettlementEngine(address(0), address(localGenerator));
    }

    function testRevertConstructorWhenTokenURIGeneratorIsZeroAddress() public {
        vm.expectRevert(abi.encodeWithSelector(IOptionSettlementEngine.InvalidAddress.selector, address(0)));

        new OptionSettlementEngine(FEE_TO, address(0));
    }

    function testSetFeeTo() public {
        // precondition check
        assertEq(engine.feeTo(), FEE_TO);

        vm.prank(FEE_TO);
        engine.setFeeTo(address(0xCAFE));

        assertEq(engine.feeTo(), address(0xCAFE));
    }

    function testEventSetFeeTo() public {
        vm.expectEmit(true, true, true, true);
        emit FeeToUpdated(address(0xCAFE));

        vm.prank(FEE_TO);
        engine.setFeeTo(address(0xCAFE));

        assertEq(engine.feeTo(), address(0xCAFE));
    }

    function testRevertSetFeeToWhenNotCurrentFeeTo() public {
        vm.expectRevert(abi.encodeWithSelector(IOptionSettlementEngine.AccessControlViolation.selector, ALICE, FEE_TO));
        vm.prank(ALICE);
        engine.setFeeTo(address(0xCAFE));
    }

    function testRevertSetFeeToWhenZeroAddress() public {
        vm.expectRevert(abi.encodeWithSelector(IOptionSettlementEngine.InvalidAddress.selector, address(0)));
        vm.prank(FEE_TO);
        engine.setFeeTo(address(0));
    }

    function testSetTokenURIGenerator() public {
        TokenURIGenerator newTokenURIGenerator = new TokenURIGenerator();

        vm.prank(FEE_TO);
        engine.setTokenURIGenerator(address(newTokenURIGenerator));

        assertEq(address(engine.tokenURIGenerator()), address(newTokenURIGenerator));
    }

    function testEventSetTokenURIGenerator() public {
        TokenURIGenerator newTokenURIGenerator = new TokenURIGenerator();

        vm.expectEmit(true, true, true, true);
        emit TokenURIGeneratorUpdated(address(newTokenURIGenerator));

        vm.prank(FEE_TO);
        engine.setTokenURIGenerator(address(newTokenURIGenerator));
    }

    function testRevertSetTokenURIGeneratorWhenNotCurrentFeeTo() public {
        vm.expectRevert(abi.encodeWithSelector(IOptionSettlementEngine.AccessControlViolation.selector, ALICE, FEE_TO));
        vm.prank(ALICE);
        engine.setTokenURIGenerator(address(0xCAFE));
    }

    function testRevertSetTokenURIGeneratorWhenZeroAddress() public {
        vm.expectRevert(abi.encodeWithSelector(IOptionSettlementEngine.InvalidAddress.selector, address(0)));
        vm.prank(FEE_TO);
        engine.setTokenURIGenerator(address(0));
    }

    // **********************************************************************
    //                            EVENT TESTS
    // **********************************************************************

    function testEventExercise() public {
        vm.startPrank(ALICE);
        engine.write(testOptionId, 1);
        engine.safeTransferFrom(ALICE, BOB, testOptionId, 1, "");
        vm.stopPrank();

        vm.warp(testExpiryTimestamp - 1 seconds);

        decodeTokenId(testOptionId);
        uint256 expectedFeeAccruedAmount = (testExerciseAmount / 10_000) * engine.feeBps();

        vm.expectEmit(true, true, true, true);
        emit FeeAccrued(testOptionId, address(DAILIKE), BOB, expectedFeeAccruedAmount);

        vm.expectEmit(true, true, true, true);
        emit OptionsExercised(testOptionId, BOB, 1);

        vm.prank(BOB);
        engine.exercise(testOptionId, 1);
    }

    function testSweepFeesWhenFeesAccruedForWrite() public {
        address[] memory tokens = new address[](3);
        tokens[0] = address(WETHLIKE);
        tokens[1] = address(DAILIKE);
        tokens[2] = address(USDCLIKE);

        uint96 daiUnderlyingAmount = 9 * 10 ** 18;
        uint96 usdcUnderlyingAmount = 7 * 10 ** 6; // not 18 decimals

        uint8 optionsWrittenWethUnderlying = 3;
        uint8 optionsWrittenDaiUnderlying = 4;
        uint8 optionsWrittenUsdcUnderlying = 5;

        // Write option that will generate WETH fees
        vm.startPrank(ALICE);
        engine.write(testOptionId, optionsWrittenWethUnderlying);

        // Write option that will generate DAI fees
        (uint256 daiOptionId,) = _createNewOptionType({
            underlyingAsset: address(DAILIKE),
            underlyingAmount: daiUnderlyingAmount,
            exerciseAsset: address(WETHLIKE),
            exerciseAmount: testExerciseAmount,
            exerciseTimestamp: testExerciseTimestamp,
            expiryTimestamp: testExpiryTimestamp
        });
        engine.write(daiOptionId, optionsWrittenDaiUnderlying);

        // Write option that will generate USDC fees
        (uint256 usdcOptionId,) = _createNewOptionType({
            underlyingAsset: address(USDCLIKE),
            underlyingAmount: usdcUnderlyingAmount,
            exerciseAsset: address(DAILIKE),
            exerciseAmount: testExerciseAmount,
            exerciseTimestamp: testExerciseTimestamp,
            expiryTimestamp: testExpiryTimestamp
        });
        engine.write(usdcOptionId, optionsWrittenUsdcUnderlying);
        vm.stopPrank();

        // Then assert expected fee amounts
        uint256[] memory expectedFees = new uint256[](3);
        expectedFees[0] = (((testUnderlyingAmount * optionsWrittenWethUnderlying) / 10_000) * engine.feeBps());
        expectedFees[1] = (((daiUnderlyingAmount * optionsWrittenDaiUnderlying) / 10_000) * engine.feeBps());
        expectedFees[2] = (((usdcUnderlyingAmount * optionsWrittenUsdcUnderlying) / 10_000) * engine.feeBps());

        // Pre feeTo balance check
        assertEq(WETHLIKE.balanceOf(FEE_TO), 0);
        assertEq(DAILIKE.balanceOf(FEE_TO), 0);
        assertEq(USDCLIKE.balanceOf(FEE_TO), 0);

        for (uint256 i = 0; i < tokens.length; i++) {
            vm.expectEmit(true, true, true, true);
            emit FeeSwept(tokens[i], engine.feeTo(), expectedFees[i] - 1); // sweeps 1 wei less as gas optimization
        }

        // When fees are swept
        engine.sweepFees(tokens);

        // Post feeTo balance check, first sweep
        uint256 feeToBalanceWeth = WETHLIKE.balanceOf(FEE_TO);
        uint256 feeToBalanceDai = DAILIKE.balanceOf(FEE_TO);
        uint256 feeToBalanceUsdc = USDCLIKE.balanceOf(FEE_TO);
        assertEq(feeToBalanceWeth, expectedFees[0] - 1);
        assertEq(feeToBalanceDai, expectedFees[1] - 1);
        assertEq(feeToBalanceUsdc, expectedFees[2] - 1);

        // Write and sweep again, but assert this time we sweep the true fee amount,
        // not 1 wei less, bc we've already done the gas optimization
        optionsWrittenWethUnderlying = 6;
        optionsWrittenDaiUnderlying = 3;
        optionsWrittenUsdcUnderlying = 2;
        vm.startPrank(ALICE);
        engine.write(testOptionId, optionsWrittenWethUnderlying);
        engine.write(daiOptionId, optionsWrittenDaiUnderlying);
        engine.write(usdcOptionId, optionsWrittenUsdcUnderlying);
        vm.stopPrank();
        expectedFees[0] = (((testUnderlyingAmount * optionsWrittenWethUnderlying) / 10_000) * engine.feeBps());
        expectedFees[1] = (((daiUnderlyingAmount * optionsWrittenDaiUnderlying) / 10_000) * engine.feeBps());
        expectedFees[2] = (((usdcUnderlyingAmount * optionsWrittenUsdcUnderlying) / 10_000) * engine.feeBps());
        for (uint256 i = 0; i < tokens.length; i++) {
            vm.expectEmit(true, true, true, true);
            emit FeeSwept(tokens[i], engine.feeTo(), expectedFees[i]); // true amount
        }
        engine.sweepFees(tokens);

        // Post feeTo balance check, second sweep
        assertEq(WETHLIKE.balanceOf(FEE_TO), feeToBalanceWeth + expectedFees[0]);
        assertEq(DAILIKE.balanceOf(FEE_TO), feeToBalanceDai + expectedFees[1]);
        assertEq(USDCLIKE.balanceOf(FEE_TO), feeToBalanceUsdc + expectedFees[2]);
    }

    function testSweepFeesWhenFeesAccruedForExercise() public {
        address[] memory tokens = new address[](3);
        tokens[0] = address(DAILIKE);
        tokens[1] = address(WETHLIKE);
        tokens[2] = address(USDCLIKE);

        uint96 daiExerciseAmount = 9 * 10 ** 18;
        uint96 wethExerciseAmount = 3 * 10 ** 18;
        uint96 usdcExerciseAmount = 7 * 10 ** 6; // not 18 decimals

        uint8 optionsWrittenDaiExercise = 3;
        uint8 optionsWrittenWethExercise = 4;
        uint8 optionsWrittenUsdcExercise = 5;

        // Write option for WETH-DAI pair
        vm.startPrank(ALICE);
        (uint256 daiExerciseOptionId,) = _createNewOptionType({
            underlyingAsset: address(WETHLIKE),
            underlyingAmount: testUnderlyingAmount,
            exerciseAsset: address(DAILIKE),
            exerciseAmount: daiExerciseAmount,
            exerciseTimestamp: testExerciseTimestamp,
            expiryTimestamp: testExpiryTimestamp
        });
        engine.write(daiExerciseOptionId, optionsWrittenDaiExercise);

        // Write option for DAI-WETH pair
        (uint256 wethExerciseOptionId,) = _createNewOptionType({
            underlyingAsset: address(DAILIKE),
            underlyingAmount: testUnderlyingAmount,
            exerciseAsset: address(WETHLIKE),
            exerciseAmount: wethExerciseAmount,
            exerciseTimestamp: testExerciseTimestamp,
            expiryTimestamp: testExpiryTimestamp
        });
        engine.write(wethExerciseOptionId, optionsWrittenWethExercise);

        // Write option for DAI-USDC pair
        (uint256 usdcExerciseOptionId,) = _createNewOptionType({
            underlyingAsset: address(DAILIKE),
            underlyingAmount: testUnderlyingAmount,
            exerciseAsset: address(USDCLIKE),
            exerciseAmount: usdcExerciseAmount,
            exerciseTimestamp: testExerciseTimestamp,
            expiryTimestamp: testExpiryTimestamp
        });
        engine.write(usdcExerciseOptionId, optionsWrittenUsdcExercise);

        // Write option for USDC-DAI pair, so that USDC feeBalance will be 1 wei after writing
        (uint256 usdcUnderlyingOptionId,) = _createNewOptionType({
            underlyingAsset: address(USDCLIKE),
            underlyingAmount: usdcExerciseAmount,
            exerciseAsset: address(DAILIKE),
            exerciseAmount: daiExerciseAmount,
            exerciseTimestamp: testExerciseTimestamp,
            expiryTimestamp: testExpiryTimestamp
        });
        engine.write(usdcUnderlyingOptionId, 1);

        // Transfer all option contracts to Bob
        engine.safeTransferFrom(ALICE, BOB, daiExerciseOptionId, optionsWrittenDaiExercise, "");
        engine.safeTransferFrom(ALICE, BOB, wethExerciseOptionId, optionsWrittenWethExercise, "");
        engine.safeTransferFrom(ALICE, BOB, usdcExerciseOptionId, optionsWrittenUsdcExercise, "");
        vm.stopPrank();

        vm.warp(testExpiryTimestamp - 1 seconds);

        // Clear away fees generated by writing options
        engine.sweepFees(tokens);

        // Get feeTo balances after sweeping fees from write
        uint256[] memory initialFeeToBalances = new uint256[](3);
        initialFeeToBalances[0] = DAILIKE.balanceOf(FEE_TO);
        initialFeeToBalances[1] = WETHLIKE.balanceOf(FEE_TO);
        initialFeeToBalances[2] = USDCLIKE.balanceOf(FEE_TO);

        // Exercise option that will generate WETH fees
        vm.startPrank(BOB);
        engine.exercise(daiExerciseOptionId, optionsWrittenDaiExercise);

        // // Exercise option that will generate DAI fees
        engine.exercise(wethExerciseOptionId, optionsWrittenWethExercise);

        // Exercise option that will generate USDC fees
        engine.exercise(usdcExerciseOptionId, optionsWrittenUsdcExercise);
        vm.stopPrank();

        // Then assert expected fee amounts, but because this isn't the first fee
        // taken for any of these assets, and the 1 wei-left-behind gas optimization
        // has already happened, therefore actual fee swept amount = true fee amount.
        uint256[] memory expectedFees = new uint256[](3);
        expectedFees[0] = (((daiExerciseAmount * optionsWrittenDaiExercise) / 10_000) * engine.feeBps());
        expectedFees[1] = (((wethExerciseAmount * optionsWrittenWethExercise) / 10_000) * engine.feeBps());
        expectedFees[2] = (((usdcExerciseAmount * optionsWrittenUsdcExercise) / 10_000) * engine.feeBps());

        for (uint256 i = 0; i < tokens.length; i++) {
            vm.expectEmit(true, true, true, true);
            emit FeeSwept(tokens[i], engine.feeTo(), expectedFees[i]);
        }

        // When fees are swept
        engine.sweepFees(tokens);

        // Check feeTo balances after sweeping fees from exercise
        assertEq(DAILIKE.balanceOf(FEE_TO), initialFeeToBalances[0] + expectedFees[0]);
        assertEq(WETHLIKE.balanceOf(FEE_TO), initialFeeToBalances[1] + expectedFees[1]);
        assertEq(USDCLIKE.balanceOf(FEE_TO), initialFeeToBalances[2] + expectedFees[2]);
    }

    // **********************************************************************
    //                            FAIL TESTS
    // **********************************************************************

    function testRevertExerciseBeforeExcercise() public {
        _createNewOptionType({
            underlyingAsset: address(WETHLIKE),
            underlyingAmount: testUnderlyingAmount,
            exerciseAsset: address(DAILIKE),
            exerciseAmount: testExerciseTimestamp + 1,
            exerciseTimestamp: testExerciseTimestamp,
            expiryTimestamp: testExpiryTimestamp + 1
        });

        vm.startPrank(ALICE);
        engine.write(testOptionId, 1);

        vm.stopPrank();
    }

    function testRevertExerciseWhenExerciseTooEarly() public {
        // Alice writes
        vm.startPrank(ALICE);
        engine.write(testOptionId, 1);
        engine.safeTransferFrom(ALICE, BOB, testOptionId, 1, "");
        vm.stopPrank();

        vm.warp(testExerciseTimestamp - 1 seconds);

        // Bob immediately exercises before exerciseTimestamp
        vm.startPrank(BOB);
        vm.expectRevert(
            abi.encodeWithSelector(
                IOptionSettlementEngine.ExerciseTooEarly.selector, testOptionId, testExerciseTimestamp
            )
        );
        engine.exercise(testOptionId, 1);
        vm.stopPrank();
    }

    function testRevertExerciseWhenInvalidOption() public {
        vm.startPrank(ALICE);
        engine.write(testOptionId, 1);

        uint256 invalidOptionId = testOptionId + 1;

        vm.expectRevert(abi.encodeWithSelector(IOptionSettlementEngine.InvalidOption.selector, invalidOptionId));

        engine.exercise(invalidOptionId, 1);
    }

    function testRevertExerciseWhenExpiredOption() public {
        uint256 ts = block.timestamp;
        // ====== Exercise at Expiry =======
        // Alice writes
        vm.startPrank(ALICE);
        engine.write(testOptionId, 1);
        engine.safeTransferFrom(ALICE, BOB, testOptionId, 1, "");
        vm.stopPrank();

        // Fast-forward to at expiry
        vm.warp(testExpiryTimestamp);

        // Bob exercises
        vm.startPrank(BOB);
        vm.expectRevert(
            abi.encodeWithSelector(IOptionSettlementEngine.ExpiredOption.selector, testOptionId, testExpiryTimestamp)
        );
        engine.exercise(testOptionId, 1);
        vm.stopPrank();

        vm.warp(ts);
        // ====== Exercise after Expiry =======
        // Alice writes
        vm.startPrank(ALICE);
        engine.write(testOptionId, 1);
        engine.safeTransferFrom(ALICE, BOB, testOptionId, 1, "");
        vm.stopPrank();

        // Fast-forward to at expiry
        vm.warp(testExpiryTimestamp + 1 seconds);

        // Bob exercises
        vm.startPrank(BOB);
        vm.expectRevert(
            abi.encodeWithSelector(IOptionSettlementEngine.ExpiredOption.selector, testOptionId, testExpiryTimestamp)
        );
        engine.exercise(testOptionId, 1);
        vm.stopPrank();
    }

    function testRevertExerciseWhenCallerHoldsInsufficientOptions() public {
        vm.warp(testExerciseTimestamp + 1 seconds);

        // Should revert if you hold 0
        vm.expectRevert(
            abi.encodeWithSelector(IOptionSettlementEngine.CallerHoldsInsufficientOptions.selector, testOptionId, 1)
        );
        engine.exercise(testOptionId, 1);

        // Should revert if you hold some, but not enough
        vm.startPrank(ALICE);
        engine.write(testOptionId, 1);
        vm.expectRevert(
            abi.encodeWithSelector(IOptionSettlementEngine.CallerHoldsInsufficientOptions.selector, testOptionId, 2)
        );
        engine.exercise(testOptionId, 2);
    }

    function testRevertUriWhenTokenNotFound() public {
        uint256 tokenId = 420;
        vm.expectRevert(abi.encodeWithSelector(IOptionSettlementEngine.TokenNotFound.selector, tokenId));
        engine.uri(420);
    }
}
