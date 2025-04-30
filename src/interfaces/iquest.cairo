use quest_contract::base::types::{
    PlayerAttempt, Puzzle, Question, QuestionType, RewardParameters, options,
};
use starknet::ContractAddress;
// Interface trait

#[starknet::interface]
pub trait ILogicQuestPuzzle<TContractState> {
    // Admin functions
    fn authorize_creator(ref self: TContractState, creator_address: ContractAddress);
    fn revoke_creator(ref self: TContractState, creator_address: ContractAddress);
    fn update_contract_version(ref self: TContractState, new_version: u32);

    // Creator functions
    fn create_puzzle(
        ref self: TContractState,
        title: felt252,
        description: felt252,
        difficulty_level: u8,
        time_limit: u32,
    ) -> u32;
    fn claim_puzzle_reward(ref self: TContractState, puzzle_id: u32) -> u256;
    fn get_puzzle(self: @TContractState, puzzle_id: u32) -> Puzzle;
    fn get_estimated_reward(
        self: @TContractState, puzzle_id: u32, score: u32, time_taken: u64,
    ) -> u256;
    fn get_reward_parameters(self: @TContractState) -> RewardParameters;
    fn get_player_attempts(
        self: @TContractState, player: ContractAddress, puzzle_id: u32,
    ) -> PlayerAttempt;
    fn has_sufficient_pool(ref self: TContractState, amount: u256) -> bool;
    fn update_player_attempt(
        ref self: TContractState,
        score: u32,
        player_attempt: PlayerAttempt,
        time_taken: u64,
        player: ContractAddress,
        puzzle_id: u32,
        reward_amount: u256,
        current_time: u64,
    );
    fn add_question(
        ref self: TContractState,
        puzzle_id: u32,
        content: felt252,
        question_type: QuestionType,
        difficulty: u8,
        points: u32,
    ) -> u32;
    fn get_reward_pool_balance(self: @TContractState) -> u256;
    fn get_total_rewards_distributed(self: @TContractState) -> u256;
    fn is_player_blacklisted(self: @TContractState, player: ContractAddress) -> bool;
    fn is_contract_paused(self: @TContractState) -> bool;
    fn fund_reward_pool_balance(ref self: TContractState);
    fn update_reward_parameters(
        ref self: TContractState,
        base_reward: u256,
        time_bonus_factor: u256,
        difficulty_multiplier: u256,
        perfect_score_bonus: u256,
        max_reward_cap: u256,
        cooldown_period: u64,
        reward_decay_factor: u256,
    );
    fn blacklist_player(ref self: TContractState, player: ContractAddress, is_blacklisted: bool);
    fn set_paused(ref self: TContractState, paused: bool);
    fn emergency_withdraw(ref self: TContractState, amount: u256, recipient: ContractAddress);
    fn add_option(
        ref self: TContractState,
        puzzle_id: u32,
        question_id: u32,
        content: felt252,
        is_correct: bool,
    ) -> u32;

    // // Query functions
    fn get_question(self: @TContractState, puzzle_id: u32, question_id: u32) -> Question;
    fn get_option(
        self: @TContractState, puzzle_id: u32, question_id: u32, option_id: u32,
    ) -> options;
    fn get_puzzle_questions_count(self: @TContractState, puzzle_id: u32) -> u32;
    fn get_question_options_count(self: @TContractState, puzzle_id: u32, question_id: u32) -> u32;
    fn get_total_puzzles(self: @TContractState) -> u32;
    fn get_contract_version(self: @TContractState) -> u32;
    fn is_authorized_creator(self: @TContractState, address: ContractAddress) -> bool;
    
    // Verification system integration functions
    fn set_verification_contract(ref self: TContractState, verification_contract: ContractAddress);
    fn set_verification_required(ref self: TContractState, required: bool);
    fn is_verification_required(self: @TContractState) -> bool;
    fn get_verification_contract(self: @TContractState) -> ContractAddress;
}
