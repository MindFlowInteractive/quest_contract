#[starknet::contract]
pub mod LogicQuestPuzzle {
    // Imports
    use core::array::ArrayTrait;
    use core::num::traits::Zero;
    use core::option::OptionTrait;
    use core::traits::TryInto;
    use openzeppelin::access::accesscontrol::AccessControlComponent;
    use openzeppelin::introspection::src5::SRC5Component;
    use openzeppelin::token::erc20::interface::{
        ERC20ABIDispatcher, ERC20ABIDispatcherTrait, IERC20Dispatcher, IERC20DispatcherTrait,
        IERC20MetadataDispatcher, IERC20MetadataDispatcherTrait,
    };
    use starknet::storage::{
        Map, StorageMapReadAccess, StorageMapWriteAccess, StoragePointerReadAccess,
        StoragePointerWriteAccess,
    };
    use starknet::{ContractAddress, get_block_timestamp, get_caller_address, get_contract_address};
    use crate::base::types::{
        PlayerAttempt, Puzzle, Question, QuestionType, RewardParameters, options,
    };
    use crate::interfaces::iquest::ILogicQuestPuzzle;
    use crate::interfaces::iverification::{ISolutionVerificationDispatcher, ISolutionVerificationDispatcherTrait};

    // Constants
    const BASE_REWARD: u256 = 1_000_000_000_000_000; // 0.001 STRK base reward
    const TIME_BONUS_FACTOR: u256 = 2_000_000_000_000_000; // 0.002 STRK time bonus factor
    const DIFFICULTY_MULTIPLIER: u256 = 500_000_000_000_000; // 0.0005 STRK per difficulty level
    const PERFECT_SCORE_BONUS: u256 = 5_000_000_000_000_000; // 0.005 STRK for perfect score
    const MAX_REWARD_CAP: u256 = 50_000_000_000_000_000_000; // 50 STRK maximum reward cap
    const COOLDOWN_PERIOD: u64 = 86400; // 24 hours in seconds
    const REWARD_DECAY_FACTOR: u256 =
        800; // 80% decay factor for repeated attempts (divide by 1000)
    const TWO_STARK: u256 = 2_000_000_000_000_000_000;

    // components definition
    component!(path: AccessControlComponent, storage: accesscontrol, event: AccessControlEvent);
    component!(path: SRC5Component, storage: src5, event: SRC5Event);

    // AccessControl
    #[abi(embed_v0)]
    impl AccessControlImpl =
        AccessControlComponent::AccessControlImpl<ContractState>;
    impl AccessControlInternalImpl = AccessControlComponent::InternalImpl<ContractState>;

    // SRC5
    #[abi(embed_v0)]
    impl SRC5Impl = SRC5Component::SRC5Impl<ContractState>;

    // Events
    #[event]
    #[derive(Drop, starknet::Event, starknet::Event)]
    enum Event {
        PuzzleCreated: PuzzleCreated,
        QuestionAdded: QuestionAdded,
        OptionAdded: OptionAdded,
        CreatorAuthorized: CreatorAuthorized,
        CreatorRevoked: CreatorRevoked,
        ContractVersionUpdated: ContractVersionUpdated,
        RewardPaid: RewardPaid,
        PuzzleAttemptRecorded: PuzzleAttemptRecorded,
        RewardPoolFunded: RewardPoolFunded,
        EmergencyWithdrawal: EmergencyWithdrawal,
        #[flat]
        AccessControlEvent: AccessControlComponent::Event,
        #[flat]
        SRC5Event: SRC5Component::Event,
    }

