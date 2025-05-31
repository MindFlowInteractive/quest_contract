#[cfg(test)]
mod tests {
    use core::array::ArrayTrait;
    use core::num::traits::Zero;
    use core::option::OptionTrait;
    use core::traits::Into;
    use quest_contract::base::types::{PlayerProfile, LevelUnlock};
    use quest_contract::interfaces::iplayerprofile::IPlayerProfileDispatcherTrait;
    use quest_contract::interfaces::istark::ISTARKEmitter;
    use starknet::ContractAddress;
    use starknet::contract_address_const;
    use starknet::testing::{set_contract_address, set_block_timestamp};
    use super::IPlayerTokenSpendingDispatcherTrait;
    use super::IPlayerTokenSpendingDispatcher;
    use quest_contract::interfaces::iplayerprofile::IPlayerProfileDispatcher;

    // Helper function to setup test environment with multiple players
    fn setup() -> (
        IPlayerProfileDispatcher,
        ContractAddress, // contract address
        ContractAddress, // admin
        ContractAddress, // player1
        ContractAddress, // player2
        ContractAddress  // token contract
    ) {
        let admin = contract_address_const::<'admin'>();
        let player1 = contract_address_const::<'player1'>();
        let player2 = contract_address_const::<'player2'>();
        let token_contract = contract_address_const::<'token_contract'>();
        
        // Set caller to admin for deployment
        set_contract_address(admin);
        
        // Deploy the player profile contract
        let contract_address = deploy_contract('playerprofile', array![token_contract.into()].span());
        let dispatcher = IPlayerProfileDispatcher { contract_address };
        
        // Set up token contract with initial balances
        let token_dispatcher = ISTARKEmitter { contract_address: token_contract };
        
        // Set caller to players for profile creation
        set_contract_address(player1);
        dispatcher.create_profile('player1');
        
        set_contract_address(player2);
        dispatcher.create_profile('player2');
        
        // Set up token allowances and initial balances
        set_contract_address(admin);
        token_dispatcher.emit_approve(player1, contract_address, u256!(1000000));
        token_dispatcher.emit_approve(player2, contract_address, u256!(1000000));
        token_dispatcher.emit_transfer(ContractAddress::ZERO, player1, u256!(1000000));
        token_dispatcher.emit_transfer(ContractAddress::ZERO, player2, u256!(1000000));
        
        (dispatcher, contract_address, admin, player1, player2, token_contract)
    }

    #[test]
    fn test_purchase_hint() {
        let (dispatcher, _, _, player1, _, token_contract) = setup();
        let token_spending = IPlayerTokenSpendingDispatcher { contract_address: dispatcher.contract_address };
        let token_dispatcher = ISTARKEmitter { contract_address: token_contract };
        
        // Purchase a basic hint (level 1)
        token_spending.purchase_hint(1, 1, 'Basic hint');
        
        // Verify hint was purchased and tokens deducted
        assert(token_spending.has_hint(player1, 1, 1), 'Basic hint should be purchased');
        assert(
            token_dispatcher.balance_of(player1) == u256!(999900),
            'Should have deducted 100 tokens for basic hint'
        );
        
        // Purchase advanced hint (level 2)
        token_spending.purchase_hint(1, 2, 'Advanced hint');
        assert(token_spending.has_hint(player1, 1, 2), 'Advanced hint should be purchased');
        
        // Purchase solution hint (level 3)
        token_spending.purchase_hint(1, 3, 'Solution hint');
        assert(token_spending.has_hint(player1, 1, 3), 'Solution hint should be purchased');
    }
    
    #[test]
    #[should_panic(expected: ('Hint already purchased', ))]
    fn test_cannot_purchase_same_hint_twice() {
        let (dispatcher, _, _, player1, _, _) = setup();
        let token_spending = IPlayerTokenSpendingDispatcher { contract_address: dispatcher.contract_address };
        
        // Purchase same hint twice
        token_spending.purchase_hint(1, 1, 'Test hint');
        token_spending.purchase_hint(1, 1, 'Test hint'); // Should panic
    }
    
    #[test]
    #[should_panic(expected: ('Insufficient token balance', ))]
    fn test_cannot_purchase_with_insufficient_balance() {
        let (dispatcher, _, _, player1, _, token_contract) = setup();
        let token_spending = IPlayerTokenSpendingDispatcher { contract_address: dispatcher.contract_address };
        let token_dispatcher = ISTARKEmitter { contract_address: token_contract };
        
        // Set up player with only 50 tokens
        token_dispatcher.emit_transfer(player1, ContractAddress::ZERO, u256!(999950));
        
        // Try to purchase hint that costs 100 tokens
        token_spending.purchase_hint(1, 1, 'Test hint'); // Should panic
    }

