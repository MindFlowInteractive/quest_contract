use starknet::ContractAddress;
use starknet::storage::StorageMap;
use openzeppelin::access::ownable::OwnableComponent;
use openzeppelin::token::erc20::interface::{IERC20Dispatcher, IERC20DispatcherTrait};
use core::array::ArrayTrait;
use core::traits::Into;

#[starknet::interface]
pub trait IEnhancedDailyChallenges<TContractState> {
    // Existing functions
    fn submit_challenge_completion(ref self: TContractState, category_id: Option<u32>);
    fn get_user_data(self: @TContractState, user: ContractAddress) -> UserData;
    fn get_current_system_day(self: @TContractState) -> u64;
    
    // New functions
    fn add_challenge_category(
        ref self: TContractState,
        id: u32,
        name: felt252,
        description: felt252,
        target: u32,
        reward_multiplier: u8
    );
    
    fn update_category_progress(
        ref self: TContractState,
        category_id: u32,
        progress: u32
    );
    
    fn get_category_progress(
        self: @TContractState,
        user: ContractAddress,
        category_id: u32
    ) -> u32;
    
    fn get_category_info(self: @TContractState, category_id: u32) -> ChallengeCategory;
    
    fn get_active_categories(self: @TContractState) -> Array<u32>;
}

// Achievement milestones
const SEVEN_DAY_ACHIEVEMENT_ID: u32 = 0;
const THIRTY_DAY_ACHIEVEMENT_ID: u32 = 1;
const NINETY_DAY_ACHIEVEMENT_ID: u32 = 2;
const WEEKLY_CHALLENGE_MASTER: u32 = 3;
const MONTHLY_CHALLENGE_MASTER: u32 = 4;

// Milestone constants
const SEVEN_DAY_STREAK_MILESTONE: u32 = 7;
const THIRTY_DAY_STREAK_MILESTONE: u32 = 30;
const NINETY_DAY_STREAK_MILESTONE: u32 = 90;

// Reward constants
const SEVEN_DAY_ACHIEVEMENT_BONUS: u256 = 50;
const THIRTY_DAY_ACHIEVEMENT_BONUS: u256 = 250;
const NINETY_DAY_ACHIEVEMENT_BONUS: u256 = 1000;
const WEEKLY_MASTER_BONUS: u256 = 200;
const MONTHLY_MASTER_BONUS: u256 = 1000;

// Data structures
#[derive(Copy, Drop, Serde, starknet::Store)]
pub struct UserData {
    pub last_completed_system_day: u64,
    pub current_streak: u32,
    pub total_challenges_completed: u32,
    pub weekly_challenges_completed: u32,
    pub monthly_challenges_completed: u32,
}

#[derive(Copy, Drop, Serde, starknet::Store)]
pub struct ChallengeCategory {
    pub id: u32,
    pub name: felt252,
    pub description: felt252,
    pub target: u32,
    pub reward_multiplier: u8,
    pub is_active: bool,
}

#[starknet::contract]
mod EnhancedDailyChallenges {
    use super::*;
    use starknet::{get_caller_address, get_block_timestamp};
    use core::option::OptionTrait;
    use core::num::traits::Zero;
    
    component!(path: OwnableComponent, storage: ownable, event: OwnableEvent);

    #[storage]
    struct Storage {
        // Core storage
        initialized: bool,
        system_start_timestamp: u64,
        seconds_per_day: u64,
        reward_token_address: ContractAddress,
        base_reward: u256,
        streak_bonus: u256,
        
        // User data
        user_data: StorageMap<ContractAddress, UserData>,
        
        // Challenge categories
        challenge_categories: StorageMap<u32, ChallengeCategory>,
        active_categories: Array<u32>,
        
        // User progress
        user_category_progress: StorageMap<(ContractAddress, u32), u32>,
        
        // Achievement tracking
        achievements_unlocked: StorageMap<(ContractAddress, u32), bool>,
        
