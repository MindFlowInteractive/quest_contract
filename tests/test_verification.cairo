#[cfg(test)]
mod tests {
    use core::array::ArrayTrait;
    use core::option::OptionTrait;
    use core::traits::TryInto;
    use core::num::traits::Zero;
    use starknet::testing::{set_caller_address, set_contract_address, set_block_timestamp};
    use starknet::{ContractAddress, contract_address_const, get_caller_address, get_contract_address};
    use openzeppelin::token::erc20::interface::{
        IERC20Dispatcher, IERC20DispatcherTrait, IERC20MetadataDispatcher, IERC20MetadataDispatcherTrait,
    };
    use quest_contract::verification::SolutionVerification;
    use quest_contract::verification::SolutionVerification::{
        Challenge, SolutionProof, SolutionVerificationImpl
    };
    use quest_contract::interfaces::iverification::{
        ISolutionVerificationDispatcher, ISolutionVerificationDispatcherTrait
    };

    // Helper function to create contract addresses
    fn contract_address(value: felt252) -> ContractAddress {
        contract_address_const::<value>()
    }

    // Test setup
    fn setup() -> (ContractAddress, ContractAddress, ContractAddress) {
        let admin = contract_address('admin');
        let oracle = contract_address('oracle');
        let quest_contract = contract_address('quest_contract');
        
        // Deploy verification contract
        let mut calldata = ArrayTrait::new();
        calldata.append(admin.into());
        calldata.append(quest_contract.into());
        
        let (verification_address, _) = starknet::deploy_syscall(
            SolutionVerification::TEST_CLASS_HASH.try_into().unwrap(),
            0,
            calldata.span(),
            false
        ).unwrap();
        
        (admin, oracle, verification_address)
    }

    #[test]
    fn test_add_oracle() {
        let (admin, oracle, verification_address) = setup();
        
        // Set caller to admin
        set_caller_address(admin);
        
        // Create dispatcher
        let verification_dispatcher = ISolutionVerificationDispatcher { 
            contract_address: verification_address
        };
        
        // Add oracle
        verification_dispatcher.add_oracle(oracle);
        
        // Verify oracle was added
        let is_authorized = verification_dispatcher.is_oracle_authorized(oracle);
        assert(is_authorized, 'Oracle should be authorized');
    }

    #[test]
    fn test_remove_oracle() {
        let (admin, oracle, verification_address) = setup();
        
        // Set caller to admin
        set_caller_address(admin);
        
        // Create dispatcher
        let verification_dispatcher = ISolutionVerificationDispatcher { 
            contract_address: verification_address
        };
        
        // Add oracle
        verification_dispatcher.add_oracle(oracle);
        
        // Remove oracle
        verification_dispatcher.remove_oracle(oracle);
        
        // Verify oracle was removed
        let is_authorized = verification_dispatcher.is_oracle_authorized(oracle);
        assert(!is_authorized, 'Oracle should not be authorized');
    }

    #[test]
    fn test_challenge_generation() {
        let (admin, oracle, verification_address) = setup();
        let player = contract_address('player');
        let puzzle_id = 1_u32;
        
        // Set caller to player
        set_caller_address(player);
        
        // Create dispatcher
        let verification_dispatcher = ISolutionVerificationDispatcher { 
            contract_address: verification_address
        };
        
        // Generate challenge
        let challenge_hash = verification_dispatcher.generate_challenge(puzzle_id);
        
        // Verify challenge was created
        let challenge = verification_dispatcher.get_challenge(player, puzzle_id);
        assert(challenge.challenge_hash == challenge_hash, 'Challenge hash mismatch');
        assert(challenge.player == player, 'Player mismatch');
        assert(challenge.puzzle_id == puzzle_id, 'Puzzle ID mismatch');
        assert(!challenge.used, 'Challenge should not be used');
    }

    #[test]
    fn test_solution_verification() {
        let (admin, oracle, verification_address) = setup();
        let player = contract_address('player');
        let puzzle_id = 1_u32;
        let score = 100_u32;
        let time_taken = 60_u64; // 60 seconds
        let solution_hash = 'solution_hash';
        
        // Set caller to player to generate challenge
        set_caller_address(player);
        
        // Create dispatcher
        let verification_dispatcher = ISolutionVerificationDispatcher { 
            contract_address: verification_address
        };
        
        // Generate challenge
        let challenge_hash = verification_dispatcher.generate_challenge(puzzle_id);
        
        // Set caller to admin to add oracle
        set_caller_address(admin);
        verification_dispatcher.add_oracle(oracle);
        
        // Set caller to oracle to verify solution
        set_caller_address(oracle);
        let verified = verification_dispatcher.verify_solution(
            player, puzzle_id, score, time_taken, solution_hash
        );
        
        // Verify solution was verified (with default threshold of 1)
        assert(verified, 'Solution should be verified');
        
        // Check if solution is marked as verified
        let is_verified = verification_dispatcher.is_solution_verified(player, puzzle_id);
        assert(is_verified, 'Solution should be marked as verified');
        
        // Get solution proof
        let proof = verification_dispatcher.get_solution_proof(player, puzzle_id);
        assert(proof.player == player, 'Player mismatch in proof');
        assert(proof.puzzle_id == puzzle_id, 'Puzzle ID mismatch in proof');
        assert(proof.score == score, 'Score mismatch in proof');
        assert(proof.time_taken == time_taken, 'Time taken mismatch in proof');
        assert(proof.solution_hash == solution_hash, 'Solution hash mismatch in proof');
        assert(proof.verified, 'Proof should be verified');
    }