    #[derive(Drop, starknet::Event)]
    struct PuzzleCreated {
        #[key]
        puzzle_id: u32,
        creator: ContractAddress,
        title: felt252,
        version: u32,
    }
    #[derive(Drop, starknet::Event)]
    struct RewardPoolFunded {
        amount: u256,
        funder: ContractAddress,
        new_balance: u256,
    }
    #[derive(Drop, starknet::Event)]
    struct PuzzleAttemptRecorded {
        #[key]
        player: ContractAddress,
        #[key]
        puzzle_id: u32,
        attempt_count: u32,
        timestamp: u64,
    }
    #[derive(Drop, starknet::Event)]
    struct RewardPaid {
        #[key]
        player: ContractAddress,
        #[key]
        puzzle_id: u32,
        reward_amount: u256,
        time_taken: u64,
        completion_timestamp: u64,
    }
    #[derive(Drop, starknet::Event)]
    struct EmergencyWithdrawal {
        amount: u256,
        recipient: ContractAddress,
        timestamp: u64,
    }

    #[derive(Drop, starknet::Event)]
    struct QuestionAdded {
        #[key]
        puzzle_id: u32,
        #[key]
        question_id: u32,
        question_type: QuestionType,
    }

    #[derive(Drop, starknet::Event)]
    struct OptionAdded {
        #[key]
        puzzle_id: u32,
        #[key]
        question_id: u32,
        #[key]
        option_id: u32,
        is_correct: bool,
    }

    #[derive(Drop, starknet::Event)]
    struct CreatorAuthorized {
        creator: ContractAddress,
    }

    #[derive(Drop, starknet::Event)]
    struct CreatorRevoked {
        creator: ContractAddress,
    }

    #[derive(Drop, starknet::Event)]
    struct ContractVersionUpdated {
        old_version: u32,
        new_version: u32,
    }

    // Contract storage
    #[storage]
    struct Storage {
        // Admin management
        admin: ContractAddress,
        authorized_creators: Map<ContractAddress, bool>,
        puzzles_count: u32,
        puzzles: Map<u32, Puzzle>,
        questions_count: Map<u32, u32>,
        questions: Map<(u32, u32), Question>,
        options_count: Map<(u32, u32), u32>,
        options: Map<(u32, u32, u32), options>,
        current_contract_version: u32,
        token_addr: ContractAddress,
        reward_parameters: RewardParameters,
        reward_pool_balance: u256,
        total_rewards_distributed: u256,
        // Player tracking
        player_attempts: Map<(ContractAddress, u32), PlayerAttempt>,
        player_last_puzzle_completion: Map<ContractAddress, u64>,
        player_puzzle_cooldowns: Map<(ContractAddress, u32), bool>,
        // Anti-gaming and security
        blacklisted_players: Map<ContractAddress, bool>,
        paused: bool,
        // Verification system integration
        verification_contract: ContractAddress,
        verification_required: bool,
        #[substorage(v0)]
        pub accesscontrol: AccessControlComponent::Storage,
        #[substorage(v0)]
        src5: SRC5Component::Storage,
    }

    // Constructor
    #[constructor]
    fn constructor(
        ref self: ContractState,
        token_addr: ContractAddress,
        admin_address: ContractAddress,
        verification_contract: ContractAddress,
    ) {
        self.admin.write(admin_address);
        self.puzzles_count.write(0);
        self.current_contract_version.write(1);
        self.token_addr.write(token_addr);
        self.paused.write(false);
        // Set verification contract address
        self.verification_contract.write(verification_contract);
        self.verification_required.write(true);
        // Authorize admin as a creator
        self.authorized_creators.write(admin_address, true);
    }

    // Modifiers
    #[generate_trait]
    impl ModifierImpl of ModifierTrait {
        fn only_admin(self: @ContractState) {
            let caller = get_caller_address();
            assert(caller == self.admin.read(), 'Only admin can call this');
        }

        fn only_authorized(self: @ContractState) {
            let caller = get_caller_address();
            assert(
                self.authorized_creators.read(caller) || caller == self.admin.read(),
                'Not authorized',
            );
        }
    }

    // Implementation
    #[abi(embed_v0)]
    impl LogicQuestPuzzleImpl of ILogicQuestPuzzle<ContractState> {
        // Add your function implementations here

