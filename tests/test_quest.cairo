// use openzeppelin::token::erc20::interface::{IERC20Dispatcher, IERC20DispatcherTrait};
// use quest_contract::base::types::QuestionType;
// use quest_contract::interfaces::iquest::{
//     ILogicQuestPuzzleDispatcher, ILogicQuestPuzzleDispatcherTrait,
// };
// use snforge_std::{
//     ContractClassTrait, DeclareResultTrait, declare, start_cheat_caller_address,
//     stop_cheat_caller_address,
// };
// use starknet::{ContractAddress, contract_address_const};


// fn setup() -> (ContractAddress, ContractAddress, ContractAddress, ContractAddress) {
//     let admin: ContractAddress = 'Admin'.try_into().unwrap();
//     let owner: ContractAddress = contract_address_const::<'owner'>();
//     let recipient: ContractAddress = contract_address_const::<'recipient'>();

//     // Deploy mock ERC20
//     let erc20_class = declare("STARKTOKEN").unwrap().contract_class();
//     let mut calldata = array![admin.into(), owner.into(), 6];
//     let (erc20_address, _) = erc20_class.deploy(@calldata).unwrap();

//     let contract = declare("LogicQuestPuzzle").unwrap().contract_class();
//     let (contract_address, _) = contract
//         .deploy(@array![erc20_address.into(), admin.into()])
//         .unwrap();
//     (contract_address, admin, recipient, erc20_address)
// }

// #[test]
// fn test_admin_is_set_correctly() {
//     let (contract_address, expected_admin, _, _) = setup();
//     let contract = ILogicQuestPuzzleDispatcher { contract_address };

//     // Check if admin is an authorized creator
//     let is_authorized = contract.is_authorized_creator(expected_admin);
//     assert(is_authorized, 'Admin should be authorized');
// }

// #[test]
// fn test_create_puzzle() {
//     let (contract_address, admin, recipient, erc20_address) = setup();
//     let contract = ILogicQuestPuzzleDispatcher { contract_address };

//     // Set the caller address to admin for the test
//     start_cheat_caller_address(contract_address, admin);

//     // Test data
//     let title: felt252 = 'Logic Puzzle 1';
//     let description: felt252 = 'Test description';
//     let difficulty_level: u8 = 5;
//     let time_limit: u32 = 3600; // 1 hour in seconds

//     let erc20 = IERC20Dispatcher { contract_address: erc20_address };

//     start_cheat_caller_address(erc20_address, admin);
//     erc20.approve(contract.contract_address, 200_000_000_000_000_000_000_000);
//     stop_cheat_caller_address(erc20_address);
//     // Create puzzle
//     start_cheat_caller_address(contract.contract_address, admin);
//     let puzzle_id = contract.create_puzzle(title, description, difficulty_level, time_limit);

//     // Assert puzzle was created correctly
//     assert(puzzle_id == 1, 'First puzzle should have ID 1');

//     // Get the puzzle to verify
//     let puzzle = contract.get_puzzle(puzzle_id);
//     assert(puzzle.title == title, 'Puzzle title mismatch');
//     assert(puzzle.description == description, 'Puzzle description mismatch');
//     assert(puzzle.difficulty_level == difficulty_level, 'Puzzle difficulty mismatch');
//     assert(puzzle.time_limit == time_limit, 'Puzzle time limit mismatch');
//     assert(puzzle.creator == admin, 'Puzzle creator mismatch');
//     assert(puzzle.version == 1, 'Puzzle version mismatch');
//     assert(puzzle.total_points == 0, 'Initial points should be 0');
// }

// #[test]
// fn test_authorize_creator() {
//     let (contract_address, admin, _, erc20_address) = setup();
//     let contract = ILogicQuestPuzzleDispatcher { contract_address };

//     start_cheat_caller_address(contract_address, admin);

//     // Create a new creator
//     let new_creator: ContractAddress = 'Creator1'.try_into().unwrap();

//     // Check that the new creator is not authorized initially
//     let initially_authorized = contract.is_authorized_creator(new_creator);
//     assert!(!initially_authorized, "Creator should not be authorized yet");

