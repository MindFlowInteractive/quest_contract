#[starknet::contract]
pub mod LogicQuestPlayerProfile {
    // Imports
    use core::array::ArrayTrait;
    use core::num::traits::Zero;
    use core::option::OptionTrait;
    use core::traits::{Into, TryInto};
    use iplayerprofile::IPlayerProfile;
    use quest_contract::base::types::{LevelUnlock, PlayerProfile, PuzzleStats};
    use quest_contract::interfaces::iplayerprofile;
    use starknet::storage::{
        Map, StorageMapReadAccess, StorageMapWriteAccess, StoragePointerReadAccess,
        StoragePointerWriteAccess,
    };
    use starknet::{ContractAddress, get_block_timestamp, get_caller_address, contract_address_const};
use starknet::contract_address_const;
use starknet::contract_address::ContractAddressZeroable;
use core::option::OptionTrait;
use core::traits::Into;


    // Events
    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        ProfileCreated: ProfileCreated,
        ProfileUpdated: ProfileUpdated,
        PuzzleCompleted: PuzzleCompleted,
        LevelUnlocked: LevelUnlocked,
        StreakUpdated: StreakUpdated,
        TokensSpent: TokensSpent,
        FeatureUnlocked: FeatureUnlocked,
        HintPurchased: HintPurchased,
        BundlePurchased: BundlePurchased,
        SaleStarted: SaleStarted,
        SaleEnded: SaleEnded,
        TokensStaked: TokensStaked,
        TokensUnstaked: TokensUnstaked,
        RewardsClaimed: RewardsClaimed,
        ReferralRegistered: ReferralRegistered,
        ReferralRewardPaid: ReferralRewardPaid,
    }

    #[derive(Drop, starknet::Event)]
    struct ProfileCreated {
        #[key]
        player: ContractAddress,
        player_id: u32,
        username: felt252,
        timestamp: u64,
    }

    #[derive(Drop, starknet::Event)]
    struct ProfileUpdated {
        #[key]
        player: ContractAddress,
        username: felt252,
    }

    #[derive(Drop, Copy, starknet::Event)]
    struct PuzzleCompleted {
        #[key]
        player: ContractAddress,
        #[key]
        puzzle_id: u32,
        score: u32,
        time_taken: u64,
        total_puzzles_solved: u32,
    }

    #[derive(Drop, starknet::Event)]
    struct LevelUnlocked {
        #[key]
        player: ContractAddress,
        #[key]
        level_id: u32,
        unlock_method: felt252 // "achievement" or "token"
    }

    #[derive(Drop, starknet::Event)]
    struct StreakUpdated {
        #[key]
        player: ContractAddress,
        streak_days: u32,
    }

    #[derive(Drop, starknet::Event)]
    struct TokensSpent {
        #[key]
        player: ContractAddress,
        amount: u256,
        feature_type: felt252,
        feature_id: u32,
    }

    #[derive(Drop, starknet::Event)]
    struct FeatureUnlocked {
        #[key]
        player: ContractAddress,
        feature_type: felt252,
        feature_id: u32,
        cost: u256,
    }

    #[derive(Drop, starknet::Event)]
    struct HintPurchased {
        #[key]
        player: ContractAddress,
        puzzle_id: u32,
        hint_level: u8,
        hint_text: felt252,
        cost: u256,
    }

    #[derive(Drop, starknet::Event)]
    struct BundlePurchased {
        #[key]
        player: ContractAddress,
        bundle_id: u32,
        items: Array<u32>,
        total_cost: u256,
        discount: u256,
    }
    
    #[derive(Drop, starknet::Event)]
    struct SaleStarted {
        sale_id: u32,
        item_type: felt252,
        item_id: u32,
        discount_percent: u8,
        start_time: u64,
        end_time: u64,
    }
    
    #[derive(Drop, starknet::Event)]
    struct SaleEnded {
        sale_id: u32,
    }
    
    #[derive(Drop, starknet::Event)]
    struct TokensStaked {
        #[key]
        player: ContractAddress,
        amount: u256,
        unlock_time: u64,
    }
    
    #[derive(Drop, starknet::Event)]
    struct TokensUnstaked {
        #[key]
        player: ContractAddress,
        amount: u256,
        reward: u256,
    }
    
    #[derive(Drop, starknet::Event)]
    struct RewardsClaimed {
        #[key]
        player: ContractAddress,
        amount: u256,
    }
    
    #[derive(Drop, starknet::Event)]
    struct ReferralRegistered {
        #[key]
        referrer: ContractAddress,
        referee: ContractAddress,
    }
    
    #[derive(Drop, starknet::Event)]
    struct ReferralRewardPaid {
        #[key]
        referrer: ContractAddress,
        amount: u256,
        referee: ContractAddress,
    }

    // Contract storage
    #[storage]
    struct Storage {
        // Admin management
        admin: ContractAddress,
        // Player profiles
        players_count: u32,
        player_profiles: Map<ContractAddress, PlayerProfile>,
        player_ids: Map<u32, ContractAddress>,
        // Puzzle statistics
        player_puzzle_stats: Map<
            (ContractAddress, u32), PuzzleStats,
        >, // Maps (player, puzzle_id) to stats
        // Level unlocking
        levels_count: u32,
        level_unlocks: Map<u32, LevelUnlock>, // Maps level_id to unlock requirements
        player_unlocked_levels: Map<
            (ContractAddress, u32), bool,
        >, // Maps (player, level_id) to unlock status
        player_level_count: Map<ContractAddress, u32>, // Maps player to number of unlocked levels
        player_levels: Map<(ContractAddress, u32), u32>, // Maps (player, index) to level_id
        // Token interface and spending
        token_contract: ContractAddress,
        // Feature costs
        hint_costs: Map<u8, u256>, // hint_level -> cost
        feature_costs: Map<felt252, u256>, // feature_type -> cost
        // Player unlocks and purchases
        player_hints: Map<(ContractAddress, u32, u8), bool>, // (player, puzzle_id, hint_level) -> purchased
        player_features: Map<(ContractAddress, felt252, u32), bool>, // (player, feature_type, feature_id) -> unlocked
        // Cooldowns
        last_purchase: Map<ContractAddress, u64>, // player -> timestamp
        daily_spend: Map<ContractAddress, u256>, // player -> amount spent today
        daily_spend_reset: Map<ContractAddress, u64>, // player -> last reset timestamp
        // Bundles and Sales
        bundles: Map<u32, Bundle>,
        active_sales: Map<u32, Sale>,
        next_sale_id: u32,
        
        // Staking
        staked_balances: Map<ContractAddress, u256>,
        staking_start_time: Map<ContractAddress, u64>,
        staking_rewards: Map<ContractAddress, u256>,
        total_staked: u256,
        
        // Referral system
        referrals: Map<ContractAddress, ContractAddress>, // referee => referrer
        referral_counts: Map<ContractAddress, u32>,
        referral_rewards: Map<ContractAddress, u256>,
        
        // Constants
        DAILY_SPEND_LIMIT: u256,
        PURCHASE_COOLDOWN: u64,
        REFERRAL_REWARD_PERCENT: u8,
        STAKING_APY: u64, // APY as basis points (e.g., 500 = 5%)
        MIN_STAKING_DURATION: u64, // seconds
        MAX_STAKING_DURATION: u64, // seconds
        // Streak tracking
        last_day_timestamp: Map<
            ContractAddress, u64,
        > // Maps player to last day timestamp (for streak)
    }

    // Constructor
    #[constructor]
    fn constructor(ref self: ContractState, token_contract: ContractAddress) {
        self.admin.write(get_caller_address());
        self.token_contract.write(token_contract);
        
        // Set default costs (can be updated by admin)
        self.hint_costs.write(1, u256!(100)); // Basic hint
        self.hint_costs.write(2, u256!(250)); // Advanced hint
        self.hint_costs.write(3, u256!(500)); // Solution hint
        
        // Set default feature costs
        self.feature_costs.write('theme_rare', u256!(1000));
        self.feature_costs.write('theme_legendary', u256!(2500));
        self.feature_costs.write('powerup_extra_time', u256!(500));
        self.feature_costs.write('powerup_skip_puzzle', u256!(1000));
        
        // Set constants
        self.DAILY_SPEND_LIMIT.write(u256!(10000));
        self.PURCHASE_COOLDOWN.write(86400); // 24 hours in seconds
        self.REFERRAL_REWARD_PERCENT.write(5); // 5% referral reward
        self.STAKING_APY.write(1500); // 15% APY for staking
        self.MIN_STAKING_DURATION.write(7 * 86400); // 7 days
        self.MAX_STAKING_DURATION.write(365 * 86400); // 1 year
        
        // Initialize counters
        self.next_sale_id.write(0);
        self.next_bundle_id.write(0);
        self.total_staked.write(0);
        
        self._create_default_levels();
    }

    // Modifiers
    #[generate_trait]
    impl ModifierImpl of ModifierTrait {
        fn only_admin(self: @ContractState) {
            let caller = get_caller_address();
            assert(caller == self.admin.read(), 'Only admin can call this');
        }

        fn only_player_or_admin(self: @ContractState, player: ContractAddress) {
            let caller = get_caller_address();
            assert(caller == player || caller == self.admin.read(), 'Not authorized');
        }

        fn profile_exists(self: @ContractState, player: ContractAddress) -> PlayerProfile {
            let profile = self.player_profiles.read(player);
            assert(!profile.address.is_zero(), 'Profile does not exist');
            profile
        }
    }

    // Implementation
    #[abi(embed_v0)]
    impl PlayerProfileImpl of IPlayerProfile<ContractState> {
        // Player profile management
        fn create_profile(ref self: ContractState, username: felt252) -> u32 {
            let caller = get_caller_address();
            let existing_profile = self.player_profiles.read(caller);

            // Check if profile already exists
            assert(existing_profile.address.is_zero(), 'Profile already exists');

            // Create new profile
            let player_id = self.players_count.read() + 1;
            let current_timestamp = get_block_timestamp();

            let new_profile = PlayerProfile {
                player_id: player_id,
                address: caller,
                username: username,
                level: 1, // Start at level 1
                total_score: 0,
                puzzles_solved: 0,
                total_time_spent: 0,
                streak_days: 0,
                last_active_timestamp: current_timestamp,
                creation_timestamp: current_timestamp,
            };

            // Store the profile
            self.player_profiles.write(caller, new_profile);
            self.player_ids.write(player_id, caller);
            self.players_count.write(player_id);

            // Unlock the first level by default
            self.player_unlocked_levels.write((caller, 1), true);
            self.player_level_count.write(caller, 1);
            self.player_levels.write((caller, 0), 1); // Index 0 -> Level 1

            // Emit event
            self
                .emit(
                    Event::ProfileCreated(
                        ProfileCreated {
                            player: caller, player_id, username, timestamp: current_timestamp,
                        },
                    ),
                );

            player_id
        }

        fn update_profile(ref self: ContractState, username: felt252) {
            let caller = get_caller_address();
            let profile = self.profile_exists(caller);

            // Create updated profile
            let updated_profile = PlayerProfile {
                player_id: profile.player_id,
                address: profile.address,
                username: username,
                level: profile.level,
                total_score: profile.total_score,
                puzzles_solved: profile.puzzles_solved,
                total_time_spent: profile.total_time_spent,
                streak_days: profile.streak_days,
                last_active_timestamp: get_block_timestamp(),
                creation_timestamp: profile.creation_timestamp,
            };

            // Store updated profile
            self.player_profiles.write(caller, updated_profile);

            // Emit event
            self.emit(Event::ProfileUpdated(ProfileUpdated { player: caller, username }));
        }

        fn get_profile(self: @ContractState, player: ContractAddress) -> PlayerProfile {
            self.profile_exists(player)
        }

        // Progression tracking
        fn record_puzzle_completion(
            ref self: ContractState, puzzle_id: u32, score: u32, time_taken: u64,
        ) {
            let caller = get_caller_address();
            let profile = self.profile_exists(caller);
            let current_timestamp = get_block_timestamp();

            // Create a mutable copy of the profile
            let updated_profile = PlayerProfile {
                player_id: profile.player_id,
                address: profile.address,
                username: profile.username,
                level: profile.level,
                total_score: profile.total_score + score,
                puzzles_solved: profile.puzzles_solved + 1,
                total_time_spent: profile.total_time_spent + time_taken,
                streak_days: profile.streak_days,
                last_active_timestamp: current_timestamp,
                creation_timestamp: profile.creation_timestamp,
            };

            // Update puzzle stats
            let mut puzzle_stats = self.player_puzzle_stats.read((caller, puzzle_id));

            if puzzle_stats.player.is_zero() {
                // First attempt for this puzzle
                puzzle_stats =
                    PuzzleStats {
                        puzzle_id: puzzle_id,
                        player: caller,
                        attempts: 1,
                        best_score: score,
                        best_time: time_taken,
                        last_completion_timestamp: current_timestamp,
                    };
            } else {
                // Update existing stats
                puzzle_stats.attempts += 1;
                puzzle_stats.last_completion_timestamp = current_timestamp;

                // Update best score if current score is better
                if score > puzzle_stats.best_score {
                    puzzle_stats.best_score = score;
                }

                // Update best time if current time is better
                if time_taken < puzzle_stats.best_time {
                    puzzle_stats.best_time = time_taken;
                }
            }

            // Check and update streak
            self._update_streak(caller, current_timestamp);

            // Update level based on puzzles solved
            self._update_level(caller, updated_profile.puzzles_solved);

            // Store updated profile and stats
            self.player_profiles.write(caller, updated_profile);
            self.player_puzzle_stats.write((caller, puzzle_id), puzzle_stats);

            // Emit event
            self
                .emit(
                    Event::PuzzleCompleted(
                        PuzzleCompleted {
                            player: caller,
                            puzzle_id,
                            score,
                            time_taken,
                            total_puzzles_solved: updated_profile.puzzles_solved,
                        },
                    ),
                );
        }

        fn get_puzzle_stats(self: @ContractState, puzzle_id: u32) -> PuzzleStats {
            let caller = get_caller_address();
            self.player_puzzle_stats.read((caller, puzzle_id))
        }

        fn get_player_level(self: @ContractState, player: ContractAddress) -> u32 {
            let profile = self.profile_exists(player);
            profile.level
        }

        // Level unlocking
        fn unlock_level_with_achievement(
            ref self: ContractState, level_id: u32, achievement_id: u32,
        ) {
            let caller = get_caller_address();
            let _profile = self.profile_exists(caller);

            // Verify level exists
            assert(level_id <= self.levels_count.read(), 'Invalid level ID');
            let level = self.level_unlocks.read(level_id);

            // Check if already unlocked
            let is_unlocked = self.player_unlocked_levels.read((caller, level_id));
            assert(!is_unlocked, 'Level already unlocked');

            // Verify achievement requirement
            assert(level.achievement_requirement > 0, 'No achievement requirement');
            assert(achievement_id == level.achievement_requirement, 'Wrong achievement');

            // Check prerequisite level
            if level.prerequisite_level > 0 {
                let prereq_unlocked = self
                    .player_unlocked_levels
                    .read((caller, level.prerequisite_level));
                assert(prereq_unlocked, 'Prerequisite level not unlocked');
            }

            // Unlock the level
            self._unlock_level(caller, level_id, 'ach'); // Short string literal
        }

        fn unlock_level_with_tokens(ref self: ContractState, level_id: u32, token_amount: u256) {
            let caller = get_caller_address();
            let _profile = self.profile_exists(caller);

            // Verify level exists
            assert(level_id <= self.levels_count.read(), 'Invalid level ID');
            let level = self.level_unlocks.read(level_id);

            // Check if already unlocked
            let is_unlocked = self.player_unlocked_levels.read((caller, level_id));
            assert(!is_unlocked, 'Level already unlocked');

            // Verify token requirement
            assert(level.token_requirement > 0, 'No token requirement');
            assert(token_amount >= level.token_requirement, 'Insufficient tokens');

            // Check prerequisite level
            if level.prerequisite_level > 0 {
                let prereq_unlocked = self
                    .player_unlocked_levels
                    .read((caller, level.prerequisite_level));
                assert(prereq_unlocked, 'Prerequisite level not unlocked');
            }

            // TODO: Transfer tokens from caller to contract
            // This would require integration with the token contract
            // For now, we'll just unlock the level

            // Unlock the level
            self._unlock_level(caller, level_id, 'tok'); // Short string literal
        }

        fn is_level_unlocked(self: @ContractState, player: ContractAddress, level_id: u32) -> bool {
            // Verify level exists
            assert(level_id <= self.levels_count.read(), 'Invalid level ID');

            self.player_unlocked_levels.read((player, level_id))
        }

        fn get_unlocked_levels(self: @ContractState, player: ContractAddress) -> Array<u32> {
            let _profile = self.profile_exists(player);
            let level_count = self.player_level_count.read(player);

            let mut unlocked_levels = ArrayTrait::new();
            let mut i: u32 = 0;

            // Collect all unlocked levels
            while i != level_count {
                let level_id = self.player_levels.read((player, i));
                unlocked_levels.append(level_id);

                i += 1;
            }

            unlocked_levels
        }

        // Statistics
        fn get_total_puzzles_solved(self: @ContractState, player: ContractAddress) -> u32 {
            let profile = self.profile_exists(player);
            profile.puzzles_solved
        }

        fn get_average_completion_time(self: @ContractState, player: ContractAddress) -> u64 {
            let profile = self.profile_exists(player);

            if profile.puzzles_solved == 0 {
                return 0;
            }

            profile.total_time_spent / profile.puzzles_solved.into()
        }

        fn get_current_streak(self: @ContractState, player: ContractAddress) -> u32 {
            let profile = self.profile_exists(player);
            profile.streak_days
        }

        fn get_player_statistics(
            self: @ContractState, player: ContractAddress,
        ) -> (u32, u64, u32, u32) {
            let profile = self.profile_exists(player);
            let avg_time = if profile.puzzles_solved == 0 {
                0
            } else {
                profile.total_time_spent / profile.puzzles_solved.into()
            };

            (profile.puzzles_solved, avg_time, profile.streak_days, profile.total_score)
        }
    }

    // Bundle and Sale structures
    #[derive(Drop, Serde)]
    struct Bundle {
        id: u32,
        name: felt252,
        items: Array<(felt252, u32)>, // (item_type, item_id)
        total_cost: u256,
        discount_percent: u8,
        is_active: bool,
    }
    
    #[derive(Drop, Serde)]
    struct Sale {
        id: u32,
        item_type: felt252,
        item_id: u32,
        original_cost: u256,
        sale_cost: u256,
        start_time: u64,
        end_time: u64,
        is_active: bool,
    }
    
    // Staking position
    #[derive(Drop, Serde)]
    struct StakingPosition {
        amount: u256,
        start_time: u64,
        unlock_time: u64,
        claimed: bool,
    }

    // Implement token spending functionality
    #[generate_trait]
    impl PlayerTokenSpendingImpl of IPlayerTokenSpending<ContractState> {
        // ... existing functions ...
        
        // New functions for bundles and sales
        fn create_bundle(
            ref self: ContractState,
            name: felt252,
            items: Array<(felt252, u32)>,
            total_cost: u256,
            discount_percent: u8
        ) -> u32 {
            self.only_admin();
            let bundle_id = self.next_bundle_id.read() + 1;
            self.next_bundle_id.write(bundle_id);
            
            let bundle = Bundle {
                id: bundle_id,
                name,
                items,
                total_cost,
                discount_percent,
                is_active: true,
            };
            
            self.bundles.write(bundle_id, bundle);
            bundle_id
        }
        
        fn purchase_bundle(
            ref self: ContractState,
            bundle_id: u32,
            referral_code: Option<ContractAddress>
        ) {
            let caller = get_caller_address();
            self._check_cooldown(caller);
            
            let bundle = self.bundles.read(bundle_id);
            assert(bundle.is_active, 'Bundle not available');
            
            // Process payment with discount
            let final_cost = bundle.total_cost * (100 - bundle.discount_percent.into()) / 100;
            self._spend_tokens(caller, final_cost, 'bundle', bundle_id);
            
            // Unlock all items in the bundle
            let mut item_ids = ArrayTrait::new();
            let mut i = 0;
            loop {
                match bundle.items.at(i) {
                    Option::Some((item_type, item_id)) => {
                        let feature_key = (caller, item_type, item_id);
                        self.player_features.write(feature_key, true);
                        item_ids.append(item_id);
                        i += 1;
                    },
                    Option::None => { break; },
                };
            }
            
            // Process referral if provided
            self._process_referral(referral_code, final_cost);
            
            self.emit(BundlePurchased {
                player: caller,
                bundle_id,
                items: item_ids,
                total_cost: final_cost,
                discount: bundle.discount_percent.into(),
            });
        }
        
        fn start_sale(
            ref self: ContractState,
            item_type: felt252,
            item_id: u32,
            original_cost: u256,
            discount_percent: u8,
            duration_days: u64
        ) -> u32 {
            self.only_admin();
            let sale_id = self.next_sale_id.read() + 1;
            self.next_sale_id.write(sale_id);
            
            let start_time = get_block_timestamp();
            let end_time = start_time + (duration_days * 86400); // days to seconds
            
            let sale_cost = original_cost * (100 - discount_percent.into()) / 100;
            
            let sale = Sale {
                id: sale_id,
                item_type,
                item_id,
                original_cost,
                sale_cost,
                start_time,
                end_time,
                is_active: true,
            };
            
            self.active_sales.write(sale_id, sale);
            
            self.emit(SaleStarted {
                sale_id,
                item_type,
                item_id,
                discount_percent,
                start_time,
                end_time,
            });
            
            sale_id
        }
        
        // Staking functions
        fn stake_tokens(ref self: ContractState, amount: u256, duration_days: u64) {
            let caller = get_caller_address();
            let current_time = get_block_timestamp();
            
            // Validate staking duration
            let duration_seconds = duration_days * 86400;
            assert(
                duration_seconds >= self.MIN_STAKING_DURATION.read() && 
                duration_seconds <= self.MAX_STAKING_DURATION.read(),
                'Invalid staking duration'
            );
            
            // Transfer tokens from player to contract
            let token_contract = self.token_contract.read();
            let token_dispatcher = ISTARKDispatcher { contract_address: token_contract };
            
            let success = token_dispatcher.transfer_from(caller, contract_address!(), amount);
            assert(success, 'Token transfer failed');
            
            // Update staking position
            let unlock_time = current_time + duration_seconds;
            let staked_amount = self.staked_balances.read(caller) + amount;
            self.staked_balances.write(caller, staked_amount);
            self.staking_start_time.write(caller, current_time);
            self.total_staked.write(self.total_staked.read() + amount);
            
            self.emit(TokensStaked {
                player: caller,
                amount,
                unlock_time,
            });
        }
        
        fn unstake_tokens(ref self: ContractState) -> (u256, u256) {
            let caller = get_caller_address();
            let current_time = get_block_timestamp();
            
            let staked_amount = self.staked_balances.read(caller);
            assert(staked_amount > 0, 'No staked tokens');
            
            let start_time = self.staking_start_time.read(caller);
            assert(current_time >= start_time, 'Invalid staking period');
            
            // Calculate rewards (simple interest)
            let staking_duration = current_time - start_time;
            let apy = self.STAKING_APY.read().into();
            let rewards = (staked_amount * apy * staking_duration.into()) / (10000 * 31536000); // APY to per-second rate
            
            // Transfer staked amount + rewards back to player
            let token_contract = self.token_contract.read();
            let token_dispatcher = ISTARKDispatcher { contract_address: token_contract };
            
            let total_amount = staked_amount + rewards;
            let success = token_dispatcher.transfer(caller, total_amount);
            assert(success, 'Token transfer failed');
            
            // Update state
            self.staked_balances.write(caller, 0);
            self.staking_start_time.write(caller, 0);
            self.total_staked.write(self.total_staked.read() - staked_amount);
            
            self.emit(TokensUnstaked {
                player: caller,
                amount: staked_amount,
                reward: rewards,
            });
            
            (staked_amount, rewards)
        }
        
        // Referral system
        fn register_referral(ref self: ContractState, referrer: ContractAddress) {
            let caller = get_caller_address();
            assert(caller != referrer, 'Cannot refer yourself');
            
            // Check if already referred
            assert(
                !self.referrals.read(caller).is_some(),
                'Already registered with a referrer'
            );
            
            // Register referral
            self.referrals.write(caller, referrer);
            
            // Update referral count
            let ref_count = self.referral_counts.read(referrer) + 1;
            self.referral_counts.write(referrer, ref_count);
            
            self.emit(ReferralRegistered {
                referrer,
                referee: caller,
            });
        }
        
        // Internal function to process referral rewards
        fn _process_referral(
            ref self: ContractState,
            referrer_opt: Option<ContractAddress>,
            purchase_amount: u256
        ) {
            match referrer_opt {
                Option::Some(referrer) => {
                    // Check if referrer exists and is valid
                    if referrer != ContractAddress::ZERO && 
                       self.referral_counts.read(referrer) > 0 {
                        
                        let reward = purchase_amount * self.REFERRAL_REWARD_PERCENT.into() / 100;
                        if reward > 0 {
                            // Update referrer's rewards
                            let total_rewards = self.referral_rewards.read(referrer) + reward;
                            self.referral_rewards.write(referrer, total_rewards);
                            
                            // Emit event
                            self.emit(ReferralRewardPaid {
                                referrer,
                                amount: reward,
                                referee: get_caller_address(),
                            });
                        }
                    }
                },
                Option::None => {}
            };
        }
        
        // Admin function to update staking parameters
        fn update_staking_params(
            ref self: ContractState,
            min_duration: u64,
            max_duration: u64,
            apy: u64
        ) {
            self.only_admin();
            self.MIN_STAKING_DURATION.write(min_duration);
            self.MAX_STAKING_DURATION.write(max_duration);
            self.STAKING_APY.write(apy);
        }
        
        // Admin function to update referral reward percentage
        fn update_referral_reward(ref self: ContractState, reward_percent: u8) {
            self.only_admin();
            assert(reward_percent <= 100, 'Invalid reward percentage');
            self.REFERRAL_REWARD_PERCENT.write(reward_percent);
        }
        fn purchase_hint(
            ref self: ContractState,
            puzzle_id: u32,
            hint_level: u8,
            hint_text: felt252
        ) {
            let caller = get_caller_address();
            self._check_cooldown(caller);
            
            // Check if hint already purchased
            let hint_key = (caller, puzzle_id, hint_level);
            assert(!self.player_hints.read(hint_key), 'Hint already purchased');
            
            // Get and verify hint cost
            let cost = self.hint_costs.read(hint_level);
            assert(!cost.is_zero(), 'Invalid hint level');
            
            // Process payment
            self._spend_tokens(caller, cost, 'hint', hint_level.into());
            
            // Unlock hint
            self.player_hints.write(hint_key, true);
            
            // Emit event
            self.emit(HintPurchased {
                player: caller,
                puzzle_id,
                hint_level,
                hint_text,
                cost,
            });
        }
        
        fn unlock_feature(
            ref self: ContractState,
            feature_type: felt252,
            feature_id: u32
        ) {
            let caller = get_caller_address();
            self._check_cooldown(caller);
            
            // Check if feature already unlocked
            let feature_key = (caller, feature_type, feature_id);
            assert(!self.player_features.read(feature_key), 'Feature already unlocked');
            
            // Get and verify feature cost
            let cost = self.feature_costs.read(feature_type);
            assert(!cost.is_zero(), 'Invalid feature type');
            
            // Process payment
            self._spend_tokens(caller, cost, 'feature', feature_id);
            
            // Unlock feature
            self.player_features.write(feature_key, true);
            
            // Emit event
            self.emit(FeatureUnlocked {
                player: caller,
                feature_type,
                feature_id,
                cost,
            });
        }
        
        fn set_hint_cost(ref self: ContractState, hint_level: u8, cost: u256) {
            self.only_admin();
            self.hint_costs.write(hint_level, cost);
        }
        
        fn set_feature_cost(ref self: ContractState, feature_type: felt252, cost: u256) {
            self.only_admin();
            self.feature_costs.write(feature_type, cost);
        }
        
        fn get_daily_spend(self: @ContractState, player: ContractAddress) -> (u256, u256) {
            self._check_daily_reset(player);
            (self.daily_spend.read(player), self.DAILY_SPEND_LIMIT.read())
        }
        
        fn has_feature(
            self: @ContractState,
            player: ContractAddress,
            feature_type: felt252,
            feature_id: u32
        ) -> bool {
            self.player_features.read((player, feature_type, feature_id))
        }
        
        fn has_hint(
            self: @ContractState,
            player: ContractAddress,
            puzzle_id: u32,
            hint_level: u8
        ) -> bool {
            self.player_hints.read((player, puzzle_id, hint_level))
        }
    }
    
    // Internal functions
    #[generate_trait]
    impl InternalFunctions of InternalFunctionsTrait {
        fn _spend_tokens(
            ref self: ContractState,
            player: ContractAddress,
            amount: u256,
            feature_type: felt252,
            feature_id: u32
        ) {
            // Check daily spend limit
            self._check_daily_reset(player);
            let mut daily_spend = self.daily_spend.read(player);
            let new_daily_spend = daily_spend + amount;
            assert(
                new_daily_spend <= self.DAILY_SPEND_LIMIT.read(),
                'Daily spend limit exceeded'
            );
            self.daily_spend.write(player, new_daily_spend);
            
            // Transfer tokens from player to contract
            let token_contract = self.token_contract.read();
            let token_dispatcher = ISTARKDispatcher { contract_address: token_contract };
            
            // Check allowance and balance
            let allowance = token_dispatcher.allowance(player, contract_address!());
            let balance = token_dispatcher.balance_of(player);
            
            assert(allowance >= amount, 'Insufficient token allowance');
            assert(balance >= amount, 'Insufficient token balance');
            
            // Transfer tokens
            let success = token_dispatcher.transfer_from(player, contract_address!(), amount);
            assert(success, 'Token transfer failed');
            
            // Update last purchase timestamp
            self.last_purchase.write(player, get_block_timestamp());
            
            // Emit event
            self.emit(TokensSpent {
                player,
                amount,
                feature_type,
                feature_id,
            });
        }
        
        fn _check_cooldown(ref self: ContractState, player: ContractAddress) {
            let last_purchase = self.last_purchase.read(player);
            let cooldown = self.PURCHASE_COOLDOWN.read();
            let current_time = get_block_timestamp();
            
            if !last_purchase.is_zero() {
                let time_since_last = current_time - last_purchase;
                assert(time_since_last >= cooldown, 'Purchase cooldown active');
            }
        }
        
        fn _check_daily_reset(ref self: ContractState, player: ContractAddress) {
            let last_reset = self.daily_spend_reset.read(player);
            let current_time = get_block_timestamp();
            
            // Reset daily spend if it's a new day
            if last_reset.is_zero() || (current_time - last_reset) >= 86400 { // 24 hours in seconds
                self.daily_spend.write(player, u256!(0));
                self.daily_spend_reset.write(player, current_time);
            }
        }
        
        fn _create_default_levels(ref self: ContractState) {
        fn _create_default_levels(ref self: ContractState) {
            // Level 1 (Starting level)
            let level_id = self.levels_count.read() + 1;
            let level = LevelUnlock {
                level_id: level_id,
                name: 'Beg', // Shortened string literal
                description: 'Start', // Shortened string literal
                achievement_requirement: 0, // No achievement required
                token_requirement: 0, // No tokens required
                prerequisite_level: 0, // No prerequisite
                creation_timestamp: get_block_timestamp(),
            };

            self.level_unlocks.write(level_id, level);
            self.levels_count.write(level_id);

            // Level 2
            let level_id = self.levels_count.read() + 1;
            let level = LevelUnlock {
                level_id: level_id,
                name: 'Int', // Shortened string literal
                description: 'Lvl2', // Shortened string literal
                achievement_requirement: 1, // Achievement ID 1
                token_requirement: 100, // 100 tokens
                prerequisite_level: 1, // Requires Level 1
                creation_timestamp: get_block_timestamp(),
            };

            self.level_unlocks.write(level_id, level);
            self.levels_count.write(level_id);

            // Level 3
            let level_id = self.levels_count.read() + 1;
            let level = LevelUnlock {
                level_id: level_id,
                name: 'Adv', // Shortened string literal
                description: 'Lvl3', // Shortened string literal
                achievement_requirement: 2, // Achievement ID 2
                token_requirement: 250, // 250 tokens
                prerequisite_level: 2, // Requires Level 2
                creation_timestamp: get_block_timestamp(),
            };

            self.level_unlocks.write(level_id, level);
            self.levels_count.write(level_id);

            // Level 4
            let level_id = self.levels_count.read() + 1;
            let level = LevelUnlock {
                level_id: level_id,
                name: 'Exp', // Shortened string literal
                description: 'Lvl4', // Shortened string literal
                achievement_requirement: 3, // Achievement ID 3
                token_requirement: 500, // 500 tokens
                prerequisite_level: 3, // Requires Level 3
                creation_timestamp: get_block_timestamp(),
            };

            self.level_unlocks.write(level_id, level);
            self.levels_count.write(level_id);

            // Level 5
            let level_id = self.levels_count.read() + 1;
            let level = LevelUnlock {
                level_id: level_id,
                name: 'Mas', // Shortened string literal
                description: 'Lvl5', // Shortened string literal
                achievement_requirement: 4, // Achievement ID 4
                token_requirement: 1000, // 1000 tokens
                prerequisite_level: 4, // Requires Level 4
                creation_timestamp: get_block_timestamp(),
            };

            self.level_unlocks.write(level_id, level);
            self.levels_count.write(level_id);
        }

        fn _unlock_level(
            ref self: ContractState, player: ContractAddress, level_id: u32, unlock_method: felt252,
        ) {
            // Mark level as unlocked
            self.player_unlocked_levels.write((player, level_id), true);

            // Add to player's unlocked levels
            let level_count = self.player_level_count.read(player);
            self.player_levels.write((player, level_count), level_id);
            self.player_level_count.write(player, level_count + 1);

            // Emit event
            self.emit(Event::LevelUnlocked(LevelUnlocked { player, level_id, unlock_method }));
        }

        fn _update_streak(
            ref self: ContractState, player: ContractAddress, current_timestamp: u64,
        ) {
            let last_day = self.last_day_timestamp.read(player);
            let profile = self.player_profiles.read(player);

            // Calculate day difference (86400 seconds in a day)
            let day_diff = if last_day == 0 {
                0 // First activity
            } else {
                (current_timestamp - last_day) / 86400
            };

            let new_streak = if last_day == 0 || day_diff == 0 {
                // First activity or same day, no streak change
                profile.streak_days
            } else if day_diff == 1 {
                // Next consecutive day, increase streak
                profile.streak_days + 1
            } else {
                // Streak broken
                1 // Reset to 1 (today)
            };

            // Only emit event if streak changed
            if new_streak != profile.streak_days {
                self.emit(Event::StreakUpdated(StreakUpdated { player, streak_days: new_streak }));
            }

            // Update last day timestamp (normalize to start of day)
            let day_start = current_timestamp - (current_timestamp % 86400);
            self.last_day_timestamp.write(player, day_start);

            // Update profile with new streak
            let updated_profile = PlayerProfile {
                player_id: profile.player_id,
                address: profile.address,
                username: profile.username,
                level: profile.level,
                total_score: profile.total_score,
                puzzles_solved: profile.puzzles_solved,
                total_time_spent: profile.total_time_spent,
                streak_days: new_streak,
                last_active_timestamp: profile.last_active_timestamp,
                creation_timestamp: profile.creation_timestamp,
            };
            self.player_profiles.write(player, updated_profile);
        }

        fn _update_level(ref self: ContractState, player: ContractAddress, puzzles_solved: u32) {
            let profile = self.player_profiles.read(player);

            // Simple level progression based on puzzles solved
            let new_level = if puzzles_solved < 5 {
                1 // Beginner
            } else if puzzles_solved < 15 {
                2 // Intermediate
            } else if puzzles_solved < 30 {
                3 // Advanced
            } else if puzzles_solved < 50 {
                4 // Expert
            } else {
                5 // Master
            };

            // Update level if increased
            if new_level > profile.level {
                let updated_profile = PlayerProfile {
                    player_id: profile.player_id,
                    address: profile.address,
                    username: profile.username,
                    level: new_level,
                    total_score: profile.total_score,
                    puzzles_solved: profile.puzzles_solved,
                    total_time_spent: profile.total_time_spent,
                    streak_days: profile.streak_days,
                    last_active_timestamp: profile.last_active_timestamp,
                    creation_timestamp: profile.creation_timestamp,
                };
                self.player_profiles.write(player, updated_profile);
            }
        }
    }
}