        // Admin functions
        fn authorize_creator(ref self: ContractState, creator_address: ContractAddress) {
            self.only_admin();
            self.authorized_creators.write(creator_address, true);
            //self.emit(CreatorAuthorized { creator: creator_address });
        }

        fn revoke_creator(ref self: ContractState, creator_address: ContractAddress) {
            self.only_admin();
            self.authorized_creators.write(creator_address, false);
            //self.emit(CreatorRevoked { creator: creator_address });
        }

        fn update_contract_version(ref self: ContractState, new_version: u32) {
            self.only_admin();
            let old_version = self.current_contract_version.read();
            assert(new_version > old_version, 'Version must increase');
            self.current_contract_version.write(new_version);
            //self.emit(ContractVersionUpdated { old_version, new_version });
        }

        // Creator functions
        fn create_puzzle(
            ref self: ContractState,
            title: felt252,
            description: felt252,
            difficulty_level: u8,
            time_limit: u32,
        ) -> u32 {
            self.only_authorized();

            // Validate inputs
            assert(difficulty_level <= 10, 'Difficulty must be 1-10');

            let caller = get_caller_address();
            let puzzle_id = self.puzzles_count.read() + 1;
            let current_timestamp = starknet::get_block_timestamp();

            // Create new puzzle
            let new_puzzle = Puzzle {
                id: puzzle_id,
                title: title,
                description: description,
                version: self.current_contract_version.read(),
                difficulty_level: difficulty_level,
                total_points: 0, // Will be updated as questions are added
                time_limit: time_limit,
                creator: caller,
                creation_timestamp: current_timestamp,
            };

            // Store the puzzle
            self.fund_reward_pool_balance();
            self.puzzles.write(puzzle_id, new_puzzle);
            self.puzzles_count.write(puzzle_id);
            self.questions_count.write(puzzle_id, 0);

            //Emit event
            self
                .emit(
                    PuzzleCreated {
                        puzzle_id,
                        creator: caller,
                        title,
                        version: self.current_contract_version.read(),
                    },
                );

            puzzle_id
        }

        fn add_question(
            ref self: ContractState,
            puzzle_id: u32,
            content: felt252,
            question_type: QuestionType,
            difficulty: u8,
            points: u32,
        ) -> u32 {
            self.only_authorized();

            // Validate inputs
            assert(puzzle_id <= self.puzzles_count.read(), 'Invalid puzzle ID');
            assert(difficulty <= 10, 'Difficulty must be 1-10');

            // Get puzzle and validate caller is creator
            let puzzle = self.puzzles.read(puzzle_id);
            let caller = get_caller_address();
            assert(puzzle.creator == caller || self.admin.read() == caller, 'Not puzzle creator');

            // Create new question
            let question_id = self.questions_count.read(puzzle_id) + 1;
            let new_question = Question {
                id: question_id,
                content,
                question_type,
                difficulty,
                points,
            };

            // Store the question
            self.questions.write((puzzle_id, question_id), new_question);
            self.questions_count.write(puzzle_id, question_id);
            self.options_count.write((puzzle_id, question_id), 0);

            // Update puzzle total points
            let mut puzzle = self.puzzles.read(puzzle_id);
            puzzle.total_points += points;
            self.puzzles.write(puzzle_id, puzzle);

            // Emit event
            // self.emit(
            //     QuestionAdded {
            //         puzzle_id,
            //         question_id,
            //         question_type,
            //     }
            // );

            question_id
        }