    #[test]
    fn test_solution_rejection() {
        let (admin, oracle, verification_address) = setup();
        let player = contract_address('player');
        let puzzle_id = 1_u32;
        let reason = 'Invalid solution';
        
        // Set caller to player to generate challenge
        set_caller_address(player);
        
        // Create dispatcher
        let verification_dispatcher = ISolutionVerificationDispatcher { 
            contract_address: verification_address
        };
        
        // Generate challenge
        let challenge_hash = verification_dispatcher.generate_challenge(puzzle_id);
        
        // Set caller to admin to add oracle
        set_caller_address(admin);
        verification_dispatcher.add_oracle(oracle);
        
        // Set caller to oracle to reject solution
        set_caller_address(oracle);
        verification_dispatcher.reject_solution(player, puzzle_id, reason);
        
        // Verify challenge is marked as used
        let challenge = verification_dispatcher.get_challenge(player, puzzle_id);
        assert(challenge.used, 'Challenge should be marked as used');
        
        // Verify solution is not verified
        let is_verified = verification_dispatcher.is_solution_verified(player, puzzle_id);
        assert(!is_verified, 'Solution should not be verified');
    }

    #[test]
    fn test_challenge_expiry() {
        let (admin, oracle, verification_address) = setup();
        let player = contract_address('player');
        let puzzle_id = 1_u32;
        let score = 100_u32;
        let time_taken = 60_u64;
        let solution_hash = 'solution_hash';
        
        // Set initial block timestamp
        set_block_timestamp(1000);
        
        // Set caller to player to generate challenge
        set_caller_address(player);
        
        // Create dispatcher
        let verification_dispatcher = ISolutionVerificationDispatcher { 
            contract_address: verification_address
        };
        
        // Generate challenge
        let challenge_hash = verification_dispatcher.generate_challenge(puzzle_id);
        
        // Set caller to admin to add oracle
        set_caller_address(admin);
        verification_dispatcher.add_oracle(oracle);
        
        // Set block timestamp to after challenge expiry
        // Default MAX_CHALLENGE_VALIDITY is 300 seconds
        set_block_timestamp(1000 + 301);
        
        // Set caller to oracle to verify solution
        set_caller_address(oracle);
        
        // Attempt to verify expired challenge should fail
        let mut success = false;
        match verification_dispatcher.verify_solution(player, puzzle_id, score, time_taken, solution_hash) {
            Result::Ok(_) => {
                success = true;
            },
            Result::Err(_) => {
                // Expected to fail
            }
        };
        
        assert(!success, 'Should fail with expired challenge');
    }

    #[test]
    fn test_multiple_oracle_verification() {
        let (admin, oracle1, verification_address) = setup();
        let oracle2 = contract_address('oracle2');
        let player = contract_address('player');
        let puzzle_id = 1_u32;
        let score = 100_u32;
        let time_taken = 60_u64;
        let solution_hash = 'solution_hash';
        
        // Set caller to admin
        set_caller_address(admin);
        
        // Create dispatcher
        let verification_dispatcher = ISolutionVerificationDispatcher { 
            contract_address: verification_address
        };
        
        // Add oracles
        verification_dispatcher.add_oracle(oracle1);
        verification_dispatcher.add_oracle(oracle2);
        
        // Set verification threshold to 2
        verification_dispatcher.update_verification_config(300, 2);
        
        // Set caller to player to generate challenge
        set_caller_address(player);
        let challenge_hash = verification_dispatcher.generate_challenge(puzzle_id);
        
        // Set caller to first oracle to verify
        set_caller_address(oracle1);
        let verified1 = verification_dispatcher.verify_solution(
            player, puzzle_id, score, time_taken, solution_hash
        );
        
        // Should not be fully verified yet
        assert(!verified1, 'Should not be verified with only one oracle');
        
        // Check verification count
        let count = verification_dispatcher.get_verification_count(player, puzzle_id);
        assert(count == 1, 'Should have 1 verification');
        
        // Set caller to second oracle to verify
        set_caller_address(oracle2);
        let verified2 = verification_dispatcher.verify_solution(
            player, puzzle_id, score, time_taken, solution_hash
        );
        
        // Now should be fully verified
        assert(verified2, 'Should be verified with two oracles');
        
        // Check if solution is marked as verified
        let is_verified = verification_dispatcher.is_solution_verified(player, puzzle_id);
        assert(is_verified, 'Solution should be marked as verified');
    }
}
