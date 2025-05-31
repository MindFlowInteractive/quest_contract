use starknet::ContractAddress;
use starknet::testing::{deploy, set_contract_address, set_caller_address, set_block_timestamp};
use starknet::contract_address_const;
use starknet::ClassHash;

// Helper function to deploy a contract
fn deploy_contract(contract_name: felt252, constructor_calldata: Array<felt252>) -> ContractAddress {
    let contract_address = deploy('src', contract_name, ArrayTrait::new(), constructor_calldata);
    contract_address
}

// Helper function to deploy a test ERC20 token
fn deploy_token_contract() -> ContractAddress {
    let token_contract = deploy_contract(
        'TestToken', 
        array!['TestToken'.into(), 'TTK'.into(), 18.into(), 1000000000000000000000000_u256.into()].span()
    );
    token_contract
}

// Helper function to mint tokens to an address
fn mint_tokens(token_contract: ContractAddress, to: ContractAddress, amount: u256) {
    set_caller_address(contract_address_const::<0x01>()); // Owner
    let token_dispatcher = IERC20Dispatcher { contract_address: token_contract };
    token_dispatcher.mint(to, amount);
}

// Helper function to advance time by a number of days
fn advance_time_days(days: u64) {
    let current_timestamp = starknet::get_block_timestamp();
    set_block_timestamp(current_timestamp + (days * 86400));
}

// ERC20 interface for testing
#[starknet::interface]
trait IERC20<T> {
    fn name(self: @T) -> felt252;
    fn symbol(self: @T) -> felt252;
    fn decimals(self: @T) -> u8;
    fn total_supply(self: @T) -> u256;
    fn balance_of(self: @T, account: ContractAddress) -> u256;
    fn allowance(self: @T, owner: ContractAddress, spender: ContractAddress) -> u256;
    fn transfer(ref self: T, recipient: ContractAddress, amount: u256) -> bool;
    fn transfer_from(ref self: T, sender: ContractAddress, recipient: ContractAddress, amount: u256) -> bool;
    fn approve(ref self: T, spender: ContractAddress, amount: u256) -> bool;
    fn mint(ref self: T, to: ContractAddress, amount: u256);
}
