use starknet::ContractAddress;
use starknet::testing::{set_contract_address, set_caller_address, set_block_timestamp};
use starknet::block_info::{BlockInfo, BlockInfoTrait};
use starknet::testing::set_block_info;
use core::array::ArrayTrait;
use core::option::OptionTrait;
use core::traits::Into;

// Import the contract interfaces
use quest_contract::enhanced_daily_challenges::IEnhancedDailyChallengesDispatcherTrait;
use quest_contract::enhanced_daily_challenges::IEnhancedDailyChallengesDispatcher;
use quest_contract::enhanced_daily_challenges::IEnhancedDailyChallengesLibraryDispatcher;
use quest_contract::enhanced_daily_challenges::IEnhancedDailyChallengesLibraryDispatcherTrait;

// Import the test utils
mod test_utils;
use test_utils::{deploy_contract, deploy_token_contract, mint_tokens, advance_time_days};

// Constants for testing
const START_TIMESTAMP: u64 = 1640995200; // Jan 1, 2022 00:00:00 UTC
const SECONDS_PER_DAY: u64 = 86400;

#[test]
#[available_gas(3000000000000000)]
fn test_challenge_completion() {
    // Setup
    let (owner, user) = setup_contracts();
    
    // Submit first challenge completion
    set_caller_address(user);
    let result = enhanced_daily_challenge_contract.submit_challenge_completion(Option::Some(1));
    
    // Check user data
    let user_data = enhanced_daily_challenge_contract.get_user_data(user);
    assert(user_data.current_streak == 1, 'Streak should be 1');
    assert(user_data.total_challenges_completed == 1, 'Total challenges should be 1');
    
    // Check category progress
    let progress = enhanced_daily_challenge_contract.get_category_progress(user, 1);
    assert(progress == 1, 'Category progress should be 1');
}

#[test]
#[available_gas(3000000000000000)]
fn test_streak_calculation() {
    // Setup
    let (owner, user) = setup_contracts();
    
    // Complete challenges for 3 consecutive days
    for day in 0..3 {
        let timestamp = START_TIMESTAMP + (day * SECONDS_PER_DAY);
        set_block_timestamp(timestamp);
        set_caller_address(user);
        enhanced_daily_challenge_contract.submit_challenge_completion(Option::Some(1));
    }
    
    // Check streak
    let user_data = enhanced_daily_challenge_contract.get_user_data(user);
    assert(user_data.current_streak == 3, 'Streak should be 3');
    
    // Skip a day and check if streak resets
    set_block_timestamp(START_TIMESTAMP + (4 * SECONDS_PER_DAY) + 1);
    set_caller_address(user);
    enhanced_daily_challenge_contract.submit_challenge_completion(Option::Some(1));
    
    let user_data = enhanced_daily_challenge_contract.get_user_data(user);
    assert(user_data.current_streak == 1, 'Streak should reset to 1');
}

#[test]
#[available_gas(3000000000000000)]
fn test_achievement_unlocking() {
    // Setup
    let (owner, user) = setup_contracts();
    
    // Complete challenges for 7 consecutive days
    for day in 0..7 {
        let timestamp = START_TIMESTAMP + (day * SECONDS_PER_DAY);
        set_block_timestamp(timestamp);
        set_caller_address(user);
        enhanced_daily_challenge_contract.submit_challenge_completion(Option::Some(1));
    }
    
    // Check if 7-day achievement is unlocked
    let user_data = enhanced_daily_challenge_contract.get_user_data(user);
    assert(user_data.current_streak == 7, '7-day streak should be achieved');
    
    // Note: In a real test, you would check the AchievementUnlocked event
    // and verify the user received the achievement bonus
}

#[test]
#[available_gas(3000000000000000)]
fn test_category_completion() {
    // Setup
    let (owner, user) = setup_contracts();
    set_caller_address(user);
    
    // Get category info
    let category = enhanced_daily_challenge_contract.get_category_info(1);
    let target = category.target;
    
    // Complete challenges to reach target
    for i in 0..target {
        enhanced_daily_challenge_contract.update_category_progress(1, 1);
    }
    
    // Check if progress was reset
    let progress = enhanced_daily_challenge_contract.get_category_progress(user, 1);
    assert(progress == 0, 'Progress should reset after reaching target');
}

#[test]
#[available_gas(3000000000000000)]
fn test_admin_functions() {
    // Setup
    let (owner, user) = setup_contracts();
    
    // Try to add category as non-owner (should fail)
    set_caller_address(user);
    let mut error_happened = false;
    
    match std::panic::catch_unwind(|| {
        enhanced_daily_challenge_contract.add_challenge_category(
            10, 
            'Test Category', 
            'Test Description', 
            5, 
            10
        );
    }) {
        Result::Ok(_) => {},
        Result::Err(_) => {
            error_happened = true;
        },
    };
    
    assert(error_happened, 'Non-owner should not be able to add category');
    
    // Add category as owner
    set_caller_address(owner);
    enhanced_daily_challenge_contract.add_challenge_category(
        10, 
        'Test Category', 
        'Test Description', 
        5, 
        10
    );
    
    // Verify category was added
    let category = enhanced_daily_challenge_contract.get_category_info(10);
    assert(category.name == 'Test Category', 'Category should be added');
}

// Helper function to set up test environment
fn setup_contracts() -> (ContractAddress, ContractAddress) {
    // Deploy test token
    let token_contract = deploy_token_contract();
    
    // Deploy daily challenges contract
    let owner = starknet::contract_address_const::<0x01>();
    let enhanced_daily_challenge_contract = deploy_contract(
        'EnhancedDailyChallenges', 
        array![owner.into(), token_contract.into(), START_TIMESTAMP.into()].span()
    );
    
    // Mint tokens to user for testing
    let user = starknet::contract_address_const::<0x02>();
    mint_tokens(token_contract, user, 1000000000000000000_u256);
    
    // Set initial block timestamp
    set_block_timestamp(START_TIMESTAMP);
    
    (owner, user)
}