        fn add_option(
            ref self: ContractState,
            puzzle_id: u32,
            question_id: u32,
            content: felt252,
            is_correct: bool,
        ) -> u32 {
            self.only_authorized();

            // Validate inputs
            assert(puzzle_id <= self.puzzles_count.read(), 'Invalid puzzle ID');
            assert(question_id <= self.questions_count.read(puzzle_id), 'Invalid question ID');

            // Get puzzle and validate caller is creator
            let puzzle = self.puzzles.read(puzzle_id);
            let caller = get_caller_address();
            assert(puzzle.creator == caller || self.admin.read() == caller, 'Not puzzle creator');

            // Create new option
            let option_id = self.options_count.read((puzzle_id, question_id)) + 1;
            let new_option = options { id: option_id, content, is_correct };

            // Store the option
            self.options.write((puzzle_id, question_id, option_id), new_option);
            self.options_count.write((puzzle_id, question_id), option_id);

            // // Emit event
            // self.emit(
            //     OptionAdded {
            //         puzzle_id,
            //         question_id,
            //         option_id,
            //         is_correct,
            //     }
            // );

            option_id
        }

        // Query functions
        fn get_puzzle(self: @ContractState, puzzle_id: u32) -> Puzzle {
            assert(puzzle_id <= self.puzzles_count.read(), 'Invalid puzzle ID');
            self.puzzles.read(puzzle_id)
        }

        fn get_question(self: @ContractState, puzzle_id: u32, question_id: u32) -> Question {
            assert(puzzle_id <= self.puzzles_count.read(), 'Invalid puzzle ID');
            assert(question_id <= self.questions_count.read(puzzle_id), 'Invalid question ID');
            self.questions.read((puzzle_id, question_id))
        }

        fn get_option(
            self: @ContractState, puzzle_id: u32, question_id: u32, option_id: u32,
        ) -> options {
            assert(puzzle_id <= self.puzzles_count.read(), 'Invalid puzzle ID');
            assert(question_id <= self.questions_count.read(puzzle_id), 'Invalid question ID');
            assert(
                option_id <= self.options_count.read((puzzle_id, question_id)), 'Invalid option ID',
            );
            self.options.read((puzzle_id, question_id, option_id))
        }

        fn get_puzzle_questions_count(self: @ContractState, puzzle_id: u32) -> u32 {
            assert(puzzle_id <= self.puzzles_count.read(), 'Invalid puzzle ID');
            self.questions_count.read(puzzle_id)
        }

        fn get_question_options_count(
            self: @ContractState, puzzle_id: u32, question_id: u32,
        ) -> u32 {
            assert(puzzle_id <= self.puzzles_count.read(), 'Invalid puzzle ID');
            assert(question_id <= self.questions_count.read(puzzle_id), 'Invalid question ID');
            self.options_count.read((puzzle_id, question_id))
        }

        fn get_total_puzzles(self: @ContractState) -> u32 {
            self.puzzles_count.read()
        }

        fn get_contract_version(self: @ContractState) -> u32 {
            self.current_contract_version.read()
        }