//     // Authorize the new creator
//     contract.authorize_creator(new_creator);

//     // Check that the new creator is now authorized
//     let now_authorized = contract.is_authorized_creator(new_creator);
//     assert!(now_authorized, "Creator should be authorized now");
// }

// #[test]
// fn test_revoke_creator() {
//     let (contract_address, admin, _, _) = setup();
//     let contract = ILogicQuestPuzzleDispatcher { contract_address };

//     start_cheat_caller_address(contract_address, admin);

//     // Create and authorize a new creator
//     let creator: ContractAddress = 'Creator2'.try_into().unwrap();
//     contract.authorize_creator(creator);

//     // Verify the creator was authorized
//     let is_authorized = contract.is_authorized_creator(creator);
//     assert(is_authorized, 'Creator should be authorized');

//     // Revoke creator's authorization
//     contract.revoke_creator(creator);

//     // Verify the creator is no longer authorized
//     let is_still_authorized = contract.is_authorized_creator(creator);
//     assert(!is_still_authorized, 'Creator should be revoked');
// }

// #[test]
// fn test_update_contract_version() {
//     let (contract_address, admin, _, _) = setup();
//     let contract = ILogicQuestPuzzleDispatcher { contract_address };

//     start_cheat_caller_address(contract_address, admin);

//     // Check initial version
//     let initial_version = contract.get_contract_version();
//     assert(initial_version == 1, 'Initial version should be 1');

//     // Update version
//     let new_version: u32 = 2;
//     contract.update_contract_version(new_version);

//     // Verify version was updated
//     let updated_version = contract.get_contract_version();
//     assert(updated_version == new_version, 'Version update failed');
// }

// #[test]
// fn test_add_question() {
//     let (contract_address, admin, _, erc20_address) = setup();
//     let contract = ILogicQuestPuzzleDispatcher { contract_address };

//     let erc20 = IERC20Dispatcher { contract_address: erc20_address };

//     start_cheat_caller_address(erc20_address, admin);
//     erc20.approve(contract.contract_address, 200_000_000_000_000_000_000_000);
//     stop_cheat_caller_address(erc20_address);
//     // Create puzzle
//     start_cheat_caller_address(contract.contract_address, admin);
//     // Create a puzzle first
//     let puzzle_id = contract.create_puzzle('Puzzle', 'Description', 5, 3600);

//     // Add a question
//     let question_content: felt252 = 'What is 2+2?';
//     let question_type = QuestionType::Logical;
//     let difficulty: u8 = 3;
//     let points: u32 = 10;

//     let question_id = contract
//         .add_question(puzzle_id, question_content, question_type, difficulty, points);

//     // Verify question was added
//     assert(question_id == 1, 'First question should have ID 1');

//     // Get the question count
//     let questions_count = contract.get_puzzle_questions_count(puzzle_id);
//     assert(questions_count == 1, 'Question count mismatch');

//     // Get the question to verify details
//     let question = contract.get_question(puzzle_id, question_id);
//     assert(question.content == question_content, 'Question content mismatch');
//     assert(question.points == points, 'Question points mismatch');

//     // Verify puzzle total points were updated
//     let puzzle = contract.get_puzzle(puzzle_id);
//     assert(puzzle.total_points == points, 'Puzzle points not updated');
// }

// #[test]
// fn test_add_option() {
//     let (contract_address, admin, _, erc20_address) = setup();
//     let contract = ILogicQuestPuzzleDispatcher { contract_address };

//     let erc20 = IERC20Dispatcher { contract_address: erc20_address };

//     start_cheat_caller_address(erc20_address, admin);
//     erc20.approve(contract.contract_address, 200_000_000_000_000_000_000_000);
//     stop_cheat_caller_address(erc20_address);
//     // Create puzzle
//     start_cheat_caller_address(contract.contract_address, admin);
//     // Create a puzzle and add a question
//     let puzzle_id = contract.create_puzzle('Puzzle', 'Description', 5, 3600);
//     let question_id = contract
//         .add_question(puzzle_id, 'What is 2+2?', QuestionType::Logical, 3, 10);