        // Ownable component storage
        #[substorage(v0)]
        ownable: OwnableComponent::Storage,
    }
    
    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        ChallengeCompleted: ChallengeCompleted,
        CategoryAdded: CategoryAdded,
        AchievementUnlocked: AchievementUnlocked,
        RewardClaimed: RewardClaimed,
        OwnableEvent: OwnableComponent::Event,
    }
    
    #[derive(Drop, starknet::Event)]
    struct ChallengeCompleted {
        user: ContractAddress,
        category_id: u32,
        timestamp: u64,
    }
    
    #[derive(Drop, starknet::Event)]
    struct CategoryAdded {
        category_id: u32,
        name: felt252,
    }
    
    #[derive(Drop, starknet::Event)]
    struct AchievementUnlocked {
        user: ContractAddress,
        achievement_id: u32,
        timestamp: u64,
    }
    
    #[derive(Drop, starknet::Event)]
    struct RewardClaimed {
        user: ContractAddress,
        amount: u256,
        timestamp: u64,
    }
    
    #[constructor]
    fn constructor(
        ref self: ContractState,
        owner: ContractAddress,
        reward_token: ContractAddress,
        start_timestamp: u64,
    ) {
        self.ownable.initializer(owner);
        self.initialized.write(false);
        self.reward_token_address.write(reward_token);
        self.system_start_timestamp.write(start_timestamp);
        self.seconds_per_day.write(86400); // 24 hours in seconds
        self.base_reward.write(10_000_000_000_000_000_000_u256); // 10 STRK
        self.streak_bonus.write(1_000_000_000_000_000_000_u256); // 1 STRK per day streak
        
        // Initialize default categories
        self._add_default_categories();
        
        self.initialized.write(true);
    }
    
    // Internal function to add default challenge categories
    #[generate_trait]
    fn _add_default_categories(ref self: ContractState) {
        let categories = array![
            (1, 'Puzzle Master', 'Complete puzzle challenges', 10, 20),
            (2, 'Tournament Champion', 'Win tournament matches', 5, 30),
            (3, 'Daily Grinder', 'Complete daily challenges', 30, 15),
            (4, 'Social Butterfly', 'Interact with friends', 20, 10),
            (5, 'NFT Collector', 'Collect rare NFTs', 5, 40)
        ];
        
        let mut active = ArrayTrait::new();
        
        loop {
            match categories.pop_front() {
                Option::Some((id, name, desc, target, mult)) => {
                    let category = ChallengeCategory {
                        id,
                        name: name.into(),
                        description: desc.into(),
                        target,
                        reward_multiplier: mult,
                        is_active: true,
                    };
                    self.challenge_categories.write(id, category);
                    active.append(array![id].span());
                },
                Option::None => break,
            };
        }
        
        self.active_categories.write(active);
    }
    
    // Submit completion of a daily challenge
    #[external(v0)]
    impl EnhancedDailyChallengesImpl of IEnhancedDailyChallenges<ContractState> {
        fn submit_challenge_completion(
            ref self: ContractState,
            category_id: Option<u32>
        ) {
            self.only_initialized();
            let caller = get_caller_address();
            let current_day = self._get_current_system_day();
            
            // Get or initialize user data
            let mut user_data = self.user_data.read(caller);
            
            // Check if user already completed a challenge today
            if user_data.last_completed_system_day == current_day {
                // If category is provided, update category progress
                match category_id {
                    Option::Some(cat_id) => {
                        self._update_category_progress(caller, cat_id, 1);
                    },
                    Option::None => {}
                };
                return;
            }
            
            // Calculate streak
            if user_data.last_completed_system_day == current_day - 1 {
                user_data.current_streak += 1;
            } else if user_data.last_completed_system_day < current_day - 1 {
                user_data.current_streak = 1; // Reset streak if not consecutive
            }
            
            // Update completion stats
            user_data.last_completed_system_day = current_day;
            user_data.total_challenges_completed += 1;
            
            // Update weekly/monthly counters
            let current_time = get_block_timestamp();
            if current_time % 604800 < 86400 { // New week
                user_data.weekly_challenges_completed = 1;
            } else {
                user_data.weekly_challenges_completed += 1;
            }
            
            if current_time % 2592000 < 86400 { // New month
                user_data.monthly_challenges_completed = 1;
            } else {
                user_data.monthly_challenges_completed += 1;
            }
            
            // Update category progress if specified
            match category_id {
                Option::Some(cat_id) => {
                    self._update_category_progress(caller, cat_id, 1);
                },
                Option::None => {}
            };
            
            // Check for achievements
            self._check_achievements(caller, user_data);
            
            // Save updated user data
            self.user_data.write(caller, user_data);
            
            // Emit event
            self.emit(Event::ChallengeCompleted(ChallengeCompleted {
                user: caller,
                category_id: category_id.unwrap_or(0),
                timestamp: current_time,
            }));
            
            // Distribute rewards
            self._distribute_rewards(caller, user_data.current_streak, category_id);
        }
        
        // Add a new challenge category (admin only)
        fn add_challenge_category(
            ref self: ContractState,
            id: u32,
            name: felt252,
            description: felt252,
            target: u32,
            reward_multiplier: u8
        ) {
            self.ownable.assert_only_owner();
            
            let category = ChallengeCategory {
                id,
                name,
                description,
                target,
                reward_multiplier,
                is_active: true,
            };
            
            self.challenge_categories.write(id, category);
            
            // Add to active categories if not already present
            let mut active = self.active_categories.read();
            if !active.contains(id) {
                active.append(array![id].span());
                self.active_categories.write(active);
            }
            
            self.emit(Event::CategoryAdded(CategoryAdded {
                category_id: id,
                name: name,
            }));
        }
        
        // Update progress in a specific category
        fn update_category_progress(
            ref self: ContractState,
            category_id: u32,
            progress: u32
        ) {
            let caller = get_caller_address();
            self._update_category_progress(caller, category_id, progress);
        }
        
        // Get user's progress in a category
        fn get_category_progress(
            self: @ContractState,
            user: ContractAddress,
            category_id: u32
        ) -> u32 {
            self.user_category_progress.read((user, category_id))
        }
        
        // Get category information
        fn get_category_info(
            self: @ContractState,
            category_id: u32
        ) -> ChallengeCategory {
            self.challenge_categories.read(category_id)
        }
        
        // Get list of active category IDs
        fn get_active_categories(self: @ContractState) -> Array<u32> {
            self.active_categories.read()
        }
        
        // Get user data
        fn get_user_data(self: @ContractState, user: ContractAddress) -> UserData {
            self.user_data.read(user)
        }
        
        // Get current system day
        fn get_current_system_day(self: @ContractState) -> u64 {
            self._get_current_system_day()
        }
    }
    
    // Internal functions
    #[generate_trait]
    impl InternalImpl of InternalTrait {
        // Update category progress and check for completion
        fn _update_category_progress(
            ref self: ContractState,
            user: ContractAddress,
            category_id: u32,
            progress: u32
        ) {
            let category = self.challenge_categories.read(category_id);
            assert(category.is_active, 'Category not active');
            
            let current_progress = self.user_category_progress.read((user, category_id));
            let new_progress = current_progress + progress;
            
            self.user_category_progress.write((user, category_id), new_progress);
            
            // Check if target reached
            if new_progress >= category.target {
                // Reset progress for this category
                self.user_category_progress.write((user, category_id), 0);
                
                // Award bonus based on category multiplier
                let base_reward = self.base_reward.read();
                let bonus = (base_reward * category.reward_multiplier.into()) / 100_u256;
                self._distribute_rewards(user, 0, Option::Some(category_id));
            }
        }
        
        // Distribute rewards to user
        fn _distribute_rewards(
            ref self: ContractState,
            user: ContractAddress,
            streak: u32,
            category_id: Option<u32>
        ) {
            let mut total_reward = self.base_reward.read();
            
            // Add streak bonus
            let streak_bonus = self.streak_bonus.read() * streak.into();
            total_reward += streak_bonus;
            
            // Add category bonus if applicable
            match category_id {
                Option::Some(cat_id) => {
                    let category = self.challenge_categories.read(cat_id);
                    let category_bonus = (self.base_reward.read() * category.reward_multiplier.into()) / 100_u256;
                    total_reward += category_bonus;
                },
                Option::None => {}
            };
            
            // Transfer tokens to user
            let token = IERC20Dispatcher { contract_address: self.reward_token_address.read() };
            token.transfer(user, total_reward);
            
            self.emit(Event::RewardClaimed(RewardClaimed {
                user,
                amount: total_reward,
                timestamp: get_block_timestamp(),
            }));
        }
        
        // Check and unlock achievements
        fn _check_achievements(
            ref self: ContractState,
            user: ContractAddress,
            user_data: UserData
        ) {
            // Check streak achievements
            if user_data.current_streak >= SEVEN_DAY_STREAK_MILESTONE 
                && !self.achievements_unlocked.read((user, SEVEN_DAY_ACHIEVEMENT_ID)) {
                self.achievements_unlocked.write((user, SEVEN_DAY_ACHIEVEMENT_ID), true);
                self._award_achievement(user, SEVEN_DAY_ACHIEVEMENT_ID, SEVEN_DAY_ACHIEVEMENT_BONUS);
            }
            
            if user_data.current_streak >= THIRTY_DAY_STREAK_MILESTONE 
                && !self.achievements_unlocked.read((user, THIRTY_DAY_ACHIEVEMENT_ID)) {
                self.achievements_unlocked.write((user, THIRTY_DAY_ACHIEVEMENT_ID), true);
                self._award_achievement(user, THIRTY_DAY_ACHIEVEMENT_ID, THIRTY_DAY_ACHIEVEMENT_BONUS);
            }
            
            if user_data.current_streak >= NINETY_DAY_STREAK_MILESTONE 
                && !self.achievements_unlocked.read((user, NINETY_DAY_ACHIEVEMENT_ID)) {
                self.achievements_unlocked.write((user, NINETY_DAY_ACHIEVEMENT_ID), true);
                self._award_achievement(user, NINETY_DAY_ACHIEVEMENT_ID, NINETY_DAY_ACHIEVEMENT_BONUS);
            }
            
            // Check weekly challenge master
            if user_data.weekly_challenges_completed >= 7 
                && !self.achievements_unlocked.read((user, WEEKLY_CHALLENGE_MASTER)) {
                self.achievements_unlocked.write((user, WEEKLY_CHALLENGE_MASTER), true);
                self._award_achievement(user, WEEKLY_CHALLENGE_MASTER, WEEKLY_MASTER_BONUS);
            }
            
            // Check monthly challenge master
            if user_data.monthly_challenges_completed >= 30 
                && !self.achievements_unlocked.read((user, MONTHLY_CHALLENGE_MASTER)) {
                self.achievements_unlocked.write((user, MONTHLY_CHALLENGE_MASTER), true);
                self._award_achievement(user, MONTHLY_CHALLENGE_MASTER, MONTHLY_MASTER_BONUS);
            }
        }
        
        // Award achievement with bonus
        fn _award_achievement(
            ref self: ContractState,
            user: ContractAddress,
            achievement_id: u32,
            bonus: u256
        ) {
            // Transfer bonus tokens
            let token = IERC20Dispatcher { contract_address: self.reward_token_address.read() };
            token.transfer(user, bonus);
            
            self.emit(Event::AchievementUnlocked(AchievementUnlocked {
                user,
                achievement_id,
                timestamp: get_block_timestamp(),
            }));
        }
        
        // Get current system day
        fn _get_current_system_day(self: @ContractState) -> u64 {
            let current_time = get_block_timestamp();
            let start_time = self.system_start_timestamp.read();
            let seconds_per_day = self.seconds_per_day.read();
            
            if current_time < start_time {
                return 0;
            }
            
            (current_time - start_time) / seconds_per_day
        }
        
        // Modifier to check if contract is initialized
        fn only_initialized(self: @ContractState) {
            assert(self.initialized.read(), 'Contract not initialized');
        }
    }
}