        fn is_authorized_creator(self: @ContractState, address: ContractAddress) -> bool {
            self.authorized_creators.read(address)
        }
        fn get_player_attempts(
            self: @ContractState, player: ContractAddress, puzzle_id: u32,
        ) -> PlayerAttempt {
            self.player_attempts.read((player, puzzle_id))
        }
        fn claim_puzzle_reward(ref self: ContractState, puzzle_id: u32) -> u256 {
            let check_paused = self.is_contract_paused();
            assert(!check_paused, 'contract is paused');

            let player = get_caller_address();

            let is_player_blacklisted = self.is_player_blacklisted(player);
            assert(!is_player_blacklisted, 'player is blacklisted');

            let puzzle = self.get_puzzle(puzzle_id);
            assert(puzzle.id == puzzle_id, 'Invalid puzzle');

            // Check if verification is required
            if self.verification_required.read() {
                // Verify solution through verification contract
                let verification_dispatcher = ISolutionVerificationDispatcher {
                    contract_address: self.verification_contract.read(),
                };

                // Check if solution is verified
                let is_verified = verification_dispatcher.is_solution_verified(player, puzzle_id);
                assert(is_verified, 'Solution not verified');

                // Get solution proof to extract score and time
                let proof = verification_dispatcher.get_solution_proof(player, puzzle_id);

                // Calculate reward based on verified score and time
                let reward_amount = self.calculate_reward(
                    puzzle_id, proof.score, proof.time_taken, player,
                );

                // Ensure the reward pool has sufficient funds
                let pool_check = self.has_sufficient_pool(reward_amount);
                assert(pool_check, 'Insufficient pool funds');

                // Get player attempt data
                let player_attempt = self.get_player_attempts(player, puzzle_id);

                // Update player attempt with verified data
                self.update_player_attempt(
                    proof.score,
                    player_attempt,
                    proof.time_taken,
                    player,
                    puzzle_id,
                    reward_amount,
                    get_block_timestamp(),
                );

                // Update global stats
                self.reward_pool_balance.write(self.reward_pool_balance.read() - reward_amount);
                self.total_rewards_distributed.write(
                    self.total_rewards_distributed.read() + reward_amount,
                );

                // Transfer STRK tokens to the player
                let reward = self.reward_players(player, reward_amount);
                assert(reward == 'REWARDED', 'reward player failed');

                // Emit event
                self.emit(
                    Event::RewardPaid(
                        RewardPaid {
                            player,
                            puzzle_id,
                            reward_amount,
                            time_taken: proof.time_taken,
                            completion_timestamp: get_block_timestamp(),
                        },
                    ),
                );

                reward_amount
            } else {
                // Original reward logic without verification
                // Check if the player is on cooldown for this puzzle
                let player_attempt = self.player_attempts.read((player, puzzle_id));
                let current_time = get_block_timestamp();

                if player_attempt.attempt_count > 0 {
                    assert(
                        current_time >= player_attempt.last_attempt_timestamp
                            + self.reward_parameters.read().cooldown_period,
                        'Puzzle on cooldown',
                    );
                }

                let player_attempt = self.get_player_attempts(player, puzzle_id);
                // Calculate the reward amount
                let reward_amount = self
                    .calculate_reward(
                        puzzle_id, player_attempt.best_score, player_attempt.best_time, player,
                    );

                // Ensure the reward pool has sufficient funds
                let pool_check = self.has_sufficient_pool(reward_amount);
                assert(pool_check, 'Insufficient pool funds');

                self
                    .update_player_attempt(
                        player_attempt.best_score,
                        player_attempt,
                        player_attempt.best_time,
                        player,
                        puzzle_id,
                        reward_amount,
                        current_time,
                    );

                // Update global stats
                self.reward_pool_balance.write(self.reward_pool_balance.read() - reward_amount);
                self
                    .total_rewards_distributed
                    .write(self.total_rewards_distributed.read() + reward_amount);

                // Transfer STRK tokens to the player
                let reward = self.reward_players(player, reward_amount);
                assert(reward == 'REWARDED', 'reward player failed');

                // Emit event
                self
                    .emit(
                        Event::RewardPaid(
                            RewardPaid {
                                player,
                                puzzle_id,
                                reward_amount,
                                time_taken: player_attempt.best_time,
                                completion_timestamp: current_time,
                            },
                        ),
                    );

                reward_amount
            }
        }

        fn update_player_attempt(
            ref self: ContractState,
            score: u32,
            player_attempt: PlayerAttempt,
            time_taken: u64,
            player: ContractAddress,
            puzzle_id: u32,
            reward_amount: u256,
            current_time: u64,
        ) {
            // Update player attempt data
            let new_attempt_count = player_attempt.attempt_count + 1;
            let best_score = if score > player_attempt.best_score {
                score
            } else {
                player_attempt.best_score
            };
            let best_time = if player_attempt.best_time == 0
                || time_taken < player_attempt.best_time {
                time_taken
            } else {
                player_attempt.best_time
            };

            // Update player stats
            self
                .player_attempts
                .write(
                    (player, puzzle_id),
                    PlayerAttempt {
                        attempt_count: new_attempt_count,
                        last_attempt_timestamp: current_time,
                        last_reward_amount: reward_amount,
                        total_rewards_earned: player_attempt.total_rewards_earned + reward_amount,
                        best_score,
                        best_time,
                    },
                );
        }