//     // Add an option
//     let option_content: felt252 = '4';
//     let is_correct: bool = true;

//     let option_id = contract.add_option(puzzle_id, question_id, option_content, is_correct);

//     // Verify option was added
//     assert(option_id == 1, 'First option should have ID 1');

//     // Get the option count
//     let options_count = contract.get_question_options_count(puzzle_id, question_id);
//     assert(options_count == 1, 'Option count mismatch');

//     // Get the option to verify details
//     let option = contract.get_option(puzzle_id, question_id, option_id);
//     assert(option.content == option_content, 'Option content mismatch');
//     assert(option.is_correct == is_correct, 'Option correctness mismatch');
// }

// #[test]
// fn test_multiple_questions_and_options() {
//     let (contract_address, admin, _, erc20_address) = setup();
//     let contract = ILogicQuestPuzzleDispatcher { contract_address };

//     let erc20 = IERC20Dispatcher { contract_address: erc20_address };

//     start_cheat_caller_address(erc20_address, admin);
//     erc20.approve(contract.contract_address, 200_000_000_000_000_000_000_000);
//     stop_cheat_caller_address(erc20_address);
//     // Create puzzle
//     start_cheat_caller_address(contract.contract_address, admin);
//     // Create a puzzle
//     let puzzle_id = contract.create_puzzle('Complex Puzzle', 'Multiple Q&A', 7, 7200);

//     // Add first question
//     let q1_id = contract.add_question(puzzle_id, 'Question 1', QuestionType::Logical, 5, 15);

//     // Add second question
//     let q2_id = contract.add_question(puzzle_id, 'Question 2', QuestionType::Logical, 4, 10);

//     // Add options to first question
//     let q1_opt1 = contract.add_option(puzzle_id, q1_id, 'Option A', false);
//     let q1_opt2 = contract.add_option(puzzle_id, q1_id, 'Option B', true);

//     // Add options to second question
//     let q2_opt1 = contract.add_option(puzzle_id, q2_id, 'True', true);
//     let q2_opt2 = contract.add_option(puzzle_id, q2_id, 'False', false);

//     // Verify questions count
//     let questions_count = contract.get_puzzle_questions_count(puzzle_id);
//     assert(questions_count == 2, 'Should have 2 questions');

//     // Verify options count
//     let q1_options_count = contract.get_question_options_count(puzzle_id, q1_id);
//     let q2_options_count = contract.get_question_options_count(puzzle_id, q2_id);
//     assert!(q1_options_count == 2, "Question 1 should have 2 options");
//     assert!(q2_options_count == 2, "Question 2 should have 2 options");

//     // Verify puzzle total points
//     let puzzle = contract.get_puzzle(puzzle_id);
//     assert(puzzle.total_points == 25, 'Total points should be 25');
// }

// #[test]
// fn test_get_total_puzzles() {
//     let (contract_address, admin, _, erc20_address) = setup();
//     let contract = ILogicQuestPuzzleDispatcher { contract_address };

//     start_cheat_caller_address(contract_address, admin);
//     let erc20 = IERC20Dispatcher { contract_address: erc20_address };

//     start_cheat_caller_address(erc20_address, admin);
//     erc20.approve(contract.contract_address, 200_000_000_000_000_000_000_000);
//     stop_cheat_caller_address(erc20_address);
//     // Create puzzle
//     start_cheat_caller_address(contract.contract_address, admin);
//     // Check initial puzzle count
//     let initial_count = contract.get_total_puzzles();
//     assert(initial_count == 0, 'Should start with 0 puzzles');

//     // Create a few puzzles
//     contract.create_puzzle('Puzzle 1', 'Description 1', 5, 3600);
//     contract.create_puzzle('Puzzle 2', 'Description 2', 3, 1800);
//     contract.create_puzzle('Puzzle 3', 'Description 3', 7, 5400);

//     // Check updated puzzle count
//     let updated_count = contract.get_total_puzzles();
//     assert(updated_count == 3, 'Should have 3 puzzles');
// }