    #[test]
    fn test_unlock_feature() {
        let (dispatcher, _, _, player1, _, token_contract) = setup();
        let token_spending = IPlayerTokenSpendingDispatcher { contract_address: dispatcher.contract_address };
        let token_dispatcher = ISTARKEmitter { contract_address: token_contract };
        
        // Unlock a theme feature
        token_spending.unlock_feature('theme_rare', 1);
        
        // Verify theme was unlocked and tokens deducted
        assert(
            token_spending.has_feature(player1, 'theme_rare', 1),
            'Theme should be unlocked'
        );
        assert(
            token_dispatcher.balance_of(player1) == u256!(999000),
            'Should have deducted 1000 tokens for rare theme'
        );
        
        // Unlock a power-up feature
        token_spending.unlock_feature('powerup_extra_time', 1);
        assert(
            token_spending.has_feature(player1, 'powerup_extra_time', 1),
            'Power-up should be unlocked'
        );
    }
    
    #[test]
    fn test_feature_costs_can_be_updated_by_admin() {
        let (dispatcher, _, admin, player1, _, _) = setup();
        let token_spending = IPlayerTokenSpendingDispatcher { contract_address: dispatcher.contract_address };
        
        // Admin updates feature cost
        set_contract_address(admin);
        token_spending.set_feature_cost('theme_legendary', u256!(2000));
        
        // Player tries to purchase at new price
        set_contract_address(player1);
        token_spending.unlock_feature('theme_legendary', 1);
        
        // Verify new price was used
        let token_dispatcher = ISTARKEmitter { contract_address: contract_address_const::<'token_contract'>() };
        assert(
            token_dispatcher.balance_of(player1) == u256!(998000), // 1,000,000 - 2,000
            'Should have deducted 2000 tokens for legendary theme'
        );
    }
    
    #[test]
    fn test_admin_can_update_hint_costs() {
        let (dispatcher, _, admin, player1, _, _) = setup();
        let token_spending = IPlayerTokenSpendingDispatcher { contract_address: dispatcher.contract_address };
        
        // Admin updates hint cost
        set_contract_address(admin);
        token_spending.set_hint_cost(1, u256!(150)); // Increase basic hint cost
        
        // Player purchases hint at new price
        set_contract_address(player1);
        token_spending.purchase_hint(1, 1, 'Test hint');
        
        // Verify new price was used
        let token_dispatcher = ISTARKEmitter { contract_address: contract_address_const::<'token_contract'>() };
        assert(
            token_dispatcher.balance_of(player1) == u256!(999850), // 1,000,000 - 150
            'Should have deducted 150 tokens for basic hint'
        );
    }

    #[test]
    #[should_panic(expected: ('Daily spend limit exceeded', ))]
    fn test_daily_spend_limit() {
        let (dispatcher, _, _, player1, _, token_contract) = setup();
        let token_spending = IPlayerTokenSpendingDispatcher { contract_address: dispatcher.contract_address };
        let token_dispatcher = ISTARKEmitter { contract_address: token_contract };
        
        // Spend up to the daily limit (10,000 tokens)
        token_spending.unlock_feature('theme_legendary', 1); // 2,500
        token_spending.unlock_feature('theme_legendary', 2); // 2,500
        token_spending.unlock_feature('theme_legendary', 3); // 2,500
        token_spending.unlock_feature('theme_legendary', 4); // 2,500 (total: 10,000)
        
        // Next purchase should fail
        token_spending.unlock_feature('theme_legendary', 5); // Should panic
    }
    
    #[test]
    fn test_daily_spend_limit_resets_after_24h() {
        let (dispatcher, _, _, player1, _, token_contract) = setup();
        let token_spending = IPlayerTokenSpendingDispatcher { contract_address: dispatcher.contract_address };
        
        // Spend up to the daily limit
        token_spending.unlock_feature('theme_legendary', 1); // 2,500
        token_spending.unlock_feature('theme_legendary', 2); // 2,500
        token_spending.unlock_feature('theme_legendary', 3); // 2,500
        token_spending.unlock_feature('theme_legendary', 4); // 2,500 (total: 10,000)
        
        // Fast forward time by 25 hours
        set_block_timestamp(get_block_timestamp() + 25 * 60 * 60);
        
        // Should be able to spend again after reset
        token_spending.unlock_feature('theme_legendary', 5); // Should succeed
    }

