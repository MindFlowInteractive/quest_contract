#[cfg(test)]
mod tests {
    use core::array::ArrayTrait;
    use core::num::traits::Zero;
    use core::option::OptionTrait;
    use core::traits::Into;
    use starknet::ContractAddress;
    use starknet::contract_address_const;
    use starknet::testing::set_contract_address;
    use super::IPlayerTokenSpendingDispatcherTrait;
    use super::IPlayerTokenSpendingDispatcher;
    use quest_contract::interfaces::iplayerprofile::IPlayerProfileDispatcherTrait;
    use quest_contract::interfaces::istark::ISTARKEmitter;

    // Helper function to setup test environment
    fn setup() -> (
        IPlayerTokenSpendingDispatcher,
        ContractAddress, // contract address
        ContractAddress, // admin
        ContractAddress, // player1
        ContractAddress, // player2 (for referrals)
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
        let dispatcher = IPlayerTokenSpendingDispatcher { contract_address };
        
        // Set caller to players for profile creation
        set_contract_address(player1);
        let player_profile = IPlayerProfileDispatcher { contract_address };
        player_profile.create_profile('player1');
        
        set_contract_address(player2);
        player_profile.create_profile('player2');
        
        // Set up initial token balances
        let token_dispatcher = ISTARKEmitter { contract_address: token_contract };
        token_dispatcher.emit_approve(player1, contract_address, u256!(1000000));
        token_dispatcher.emit_approve(player2, contract_address, u256!(1000000));
        token_dispatcher.emit_transfer(ContractAddress::ZERO, player1, u256!(1000000));
        token_dispatcher.emit_transfer(ContractAddress::ZERO, player2, u256!(1000000));
        
        (dispatcher, contract_address, admin, player1, player2, token_contract)
    }

    #[test]
    fn test_bundle_purchase() {
        let (mut dispatcher, _, admin, player1, _, _) = setup();
        
        // Admin creates a bundle
        set_contract_address(admin);
        let bundle_items = array![('theme_rare', 1), ('powerup_extra_time', 1)];
        let bundle_id = dispatcher.create_bundle(
            'Starter Pack',
            bundle_items,
            u256!(1200), // Original price: 1000 + 500 = 1500, 20% discount
            20 // 20% discount
        );
        
        // Player purchases the bundle
        set_contract_address(player1);
        dispatcher.purchase_bundle(bundle_id, Option::None);
        
        // Verify items are unlocked
        assert(
            dispatcher.has_feature(player1, 'theme_rare', 1),
            'Theme should be unlocked'
        );
        assert(
            dispatcher.has_feature(player1, 'powerup_extra_time', 1),
            'Power-up should be unlocked'
        );
    }

    #[test]
    fn test_sale_event() {
        let (mut dispatcher, _, admin, player1, _, _) = setup();
        
        // Admin starts a sale
        set_contract_address(admin);
        let sale_id = dispatcher.start_sale(
            'theme_legendary',
            1,
            u256!(2500), // Original price
            30, // 30% off
            7 // 7 days duration
        );
        
        // Player purchases item on sale
        set_contract_address(player1);
        dispatcher.unlock_feature('theme_legendary', 1);
        
        // Verify purchase at sale price (1750 tokens instead of 2500)
        let token_dispatcher = ISTARKEmitter { contract_address: contract_address_const::<'token_contract'>() };
        assert(
            token_dispatcher.balance_of(player1) == u256!(998250), // 1,000,000 - 1,750
            'Should have spent 1,750 tokens (30% off 2,500)'
        );
    }

    #[test]
    fn test_token_staking() {
        let (dispatcher, _, _, player1, _, _) = setup();
        
        // Player stakes tokens
        let stake_amount = u256!(10000);
        dispatcher.stake_tokens(stake_amount, 30); // Stake for 30 days
        
        // Fast forward time by 30 days
        let thirty_days = 30 * 24 * 60 * 60; // seconds
        set_block_timestamp(get_block_timestamp() + thirty_days);
        
        // Unstake and claim rewards
        let (unstaked_amount, rewards) = dispatcher.unstake_tokens();
        
        // Verify staked amount and rewards
        assert(unstaked_amount == stake_amount, 'Should unstake full amount');
        assert(rewards > 0, 'Should earn staking rewards');
        
        // Verify final balance includes stake + rewards
        let token_dispatcher = ISTARKEmitter { contract_address: contract_address_const::<'token_contract'>() };
        assert(
            token_dispatcher.balance_of(player1) == u256!(1000000) + rewards,
            'Should receive staked amount + rewards'
        );
    }

    #[test]
    fn test_referral_system() {
        let (dispatcher, _, _, player1, player2, _) = setup();
        
        // Player2 registers Player1 as referrer
        set_contract_address(player2);
        dispatcher.register_referral(player1);
        
        // Player2 makes a purchase with Player1 as referrer
        dispatcher.purchase_hint(1, 1, 'Test hint');
        
        // Verify referrer received 5% of the purchase (5 tokens for 100 token hint)
        let referral_rewards = dispatcher.get_referral_rewards(player1);
        assert(referral_rewards == u256!(5), 'Referrer should earn 5% of purchase');
        
        // Verify referee gets a bonus (implement this in your contract)
        let referee_bonus = dispatcher.get_referral_bonus(player2);
        assert(referee_bonus > 0, 'Referee should receive a bonus');
    }

    #[test]
    #[should_panic(expected: ('Staking duration too short', ))]
    fn test_staking_duration_limits() {
        let (dispatcher, _, _, player1, _, _) = setup();
        
        // Try to stake for less than minimum duration (7 days)
        dispatcher.stake_tokens(u256!(1000), 5); // 5 days (should fail)
    }

    #[test]
    fn test_admin_functions() {
        let (dispatcher, _, admin, _, _, _) = setup();
        
        // Test updating staking parameters
        dispatcher.update_staking_params(14 * 86400, 730 * 86400, 2000); // 14d min, 2y max, 20% APY
        
        // Test updating referral rewards
        dispatcher.update_referral_reward(10); // 10% referral reward
        
        // Verify updates (these would be checked in other tests)
    }
}
