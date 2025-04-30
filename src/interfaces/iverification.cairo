use starknet::ContractAddress;
use quest_contract::verification::SolutionVerification::{Challenge, SolutionProof};

#[starknet::interface]
pub trait ISolutionVerification<TContractState> {
    // Admin functions
    fn add_oracle(ref self: TContractState, oracle_address: ContractAddress);
    fn remove_oracle(ref self: TContractState, oracle_address: ContractAddress);
    fn update_verification_config(
        ref self: TContractState, 
        max_challenge_validity: u64,
        verification_threshold: u8
    );
    
    // Player functions
    fn generate_challenge(ref self: TContractState, puzzle_id: u32) -> felt252;
    
    // Oracle functions
    fn verify_solution(
        ref self: TContractState,
        player: ContractAddress,
        puzzle_id: u32,
        score: u32,
        time_taken: u64,
        solution_hash: felt252
    ) -> bool;
    
    fn reject_solution(
        ref self: TContractState,
        player: ContractAddress,
        puzzle_id: u32,
        reason: felt252
    );
    
    // Query functions
    fn is_solution_verified(self: @TContractState, player: ContractAddress, puzzle_id: u32) -> bool;
    fn get_solution_proof(self: @TContractState, player: ContractAddress, puzzle_id: u32) -> SolutionProof;
    fn get_challenge(self: @TContractState, player: ContractAddress, puzzle_id: u32) -> Challenge;
    fn is_oracle_authorized(self: @TContractState, oracle_address: ContractAddress) -> bool;
    fn get_verification_threshold(self: @TContractState) -> u8;
    fn get_max_challenge_validity(self: @TContractState) -> u64;
    fn get_verification_count(self: @TContractState, player: ContractAddress, puzzle_id: u32) -> u8;
}