// #[should_panic(expected: ('Not authorized',))]
// #[test]
// fn test_unauthorized_create_puzzle() {
//     let (contract_address, _, _, _) = setup();
//     let contract = ILogicQuestPuzzleDispatcher { contract_address };

//     // Create unauthorized user
//     let unauthorized_user: ContractAddress = 'Unauthorized'.try_into().unwrap();
//     start_cheat_caller_address(contract_address, unauthorized_user);

//     // Attempt to create a puzzle (should panic)
//     contract.create_puzzle('Puzzle', 'Description', 5, 3600);
// }

// #[should_panic(expected: ('Only admin can call this',))]
// #[test]
// fn test_non_admin_authorize_creator() {
//     let (contract_address, _, _, _) = setup();
//     let contract = ILogicQuestPuzzleDispatcher { contract_address };

//     // Create non-admin user
//     let non_admin: ContractAddress = 'NonAdmin'.try_into().unwrap();
//     start_cheat_caller_address(contract_address, non_admin);

//     // Attempt to authorize creator (should panic)
//     let new_creator: ContractAddress = 'Creator'.try_into().unwrap();
//     contract.authorize_creator(new_creator);
// }

// #[should_panic(expected: ('Difficulty must be 1-10',))]
// #[test]
// fn test_invalid_difficulty() {
//     let (contract_address, admin, _, _) = setup();
//     let contract = ILogicQuestPuzzleDispatcher { contract_address };

//     start_cheat_caller_address(contract_address, admin);

//     // Try to create puzzle with invalid difficulty
//     contract.create_puzzle('Puzzle', 'Description', 11, 3600);
// }

// #[should_panic(expected: ('Version must increase',))]
// #[test]
// fn test_invalid_version_update() {
//     let (contract_address, admin, _, _) = setup();
//     let contract = ILogicQuestPuzzleDispatcher { contract_address };

//     start_cheat_caller_address(contract_address, admin);

//     // Try to update to same version
//     contract.update_contract_version(1);
// }

// #[should_panic(expected: ('Invalid puzzle ID',))]
// #[test]
// fn test_invalid_puzzle_id() {
//     let (contract_address, admin, _, _) = setup();
//     let contract = ILogicQuestPuzzleDispatcher { contract_address };

//     start_cheat_caller_address(contract_address, admin);

//     // Try to get non-existent puzzle
//     contract.get_puzzle(999);
// }

// #[should_panic(expected: ('Not puzzle creator',))]
// #[test]
// fn test_add_question_not_creator() {
//     let (contract_address, admin, _, erc20_address) = setup();
//     let contract = ILogicQuestPuzzleDispatcher { contract_address };

//     let erc20 = IERC20Dispatcher { contract_address: erc20_address };

//     start_cheat_caller_address(erc20_address, admin);
//     erc20.approve(contract.contract_address, 200_000_000_000_000_000_000_000);
//     stop_cheat_caller_address(erc20_address);
//     // Create puzzle
//     start_cheat_caller_address(contract.contract_address, admin);
//     // Create a puzzle
//     let puzzle_id = contract.create_puzzle('Puzzle', 'Description', 5, 3600);

//     // Switch to another authorized creator
//     let another_creator: ContractAddress = 'Creator'.try_into().unwrap();
//     contract.authorize_creator(another_creator);
//     start_cheat_caller_address(contract_address, another_creator);

//     // Try to add question to puzzle created by admin (should fail)
//     contract.add_question(puzzle_id, 'Question', QuestionType::Logical, 5, 10);
// }

// #[test]
// fn test_creator_can_add_to_own_puzzle() {
//     let (contract_address, admin, _, erc20_address) = setup();
//     let contract = ILogicQuestPuzzleDispatcher { contract_address };

//     // Create a new authorized creator
//     let creator: ContractAddress = 'Creator'.try_into().unwrap();

//     start_cheat_caller_address(contract_address, admin);
//     let erc20 = IERC20Dispatcher { contract_address: erc20_address };