        fn has_sufficient_pool(ref self: ContractState, amount: u256) -> bool {
            let pool = get_contract_address();
            let erc20dispatcher = IERC20Dispatcher { contract_address: self.token_addr.read() };
            let pool_balance = erc20dispatcher.balance_of(pool);
            if (pool_balance > amount) {
                true
            } else {
                false
            }
        }

        // Query functions
        fn get_estimated_reward(
            self: @ContractState, puzzle_id: u32, score: u32, time_taken: u64,
        ) -> u256 {
            let player = get_caller_address();
            self.calculate_reward(puzzle_id, score, time_taken, player)
        }

        fn get_reward_parameters(self: @ContractState) -> RewardParameters {
            self.reward_parameters.read()
        }

        fn get_reward_pool_balance(self: @ContractState) -> u256 {
            self.reward_pool_balance.read()
        }

        fn get_total_rewards_distributed(self: @ContractState) -> u256 {
            self.total_rewards_distributed.read()
        }

        fn is_player_blacklisted(self: @ContractState, player: ContractAddress) -> bool {
            self.blacklisted_players.read(player)
        }

        fn is_contract_paused(self: @ContractState) -> bool {
            self.paused.read()
        }

        // Admin functions
        fn fund_reward_pool_balance(ref self: ContractState) {
            let caller = get_caller_address();

            // Transfer tokens from caller to contract
            let token_dispatcher = IERC20Dispatcher { contract_address: self.token_addr.read() };
            token_dispatcher.transfer_from(caller, get_contract_address(), TWO_STARK);

            // Update reward pool
            let new_balance = self.reward_pool_balance.read() + TWO_STARK;
            self.reward_pool_balance.write(new_balance);

            // Emit event
            self
                .emit(
                    Event::RewardPoolFunded(
                        RewardPoolFunded { amount: TWO_STARK, funder: caller, new_balance },
                    ),
                );
        }

        fn update_reward_parameters(
            ref self: ContractState,
            base_reward: u256,
            time_bonus_factor: u256,
            difficulty_multiplier: u256,
            perfect_score_bonus: u256,
            max_reward_cap: u256,
            cooldown_period: u64,
            reward_decay_factor: u256,
        ) {
            self.only_admin();

            // Validate parameters
            assert(max_reward_cap > 0, 'Invalid max reward cap');
            assert(reward_decay_factor <= 1000, 'Invalid decay factor');

            // Update parameters
            let new_parameters = RewardParameters {
                base_reward,
                time_bonus_factor,
                difficulty_multiplier,
                perfect_score_bonus,
                max_reward_cap,
                cooldown_period,
                reward_decay_factor,
            };

            self.reward_parameters.write(new_parameters);
        }

        fn blacklist_player(
            ref self: ContractState, player: ContractAddress, is_blacklisted: bool,
        ) {
            self.only_admin();
            self.blacklisted_players.write(player, is_blacklisted);
        }

        fn set_paused(ref self: ContractState, paused: bool) {
            self.only_admin();
            self.paused.write(paused);
        }

        fn emergency_withdraw(ref self: ContractState, amount: u256, recipient: ContractAddress) {
            self.only_admin();
            assert(recipient.is_non_zero(), 'Invalid recipient');
            assert(amount <= self.reward_pool_balance.read(), 'Amount exceeds pool');

            // Update reward pool
            self.reward_pool_balance.write(self.reward_pool_balance.read() - amount);

            // Transfer tokens
            let token_dispatcher = IERC20Dispatcher { contract_address: self.token_addr.read() };
            token_dispatcher.transfer(recipient, amount);

            // Emit event
            self
                .emit(
                    Event::EmergencyWithdrawal(
                        EmergencyWithdrawal { amount, recipient, timestamp: get_block_timestamp() },
                    ),
                );
        }

