#[starknet::contract]
pub mod SolutionVerification {
    // Imports
    use core::array::ArrayTrait;
    use core::hash::{LegacyHash, HashStateExTrait};
    use core::option::OptionTrait;
    use core::traits::TryInto;
    use starknet::storage::{
        Map, StorageMapReadAccess, StorageMapWriteAccess, StoragePointerReadAccess,
        StoragePointerWriteAccess,
    };
    use starknet::{ContractAddress, get_block_timestamp, get_caller_address, get_contract_address, get_tx_info};
    use quest_contract::base::types::{Puzzle, PlayerAttempt, Question, QuestionType};
    use quest_contract::interfaces::iverification::ISolutionVerification;

    // Constants
    const VERIFICATION_VERSION: u32 = 1;
    const MAX_CHALLENGE_VALIDITY: u64 = 300; // Challenge valid for 5 minutes (in seconds)
    const CHALLENGE_SALT_BASE: felt252 = 'QUEST_VERIFICATION_SALT';

    // Events
    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        ChallengeCreated: ChallengeCreated,
        SolutionVerified: SolutionVerified,
        VerificationFailed: VerificationFailed,
        OracleAdded: OracleAdded,
        OracleRemoved: OracleRemoved,
        VerificationConfigUpdated: VerificationConfigUpdated,
    }

    #[derive(Drop, starknet::Event)]
    struct ChallengeCreated {
        #[key]
        player: ContractAddress,
        #[key]
        puzzle_id: u32,
        challenge_hash: felt252,
        timestamp: u64,
    }

    #[derive(Drop, starknet::Event)]
    struct SolutionVerified {
        #[key]
        player: ContractAddress,
        #[key]
        puzzle_id: u32,
        score: u32,
        time_taken: u64,
        timestamp: u64,
    }

    #[derive(Drop, starknet::Event)]
    struct VerificationFailed {
        #[key]
        player: ContractAddress,
        #[key]
        puzzle_id: u32,
        reason: felt252,
        timestamp: u64,
    }

    #[derive(Drop, starknet::Event)]
    struct OracleAdded {
        oracle_address: ContractAddress,
    }

    #[derive(Drop, starknet::Event)]
    struct OracleRemoved {
        oracle_address: ContractAddress,
    }

    #[derive(Drop, starknet::Event)]
    struct VerificationConfigUpdated {
        max_challenge_validity: u64,
        verification_threshold: u8,
    }

    // Structs for verification
    #[derive(Drop, Serde, starknet::Store)]
    struct Challenge {
        player: ContractAddress,
        puzzle_id: u32,
        challenge_hash: felt252,
        timestamp: u64,
        used: bool,
    }

    #[derive(Drop, Serde, starknet::Store)]
    struct SolutionProof {
        player: ContractAddress,
        puzzle_id: u32,
        score: u32,
        time_taken: u64,
        challenge_hash: felt252,
        solution_hash: felt252,
        verified: bool,
        timestamp: u64,
    }

    // Contract storage
    #[storage]
    struct Storage {
        admin: ContractAddress,
        quest_contract: ContractAddress,
        authorized_oracles: Map<ContractAddress, bool>,
        oracle_count: u32,
        verification_threshold: u8, // Minimum number of oracles needed to verify a solution
        max_challenge_validity: u64, // Time in seconds a challenge is valid
        
        // Challenge-response system
        player_challenges: Map<(ContractAddress, u32), Challenge>,
        solution_proofs: Map<(ContractAddress, u32), SolutionProof>,
        
        // Oracle verification tracking
        oracle_verifications: Map<(ContractAddress, u32, ContractAddress), bool>,
        verification_counts: Map<(ContractAddress, u32), u8>,
    }

    // Constructor
    #[constructor]
    fn constructor(ref self: ContractState, admin_address: ContractAddress, quest_contract: ContractAddress) {
        self.admin.write(admin_address);
        self.quest_contract.write(quest_contract);
        self.max_challenge_validity.write(MAX_CHALLENGE_VALIDITY);
        self.verification_threshold.write(1); // Default: require at least 1 oracle verification
    }

    // Modifiers
    #[generate_trait]
    impl ModifierImpl of ModifierTrait {
        fn only_admin(self: @ContractState) {
            let caller = get_caller_address();
            assert(caller == self.admin.read(), 'Only admin can call this');
        }

        fn only_oracle(self: @ContractState) {
            let caller = get_caller_address();
            assert(self.authorized_oracles.read(caller), 'Only oracle can call this');
        }
    }

    // Implementation
    #[abi(embed_v0)]
    impl SolutionVerificationImpl of ISolutionVerification<ContractState> {
        // Admin functions
        fn add_oracle(ref self: ContractState, oracle_address: ContractAddress) {
            self.only_admin();
            assert(!self.authorized_oracles.read(oracle_address), 'Oracle already authorized');
            
            self.authorized_oracles.write(oracle_address, true);
            self.oracle_count.write(self.oracle_count.read() + 1);
            
            self.emit(OracleAdded { oracle_address });
        }

        fn remove_oracle(ref self: ContractState, oracle_address: ContractAddress) {
            self.only_admin();
            assert(self.authorized_oracles.read(oracle_address), 'Oracle not authorized');
            
            self.authorized_oracles.write(oracle_address, false);
            self.oracle_count.write(self.oracle_count.read() - 1);
            
            self.emit(OracleRemoved { oracle_address });
        }

        fn update_verification_config(
            ref self: ContractState, 
            max_challenge_validity: u64,
            verification_threshold: u8
        ) {
            self.only_admin();
            
            // Validate inputs
            assert(max_challenge_validity > 0, 'Invalid challenge validity');
            assert(verification_threshold > 0, 'Invalid threshold');
            assert(verification_threshold <= self.oracle_count.read(), 'Threshold exceeds oracles');
            
            self.max_challenge_validity.write(max_challenge_validity);
            self.verification_threshold.write(verification_threshold);
            
            self.emit(VerificationConfigUpdated { 
                max_challenge_validity,
                verification_threshold
            });
        }

        // Player functions
        fn generate_challenge(ref self: ContractState, puzzle_id: u32) -> felt252 {
            let player = get_caller_address();
            let current_time = get_block_timestamp();
            
            // Generate a unique challenge hash using player address, puzzle ID, timestamp, and a salt
            let tx_info = get_tx_info().unbox();
            let mut state = LegacyHash::new(CHALLENGE_SALT_BASE);
            state = state.update_with(player);
            state = state.update_with(puzzle_id);
            state = state.update_with(current_time);
            state = state.update_with(tx_info.transaction_hash);
            let challenge_hash = state.finalize();
            
            // Store the challenge
            let challenge = Challenge {
                player,
                puzzle_id,
                challenge_hash,
                timestamp: current_time,
                used: false
            };
            
            self.player_challenges.write((player, puzzle_id), challenge);
            
            // Emit event
            self.emit(ChallengeCreated { 
                player,
                puzzle_id,
                challenge_hash,
                timestamp: current_time
            });
            
            challenge_hash
        }

        // Oracle functions
        fn verify_solution(
            ref self: ContractState,
            player: ContractAddress,
            puzzle_id: u32,
            score: u32,
            time_taken: u64,
            solution_hash: felt252
        ) -> bool {
            self.only_oracle();
            let oracle = get_caller_address();
            let current_time = get_block_timestamp();
            
            // Get the challenge for this player and puzzle
            let challenge = self.player_challenges.read((player, puzzle_id));
            
            // Verify the challenge exists and is still valid
            assert(challenge.challenge_hash != 0, 'No challenge found');
            assert(!challenge.used, 'Challenge already used');
            assert(
                current_time <= challenge.timestamp + self.max_challenge_validity.read(),
                'Challenge expired'
            );
            
            // Check if this oracle has already verified this solution
            assert(
                !self.oracle_verifications.read((player, puzzle_id, oracle)),
                'Already verified by oracle'
            );
            
            // Record this oracle's verification
            self.oracle_verifications.write((player, puzzle_id, oracle), true);
            
            // Increment verification count
            let new_count = self.verification_counts.read((player, puzzle_id)) + 1;
            self.verification_counts.write((player, puzzle_id), new_count);
            
            // Create or update solution proof
            let mut proof = self.solution_proofs.read((player, puzzle_id));
            if proof.challenge_hash == 0 {
                // First verification for this solution
                proof = SolutionProof {
                    player,
                    puzzle_id,
                    score,
                    time_taken,
                    challenge_hash: challenge.challenge_hash,
                    solution_hash,
                    verified: false,
                    timestamp: current_time
                };
            }
            
            // Check if we've reached the verification threshold
            if new_count >= self.verification_threshold.read() {
                // Mark the challenge as used
                let mut updated_challenge = challenge;
                updated_challenge.used = true;
                self.player_challenges.write((player, puzzle_id), updated_challenge);
                
                // Mark the solution as verified
                proof.verified = true;
                
                // Emit success event
                self.emit(SolutionVerified { 
                    player,
                    puzzle_id,
                    score,
                    time_taken,
                    timestamp: current_time
                });
            }
            
            // Save the updated proof
            self.solution_proofs.write((player, puzzle_id), proof);
            
            proof.verified
        }

        fn reject_solution(
            ref self: ContractState,
            player: ContractAddress,
            puzzle_id: u32,
            reason: felt252
        ) {
            self.only_oracle();
            let current_time = get_block_timestamp();
            
            // Get the challenge
            let challenge = self.player_challenges.read((player, puzzle_id));
            assert(challenge.challenge_hash != 0, 'No challenge found');
            
            // Mark the challenge as used (rejected)
            let mut updated_challenge = challenge;
            updated_challenge.used = true;
            self.player_challenges.write((player, puzzle_id), updated_challenge);
            
            // Emit failure event
            self.emit(VerificationFailed { 
                player,
                puzzle_id,
                reason,
                timestamp: current_time
            });
        }

        // Query functions
        fn is_solution_verified(self: @ContractState, player: ContractAddress, puzzle_id: u32) -> bool {
            let proof = self.solution_proofs.read((player, puzzle_id));
            proof.verified
        }

        fn get_solution_proof(self: @ContractState, player: ContractAddress, puzzle_id: u32) -> SolutionProof {
            self.solution_proofs.read((player, puzzle_id))
        }

        fn get_challenge(self: @ContractState, player: ContractAddress, puzzle_id: u32) -> Challenge {
            self.player_challenges.read((player, puzzle_id))
        }

        fn is_oracle_authorized(self: @ContractState, oracle_address: ContractAddress) -> bool {
            self.authorized_oracles.read(oracle_address)
        }

        fn get_verification_threshold(self: @ContractState) -> u8 {
            self.verification_threshold.read()
        }

        fn get_max_challenge_validity(self: @ContractState) -> u64 {
            self.max_challenge_validity.read()
        }

        fn get_verification_count(self: @ContractState, player: ContractAddress, puzzle_id: u32) -> u8 {
            self.verification_counts.read((player, puzzle_id))
        }
    }
}