//     start_cheat_caller_address(erc20_address, admin);
//     erc20.approve(contract.contract_address, 200_000_000_000_000_000_000_000);
//     stop_cheat_caller_address(erc20_address);
//     // Create puzzle

//     contract.authorize_creator(creator);

//     // Switch to creator and create a puzzle
//     start_cheat_caller_address(contract_address, admin);
//     let puzzle_id = contract.create_puzzle('Creator Puzzle', 'Made by creator', 5, 3600);

//     // Creator should be able to add questions to their puzzle
//     let question_id = contract
//         .add_question(puzzle_id, 'Creator Question', QuestionType::Logical, 5, 10);

//     // Verify question was added
//     assert(question_id == 1, 'Question should be added');
// }

// #[test]
// fn test_admin_can_edit_any_puzzle() {
//     let (contract_address, admin, _, erc20_address) = setup();
//     let contract = ILogicQuestPuzzleDispatcher { contract_address };

//     // Create and authorize a creator
//     let creator: ContractAddress = 'Creator'.try_into().unwrap();

//     let erc20 = IERC20Dispatcher { contract_address: erc20_address };

//     start_cheat_caller_address(erc20_address, admin);
//     erc20.approve(contract.contract_address, 200_000_000_000_000_000_000_000);
//     stop_cheat_caller_address(erc20_address);

//     start_cheat_caller_address(contract_address, admin);
//     // Create puzzle
//     contract.authorize_creator(creator);

//     // Creator creates a puzzle
//     let puzzle_id = contract.create_puzzle('Creator Puzzle', 'Made by creator', 5, 3600);

//     // Admin should be able to add questions to creator's puzzle
//     let question_id = contract
//         .add_question(puzzle_id, 'Admin Question', QuestionType::Logical, 5, 10);
//     stop_cheat_caller_address(contract_address);

//     // Verify question was added
//     assert!(question_id == 1, "Admin should be able to add question");
// }

// #[test]
// fn test_claim_prize_reward() {
//     let (contract_address, admin, _, erc20_address) = setup();
//     let dispatcher = ILogicQuestPuzzleDispatcher { contract_address };

//     let erc20 = IERC20Dispatcher { contract_address: erc20_address };

//     start_cheat_caller_address(erc20_address, admin);
//     erc20.approve(dispatcher.contract_address, 200_000_000_000_000_000_000_000);
//     stop_cheat_caller_address(erc20_address);

//     // Creator creates a puzzle
//     start_cheat_caller_address(contract_address, admin);
//     // Create a puzzle first
//     let puzzle_id = dispatcher.create_puzzle('Puzzle', 'Description', 5, 3600);
//     stop_cheat_caller_address(dispatcher.contract_address);
//     assert(puzzle_id == 1, 'puzzle creation failed');

//     dispatcher.claim_puzzle_reward(puzzle_id);
// }

// #[should_panic(expected: ('Version must increase',))]
// #[test]
// fn test_invalid_version_update_() {
//     let (contract_address, admin, _, _) = setup();
//     let contract = ILogicQuestPuzzleDispatcher { contract_address };

//     start_cheat_caller_address(contract_address, admin);

//     // Try to update to same version
//     contract.update_contract_version(1);
// }

// #[should_panic(expected: ('Invalid puzzle ID',))]
// #[test]
// fn test_invalid_puzzle_ids() {
//     let (contract_address, admin, _, _) = setup();
//     let contract = ILogicQuestPuzzleDispatcher { contract_address };

//     start_cheat_caller_address(contract_address, admin);

//     // Try to get non-existent puzzle
//     contract.get_puzzle(9099999);
// }

// #[should_panic(expected: ('Not puzzle creator',))]
// #[test]
// fn test_add_question_not_by_creator() {
//     let (contract_address, admin, _, erc20_address) = setup();
//     let contract = ILogicQuestPuzzleDispatcher { contract_address };

//     let erc20 = IERC20Dispatcher { contract_address: erc20_address };