    #[test]
    #[should_panic(expected: ('Purchase cooldown active', ))]
    fn test_purchase_cooldown() {
        let (dispatcher, _, _, player1, _, token_contract) = setup();
        let token_spending = IPlayerTokenSpendingDispatcher { contract_address: dispatcher.contract_address };
        
        // First purchase should succeed
        token_spending.purchase_hint(1, 1, 'First hint');
        
        // Second purchase should fail due to cooldown
        token_spending.purchase_hint(1, 2, 'Second hint'); // Should panic
    }
    
    #[test]
    fn test_cooldown_expires_after_duration() {
        let (dispatcher, _, _, player1, _, _) = setup();
        let token_spending = IPlayerTokenSpendingDispatcher { contract_address: dispatcher.contract_address };
        
        // First purchase
        token_spending.purchase_hint(1, 1, 'First hint');
        
        // Fast forward time to just before cooldown expires
        set_block_timestamp(get_block_timestamp() + 86399); // 1 second before 24h
        
        // Should still be on cooldown
        let mut failed = false;
        match token_spending.try_purchase_hint(1, 2, 'Second hint') {
            Result::Ok(_) => {},
            Result::Err(_) => { failed = true; }
        }
        assert(failed, 'Should still be on cooldown');
        
        // Fast forward past cooldown
        set_block_timestamp(get_block_timestamp() + 2);
        
        // Should be able to purchase again
        token_spending.purchase_hint(1, 2, 'Second hint'); // Should succeed
    }

    #[test]
    fn test_admin_functions() {
        let (dispatcher, _, admin, _, _, _) = setup();
        let token_spending = IPlayerTokenSpendingDispatcher { contract_address: dispatcher.contract_address };
        
        // Test updating hint costs
        set_contract_address(admin);
        token_spending.set_hint_cost(1, u256!(200));
        token_spending.set_hint_cost(2, u256!(300));
        token_spending.set_hint_cost(3, u256!(600));
        
        // Test updating feature costs
        token_spending.set_feature_cost('theme_rare', u256!(1500));
        token_spending.set_feature_cost('theme_legendary', u256!(3000));
        token_spending.set_feature_cost('powerup_extra_time', u256!(750));
        token_spending.set_feature_cost('powerup_skip_puzzle', u256!(1500));
        
        // Test updating staking parameters
        token_spending.update_staking_params(
            7 * 86400,   // 7 days min
            365 * 86400, // 1 year max
            2000         // 20% APY
        );
        
        // Test updating referral reward percentage
        token_spending.update_referral_reward(10); // 10%
        
        // Verify admin-only protection
        set_contract_address(contract_address_const::<'player1'>());
        let mut failed = false;
        match token_spending.try_set_hint_cost(1, u256!(100)) {
            Result::Ok(_) => {},
            Result::Err(_) => { failed = true; }
        }
        assert(failed, 'Non-admin should not be able to set hint cost');
    }
    
    #[test]
    fn test_multiple_players_can_purchase_independently() {
        let (dispatcher, _, _, player1, player2, _) = setup();
        let token_spending = IPlayerTokenSpendingDispatcher { contract_address: dispatcher.contract_address };
        
        // Player1 purchases a hint
        set_contract_address(player1);
        token_spending.purchase_hint(1, 1, 'Player1 hint');
        
        // Player2 purchases a hint (should work even though player1 just purchased)
        set_contract_address(player2);
        token_spending.purchase_hint(1, 1, 'Player2 hint');
        
        // Verify both purchases were recorded
        assert(token_spending.has_hint(player1, 1, 1), 'Player1 hint should be purchased');
        assert(token_spending.has_hint(player2, 1, 1), 'Player2 hint should be purchased');
    }
    
    #[test]
    fn test_feature_unlocks_are_player_specific() {
        let (dispatcher, _, _, player1, player2, _) = setup();
        let token_spending = IPlayerTokenSpendingDispatcher { contract_address: dispatcher.contract_address };
        
        // Player1 unlocks a feature
        set_contract_address(player1);
        token_spending.unlock_feature('theme_rare', 1);
        
        // Verify only player1 has the feature
        assert(
            token_spending.has_feature(player1, 'theme_rare', 1),
            'Player1 should have the feature'
        );
        assert(
            !token_spending.has_feature(player2, 'theme_rare', 1),
            'Player2 should not have the feature'
        );
    }
}