        // Add function to set verification contract address
        fn set_verification_contract(ref self: ContractState, verification_contract: ContractAddress) {
            self.only_admin();
            assert(verification_contract.is_non_zero(), 'Invalid contract address');
            self.verification_contract.write(verification_contract);
        }

        // Add function to toggle verification requirement
        fn set_verification_required(ref self: ContractState, required: bool) {
            self.only_admin();
            self.verification_required.write(required);
        }

        // Add function to check if verification is required
        fn is_verification_required(self: @ContractState) -> bool {
            self.verification_required.read()
        }

        // Add function to get verification contract address
        fn get_verification_contract(self: @ContractState) -> ContractAddress {
            self.verification_contract.read()
        }
    }

    #[generate_trait]
    impl Private of PrivateTrait {
        fn reward_players(
            ref self: ContractState, player: ContractAddress, amount: u256,
        ) -> felt252 {
            let dispatcher = IERC20Dispatcher { contract_address: self.token_addr.read() };

            // Transfer the tokens
            let reward = dispatcher.transfer(player, amount);
            if (reward) {
                'REWARDED'
            } else {
                'REWARD FAILED'
            }
        }

        fn calculate_reward(
            self: @ContractState,
            puzzle_id: u32,
            score: u32,
            time_taken: u64,
            player: ContractAddress,
        ) -> u256 {
            // Get reward parameters
            let params = self.reward_parameters.read();
            let puzzle = self.get_puzzle(puzzle_id);

            // Calculate base reward based on difficulty
            let difficulty_reward = params.base_reward
                + (puzzle.difficulty_level.into() * params.difficulty_multiplier);

            // Calculate total points from questions
            let total_points = puzzle.total_points;

            // Calculate score percentage (score out of total points)
            let score_percentage = if total_points > 0 {
                (score * 100) / total_points
            } else {
                0
            };

            // Apply score factor (linear scaling based on percentage)
            let score_factor = score_percentage.into();
            let score_reward = (difficulty_reward * score_factor) / 100;

            // Apply time bonus if under time limit
            let time_bonus = if puzzle.time_limit > 0 && time_taken < puzzle.time_limit.into() {
                let time_saved_percentage = ((puzzle.time_limit.into() - time_taken) * 100)
                    / puzzle.time_limit.into();
                (params.time_bonus_factor * time_saved_percentage.into()) / 100
            } else {
                0
            };

            // Add perfect score bonus if applicable
            let perfect_bonus = if score == total_points {
                params.perfect_score_bonus
            } else {
                0
            };

            // Calculate base reward before attempt decay
            let base_reward = score_reward + time_bonus + perfect_bonus;

            // Apply attempt decay for repeated attempts
            let player_attempt = self.player_attempts.read((player, puzzle_id));
            let attempt_decay = if player_attempt.attempt_count > 0 {
                // Apply decay factor for repeat attempts
                // Decay formula: reward * (decay_factor/1000)^(attempt_count-1)
                let mut decay = params.reward_decay_factor;
                let mut attempt_count = player_attempt.attempt_count;

                if attempt_count > 10 {
                    attempt_count = 10; // Cap decay at 10 attempts to prevent excessive reduction
                }

                // Apply decay for each attempt after the first
                let mut i = 1;
                while i < attempt_count {
                    decay = (decay * params.reward_decay_factor) / 1000;
                    i += 1;
                }

                decay
            } else {
                1000 // No decay for first attempt (1000/1000 = 1.0)
            };

            // Apply attempt decay
            let decayed_reward = (base_reward * attempt_decay.into()) / 1000;

            // Apply maximum cap
            if decayed_reward > params.max_reward_cap {
                params.max_reward_cap
            } else {
                decayed_reward
            }
        }
    }
}
