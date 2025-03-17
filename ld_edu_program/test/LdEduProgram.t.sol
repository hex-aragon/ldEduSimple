// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {LdEduProgram} from "../src/LdEduProgram.sol";

contract LdEduProgramTest is Test {
    LdEduProgram public program;
    
    address owner = address(1);
    address maker = address(2);
    address validator = address(3);
    address builder = address(4);
    
    uint256 price = 1 ether;
    uint256 startTime;
    uint256 endTime;
    
    function setUp() public {
        // Set the owner as the current block's coinbase and prank as owner
        vm.startPrank(owner);
        
        // Deploy the contract with the owner as the initial owner
        program = new LdEduProgram(owner);
        
        // Stop pranking as owner
        vm.stopPrank();
        
        // Set the start and end times for programs
        startTime = block.timestamp + 1 days;
        endTime = block.timestamp + 7 days;
    }
    
    function testCreateEduProgram() public {
        // Prank as maker and give them some ETH
        vm.deal(maker, 10 ether);
        vm.startPrank(maker);
        
        // Create a program
        program.createEduProgram{value: price}(
            "Test Program",
            price,
            startTime,
            endTime,
            validator
        );
        
        // Check that the program was created correctly
        LdEduProgram.EduProgram memory eduProgram = program.eduPrograms(0);
        assertEq(eduProgram.id, 0);
        assertEq(eduProgram.name, "Test Program");
        assertEq(eduProgram.price, price);
        assertEq(eduProgram.startTime, startTime);
        assertEq(eduProgram.endTime, endTime);
        assertEq(eduProgram.maker, maker);
        assertEq(eduProgram.validator, validator);
        assertFalse(eduProgram.approve);
        assertFalse(eduProgram.claimed);
        assertEq(eduProgram.builder, address(0));
        
        vm.stopPrank();
    }
    
    function testFailCreateEduProgramWithIncorrectAmount() public {
        // Prank as maker and give them some ETH
        vm.deal(maker, 10 ether);
        vm.startPrank(maker);
        
        // Try to create a program with incorrect amount
        program.createEduProgram{value: 0.5 ether}(
            "Test Program",
            price,
            startTime,
            endTime,
            validator
        );
        
        vm.stopPrank();
    }
    
    function testFailCreateEduProgramWithInvalidTimes() public {
        // Prank as maker and give them some ETH
        vm.deal(maker, 10 ether);
        vm.startPrank(maker);
        
        // Try to create a program with end time before start time
        program.createEduProgram{value: price}(
            "Test Program",
            price,
            endTime,
            startTime,
            validator
        );
        
        vm.stopPrank();
    }
    
    function testApproveProgram() public {
        // Create a program first
        testCreateEduProgram();
        
        // Prank as validator
        vm.startPrank(validator);
        
        // Approve the program
        program.approveProgram(0, builder);
        
        // Check that the program was approved correctly
        LdEduProgram.EduProgram memory eduProgram = program.eduPrograms(0);
        assertTrue(eduProgram.approve);
        assertEq(eduProgram.builder, builder);
        
        vm.stopPrank();
    }
    
    function testFailApproveAsProgramMaker() public {
        // Create a program first
        testCreateEduProgram();
        
        // Prank as maker
        vm.startPrank(maker);
        
        // Try to approve the program
        program.approveProgram(0, builder);
        
        vm.stopPrank();
    }
    
    function testFailApproveAfterEndTime() public {
        // Create a program first
        testCreateEduProgram();
        
        // Warp to after the end time
        vm.warp(endTime + 1);
        
        // Prank as validator
        vm.startPrank(validator);
        
        // Try to approve the program
        program.approveProgram(0, builder);
        
        vm.stopPrank();
    }
    
    function testClaimGrants() public {
        // Create and approve a program first
        testApproveProgram();
        
        // Warp to the start time
        vm.warp(startTime);
        
        // Check builder's balance before
        uint256 builderBalanceBefore = address(builder).balance;
        
        // Prank as builder
        vm.startPrank(builder);
        
        // Claim the grants
        program.claimGrants(0);
        
        // Check builder's balance after
        uint256 builderBalanceAfter = address(builder).balance;
        assertEq(builderBalanceAfter - builderBalanceBefore, price);
        
        // Check that the program was claimed
        LdEduProgram.EduProgram memory eduProgram = program.eduPrograms(0);
        assertTrue(eduProgram.claimed);
        
        vm.stopPrank();
    }
    
    function testClaimGrantsWithFee() public {
        // Create and approve a program first
        testApproveProgram();
        
        // Set a fee of 5% (500 basis points)
        vm.startPrank(owner);
        program.setFee(500);
        vm.stopPrank();
        
        // Warp to the start time
        vm.warp(startTime);
        
        // Check builder's and owner's balances before
        uint256 builderBalanceBefore = address(builder).balance;
        uint256 ownerBalanceBefore = address(owner).balance;
        
        // Prank as builder
        vm.startPrank(builder);
        
        // Claim the grants
        program.claimGrants(0);
        
        // Check balances after
        uint256 builderBalanceAfter = address(builder).balance;
        uint256 ownerBalanceAfter = address(owner).balance;
        
        // Calculate expected amounts
        uint256 feeAmount = (price * 500) / 10000;
        uint256 payout = price - feeAmount;
        
        assertEq(builderBalanceAfter - builderBalanceBefore, payout);
        assertEq(ownerBalanceAfter - ownerBalanceBefore, feeAmount);
        
        vm.stopPrank();
    }
    
    function testFailClaimBeforeStartTime() public {
        // Create and approve a program first
        testApproveProgram();
        
        // Time is still before start time
        
        // Prank as builder
        vm.startPrank(builder);
        
        // Try to claim the grants
        program.claimGrants(0);
        
        vm.stopPrank();
    }
    
    function testFailClaimAfterEndTime() public {
        // Create and approve a program first
        testApproveProgram();
        
        // Warp to after the end time
        vm.warp(endTime + 1);
        
        // Prank as builder
        vm.startPrank(builder);
        
        // Try to claim the grants
        program.claimGrants(0);
        
        vm.stopPrank();
    }
    
    function testReclaimFunds() public {
        // Create a program first
        testCreateEduProgram();
        
        // Warp to after the end time
        vm.warp(endTime + 1);
        
        // Check maker's balance before
        uint256 makerBalanceBefore = address(maker).balance;
        
        // Prank as maker
        vm.startPrank(maker);
        
        // Reclaim the funds
        program.reclaimFunds(0);
        
        // Check maker's balance after
        uint256 makerBalanceAfter = address(maker).balance;
        assertEq(makerBalanceAfter - makerBalanceBefore, price);
        
        // Check that the program was claimed
        LdEduProgram.EduProgram memory eduProgram = program.eduPrograms(0);
        assertTrue(eduProgram.claimed);
        
        vm.stopPrank();
    }
    
    function testFailReclaimBeforeEndTime() public {
        // Create a program first
        testCreateEduProgram();
        
        // Time is still before end time
        
        // Prank as maker
        vm.startPrank(maker);
        
        // Try to reclaim the funds
        program.reclaimFunds(0);
        
        vm.stopPrank();
    }
    
    function testFailReclaimApprovedProgram() public {
        // Create and approve a program first
        testApproveProgram();
        
        // Warp to after the end time
        vm.warp(endTime + 1);
        
        // Prank as maker
        vm.startPrank(maker);
        
        // Try to reclaim the funds
        program.reclaimFunds(0);
        
        vm.stopPrank();
    }
    
    function testUpdateValidator() public {
        // Create a program first
        testCreateEduProgram();
        
        address newValidator = address(5);
        
        // Prank as maker
        vm.startPrank(maker);
        
        // Update the validator
        program.updateValidator(0, newValidator);
        
        // Check that the validator was updated
        LdEduProgram.EduProgram memory eduProgram = program.eduPrograms(0);
        assertEq(eduProgram.validator, newValidator);
        
        vm.stopPrank();
    }
    
    function testFailUpdateValidatorAsNonMaker() public {
        // Create a program first
        testCreateEduProgram();
        
        address newValidator = address(5);
        
        // Prank as someone else
        vm.startPrank(builder);
        
        // Try to update the validator
        program.updateValidator(0, newValidator);
        remix/LdEduProgram.sol
        vm.stopPrank();
    }
    
    function testSetFee() public {
        // Prank as owner
        vm.startPrank(owner);
        
        // Set a fee
        program.setFee(300);
        
        // Check that the fee was set
        assertEq(program.getFee(), 300);
        
        vm.stopPrank();
    }
    
    function testFailSetFeeAsNonOwner() public {
        // Prank as someone else
        vm.startPrank(maker);
        
        // Try to set a fee
        program.setFee(300);
        
        vm.stopPrank();
    }
}