//     start_cheat_caller_address(erc20_address, admin);
//     erc20.approve(contract.contract_address, 200_000_000_000_000_000_000_000);
//     stop_cheat_caller_address(erc20_address);
//     // Create puzzle
//     start_cheat_caller_address(contract.contract_address, admin);
//     // Create a puzzle
//     let puzzle_id = contract.create_puzzle('QUIZ', 'Description', 5, 86000);

//     // Switch to another authorized creator
//     let another_creator: ContractAddress = 'Creator'.try_into().unwrap();
//     contract.authorize_creator(another_creator);
//     start_cheat_caller_address(contract_address, another_creator);

//     // Try to add question to puzzle created by admin (should fail)
//     contract.add_question(puzzle_id, 'Question', QuestionType::Logical, 5, 10);
// }

// #[test]
// fn test_creator_can_add_to_own_puzzle_by_owner() {
//     let (contract_address, owner, _, erc20_address) = setup();
//     let contract = ILogicQuestPuzzleDispatcher { contract_address };

//     // Create a new authorized creator
//     let creator: ContractAddress = 'Creator'.try_into().unwrap();

//     start_cheat_caller_address(contract_address, owner);
//     let erc20 = IERC20Dispatcher { contract_address: erc20_address };

//     start_cheat_caller_address(erc20_address, owner);
//     erc20.approve(contract.contract_address, 200_000_000_000_000_000_000_000);
//     stop_cheat_caller_address(erc20_address);
//     // Create puzzle

//     contract.authorize_creator(creator);

//     // Switch to creator and create a puzzle
//     start_cheat_caller_address(contract_address, owner);
//     let puzzle_id = contract.create_puzzle('Creator Puzzle', 'Made by creator', 5, 3600);

//     // Creator should be able to add questions to their puzzle
//     let question_id = contract
//         .add_question(puzzle_id, 'Creator Question', QuestionType::Logical, 5, 10);

//     // Verify question was added
//     assert(question_id == 1, 'Question should be added');
// }

// #[test]
// fn test_admin_can_edit_any_puzzle_() {
//     let (contract_address, admin, _, erc20_address) = setup();
//     let contract = ILogicQuestPuzzleDispatcher { contract_address };

//     // Create and authorize a creator
//     let creator: ContractAddress = 'Creator'.try_into().unwrap();

//     let erc20 = IERC20Dispatcher { contract_address: erc20_address };

//     start_cheat_caller_address(erc20_address, admin);
//     erc20.approve(contract.contract_address, 200_000_000_000_000_000_000_000);
//     stop_cheat_caller_address(erc20_address);

//     start_cheat_caller_address(contract_address, admin);
//     // Create puzzle
//     contract.authorize_creator(creator);

//     // Creator creates a puzzle
//     let puzzle_id = contract.create_puzzle('Creator Puzzle', 'Made by creator', 5, 3600);

//     // Admin should be able to add questions to creator's puzzle
//     let question_id = contract
//         .add_question(puzzle_id, 'Owner Question', QuestionType::Logical, 5, 10);
//     stop_cheat_caller_address(contract_address);

//     // Verify question was added
//     assert!(question_id == 1, "Admin should be able to add question");
// }

// #[test]
// #[should_panic(expected: 'Difficulty must be 1-10')]
// fn test_claim_prize_reward_different_values() {
//     let (contract_address, admin, _, erc20_address) = setup();
//     let dispatcher = ILogicQuestPuzzleDispatcher { contract_address };

//     let erc20 = IERC20Dispatcher { contract_address: erc20_address };

//     start_cheat_caller_address(erc20_address, admin);
//     erc20.approve(dispatcher.contract_address, 200_000_000_000_000_000_000_000);
//     stop_cheat_caller_address(erc20_address);

//     // Creator creates a puzzle
//     start_cheat_caller_address(contract_address, admin);
//     // Create a puzzle first
//     let puzzle_id = dispatcher.create_puzzle('Puzzle', 'Description', 89, 3600);
//     stop_cheat_caller_address(dispatcher.contract_address);
//     assert(puzzle_id == 1, 'puzzle creation failed');

//     dispatcher.claim_puzzle_reward(puzzle_id);
// }
